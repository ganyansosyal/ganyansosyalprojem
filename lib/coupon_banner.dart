import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'bets.dart' show couponCost, money;
import 'feed.dart' show FeedTarget, feedTarget;
import 'theme.dart';

/// Yöneticinin "özel" işaretlediği kullanıcılar kupon paylaşınca, uygulamayı
/// açık olan herkesin üstünden kayan şerit (TikTok hediye şeridi gibi).
/// İşaret: users/{uid}.star == true  (yönetim menüsünden açılıp kapanır)
class CouponBanner extends StatefulWidget {
  const CouponBanner({super.key});
  @override
  State<CouponBanner> createState() => _CouponBannerState();
}

class _Item {
  final String postId, uid, name, label;
  final double amount;
  _Item(this.postId, this.uid, this.name, this.label, this.amount);
}

// Aynı kupon aynı oturumda ikinci kez çıkmasın
final Map<String, int> _shown = {};

// Uygulamaya sonradan girenler: son 10 dakikadaki kuponu da görür
const _freshMs = 10 * 60 * 1000;

// Kuponun en erken koşu saati (ms); bulunamazsa null
int? _raceStart(Map cp, int ts) {
  final legs = ((cp['legs'] as List?) ?? const []).whereType<Map>();
  String iso = (cp['iso'] ?? '').toString();
  if (iso.isEmpty && ts > 0) {
    final t = DateTime.fromMillisecondsSinceEpoch(ts);
    iso = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
  final day = DateTime.tryParse(iso);
  if (day == null) return null;
  int? best;
  for (final l in legs) {
    final m = RegExp(r'(\d{1,2})[:.](\d{2})').firstMatch((l['t'] ?? '').toString());
    if (m == null) continue;
    final v = DateTime(day.year, day.month, day.day, int.parse(m.group(1)!), int.parse(m.group(2)!)).millisecondsSinceEpoch;
    if (best == null || v < best) best = v;
  }
  return best;
}

class _CouponBannerState extends State<CouponBanner> with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;
  StreamSubscription? _sp, _ss;
  Map<String, Map<String, dynamic>> _stars = {};
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _posts = [];
  bool _gotStars = false, _gotPosts = false;
  final _queue = <_Item>[];
  _Item? _cur;
  Profile? _curProfile;
  bool _busy = false;
  late final AnimationController _ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 4600));
  Timer? _poll;

  String get _me => profileNotifier.value?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _ss = _db.collection('users').where('star', isEqualTo: true).limit(100).snapshots().listen((s) {
      _stars = {for (final d in s.docs) d.id: d.data()};
      _gotStars = true;
      _scan();
    }, onError: (_) {});
    _sp = _db.collection('posts').orderBy('ts', descending: true).limit(8).snapshots().listen((s) {
      _posts = s.docs;
      _gotPosts = true;
      _scan();
    }, onError: (_) {});
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _scan());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _sp?.cancel();
    _ss?.cancel();
    _ac.dispose();
    super.dispose();
  }

  void _scan() {
    if (!_gotStars || !_gotPosts || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final d in _posts.reversed) {
      final m = d.data();
      final uid = (m['uid'] ?? '').toString();
      final ts = (m['ts'] as num?)?.toInt() ?? 0;
      if (!_stars.containsKey(uid) || uid == _me) continue;
      if (m['coupon'] is! Map || m['adminHidden'] == true) continue;
      final cp = Map<String, dynamic>.from(m['coupon'] as Map);
      // İlk koşunun saatine kadar göster; saat yoksa 10 dk
      final start = _raceStart(cp, ts);
      final live = start != null ? now < start : now - ts <= _freshMs;
      if (!live) continue;
      // Admin aralığı (dk): 0 = bir kez, N = her N dakikada bir tekrar
      final every = (_stars[uid]?['starEvery'] as num?)?.toInt() ?? 0;
      final last = _shown[d.id];
      if (last != null && (every <= 0 || now - last < every * 60000)) continue;
      if (_queue.any((q) => q.postId == d.id) || _cur?.postId == d.id) continue;
      _shown[d.id] = now;
      final city = (cp['city'] ?? '').toString();
      final type = (cp['type'] ?? '').toString();
      double amt = 0;
      try {
        amt = couponCost(cp);
      } catch (_) {}
      final name = (_stars[uid]?['name'] ?? m['authorName'] ?? '').toString();
      _queue.add(_Item(d.id, uid, name.isEmpty ? 'Kullanıcı' : name, [city, type].where((e) => e.isNotEmpty).join(' · '), amt));
    }
    _next();
  }

  Future<void> _next() async {
    if (_busy || _queue.isEmpty || !mounted) return;
    _busy = true;
    final it = _queue.removeAt(0);
    Profile? pr;
    try {
      pr = await AuthService.loadProfile(it.uid);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _cur = it;
      _curProfile = pr;
    });
    _ac.value = 0;
    await _ac.forward().orCancel.catchError((_) {});
    if (!mounted) return;
    setState(() => _cur = null);
    _busy = false;
    _next();
  }

  void _tap() {
    final it = _cur;
    if (it == null) return;
    feedTarget.value = FeedTarget(it.postId, 'coupon');
    _ac.stop();
    setState(() => _cur = null);
    _busy = false;
    _next();
  }

  @override
  Widget build(BuildContext context) {
    final it = _cur;
    if (it == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _ac,
      builder: (_, __) {
        final t = _ac.value;
        // 0-0.1 iner, 0.1-0.9 durur, 0.9-1 çıkar
        final inT = Curves.easeOutBack.transform((t / 0.1).clamp(0.0, 1.0));
        final outT = Curves.easeInCubic.transform(((t - 0.9) / 0.1).clamp(0.0, 1.0));
        final slide = (1 - inT) * -70 + outT * -70;
        final shine = ((t - 0.2) / 0.5).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, slide),
          child: Opacity(
            opacity: (1 - outT).clamp(0.0, 1.0),
            child: GestureDetector(
              onTap: _tap,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) < 0) _tap2();
              },
              child: _capsule(it, shine),
            ),
          ),
        );
      },
    );
  }

  // yukarı kaydırınca kapat (kupona gitmeden)
  void _tap2() {
    _ac.stop();
    setState(() => _cur = null);
    _busy = false;
    _next();
  }

  Widget _capsule(_Item it, double shine) {
    const gold = Color(0xFFFFC93C);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 36),
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        gradient: const LinearGradient(colors: [Color(0xFF0B1330), Color(0xFF16224A)]),
        border: Border.all(color: gold.withAlpha(70), width: 1),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        // üstten geçen parlama
        Positioned.fill(
          child: IgnorePointer(
            child: FractionallySizedBox(
              alignment: Alignment(-1.6 + shine * 3.6, 0),
              widthFactor: 0.25,
              child: Transform(
                transform: Matrix4.skewX(-0.35),
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0x00FFFFFF), Color(0x33FFFFFF), Color(0x00FFFFFF)]),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(5, 4, 7, 4),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(1.5),
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [gold, Color(0xFFFF9F1C)])),
              child: Avatar(profile: _curProfile, size: 32),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(11.5, FontWeight.w800, Colors.white)),
                const SizedBox(height: 0),
                Text(
                  it.label.isEmpty ? 'yeni kupon paylaştı' : 'yeni kupon paylaştı · ${it.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: jakarta(9, FontWeight.w600, const Color(0xFFB9C3E3)),
                ),
              ]),
            ),
            if (it.amount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(colors: [Color(0xFFFFD84D), Color(0xFFFFA928)]),
                ),
                child: Text(money(it.amount), style: jakarta(10.5, FontWeight.w800, const Color(0xFF3A2600))),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
