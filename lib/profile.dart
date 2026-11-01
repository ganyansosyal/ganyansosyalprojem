import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'admin.dart' show canManageUser, showUserAdminMenu, toggleBanUser, banActive;
import 'auth_service.dart';
import 'feed.dart';
import 'credits.dart' show Credits;
import 'scoring.dart';
import 'settle.dart' show isAdminNotifier;
import 'shell.dart' show IconBox;
import 'theme.dart';
import 'tjk.dart' show liveResTick;

FirebaseFirestore get _db => FirebaseFirestore.instance;
String get _me => profileNotifier.value?.uid ?? '';

class ProfileRoute extends StatelessWidget {
  final String uid;
  const ProfileRoute({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  IconBox(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  const Brand(size: 18),
                ],
              ),
            ),
            Expanded(child: ProfileView(uid: uid)),
          ],
        ),
      ),
    );
  }
}

class ProfileView extends StatefulWidget {
  final String uid;
  const ProfileView({super.key, required this.uid});

  @override
  State<ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends State<ProfileView> {
  final _subs = <StreamSubscription>[];
  Map<String, dynamic>? _u;
  Map<String, dynamic> _grant = {};
  List<Post> _posts = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _followers = [];
  String _tab = 'k';
  bool _loaded = false;
  bool _fbusy = false;
  bool _isMod = false;
  Map<String, dynamic>? _ban;
  final _gone = <String>{}; // silinmiş hesaplar (takip listesinde kalmış)
  final _checked = <String>{};
  bool? _fol; // takip butonu anında değişsin (sunucu cevabını beklemeden)
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _meStream = _db.collection('users').doc(_me).snapshots();

  @override
  void initState() {
    super.initState();
    liveResTick.addListener(_resTick);
    final uid = widget.uid;
    _subs.add(_db.collection('users').doc(uid).snapshots().listen((s) {
      setState(() {
        _u = s.data();
        _loaded = true;
      });
      _verifyFollowing();
    }));
    _subs.add(_db.collection('mods').doc(uid).snapshots().listen((s) {
      if (mounted) setState(() => _isMod = s.exists);
    }, onError: (_) {}));
    _subs.add(_db.collection('bans').doc(uid).snapshots().listen((s) {
      if (mounted) setState(() => _ban = s.data());
    }, onError: (_) {}));
    _subs.add(_db.collection('grants').doc(uid).snapshots().listen((s) {
      setState(() => _grant = s.data() ?? {});
    }, onError: (_) {}));
    _subs.add(_db.collection('posts').where('uid', isEqualTo: uid).limit(300).snapshots().listen((s) {
      final l = s.docs.map((d) => Post(d.id, d.data())).where((p) => !p.hidden).toList()
        ..sort((a, b) => b.ts.compareTo(a.ts));
      setState(() => _posts = l);
    }, onError: (_) {}));
    _subs.add(_db.collection('users').where('following', arrayContains: uid).limit(300).snapshots().listen(
      (s) => setState(() => _followers = s.docs),
      onError: (_) {},
    ));
  }

  void _resTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    liveResTick.removeListener(_resTick);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // Takip listesindeki kullanıcılar gerçekten var mı kontrol et; silinmişleri sayıdan ve listeden çıkar
  Future<void> _verifyFollowing() async {
    final ing = ((_u?['following'] as List?) ?? const []).map((e) => e.toString()).where((u) => !_checked.contains(u)).toList();
    if (ing.isEmpty) return;
    _checked.addAll(ing);
    var changed = false;
    await Future.wait(ing.map((u) async {
      try {
        final p = await AuthService.loadProfile(u);
        if (p == null) {
          _gone.add(u);
          changed = true;
        }
      } catch (_) {
        _checked.remove(u);
      }
    }));
    if (changed && mounted) setState(() {});
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _validFollowers {
    final rem = (_u?['remFol'] as Map?) ?? const {};
    return _followers.where((d) {
      if (d.id == widget.uid) return false;
      final r = (rem[d.id] as num?) ?? 0;
      final f = ((d.data()['fts'] as Map?)?[widget.uid] as num?) ?? 0;
      return r == 0 || f > r;
    }).toList();
  }

  Color _hexColor(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }
  Future<void> _edit() async {
  final p = Profile.fromMap(widget.uid, _u ?? {});
  final name = TextEditingController(text: p.name);
  final bio = TextEditingController(text: p.bio);
  String photo = p.photo;
  String bioColor = p.bioColor ?? '';
  final c = AppColors.of(context);
  const colors = ['', '#0E9F73', '#2563EB', '#7C3AED', '#DB2777', '#E0305A', '#EA580C', '#B87F00', '#0891B2'];

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true, // <-- STATUS BAR SORUNUNU ÇÖZEN SATIR
    backgroundColor: c.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _KbPad(child: StatefulBuilder(
      builder: (ctx, setS) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Profili Düzenle', style: jakarta(18, FontWeight.w800, c.tx)),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: Icon(Icons.close, color: c.tx)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Stack(
                      children: [
                        Avatar(profile: Profile(uid: p.uid, name: name.text, handle: p.handle, photo: photo), size: 72),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () async {
                              final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 320, maxHeight: 320, imageQuality: 70);
                              if (x == null) return;
                              final b = await x.readAsBytes();
                              setS(() => photo = 'data:image/jpeg;base64,${base64Encode(b)}');
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: c.ac, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2)),
                              child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Ad', style: jakarta(12, FontWeight.w700, c.mu)),
                const SizedBox(height: 4),
                TextField(
                  controller: name,
                  maxLength: nameMax,
                  style: jakarta(14, FontWeight.w600, c.tx),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.sf2,
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Kullanıcı adı', style: jakarta(12, FontWeight.w700, c.mu)),
                const SizedBox(height: 4),
                TextField(
                  controller: TextEditingController(text: '@${p.handle}'),
                  readOnly: true,
                  style: jakarta(14, FontWeight.w600, c.mu),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.sf2,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Biyografi', style: jakarta(12, FontWeight.w700, c.mu)),
                const SizedBox(height: 4),
                TextField(
                  controller: bio,
                  maxLength: 160,
                  maxLines: 3,
                  style: jakarta(14, FontWeight.w600, bioColor.isNotEmpty ? _hexColor(bioColor) : c.tx),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.sf2,
                    hintText: 'Kendinden kısaca bahset...',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: bio,
                    builder: (_, v, __) => Text('${v.text.length}/160', style: jakarta(11, FontWeight.w600, c.mu)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Biyografi yazı rengi', style: jakarta(12, FontWeight.w700, c.mu)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final col in colors)
                        GestureDetector(
                          onTap: () => setS(() => bioColor = col),
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: col.isEmpty ? null : _hexColor(col),
                              gradient: col.isEmpty ? const LinearGradient(colors: [Colors.black, Colors.grey], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
                              border: Border.all(color: bioColor == col ? c.ac : Colors.transparent, width: 2),
                            ),
                            child: bioColor == col ? Icon(Icons.circle, size: 12, color: col.isEmpty ? Colors.white : c.bg) : null,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(color: c.ln),
                        ),
                        child: Text('Vazgeç', style: jakarta(14, FontWeight.w800, c.mu)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          final n = name.text.trim();
                          if (n.length < 2) return;
                          try {
                            await _db.collection('users').doc(widget.uid).update({
                              'name': n,
                              'bio': bio.text.trim(),
                              'bioColor': bioColor,
                              'photo': photo,
                            });
                            profileNotifier.value = await AuthService.loadProfile(widget.uid);
                            if (ctx.mounted) Navigator.pop(ctx);
                          } catch (e) {
                            if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(AuthService.errorText(e))));
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: c.ac,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('Kaydet', style: jakarta(14, FontWeight.w800, c.on)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    )),
  );
  }
  void _people(int tab) {
  final c = AppColors.of(context);
  final fol = _validFollowers.map((e) => e.id).toList();
  final ing = ((_u?['following'] as List?) ?? const []).map((e) => e.toString()).where((u) => !_gone.contains(u)).toList();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (ctx) => _PeopleSheet(
      name: Profile.fromMap(widget.uid, _u ?? {}).name,
      followers: fol,
      following: ing,
      tab: tab,
      onOpen: (u) {
        Navigator.pop(ctx);
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileRoute(uid: u)));
      },
    ),
  );
}

@override
Widget build(BuildContext context) {
  final c = AppColors.of(context);
  if (!_loaded) return Center(child: CircularProgressIndicator(color: c.ac));
  if (_u == null) return Center(child: Text('Kullanıcı bulunamadı.', style: jakarta(13, FontWeight.w600, c.mu)));

  final p = Profile.fromMap(widget.uid, _u!);
  final mine = widget.uid == _me;
  final following = ((_u!['following'] as List?) ?? const []).map((e) => e.toString()).where((u) => !_gone.contains(u)).toList();
  final coupons = _posts.where((x) => x.coupon != null).toList();
  final shown = _tab == 'k' ? coupons.where((x) => postStatus(x) != 'win').toList() : _tab == 'w' ? coupons.where((x) => postStatus(x) == 'win').toList() : coupons.where((x) => postStatus(x) == 'lose').toList();
  final score = scoreOf(widget.uid, _posts, _u!['hist'] as Map?, ((_grant['pts'] as num?)?.toDouble() ?? 0) + ((_grant['keep'] as num?)?.toDouble() ?? 0));
  final fl = _validFollowers;
  final isAdmin = _u!['isAdmin'] == true;
  final canManage = !mine && canManageUser(widget.uid, targetAdmin: isAdmin, targetMod: _isMod);
  final banned = banActive(_ban);
  void openMenu() => showUserAdminMenu(context, uid: widget.uid, name: p.name, targetAdmin: isAdmin);

  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _meStream,
    builder: (context, ms) {
      final mf = ((ms.data?.data()?['following'] as List?) ?? const []).map((e) => e.toString()).toSet();
      final isFol = _fol ?? mf.contains(widget.uid);
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 186, // avatar/@kullanıcı adı ile altındaki butonlar arasında nefes payı
            child: Stack(children: [
          Positioned(top: 0, left: 0, right: 0, child: Container(
            height: 115,
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.ac.withAlpha(20),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.ac.withAlpha(40)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(left: -50, top: -60, child: Icon(Icons.waves, size: 220, color: c.ac.withAlpha(15))),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Ganyan', style: jakarta(30, FontWeight.w800, c.tx)),
                          TextSpan(text: 'Sosyal', style: jakarta(30, FontWeight.w800, c.ac)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(width: 44, height: 3, color: c.ac),
                    const SizedBox(height: 7),
                    Text('TAHMİN ET  •  PAYLAŞ  •  KAZAN', style: jakarta(9, FontWeight.w800, c.mu).copyWith(letterSpacing: 1.5)),
                  ],
                ),
              ],
            ),
          )),
          if (canManage)
            Positioned(
              top: 10,
              right: 22,
              child: GestureDetector(
                onTap: () => toggleBanUser(context, widget.uid, p.name),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: banned ? const Color(0xFFEF4444) : c.sf.withAlpha(200),
                    border: Border.all(color: const Color(0xFFEF4444).withAlpha(banned ? 255 : 100)),
                  ),
                  child: Icon(Icons.block, size: 17, color: banned ? Colors.white : const Color(0xFFEF4444)),
                ),
              ),
            ),
          Positioned(top: 75, left: 0, right: 0, child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: p.frame.isNotEmpty ? null : Border.all(color: c.bg, width: 4.5),
                      boxShadow: p.frame.isNotEmpty ? null : [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Avatar(profile: p, size: 80),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 44),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: canManage ? openMenu : null,
                            child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(20, FontWeight.w800, c.tx)),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: c.ac.withAlpha(20), borderRadius: BorderRadius.circular(9)),
                            child: Text('@${p.handle}', style: jakarta(12.5, FontWeight.w700, c.ac)),
                          ),
                          if (isAdminNotifier.value)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: StreamBuilder<int>(
                                stream: Credits.watch(widget.uid),
                                builder: (context, snap) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(color: c.gold.withAlpha(30), borderRadius: BorderRadius.circular(9)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.toll_rounded, size: 13, color: c.gold),
                                    const SizedBox(width: 4),
                                    Text('Kredi: ${snap.data ?? '...'}', style: jakarta(12, FontWeight.w800, c.gold)),
                                  ]),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
            ]),
          ),
          Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isAdmin || _isMod)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFDB2777)]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Color(0x40A855F7), blurRadius: 6, offset: Offset(0, 2))],
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(isAdmin ? Icons.lock_outline : Icons.block, size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(isAdmin ? 'Yönetici' : 'Moderatör', style: jakarta(11.5, FontWeight.w800, Colors.white)),
                          ]),
                        ),
                      ),
                    if (p.bio.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(p.bio, style: jakarta(13.5, FontWeight.w500, p.bioColor != null && p.bioColor!.isNotEmpty ? _hexColor(p.bioColor!) : c.tx)),
                      )
                    else if (mine)
                      GestureDetector(
                        onTap: _edit,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('+ Biyografi ekle', style: jakarta(13.5, FontWeight.w700, c.ac)),
                        ),
                      ),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: mine
                          ? OutlinedButton(
                              onPressed: _edit,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: c.sf,
                                side: BorderSide(color: c.ln),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.edit_outlined, size: 16, color: c.ac),
                                const SizedBox(width: 6),
                                Text('Profili Düzenle', style: jakarta(13.5, FontWeight.w800, c.ac)),
                              ]),
                            )
                          : FilledButton(
                              onPressed: () async {
                                if (_fbusy) return;
                                _fbusy = true;
                                final was = isFol;
                                setState(() => _fol = !was);
                                try {
                                  await toggleFollow(widget.uid, was);
                                } catch (e) {
                                  if (mounted) {
                                    final code = e is FirebaseException ? e.code : e.runtimeType.toString();
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AuthService.errorText(e)} ($code)')));
                                  }
                                } finally {
                                  _fbusy = false;
                                  if (mounted) setState(() => _fol = null);
                                }
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: isFol ? c.sf : c.ac,
                                side: isFol ? BorderSide(color: c.ln) : null,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (isFol) ...[Icon(Icons.check_rounded, size: 18, color: c.ac), const SizedBox(width: 6)],
                                Text(isFol ? 'Takip Ediliyor' : 'Takip Et', style: jakarta(13.5, FontWeight.w800, isFol ? c.ac : c.on)),
                              ]),
                            ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _stat(c, fmtPts(score.pts), 'Puan', null),
                        const SizedBox(width: 8),
                        _stat(c, '${coupons.length}', 'Kupon', null),
                        const SizedBox(width: 8),
                        _stat(c, '${fl.length}', 'Takipçi', () => _people(0)),
                        const SizedBox(width: 8),
                        _stat(c, '${following.length}', 'Takip', () => _people(1)),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
                      child: Row(
                        children: [
                          _tabBtn(c, 'k', 'Kuponlar'),
                          _tabBtn(c, 'w', 'Tutanlar'),
                          _tabBtn(c, 'l', 'Kaybedenler'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            _tab == 'k' ? 'Henüz paylaşılan kupon yok.' : _tab == 'w' ? 'Tutan kupon yok.' : 'Kaybeden kupon yok.',
                            textAlign: TextAlign.center,
                            style: jakarta(14, FontWeight.w600, c.mu),
                          ),
                        ),
                      ),
                    for (final x in shown) PostCard(key: ValueKey(x.id), post: x, following: mf.contains(x.uid)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _stat(AppColors c, String v, String l, VoidCallback? onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.ln)),
          child: Column(
            children: [
              Text(v, style: jakarta(16, FontWeight.w800, c.ac)),
              Text(l, style: jakarta(10.5, FontWeight.w600, c.mu)),
              if (onTap != null) Container(margin: const EdgeInsets.only(top: 3), width: 14, height: 2, color: c.ac.withAlpha(120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(AppColors c, String k, String label) {
    final on = _tab == k;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = k),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: on ? c.ac : Colors.transparent, borderRadius: BorderRadius.circular(11)),
          child: Text(label, textAlign: TextAlign.center, style: jakarta(12.5, FontWeight.w800, on ? c.on : c.mu)),
        ),
      ),
    );
  }
}

class PersonTile extends StatelessWidget {
  final String uid;
  final VoidCallback onOpen;
  const PersonTile({super.key, required this.uid, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return FutureBuilder<Profile?>(
      future: AuthService.loadProfile(uid),
      builder: (context, s) {
        final p = s.data;
        if (p == null) return const SizedBox(height: 48);
        return ListTile(
          onTap: onOpen,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          leading: Avatar(profile: p, size: 40),
          title: Text(p.name, style: jakarta(14, FontWeight.w800, c.tx)),
          subtitle: Text('@${p.handle}', style: jakarta(12, FontWeight.w600, c.mu)),
        );
      },
    );
  }
}


/// Instagram tarzı Takipçi / Takip listesi: sekmeler, arama, her satırda Takip Et / Takiptesin
class _PeopleSheet extends StatefulWidget {
  final String name;
  final List<String> followers, following;
  final int tab;
  final void Function(String uid) onOpen;
  const _PeopleSheet({required this.name, required this.followers, required this.following, required this.tab, required this.onOpen});
  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  late int _t = widget.tab;
  final _q = TextEditingController();
  final _prof = <String, Profile>{};
  final _opt = <String, bool>{};
  final _busy = <String>{};
  bool _ready = false;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _ms = _db.collection('users').doc(_me).snapshots();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final all = {...widget.followers, ...widget.following};
    await Future.wait(all.map((u) async {
      try {
        final p = await AuthService.loadProfile(u);
        if (p != null) _prof[u] = p;
      } catch (_) {}
    }));
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _fol(String u, bool was) async {
    if (_busy.contains(u)) return;
    _busy.add(u);
    setState(() => _opt[u] = !was);
    try {
      await toggleFollow(u, was);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AuthService.errorText(e))));
    } finally {
      _busy.remove(u);
      if (mounted) setState(() => _opt.remove(u));
    }
  }

  int _cnt(List<String> l) => _ready ? l.where((u) => _prof.containsKey(u)).length : l.length;

  Widget _tabBtn(AppColors c, int i, String label) {
    final on = _t == i;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _t = i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: on ? c.ac : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Text(label, textAlign: TextAlign.center, style: jakarta(13.5, FontWeight.w800, on ? c.on : c.mu)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final q = _q.text.trim().toLowerCase();
    final base = _t == 0 ? widget.followers : widget.following;
    final list = base.where((u) {
      final p = _prof[u];
      if (p == null) return false;
      return q.isEmpty || p.name.toLowerCase().contains(q) || p.handle.toLowerCase().contains(q);
    }).toList();
    // Yükseklik listeye göre: az kişi varsa kısa, çok kişi varsa en fazla %85 (aratınca zıplamasın diye filtresiz sayı)
    final sh = MediaQuery.sizeOf(context).height;
    final fr = ((230 + base.length * 70) / sh).clamp(0.42, 0.85).toDouble();
    return KbSheet(
      fraction: fr,
      child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(children: [
              Expanded(child: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(20, FontWeight.w800, c.tx))),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: c.sf2, shape: BoxShape.circle),
                  child: Icon(Icons.close, color: c.tx, size: 20),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
              child: Row(children: [
                _tabBtn(c, 0, '${_cnt(widget.followers)} Takipçi'),
                _tabBtn(c, 1, '${_cnt(widget.following)} Takip'),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _q,
              onChanged: (_) => setState(() {}),
              style: jakarta(14, FontWeight.w600, c.tx),
              decoration: InputDecoration(
                hintText: 'Ara',
                hintStyle: jakarta(14, FontWeight.w600, c.mu),
                prefixIcon: Icon(Icons.search, color: c.mu, size: 20),
                filled: true,
                fillColor: c.sf,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.ln)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.ln)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.ac)),
              ),
            ),
          ),
          Expanded(
            child: !_ready
                ? Center(child: CircularProgressIndicator(color: c.ac))
                : list.isEmpty
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Text(q.isNotEmpty ? 'Sonuç yok.' : (_t == 0 ? 'Henüz takipçi yok.' : 'Henüz kimse takip edilmiyor.'), style: jakarta(13.5, FontWeight.w600, c.mu)),
                        ),
                      )
                    : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _ms,
                        builder: (context, ms) {
                          final mReady = ms.hasData; // veri gelmeden "Takip Et" yazıp sonradan "Takiptesin"e dönmesin
                          final mf = ((ms.data?.data()?['following'] as List?) ?? const []).map((e) => e.toString()).toSet();
                          return ListView.builder(
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final u = list[i];
                              final p = _prof[u]!;
                              final isMe = u == _me;
                              final isFol = _opt[u] ?? mf.contains(u);
                              return InkWell(
                                onTap: () => widget.onOpen(u),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 10), // çerçeveli avatarın tacı üstteki satıra binmesin
                                  child: Row(children: [
                                    Avatar(profile: p, size: 48),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(15, FontWeight.w800, c.tx)),
                                        Text('@${p.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12.5, FontWeight.w600, c.mu)),
                                      ]),
                                    ),
                                    if (!isMe && !mReady) const SizedBox(width: 104, height: 44),
                                    if (!isMe && mReady) ...[
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () => _fol(u, isFol),
                                        child: Container(
                                          constraints: const BoxConstraints(minWidth: 96),
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isFol ? c.sf : c.ac,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(color: isFol ? c.ln : c.ac),
                                          ),
                                          child: Text(isFol ? 'Takiptesin' : 'Takip Et', style: jakarta(13.5, FontWeight.w800, isFol ? c.ac : c.on)),
                                        ),
                                      ),
                                    ],
                                  ]),
                                ),
                              );
                            },
                          );
                        },
                      ),
          ),
      ]),
    );
  }
}


/// Klavye boşluğunu sadece kendisi dinler; içindeki ağır form yeniden çizilmez, sheet'in üst kenarı sabit kalır (zıplama olmaz)
class _KbPad extends StatelessWidget {
  final Widget child;
  const _KbPad({required this.child});
  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.viewPaddingOf(context).bottom + 8;
    return SizedBox(
      height: double.infinity,
      child: Padding(padding: EdgeInsets.only(bottom: kb > safe ? kb : safe), child: child),
    );
  }
}
