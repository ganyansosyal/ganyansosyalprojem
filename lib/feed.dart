import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'bets.dart';
import 'coupon_view.dart';
import 'preload.dart';
import 'share_sheet.dart';
import 'scoring.dart';
import 'profile.dart';
import 'admin.dart' show canManageUser, showUserAdminMenu, toggleBanUser;
import 'settle.dart' show isAdminNotifier;
import 'live.dart';
import 'theme.dart';
import 'tjk.dart' show TjkStore, Race, isoToday, liveResTick;

FirebaseFirestore get _db => FirebaseFirestore.instance;
String get _myUid => profileNotifier.value?.uid ?? '';

const _aylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
String fmtStamp(int ts) {
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${_aylar[d.month - 1]} ${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

void _toast(BuildContext c, String t) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));
}

class Post {
  final String id;
  final Map<String, dynamic> d;
  Post(this.id, this.d);

  String get uid => (d['uid'] ?? '').toString();
  String get authorName => (d['authorName'] ?? '').toString();
  int get ts => (d['ts'] as num?)?.toInt() ?? 0;
  String get text => (d['text'] ?? '').toString();
  bool get hidden => d['adminHidden'] == true;
  List<String> get likedBy => ((d['likedBy'] as List?) ?? const []).map((e) => e.toString()).toList();
  int get likes => likedBy.length;
  List<Map<String, dynamic>> get comments =>
      ((d['comments'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  Map<String, dynamic>? get coupon {
    if (d['coupon'] is! Map) return null;
    final m = Map<String, dynamic>.from(d['coupon'] as Map);
    if ((m['iso'] ?? '').toString().isEmpty && ts > 0) {
      final t = DateTime.fromMillisecondsSinceEpoch(ts);
      m['iso'] = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    }
    return m;
  }
}

class _Profiles {
  static final Map<String, Future<Profile?>> _m = {};
  static final Map<String, Profile?> _v = {};
  // Daha önce yüklenmiş profil varsa hemen ver (kart ilk karede boş çizilip sonra değişmesin)
  static Profile? cached(String uid) => _v[uid];
  // Canlı profil: fotoğraf/isim değişince kartlardaki avatar da anında güncellenir
  static final Map<String, Stream<Profile?>> _w = {};
  static Stream<Profile?> watch(String uid) => _w.putIfAbsent(uid, () => _db.collection('users').doc(uid).snapshots().map((d) {
        final m = d.data();
        final p = (d.exists && m != null) ? Profile.fromMap(uid, m) : null;
        _v[uid] = p;
        return p;
      }).asBroadcastStream());
  static Future<Profile?> of(String uid) {
    if (uid.isEmpty) return Future.value(null);
    return _m.putIfAbsent(uid, () => AuthService.loadProfile(uid).then((p) {
          _v[uid] = p;
          return p;
        }));
  }
}

String _ckey(Map<String, dynamic> m) => '${m['uid'] ?? ''}|${m['ts']}';

int _nextMidnight() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + 1).millisecondsSinceEpoch;
}

Future<void> _notifSet(String id, String type, String to, Post? p, String tx) async {
  final me = profileNotifier.value;
  if (me == null || to.isEmpty || to == me.uid) return;
  if (type != 'follow' && p == null) return;
  try {
    await _db.collection('notifs').doc(id.replaceAll('/', '_')).set({
      'to': to, 'from': me.uid, 'fn': me.name, 'type': type, 'pid': p?.ts ?? '', 'pd': p?.id ?? '', 'ts': DateTime.now().millisecondsSinceEpoch, 'exp': Timestamp.fromMillisecondsSinceEpoch(_nextMidnight()), 'tx': tx.length > 80 ? tx.substring(0, 80) : tx,
    });
  } catch (_) {}
}

Future<void> _notifDel(String id) async {
  try { await _db.collection('notifs').doc(id.replaceAll('/', '_')).delete(); } catch (_) {}
}

Future<void> _toggleLike(Post p) async {
  final on = !p.likedBy.contains(_myUid);
  await _db.collection('posts').doc(p.id).update({
    'likedBy': on ? FieldValue.arrayUnion([_myUid]) : FieldValue.arrayRemove([_myUid]),
  });
  final nid = 'like_${p.id}_$_myUid';
  if (on) { _notifSet(nid, 'like', p.uid, p, ''); } else { _notifDel(nid); }
}

Future<void> _toggleFollow(String targetUid, bool following) async {
  final on = !following;
  await _db.collection('users').doc(_myUid).update({
    'following': on ? FieldValue.arrayUnion([targetUid]) : FieldValue.arrayRemove([targetUid]),
    'fts.$targetUid': on ? DateTime.now().millisecondsSinceEpoch : FieldValue.delete(),
  });
  if (on) _notifSet('follow_${_myUid}_${targetUid}_${DateTime.now().millisecondsSinceEpoch}', 'follow', targetUid, null, '');
}

Future<void> _editComments(String postId, List<dynamic> Function(List<dynamic>) fn) async {
  final ref = _db.collection('posts').doc(postId);
  await _db.runTransaction((t) async {
    final s = await t.get(ref);
    if (!s.exists) return;
    final arr = ((s.data()!['comments'] as List?) ?? const []).toList();
    t.update(ref, {'comments': fn(arr)});
  });
}

Future<void> toggleFollow(String t, bool f) => _toggleFollow(t, f);

/// Alt menüde "Akış"a (zaten Akış'tayken) tekrar basılınca akışı en üste kaydırır
final ValueNotifier<int> feedScrollTop = ValueNotifier<int>(0);

// Bildirimden kupona git: bildirim sayfası bunu ayarlar, Shell akış sekmesine geçer, FeedPage kuponu bulup vurgular
class FeedTarget {
  final String id, type; // id = paylaşım (post) doküman id'si
  FeedTarget(this.id, this.type);
}
final ValueNotifier<FeedTarget?> feedTarget = ValueNotifier<FeedTarget?>(null);

class FeedPage extends StatefulWidget {
  final void Function(String city, int race)? onOpenRace;
  final VoidCallback? onOpenLeaders;
  const FeedPage({super.key, this.onOpenRace, this.onOpenLeaders});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

typedef _RankRow = ({String uid, Profile p, Score s});

String _postDay(Post p) {
  final i = (p.coupon?['iso'] ?? '').toString();
  if (i.isNotEmpty) return i;
  final t = DateTime.fromMillisecondsSinceEpoch(p.ts);
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

bool _altiliBekler(Post p) {
  final c = p.coupon;
  if (c == null) return false;
  final vir = c['vir'];
  if (vir is num && vir > 0) return false;
  if ((p.d['mark'] ?? '').toString() == 'lose') return false;
  final legs = ((c['legs'] as List?) ?? const []).whereType<Map>().toList();
  return legs.length == 6 && RegExp('ganyan', caseSensitive: false).hasMatch((c['type'] ?? '').toString()) && legs.any((l) => legSt(c, l) == 'p');
}

bool _isWon(Post p) => postStatus(p) == 'win';
bool _isLost(Post p) => postStatus(p) == 'lose' && !_altiliBekler(p);
class _FeedPageState extends State<FeedPage> {
  final _scroll = ScrollController();
  void _toTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  String _filter = 'all';

  // Bildirimden gelen kupon: bul, kaydır, vurgula
  List<Post> _lastAll = const [];
  FeedTarget? _handled;
  String? _flashId;
  final GlobalKey _tgtKey = GlobalKey();

  String _filterFor(Post? p, String type) {
    if (p != null && p.coupon != null) {
      if (_isLost(p)) return 'lost';
      if (_isWon(p)) return 'winners';
      return 'all';
    }
    if (type == 'lose') return 'lost';
    if (type == 'win') return 'winners';
    return 'all';
  }

  void _onTarget() {
    final t = feedTarget.value;
    if (t == null || identical(t, _handled) || !mounted) return;
    _handled = t;
    Post? find() {
      for (final p in _lastAll) { if (p.id == t.id) return p; }
      return null;
    }
    setState(() {
      _filter = _filterFor(find(), t.type);
      _flashId = null;
    });
    () async {
      if (_scroll.hasClients) _scroll.jumpTo(0);
      for (var tries = 0; tries < 60; tries++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !identical(_handled, t)) return;
        final p = find();
        final want = _filterFor(p, t.type);
        if (p != null && want != _filter) {
          setState(() => _filter = want); // durumu sonradan değişti: doğru sekmeye geç
          if (_scroll.hasClients) _scroll.jumpTo(0);
          continue;
        }
        final ctx = _tgtKey.currentContext;
        if (p != null && ctx != null) {
          await Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
          if (!mounted) return;
          setState(() => _flashId = t.id);
          Future.delayed(const Duration(milliseconds: 2800), () { if (mounted && _flashId == t.id) setState(() => _flashId = null); });
          return;
        }
        if (_scroll.hasClients) {
          final pos = _scroll.position;
          if (pos.pixels >= pos.maxScrollExtent - 1 && tries > 3) break;
          _scroll.jumpTo((pos.pixels + 700).clamp(0.0, pos.maxScrollExtent).toDouble());
        }
        await Future.delayed(const Duration(milliseconds: 60));
      }
      if (!mounted || !identical(_handled, t)) return;
      _toast(context, t.type == 'lose' ? 'Kaybeden kupon bulunamadı.' : 'Gönderi bugünün akışında yok ya da silinmiş.');
    }();
  }

  final _subs = <StreamSubscription>[];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = [];
  Map<String, double> _bonus = {};
  Set<String> _mods = {};
  int _ver = 0, _rankVer = -1;
  Object? _rankSnap;
  List<_RankRow> _rank = const [];

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _posts = _db.collection('posts').orderBy('ts', descending: true).limit(100).snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _me = _db.collection('users').doc(_myUid).snapshots();

  Timer? _bumpT;
  bool _fresh = false;
  Map<String, dynamic>? _meInit; // açılışta alınan profilim (takip listesi): rozetler sonradan değişmesin
  bool _followKnown = false;

  @override
  void initState() {
    super.initState();
    feedScrollTop.addListener(_toTop);
    feedTarget.addListener(_onTarget);
    liveResTick.addListener(_resTick);
    TjkStore.i.ensureLoaded();
    // Eski (önbellek) paylaşımlar hiç gösterilmesin: önce sunucudan taze veriyi al, sonra akışı aç.
    // İnternet yoksa/6 sn'de gelmezse önbellekle devam eder.
    // Tahminciler satırı, "+" rozetleri ve sıralama açılışta kademe kademe gelip zıplamasın diye
    // hepsini (paylaşım, kullanıcılar, puanlar, moderatörler, ben) birlikte alıp tek seferde göster.
    if (Preload.done && Preload.uid == _myUid) {
      // Splash sırasında alınan veri hazır: spinner/zıplama yok, akış doğrudan dolu açılır
      _users = Preload.users;
      _bonus = Preload.bonus;
      _mods = Preload.mods;
      _meInit = Preload.me;
      _fresh = true;
    } else {
      () async {
        const srv = GetOptions(source: Source.server);
        try {
          final fu = _db.collection('users').limit(300).get(srv);
          final fg = _db.collection('grants').limit(500).get(srv);
          final fm = _db.collection('mods').limit(100).get(srv);
          final fme = _db.collection('users').doc(_myUid).get(srv);
          final fp = _db.collection('posts').orderBy('ts', descending: true).limit(100).get(srv);
          await Future.wait<Object?>([fp, fu, fg, fm, fme]).timeout(const Duration(seconds: 6));
          _users = (await fu).docs;
          _bonus = {for (final d in (await fg).docs) d.id: ((d.data()['pts'] as num?)?.toDouble() ?? 0) + ((d.data()['keep'] as num?)?.toDouble() ?? 0)};
          _mods = (await fm).docs.map((d) => d.id).toSet();
          _meInit = (await fme).data();
        } catch (_) {}
        if (mounted) setState(() => _fresh = true);
      }();
    }
    // 3 Firestore akışı art arda gelince feed'i 3 kez baştan hesaplamasın
    void bump() {
      _bumpT ??= Timer(const Duration(milliseconds: 150), () {
        _bumpT = null;
        if (mounted) setState(() => _ver++);
      });
    }

    _subs.add(_db.collection('users').limit(300).snapshots().listen((s) { _users = s.docs; bump(); }, onError: (_) {}));
    _subs.add(_db.collection('grants').limit(500).snapshots().listen((s) { _bonus = {for (final d in s.docs) d.id: ((d.data()['pts'] as num?)?.toDouble() ?? 0) + ((d.data()['keep'] as num?)?.toDouble() ?? 0)}; bump(); }, onError: (_) {}));
    _subs.add(_db.collection('mods').limit(100).snapshots().listen((s) { _mods = s.docs.map((d) => d.id).toSet(); bump(); }, onError: (_) {}));
  }

  void _resTick() {
    if (mounted) setState(() {}); // kupon sonucu geldi: Sonuçlar sekmesine girmeden akış güncellensin
  }

  @override
  void dispose() {
    liveResTick.removeListener(_resTick);
    feedScrollTop.removeListener(_toTop);
    feedTarget.removeListener(_onTarget);
    _scroll.dispose();
    _bumpT?.cancel();
    for (final s in _subs) { s.cancel(); }
    super.dispose();
  }

  // Aşağı çekince: paylaşımları, kullanıcıları ve puanları sunucudan taze çek (yeni paylaşım varsa gelir)
  Future<void> _refresh() async {
    TjkStore.i.ensureLoaded();
    const srv = GetOptions(source: Source.server);
    try {
      await Future.wait([
        _db.collection('posts').orderBy('ts', descending: true).limit(100).get(srv),
        _db.collection('users').limit(300).get(srv),
        _db.collection('grants').limit(500).get(srv),
        _db.collection('mods').limit(100).get(srv),
      ]).timeout(const Duration(seconds: 8));
    } catch (_) {}
    if (mounted) setState(() => _ver++);
  }

  void _syncRank(Object snap, List<Post> posts) {
    if (identical(_rankSnap, snap) && _rankVer == _ver) return;
    _rankSnap = snap;
    _rankVer = _ver;
    final rows = _users.map((d) => (uid: d.id, p: Profile.fromMap(d.id, d.data()), s: scoreOf(d.id, posts, d.data()['hist'] as Map?, _bonus[d.id] ?? 0))).where((x) => x.s.pts > 0).toList()
      ..sort((a, b) {
        final k = b.s.pts.compareTo(a.s.pts);
        if (k != 0) return k;
        final r = b.s.pct.compareTo(a.s.pct);
        if (r != 0) return r;
        return a.p.name.compareTo(b.p.name);
      });
    _rank = rows;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (!_fresh) return Center(child: CircularProgressIndicator(color: c.ac));
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _me,
      builder: (context, meSnap) {
        final meData = meSnap.data?.data() ?? _meInit;
        _followKnown = meData != null;
        final following = ((meData?['following'] as List?) ?? const []).map((e) => e.toString()).toSet();
        final tracked = ((meData?['trackedPosts'] as List?) ?? const []).map((e) => e.toString()).toSet();
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _posts,
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text(AuthService.errorText(snap.error!), style: jakarta(14, FontWeight.w600, c.mu)));
            if (!snap.hasData) return Center(child: CircularProgressIndicator(color: c.ac));
            final all = snap.data!.docs.map((d) => Post(d.id, d.data())).toList();
            _lastAll = all;
            _syncRank(snap.data!, all);
            final visible = all.where((p) => !p.hidden).toList();
            final today = isoToday();
            final day = visible.where((p) => _postDay(p) == today).toList();

            final fc = <String, int>{
              'all': day.where((p) => !_isLost(p) && !_isWon(p)).length, 'lost': day.where(_isLost).length, 'winners': day.where(_isWon).length, 'follow': day.where((p) => following.contains(p.uid) && !_isLost(p) && !_isWon(p)).length, 'mine': visible.where((p) => p.uid == _myUid).length, 'tracked': visible.where((p) => p.coupon != null && p.uid != _myUid && tracked.contains(p.id)).length,
            };

            var list = (_filter == 'tracked' || _filter == 'mine') ? visible : day;
            if (_filter == 'winners') list = list.where(_isWon).toList();
            if (_filter == 'lost') list = list.where(_isLost).toList();
            if (_filter == 'tracked') list = list.where((p) => p.coupon != null && p.uid != _myUid && tracked.contains(p.id)).toList();
            if (_filter == 'follow') list = list.where((p) => following.contains(p.uid)).toList();
            if (_filter == 'mine') list = list.where((p) => p.uid == _myUid).toList();
            if (_filter != 'tracked' && _filter != 'mine' && _filter != 'lost') list = list.where((p) => !_isLost(p)).toList();
            if (_filter == 'all' || _filter == 'follow') list = list.where((p) => !_isWon(p)).toList();

            const rk = {'win': 4, 'live': 3, 'wait': 2, 'lose': 1};
            int rankOf(Post p) => p.coupon == null ? 0 : (rk[postStatus(p)] ?? 2);
            int hits(Post p) => p.coupon == null ? 0 : couponStatus(p.coupon!).h;
            double cpts(Post p) => p.coupon == null ? 0 : couponPts(p.coupon!).pts;
            int eng(Post p) => p.likes + p.comments.length;
            list = list.toList()..sort(_filter == 'mine' ? (a, b) => b.ts.compareTo(a.ts) : (a, b) {
              var k = rankOf(b).compareTo(rankOf(a)); if (k != 0) return k;
              k = hits(b).compareTo(hits(a)); if (k != 0) return k;
              k = cpts(b).compareTo(cpts(a)); if (k != 0) return k;
              k = eng(b).compareTo(eng(a)); if (k != 0) return k;
              return b.ts.compareTo(a.ts);
            });

            final myDoc = _users.where((d) => d.id == _myUid).toList();
            final myHist = myDoc.isNotEmpty ? myDoc.first.data()['hist'] as Map? : null;
            final myScore = scoreOf(_myUid, all, myHist, _bonus[_myUid] ?? 0);
            final myRank = _rank.indexWhere((x) => x.uid == _myUid);
            final dk = dayKey(DateTime.now().millisecondsSinceEpoch);
            var bugun = scoreDays(_myUid, all)[dk]?.pts ?? 0;
            final hd = myHist?[dk];
            if (hd is Map) bugun += (hd['p'] as num?)?.toDouble() ?? 0;
            if (bugun > gunlukTavan) bugun = gunlukTavan;

            final head = <Widget>[
              _topRow(c, myScore, myRank, bugun),
              const SizedBox(height: 8),
              _NextRaceBar(onOpen: widget.onOpenRace),
              _people(c, following),
              _filters(c, fc),
              const SizedBox(height: 10),
              if (list.isEmpty)
                Padding(padding: const EdgeInsets.all(20), child: Text(_filter == 'follow' ? 'Takip ettiğin kimsenin paylaşımı yok.' : _filter == 'mine' ? 'Henüz bir şey paylaşmadın.' : _filter == 'lost' ? 'Bugün kaybeden kupon yok.' : _filter == 'winners' ? 'Bugün tutan kupon yok.' : _filter == 'tracked' ? 'Takip ettiğin kupon yok.' : 'Henüz paylaşım yok.', textAlign: TextAlign.center, style: jakarta(13, FontWeight.w600, c.mu))),
            ];
            // Yukarıdan aşağı çekince yenile (Instagram gibi dönen simge)
            return RefreshIndicator(
              color: c.ac,
              backgroundColor: c.sf,
              onRefresh: _refresh,
              child: ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                cacheExtent: 1200, // Kartlar ekrana girmeden önce hazırlansın (kaydırırken çizim takılmasın)
                itemCount: head.length + list.length,
                itemBuilder: (context, i) {
                  if (i < head.length) return head[i];
                  final p = list[i - head.length];
                  return RepaintBoundary( // Her kartı kendi katmanına alır
                    key: ValueKey(p.id),
                    child: AnimatedContainer(
                      key: (_handled != null && p.id == _handled!.id) ? _tgtKey : null,
                      duration: const Duration(milliseconds: 300),
                      foregroundDecoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.id == _flashId ? c.ac : Colors.transparent, width: 3),
                      ),
                      child: PostCard(key: ValueKey(p.id), post: p, following: following.contains(p.uid), tracked: tracked.contains(p.id), isMod: _mods.contains(p.uid)),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }  Widget _topRow(AppColors c, Score sc, int rank, double bugun) {
    final me = profileNotifier.value;
    return SizedBox(
      height: 86,
      child: Row(children: [
        Expanded(
          flex: 11,
          child: GestureDetector(
            onTap: () { if (me != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileRoute(uid: me.uid))); },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.ac.withAlpha(20), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ac.withAlpha(90))),
              child: Row(children: [
                Avatar(profile: me, size: 46),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(me?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(14, FontWeight.w800, c.tx)),
                    Text('@${me?.handle ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(11, FontWeight.w600, c.mu)),
                    const SizedBox(height: 4),
                    ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: (bugun / gunlukTavan).clamp(0.0, 1.0), minHeight: 4, backgroundColor: c.ln, color: c.ac)),
                    const SizedBox(height: 2),
                    Text('Bugün ${fmtPts(bugun)} / ${fmtPts(gunlukTavan)} puan', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(10, FontWeight.w600, c.mu)),
                  ]),
                ),
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(fmtPts(sc.pts), style: jakarta(20, FontWeight.w800, c.ac)),
                  Text('puan', style: jakarta(10, FontWeight.w600, c.mu)),
                  if (rank > -1) Text('#${rank + 1}. sıra', style: jakarta(9.5, FontWeight.w800, c.gold)),
                ]),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 8,
          child: GestureDetector(
            onTap: () => showLive(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: c.red.withAlpha(16), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.red.withAlpha(70))),
              child: Row(children: [
                Container(width: 32, height: 32, decoration: BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.live_tv, color: Colors.white, size: 18)),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Canlı yayın', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12, FontWeight.w800, c.tx)),
                    const SizedBox(height: 2),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(8)), child: Text('İZLE', style: jakarta(10, FontWeight.w800, Colors.white))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _people(AppColors c, Set<String> following) {
    final top = _rank.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Öne Çıkan Tahminciler', style: jakarta(16, FontWeight.w800, c.tx))),
          _rank.length > 5
              ? GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpenLeaders,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Tümü', style: jakarta(12, FontWeight.w800, c.ac)),
                      Icon(Icons.chevron_right, size: 16, color: c.ac),
                    ]),
                  ),
                )
              : Text('Puana göre', style: jakarta(11, FontWeight.w600, c.mu)),
        ]),
        const SizedBox(height: 6),
        if (top.isEmpty)
          Text('Henüz puan alan yok. Kuponu tutan ilk kişi burada görünecek.', style: jakarta(11.5, FontWeight.w500, c.mu))
        else
          SizedBox(
            height: 142,
            child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
              for (var i = 0; i < top.length; i++) _person(c, i, top[i], following),
            ]),
          ),
      ]),
    );
  }

  Widget _person(AppColors c, int i, _RankRow x, Set<String> following) {
    final isMe = x.uid == _myUid;
    final fol = following.contains(x.uid);
    final ring = i == 0 ? const [Color(0xFFFFE08A), Color(0xFFD49A14)] : i == 1 ? const [Color(0xFFF7FAFF), Color(0xFF9AA6B8)] : i == 2 ? const [Color(0xFFF0B987), Color(0xFFA4642C)] : null;
    final rkCol = i == 0 ? const Color(0xFFD49A14) : i == 1 ? const Color(0xFF9AA6B8) : i == 2 ? const Color(0xFFA4642C) : const Color(0xFF8A94A6);
    final first = x.p.name.trim().split(' ').first;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileRoute(uid: x.uid))),
      child: SizedBox(
        width: 72,
        child: Column(children: [
          SizedBox(
            width: 70,
            height: 70,
            child: Stack(clipBehavior: Clip.none, children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: ring == null ? null : LinearGradient(colors: ring, begin: Alignment.topLeft, end: Alignment.bottomRight), border: ring == null ? Border.all(color: c.ln, width: 2) : null),
                  child: Avatar(profile: x.p, size: 58),
                ),
              ),
              Positioned(left: -2, top: -2, child: Container(width: 20, height: 20, alignment: Alignment.center, decoration: BoxDecoration(color: rkCol, shape: BoxShape.circle, border: Border.all(color: c.sf, width: 2)), child: Text('${i + 1}', style: jakarta(10, FontWeight.w800, Colors.white)))),
              if (!isMe && !fol && _followKnown) Positioned(right: -2, bottom: -2, child: GestureDetector(onTap: () => _toggleFollow(x.uid, false).catchError((e) { if (mounted) _toast(context, AuthService.errorText(e)); }), child: Container(width: 22, height: 22, decoration: BoxDecoration(color: c.ac, shape: BoxShape.circle, border: Border.all(color: c.sf, width: 2)), child: const Icon(Icons.add, size: 14, color: Colors.white)))),
            ]),
          ),
          const SizedBox(height: 4),
          Text(isMe ? 'Sen' : first, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12, FontWeight.w800, c.tx)),
          Text('${fmtPts(x.s.pts)} puan', style: jakarta(11, FontWeight.w800, c.ac)),
          Text(x.s.tot > 0 ? '%${x.s.pct} isabet' : 'henüz yok', style: jakarta(9.5, FontWeight.w600, c.mu)),
        ]),
      ),
    );
  }

  Widget _filters(AppColors c, Map<String, int> fc) {
    const items = <(String, String, IconData, Color?)>[
      ('all', 'Akış', Icons.home_outlined, null), ('mine', 'Paylaştıklarım', Icons.person_outline, null), ('lost', 'Kaybedenler', Icons.cancel_outlined, Color(0xFFE0305A)), ('follow', 'Takip Ettiklerim', Icons.favorite_border, Color(0xFFE0305A)), ('winners', 'Tutanlar', Icons.emoji_events_outlined, Color(0xFFD97706)), ('tracked', 'Kupon Takip', Icons.bookmark_border, Color(0xFF0EA5E9)),
    ];
    Widget chip((String, String, IconData, Color?) it) {
      final on = _filter == it.$1;
      final col = it.$4 ?? c.ac;
      final n = fc[it.$1] ?? 0;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _filter = it.$1),
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 34,
              decoration: BoxDecoration(color: on ? col.withAlpha(30) : c.sf, borderRadius: BorderRadius.circular(10), border: Border.all(color: on ? col : c.ln, width: on ? 1.5 : 1)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(it.$3, size: 14, color: col),
                const SizedBox(width: 4),
                Flexible(child: Text(it.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(10.5, FontWeight.w700, on ? col : c.tx))),
              ]),
            ),
            if (n > 0) Positioned(right: -2, top: -6, child: Container(constraints: const BoxConstraints(minWidth: 18), height: 18, padding: const EdgeInsets.symmetric(horizontal: 4), alignment: Alignment.center, decoration: BoxDecoration(color: col, shape: BoxShape.rectangle, borderRadius: BorderRadius.circular(9), border: Border.all(color: c.bg, width: 1.5)), child: Text(n > 99 ? '99+' : '$n', style: jakarta(9, FontWeight.w800, Colors.white)))),
          ]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        Row(children: [chip(items[0]), const SizedBox(width: 6), chip(items[1]), const SizedBox(width: 6), chip(items[2])]),
        const SizedBox(height: 8),
        Row(children: [chip(items[3]), const SizedBox(width: 6), chip(items[4]), const SizedBox(width: 6), chip(items[5])]),
      ]),
    );
  }
}/* ---------------- Sıradaki koşu şeridi ---------------- */

class _NextRaceBar extends StatefulWidget {
  final void Function(String city, int race)? onOpen;
  const _NextRaceBar({this.onOpen});
  @override
  State<_NextRaceBar> createState() => _NextRaceBarState();
}

class _NextRaceBarState extends State<_NextRaceBar> {
  final s = TjkStore.i;
  Timer? _t;

  @override
  void initState() { super.initState(); s.addListener(_u); _t = Timer.periodic(const Duration(seconds: 1), (_) => _u()); }
  @override
  void dispose() { _t?.cancel(); s.removeListener(_u); super.dispose(); }
  void _u() { if (mounted) setState(() {}); }

  ({String city, Race r, DateTime d})? _next() {
    if (!s.isToday) return null;
    final now = DateTime.now();
    ({String city, Race r, DateTime d})? best;
    for (final c in s.cities) {
      for (final r in s.races(c.name)) {
        final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(r.saat);
        if (m == null) continue;
        final d = DateTime(now.year, now.month, now.day, int.parse(m.group(1)!), int.parse(m.group(2)!));
        if (d.isAfter(now) && (best == null || d.isBefore(best.d))) best = (city: c.name, r: r, d: d);
      }
    }
    return best;
  }

  String _left(int sec) {
    String p2(int n) => n.toString().padLeft(2, '0');
    final h = sec ~/ 3600, m = sec % 3600 ~/ 60, sc = sec % 60;
    return h > 0 ? '$h sa ${p2(m)} dk' : m > 0 ? '$m dk ${p2(sc)} sn' : '$sc sn';
  }

  @override
  Widget build(BuildContext context) {
    final n = _next();
    final c = AppColors.of(context);
    // Yer her zaman ayrılır: veri sonradan gelince sayfa aşağı kaymasın
    if (n == null) {
      final wait = s.loading || s.cities.isEmpty;
      return Container(
        height: 46,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: c.ac.withAlpha(14), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ac.withAlpha(90))),
        child: Row(children: [
          Text('SIRADAKİ KOŞU', style: jakarta(9.5, FontWeight.w800, c.ac).copyWith(letterSpacing: 1.1)),
          const SizedBox(width: 8),
          Expanded(child: wait
              ? Container(height: 12, decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(6)))
              : Text(s.isToday ? 'Bugün başka koşu yok' : '—', maxLines: 1, style: jakarta(13, FontWeight.w700, c.mu))),
        ]),
      );
    }
    final left = n.d.difference(DateTime.now()).inSeconds.clamp(0, 999999);
    return GestureDetector(
      onTap: () => widget.onOpen?.call(n.city, n.r.no),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: c.ac.withAlpha(14), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ac.withAlpha(90))),
        child: Row(children: [
          Text('SIRADAKİ KOŞU', style: jakarta(9.5, FontWeight.w800, c.ac).copyWith(letterSpacing: 1.1)),
          const SizedBox(width: 8),
          Expanded(child: Text('${n.city} ${n.r.no}. koşu · ${n.r.saat}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13, FontWeight.w800, c.tx))),
          const SizedBox(width: 6),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.ln)), child: Text(_left(left), style: jakarta(12, FontWeight.w800, c.gold))),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: c.mu, size: 18),
        ]),
      ),
    );
  }
}

/* ---------------- Paylaşım kartı ---------------- */

class PostCard extends StatelessWidget {
  final Post post;
  final bool following, tracked, isMod;
  const PostCard({super.key, required this.post, required this.following, this.tracked = false, this.isMod = false});

  Future<void> _shareImg(BuildContext context) async {
    final cp = post.coupon;
    if (cp == null) return;
    Profile? pr = _Profiles.cached(post.uid);
    if (pr == null) {
      try {
        pr = await _Profiles.of(post.uid);
      } catch (_) {}
    }
    if (!context.mounted) return;
    final nm = post.authorName.isNotEmpty ? post.authorName : (pr?.name ?? 'Kullanıcı');
    openCouponShare(context, coupon: cp, author: nm, profile: pr, ts: post.ts, text: post.text, postId: post.id, status: postStatus(post));
  }

  Future<void> _delete(BuildContext context) async {
    final c = AppColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.sf,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: c.red.withAlpha(30), shape: BoxShape.circle),
              child: Icon(Icons.delete_outline_rounded, color: c.red, size: 28),
            ),
            const SizedBox(height: 14),
            Text('Paylaşımı sil', textAlign: TextAlign.center, style: jakarta(20, FontWeight.w800, c.tx)),
            const SizedBox(height: 10),
            Text('Bu paylaşımı silmek istediğine emin misin? Bu işlem geri alınamaz.', textAlign: TextAlign.center, style: jakarta(14.5, FontWeight.w500, c.mu).copyWith(height: 1.35)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln, width: 1.4)),
                    child: Text('Vazgeç', style: jakarta(15, FontWeight.w800, c.tx)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(16)),
                    child: Text('Sil', style: jakarta(15, FontWeight.w800, Colors.white)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    try { await _db.collection('posts').doc(post.id).delete(); } catch (e) { if (context.mounted) _toast(context, AuthService.errorText(e)); }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final p = post;
    final liked = p.likedBy.contains(_myUid);
    final mine = p.uid == _myUid;
    final cp = p.coupon;
    final pst = cp == null ? '' : postStatus(p);
    final stripe = cp == null ? null : pst == 'win' ? const Color(0xFF16A34A) : pst == 'lose' ? c.red : c.gold;
    final canDelete = (mine && cp == null) || isAdminNotifier.value;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
      child: Stack(children: [
        if (stripe != null) Positioned(left: 0, top: 0, bottom: 0, width: 4, child: ColoredBox(color: stripe)),
        Padding(
          padding: EdgeInsets.fromLTRB(stripe != null ? 14 : 12, 12, 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (cp != null && pst == 'win' && couponPts(cp).pts > 0)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Color.alphaBlend(c.ac.withAlpha(36), c.sf), borderRadius: BorderRadius.circular(12)),
                child: Text('✅ Kupon tuttu · +${fmtPts(couponPts(cp).pts)} puan', style: jakarta(12.5, FontWeight.w800, c.ac)),
              ),
            StreamBuilder<Profile?>(
              stream: _Profiles.watch(p.uid),
              initialData: _Profiles.cached(p.uid),
              builder: (context, s) {
                final pr = s.data;
                void goProfile() { if (p.uid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileRoute(uid: p.uid))); }
                final nm = p.authorName.isNotEmpty ? p.authorName : (pr?.name ?? 'Kullanıcı');
                final canMng = !mine && p.uid.isNotEmpty && canManageUser(p.uid, targetAdmin: pr?.isAdmin == true, targetMod: isMod);
                // Yönetici / moderatör başkasına dokununca doğrudan profile gitmez, yönetim menüsü açılır
                void open() {
                  if (canMng) {
                    showUserAdminMenu(context, uid: p.uid, name: nm, targetAdmin: pr?.isAdmin == true, onProfile: goProfile);
                  } else {
                    goProfile();
                  }
                }
                return Row(children: [
                  Padding(padding: const EdgeInsets.fromLTRB(4, 10, 0, 4), child: GestureDetector(onTap: goProfile, child: Avatar(profile: pr, size: 66))), // çerçeve/taç dışarı taşar: üst ve sol boşluk
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: open,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.authorName.isNotEmpty ? p.authorName : (pr?.name ?? '...'), maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13.5, FontWeight.w800, c.tx)),
                        Text(fmtStamp(p.ts), style: jakarta(10.5, FontWeight.w500, c.mu)),
                        if (pr?.isAdmin == true || isMod)
                          Padding(padding: const EdgeInsets.only(top: 4), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF8B3FD9), borderRadius: BorderRadius.circular(10)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(pr?.isAdmin == true ? Icons.lock_outline : Icons.block, size: 12, color: Colors.white), const SizedBox(width: 4), Text(pr?.isAdmin == true ? 'Yönetici' : 'Moderatör', style: jakarta(10.5, FontWeight.w800, Colors.white))]))),
                      ]),
                    ),
                  ),
                  if (!mine && p.uid.isNotEmpty)
                    GestureDetector(
                      onTap: () => _toggleFollow(p.uid, following).catchError((e) { if (context.mounted) _toast(context, AuthService.errorText(e)); }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(color: following ? c.sf : c.ac, borderRadius: BorderRadius.circular(10), border: following ? Border.all(color: c.ln) : null),
                        child: Text(following ? 'Takipte' : 'Takip Et', style: jakarta(11.5, FontWeight.w800, following ? c.ac : c.on)),
                      ),
                    ),
                  if (canMng) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => toggleBanUser(context, p.uid, nm),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF04438), Color(0xFFD92D20)]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Color(0x61D92D20), blurRadius: 8, offset: Offset(0, 3))],
                        ),
                        child: const Icon(Icons.block, size: 18, color: Colors.white),
                      ),
                    ),
                  ],
                  if (canDelete) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _delete(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: c.red.withAlpha(24), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.delete_outline, size: 18, color: c.red),
                      ),
                    ),
                  ],
                ]);
              },
            ),
            if (p.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(p.text, style: jakarta(13.5, FontWeight.w700, c.tx)),
            ],
            if (cp != null) ...[const SizedBox(height: 8), CouponView(cp, ts: p.ts)],
            const SizedBox(height: 8),
            Row(children: [
              _act(c, liked ? Icons.favorite : Icons.favorite_border, '${p.likes}', liked ? c.red : c.mu, () { _toggleLike(p).catchError((e) { if (context.mounted) _toast(context, AuthService.errorText(e)); }); }),
              const SizedBox(width: 16),
              _act(c, Icons.chat_bubble_outline, '${p.comments.length}', c.mu, () => openComments(context, p.id, p.uid)),
              // Boş alanın tamamı takip butonuna ayrılır (yazı kesilmesin); buton sağa yaslı, Paylaş'a bitişik
              if (cp != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: mine
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8),
                            child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleTrack(p.id, !tracked).catchError((e) { if (context.mounted) _toast(context, AuthService.errorText(e)); }),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: tracked ? const Color(0xFF0EA5E9).withAlpha(30) : c.sf2, borderRadius: BorderRadius.circular(12), border: Border.all(color: tracked ? const Color(0xFF0EA5E9) : c.ln)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(tracked ? Icons.bookmark : Icons.bookmark_border, size: 16, color: const Color(0xFF0EA5E9)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(tracked ? 'Takip ediliyor' : 'Kuponu takip et', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12, FontWeight.w800, tracked ? const Color(0xFF0EA5E9) : c.mu))),
                    ]),
                  ),
                  ),
                ),
                  ),
                ),
              // Paylaş: satırın sağ ucunda, kupon kutusunun sağ kenarıyla hizalı
              if (cp != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _shareImg(context),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF14B27D), Color(0xFF0E9F73)]),
                      boxShadow: const [BoxShadow(color: Color(0x4D0E9F73), blurRadius: 8, offset: Offset(0, 3))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.ios_share_rounded, size: 16, color: Colors.white),
                      const SizedBox(width: 6),
                      Text('Paylaş', style: jakarta(12, FontWeight.w800, Colors.white)),
                    ]),
                  ),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  static Future<void> _toggleTrack(String postId, bool on) => _db.collection('users').doc(_myUid).update({
        'trackedPosts': on ? FieldValue.arrayUnion([postId]) : FieldValue.arrayRemove([postId]),
      });

  Widget _act(AppColors c, IconData ic, String n, Color col, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(ic, size: 18, color: col),
          const SizedBox(width: 5),
          Text(n, style: jakarta(12.5, FontWeight.w700, col)),
        ]),
      ),
    );
  }
}
/* ---------------- Yorumlar ---------------- */

void openComments(BuildContext context, String postId, String postOwner) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.of(context).bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CommentsSheet(postId: postId, postOwner: postOwner),
  );
}

class _CommentsSheet extends StatefulWidget {
  final String postId, postOwner;
  const _CommentsSheet({required this.postId, required this.postOwner});
  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctl = TextEditingController();
  Map<String, String>? _reply;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _s = _db.collection('posts').doc(widget.postId).snapshots();

  @override
  void dispose() { _ctl.dispose(); super.dispose(); }

  Post _post([Map<String, dynamic>? d]) => Post(widget.postId, d ?? {'uid': widget.postOwner, 'ts': int.tryParse(widget.postId.split('_').first) ?? 0});

  Future<void> _add() async {
    final txt = _ctl.text.trim();
    final me = profileNotifier.value;
    if (txt.isEmpty || me == null) return;
    final t = txt.length > 500 ? txt.substring(0, 500) : txt;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rp = _reply?['key'] ?? '';
    final rn = _reply?['name'] ?? '';
    _ctl.clear();
    setState(() => _reply = null);
    try {
      await _db.collection('posts').doc(widget.postId).update({
        'comments': FieldValue.arrayUnion([
          {
            'uid': me.uid, 'n': me.name, 't': t, 'ts': ts, 'likedBy': <String>[], if (rp.isNotEmpty) 'rp': rp, if (rp.isNotEmpty) 'rn': rn.length > 60 ? rn.substring(0, 60) : rn,
          }
        ]),
      });
      final p = _post();
      final base = 'cm_${widget.postId}_${ts}_${me.uid}';
      final rTo = rp.isEmpty ? '' : rp.split('|').first;
      if (rTo.isNotEmpty) _notifSet('${base}_r', 'reply', rTo, p, t);
      if (widget.postOwner.isNotEmpty && widget.postOwner != rTo) _notifSet(base, 'comment', widget.postOwner, p, t);
    } catch (e) {
      if (mounted) _toast(context, AuthService.errorText(e));
    }
  }

  Future<void> _like(Map<String, dynamic> cm) async {
    final key = _ckey(cm);
    final on = !((cm['likedBy'] as List?) ?? const []).map((e) => e.toString()).contains(_myUid);
    await _editComments(widget.postId, (arr) => arr.map((x) {
          if (x is! Map || _ckey(Map<String, dynamic>.from(x)) != key) return x;
          final m = Map<String, dynamic>.from(x);
          final lb = ((m['likedBy'] as List?) ?? const []).map((e) => e.toString()).where((u) => u != _myUid).toList();
          if (on) lb.add(_myUid);
          m['likedBy'] = lb;
          return m;
        }).toList());
    final nid = 'cl_${widget.postId}_${key.replaceAll('|', '-')}_$_myUid';
    final to = (cm['uid'] ?? '').toString();
    if (on) { _notifSet(nid, 'cmlike', to, _post(), (cm['t'] ?? '').toString()); } else { _notifDel(nid); }
  }

  Future<void> _del(Map<String, dynamic> cm) {
    final key = _ckey(cm);
    return _editComments(widget.postId, (arr) => arr.where((x) {
          if (x is! Map) return true;
          final m = Map<String, dynamic>.from(x);
          return _ckey(m) != key && (m['rp'] ?? '') != key;
        }).toList());
  }

  Widget _av(String uid, double size) => StreamBuilder<Profile?>(
        stream: _Profiles.watch(uid),
        initialData: _Profiles.cached(uid),
        builder: (_, s) => Avatar(profile: s.data, size: size),
      );

  Widget _caption(AppColors c, Post p) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _av(p.uid, 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(p.authorName.isEmpty ? 'Kullanıcı' : p.authorName, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13, FontWeight.w800, c.tx))),
              const SizedBox(width: 6),
              Text(fmtStamp(p.ts), style: jakarta(10, FontWeight.w500, c.mu)),
            ]),
            const SizedBox(height: 2),
            Text(p.text, style: jakarta(13.5, FontWeight.w600, c.tx)),
          ]),
        ),
      ]),
    );
  }

  Widget _item(AppColors c, Map<String, dynamic> m, {required bool reply}) {
    final lb = ((m['likedBy'] as List?) ?? const []).map((e) => e.toString()).toList();
    final liked = lb.contains(_myUid);
    final canDel = (m['uid'] ?? '') == _myUid || widget.postOwner == _myUid;
    final name = (m['n'] ?? 'Kullanıcı').toString();
    return Padding(
      padding: EdgeInsets.only(left: reply ? 20 : 0, top: 6, bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _av((m['uid'] ?? '').toString(), reply ? 26 : 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12.5, FontWeight.w800, c.tx))),
              const SizedBox(width: 6),
              Text(fmtStamp((m['ts'] as num?)?.toInt() ?? 0), style: jakarta(10, FontWeight.w500, c.mu)),
            ]),
            const SizedBox(height: 2),
            Text.rich(TextSpan(children: [
              if (reply && (m['rn'] ?? '').toString().isNotEmpty) TextSpan(text: '@${m['rn']} ', style: jakarta(13, FontWeight.w800, c.ac)),
              TextSpan(text: '${m['t'] ?? ''}', style: jakarta(13, FontWeight.w600, c.tx)),
            ])),
            Row(children: [
              GestureDetector(
                onTap: () {
                  final top = reply ? (m['rp'] ?? '').toString() : _ckey(m);
                  setState(() => _reply = {'key': top, 'name': name});
                },
                child: Padding(padding: const EdgeInsets.only(top: 4, right: 12), child: Text('Yanıtla', style: jakarta(11, FontWeight.w700, c.mu))),
              ),
              if (canDel)
                GestureDetector(onTap: () => _del(m), child: Padding(padding: const EdgeInsets.only(top: 4), child: Text('Sil', style: jakarta(11, FontWeight.w700, c.red)))),
            ]),
          ]),
        ),
        GestureDetector(
          onTap: () => _like(m),
          child: Column(children: [
            Icon(liked ? Icons.favorite : Icons.favorite_border, size: 16, color: liked ? c.red : c.mu),
            if (lb.isNotEmpty) Text('${lb.length}', style: jakarta(10, FontWeight.w700, c.mu)),
          ]),
        ),
      ]),
    );
  }

  static const _emojis = ['❤️', '🙌', '🔥', '👏', '😢', '😍', '😮', '😂'];

  void _emoji(String e) {
    final t = _ctl.text;
    final sel = _ctl.selection;
    final i = sel.isValid ? sel.start : t.length;
    _ctl.value = TextEditingValue(text: t.replaceRange(i, sel.isValid ? sel.end : i, e), selection: TextSelection.collapsed(offset: i + e.length));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return KbSheet(
      fraction: 0.7,
      child: Column(children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(48, 6, 8, 6),
            child: Row(children: [
              Expanded(child: Text('Yorumlar', textAlign: TextAlign.center, style: jakarta(15, FontWeight.w800, c.tx))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(width: 34, height: 34, decoration: BoxDecoration(color: c.sf2, shape: BoxShape.circle), child: Icon(Icons.close, size: 18, color: c.tx)),
              ),
            ]),
          ),
          Divider(height: 1, color: c.ln),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _s,
              builder: (context, snap) {
                if (!snap.hasData) return Center(child: CircularProgressIndicator(color: c.ac));
                final post = _post(snap.data!.data() ?? {});
                final all = post.comments;
                final keys = all.map(_ckey).toSet();
                final tops = all.where((m) => !keys.contains((m['rp'] ?? '').toString())).toList();
                final rows = <Widget>[];
                if (post.text.trim().isNotEmpty) {
                  rows.add(_caption(c, post));
                  rows.add(Divider(height: 1, color: c.ln));
                }
                if (tops.isEmpty) {
                  rows.add(Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Center(child: Text('Henüz yorum yok. İlk yorumu sen yaz!', textAlign: TextAlign.center, style: jakarta(13.5, FontWeight.w600, c.mu))),
                  ));
                }
                for (final t in tops) {
                  rows.add(_item(c, t, reply: false));
                  for (final r in all.where((m) => (m['rp'] ?? '').toString() == _ckey(t))) {
                    rows.add(_item(c, r, reply: true));
                  }
                }
                return ListView(keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag, padding: const EdgeInsets.symmetric(horizontal: 14), children: rows);
              },
            ),
          ),
          if (_reply != null)
            Container(
              width: double.infinity,
              color: c.sf2,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(children: [
                Expanded(child: Text('@${_reply!['name']} kişisine yanıt veriyorsun', style: jakarta(11.5, FontWeight.w600, c.mu))),
                GestureDetector(onTap: () => setState(() => _reply = null), child: Icon(Icons.close, size: 16, color: c.mu)),
              ]),
            ),
          Container(
            decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.ln))),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (final e in _emojis)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _emoji(e),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Text(e, style: const TextStyle(fontSize: 24))),
                  ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                ValueListenableBuilder<Profile?>(
                  valueListenable: profileNotifier,
                  builder: (_, p, __) => Avatar(profile: p, size: 36),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(left: 14, right: 4),
                    decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(24), border: Border.all(color: c.ln)),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _ctl,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 3,
                          textInputAction: TextInputAction.send,
                          style: jakarta(13.5, FontWeight.w600, c.tx),
                          decoration: InputDecoration(border: InputBorder.none, counterText: '', isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 12), hintText: _reply == null ? 'Yorum yaz...' : 'Yanıtını yaz...', hintStyle: jakarta(13.5, FontWeight.w500, c.mu)),
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _ctl,
                        builder: (_, v, __) {
                          final hasText = v.text.trim().isNotEmpty;
                          return GestureDetector(
                            onTap: hasText ? _add : null,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(Icons.send_rounded, color: hasText ? c.ac : c.mu.withAlpha(110), size: 22),
                            ),
                          );
                        },
                      ),
                    ]),
                  ),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}
