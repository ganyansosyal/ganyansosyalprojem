import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'credits.dart';
import 'feed.dart' show Post, fmtStamp;
import 'frames.dart';
import 'profile.dart' show ProfileRoute;
import 'scoring.dart';
import 'settle.dart' show isAdminNotifier, isModNotifier;
import 'theme.dart';

/* =====================================================================
   YÖNETİM: panel, yasaklama, bakım modu, duyuru, çevrimiçi takibi
   (sitedeki js/08-admin.js ile aynı Firestore alanlarını kullanır)
   bans/{uid}            {until, reason, by, at, name, handle, deleted?}
   userMeta/{uid}        {email, name, handle, lastLogin, lastSeen, lastLogout}
   config/maintenance    {on, at, by}
   config/chat           {locked, at, by}
   shop/announce         {text, active, hours, until, at, by}
   grants/{uid}          {pts, at, note}
   mods/{uid}            {at, by, name}
   ===================================================================== */

int _now() => DateTime.now().millisecondsSinceEpoch;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

String _z(int n) => n.toString().padLeft(2, '0');

String _agoTxt(int ts) {
  if (ts <= 0) return '—';
  final d = _now() - ts;
  if (d < 60000) return 'az önce';
  if (d < 3600000) return '${d ~/ 60000} dk önce';
  if (d < 86400000) return '${d ~/ 3600000} sa önce';
  if (d < 7 * 86400000) return '${d ~/ 86400000} gün önce';
  return fmtStamp(ts);
}

String _leftTxt(int ms) => ms < 3600000
    ? '${math.max(1, (ms / 60000).ceil())} dk'
    : ms < 86400000
        ? '${(ms / 3600000).ceil()} sa'
        : '${(ms / 86400000).ceil()} gün';

bool banActive(Map? b) {
  if (b == null) return false;
  final u = b['until'];
  if (u is! num) return false;
  return u == 0 || u.toInt() > _now();
}

bool annLive(Map? a) => a != null && a['active'] == true && '${a['text'] ?? ''}'.isNotEmpty && _i(a['until']) > _now();

String _initials(String s) => (s.isEmpty ? '?' : s.substring(0, math.min(2, s.length))).toUpperCase();

String _err(Object e) {
  try {
    return AuthService.errorText(e);
  } catch (_) {
    return '$e';
  }
}

void _toast(BuildContext context, String text) {
  final ov = Overlay.maybeOf(context, rootOverlay: true);
  if (ov == null) return;
  late OverlayEntry e;
  e = OverlayEntry(
    builder: (ctx) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.viewInsetsOf(ctx).bottom + 90,
      child: IgnorePointer(
        child: Center(
          child: Material(
            color: const Color(0xEE111827),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Text(text, textAlign: TextAlign.center, style: jakarta(13.5, FontWeight.w700, Colors.white)),
            ),
          ),
        ),
      ),
    ),
  );
  ov.insert(e);
  Future.delayed(const Duration(milliseconds: 2600), () {
    try {
      e.remove();
    } catch (_) {}
  });
}

Future<void> _ask(BuildContext context, String title, String text, String ok, VoidCallback onOk, {bool danger = false}) async {
  final c = AppColors.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.sf,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(title, style: jakarta(17, FontWeight.w800, c.tx)),
      content: Text(text, style: jakarta(13.5, FontWeight.w500, c.mu)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Vazgeç', style: jakarta(14, FontWeight.w800, c.mu))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok, style: jakarta(14, FontWeight.w800, danger ? c.red : c.ac))),
      ],
    ),
  );
  if (r == true) onOk();
}

/* ---------------- Çevrimiçi takibi ---------------- */

class Presence {
  static Timer? _t;
  static String? _uid;
  static final _db = FirebaseFirestore.instance;

  static Future<void> _meta(String uid, Map<String, dynamic> extra) async {
    final u = FirebaseAuth.instance.currentUser;
    final p = profileNotifier.value;
    final d = <String, dynamic>{'email': u?.email ?? ''};
    if (p != null && p.uid == uid) {
      d['name'] = p.name;
      d['handle'] = p.handle.replaceFirst(RegExp(r'^@'), '');
    }
    d.addAll(extra);
    try {
      await _db.collection('userMeta').doc(uid).set(d, SetOptions(merge: true));
    } catch (_) {}
  }

  static void start(String uid) {
    if (_uid == uid) return;
    stop();
    _uid = uid;
    final u = FirebaseAuth.instance.currentUser;
    final li = u?.metadata.lastSignInTime?.millisecondsSinceEpoch ?? _now();
    _meta(uid, {'lastLogin': li, 'lastSeen': _now()});
    _t = Timer.periodic(const Duration(minutes: 2), (_) => _meta(uid, {'lastSeen': _now()}));
  }

  static void touch() {
    final uid = _uid;
    if (uid != null) _meta(uid, {'lastSeen': _now()});
  }

  static void stop() {
    _t?.cancel();
    _t = null;
    _uid = null;
  }

  static Future<void> logout() async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    stop();
    if (uid == null) return;
    await _meta(uid, {'lastLogout': _now()});
  }
}

/* ---------------- Yasak + bakım kapısı ---------------- */

class AccessGate extends StatefulWidget {
  final String uid;
  final Widget child;
  const AccessGate({super.key, required this.uid, required this.child});
  @override
  State<AccessGate> createState() => _AccessGateState();
}

class _AccessGateState extends State<AccessGate> with WidgetsBindingObserver {
  final _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _subs = [];
  Map<String, dynamic>? _ban, _maint;
  bool _banKnown = false, _adminKnown = false, _admin = false, _adminDoc = false, _adminFlag = false;
  Timer? _tick, _fallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final uid = widget.uid;
    _subs.add(_db.collection('bans').doc(uid).snapshots().listen((s) {
      if (!mounted) return;
      setState(() {
        _ban = s.data();
        _banKnown = true;
      });
    }, onError: (_) {
      if (mounted) setState(() => _banKnown = true);
    }));
    _subs.add(_db.collection('config').doc('maintenance').snapshots().listen((s) {
      if (mounted) setState(() => _maint = s.data());
    }, onError: (_) {
      if (mounted) setState(() => _maint = null); // okunamazsa siteyi kapatma
    }));
    _subs.add(_db.collection('users').doc(uid).snapshots().listen((s) {
      if (!mounted) return;
      setState(() {
        _adminFlag = s.data()?['isAdmin'] == true;
        _admin = _adminFlag || _adminDoc;
        _adminKnown = true;
      });
    }, onError: (_) {
      if (mounted) setState(() => _adminKnown = true);
    }));
    _db.collection('admins').doc(uid).get().then((d) {
      if (!mounted) return;
      setState(() {
        _adminDoc = d.exists;
        _admin = _adminFlag || _adminDoc;
      });
    }).catchError((_) {});
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _ban != null) setState(() {});
    });
    _fallback = Timer(const Duration(seconds: 6), () {
      if (mounted && (!_banKnown || !_adminKnown)) setState(() => _banKnown = _adminKnown = true);
    });
    Presence.start(uid);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Presence.touch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      s.cancel();
    }
    _tick?.cancel();
    _fallback?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (!_banKnown) {
      return Scaffold(backgroundColor: c.bg, body: Center(child: CircularProgressIndicator(color: c.ac)));
    }
    if (banActive(_ban)) return BannedScreen(ban: _ban!);
    final maintOn = _maint?['on'] == true;
    if (maintOn && !_admin) {
      if (!_adminKnown) return Scaffold(backgroundColor: c.bg, body: Center(child: CircularProgressIndicator(color: c.ac)));
      return const MaintenanceScreen();
    }
    return Stack(children: [
      widget.child,
      if (maintOn && _admin)
        Positioned(
          left: 0,
          right: 0,
          bottom: 84 + MediaQuery.paddingOf(context).bottom,
          child: Center(
            child: Material(
              color: c.red,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => showAdminPanel(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.build_circle_outlined, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text('Bakım modu açık', style: jakarta(12.5, FontWeight.w800, Colors.white)),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

class BannedScreen extends StatefulWidget {
  final Map<String, dynamic> ban;
  const BannedScreen({super.key, required this.ban});
  @override
  State<BannedScreen> createState() => _BannedScreenState();
}

class _BannedScreenState extends State<BannedScreen> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  String _countdown(int until) {
    final ms = until - _now();
    if (ms <= 0) return 'Süre doldu';
    final t = ms ~/ 1000;
    final d = t ~/ 86400, h = t % 86400 ~/ 3600, m = t % 3600 ~/ 60, s = t % 60;
    return '${d > 0 ? '$d gün ' : ''}${_z(h)}:${_z(m)}:${_z(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final b = widget.ban;
    final perm = _i(b['until']) == 0;
    final why = '${b['reason'] ?? ''}'.trim();
    Widget row(String l, String v, {Color? vc}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Text(l, style: jakarta(13.5, FontWeight.w600, c.mu)),
            const Spacer(),
            Text(v, style: jakarta(13.5, FontWeight.w800, vc ?? c.tx)),
          ]),
        );
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
                decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(26), border: Border.all(color: c.ln)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 78,
                    height: 78,
                    decoration: BoxDecoration(color: c.red.withAlpha(30), shape: BoxShape.circle),
                    child: Icon(Icons.block, size: 40, color: c.red),
                  ),
                  const SizedBox(height: 16),
                  Text('Hesabın askıya alındı', textAlign: TextAlign.center, style: jakarta(21, FontWeight.w800, c.tx)),
                  const SizedBox(height: 8),
                  Text(why.isNotEmpty ? 'Sebep: $why' : 'Hesabın yönetici tarafından kısıtlandı.', textAlign: TextAlign.center, style: jakarta(14, FontWeight.w600, c.mu)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
                    child: Column(children: [
                      row('Durum', 'Askıda', vc: c.red),
                      if (!perm) row('Kalan süre', _countdown(_i(b['until']))),
                      row(perm ? 'Yasak' : 'Yasak bitişi', perm ? 'Kalıcı' : fmtStamp(_i(b['until']))),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: c.ac, foregroundColor: c.on, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      onPressed: AuthService.signOut,
                      child: Text('Çıkış Yap', style: jakarta(15, FontWeight.w800, c.on)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Bir hata olduğunu düşünüyorsan yönetici ile iletişime geç.', textAlign: TextAlign.center, style: jakarta(12, FontWeight.w500, c.mu)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0E7A5A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.3), radius: 1.1, colors: [Color(0xFF15A077), Color(0xFF0E7A5A), Color(0xFF07523D)], stops: [0, .5, 1]),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                RichText(
                  text: TextSpan(style: jakarta(26, FontWeight.w800, Colors.white), children: [
                    const TextSpan(text: 'Ganyan'),
                    TextSpan(text: 'Sosyal', style: jakarta(26, FontWeight.w800, const Color(0xFFA7F3D0))),
                  ]),
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                  decoration: BoxDecoration(color: Colors.white.withAlpha(28), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white.withAlpha(50))),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.settings, size: 50, color: Color(0xFF0E7A5A)),
                    ),
                    const SizedBox(height: 20),
                    Text('Bakımdayız', style: jakarta(24, FontWeight.w800, Colors.white)),
                    const SizedBox(height: 10),
                    Text("GanyanSosyal'i senin için daha iyi hale getiriyoruz. Birazdan yepyeni bir deneyimle tekrar buradayız.",
                        textAlign: TextAlign.center, style: jakarta(14, FontWeight.w500, Colors.white.withAlpha(220))),
                    const SizedBox(height: 18),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: const LinearProgressIndicator(minHeight: 6, color: Color(0xFFFBBF24), backgroundColor: Color(0x33FFFFFF)),
                    ),
                    const SizedBox(height: 12),
                    Text('Güncelleme yapılıyor', style: jakarta(13, FontWeight.w700, Colors.white)),
                  ]),
                ),
                const SizedBox(height: 16),
                Text('Bakım bitince uygulama kendiliğinden açılır.', style: jakarta(12.5, FontWeight.w600, Colors.white.withAlpha(200))),
                const SizedBox(height: 14),
                TextButton(onPressed: AuthService.signOut, child: Text('Çıkış yap', style: jakarta(13, FontWeight.w800, Colors.white))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------------- Duyuru şeridi (kayan yazı) ---------------- */

class AnnounceTicker extends StatefulWidget {
  const AnnounceTicker({super.key});
  @override
  State<AnnounceTicker> createState() => _AnnounceTickerState();
}

class _AnnounceTickerState extends State<AnnounceTicker> {
  StreamSubscription? _s;
  Map<String, dynamic>? _a;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _s = FirebaseFirestore.instance.collection('shop').doc('announce').snapshots().listen((s) {
      if (mounted) setState(() => _a = s.data());
    }, onError: (_) {});
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _s?.cancel();
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!annLive(_a)) return const SizedBox.shrink();
    final text = '${_a!['text']}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 34,
          color: const Color(0xFFDC2626),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: const Color(0x33000000),
              alignment: Alignment.center,
              child: Text('📢 DUYURU', style: jakarta(11, FontWeight.w800, Colors.white, ls: 0.4)),
            ),
            Expanded(child: _Marquee(text: text, style: jakarta(13, FontWeight.w700, Colors.white))),
          ]),
        ),
      ),
    );
  }
}

class _Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  const _Marquee({required this.text, required this.style});
  @override
  State<_Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<_Marquee> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      final tp = TextPainter(text: TextSpan(text: widget.text, style: widget.style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
      const gap = 60.0;
      final w = tp.width + gap;
      final secs = math.max(10, (w / 60).round());
      if (_c.duration?.inSeconds != secs) {
        _c.duration = Duration(seconds: secs);
        _c.repeat();
      }
      final n = (cons.maxWidth / w).ceil() + 2;
      return ClipRect(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            child: Transform.translate(
              offset: Offset(-_c.value * w, 0),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < n; i++)
                  Padding(padding: const EdgeInsets.only(right: gap), child: Text(widget.text, maxLines: 1, softWrap: false, style: widget.style)),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

/* ---------------- Yönetim paneli ---------------- */

Future<void> showAdminPanel(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AdminSheet(),
  );
}

class _AdminSheet extends StatefulWidget {
  const _AdminSheet();
  @override
  State<_AdminSheet> createState() => _AdminSheetState();
}

class _AdminSheetState extends State<_AdminSheet> {
  final _db = FirebaseFirestore.instance;
  final List<StreamSubscription> _subs = [];
  Map<String, Map<String, dynamic>> _users = {}, _meta = {}, _bans = {}, _mods = {};
  Map<String, dynamic>? _maint, _chat, _ann;
  String _f = 'all', _q = '';
  Timer? _tick, _deb;
  final _search = TextEditingController();
  final _annT = TextEditingController();
  final _annH = TextEditingController(text: '3');
  bool _annTouched = false, _annHTouched = false, _loaded = false;

  String get _me => profileNotifier.value?.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    Map<String, Map<String, dynamic>> toMap(QuerySnapshot<Map<String, dynamic>> s) => {for (final d in s.docs) d.id: d.data()};
    void listen<T>(Stream<T> st, void Function(T) f) => _subs.add(st.listen((v) {
          if (mounted) setState(() => f(v));
        }, onError: (e) {
          if (mounted) _toast(context, _err(e));
        }));
    listen(_db.collection('users').limit(500).snapshots(), (s) {
      _users = toMap(s);
      _loaded = true;
    });
    listen(_db.collection('userMeta').limit(500).snapshots(), (s) => _meta = toMap(s));
    listen(_db.collection('bans').limit(500).snapshots(), (s) => _bans = toMap(s));
    listen(_db.collection('mods').limit(100).snapshots(), (s) => _mods = toMap(s));
    listen(_db.collection('config').doc('maintenance').snapshots(), (s) => _maint = s.data());
    listen(_db.collection('config').doc('chat').snapshots(), (s) => _chat = s.data());
    listen(_db.collection('shop').doc('announce').snapshots(), (s) {
      _ann = s.data();
      if (!_annTouched) _annT.text = '${_ann?['text'] ?? ''}';
      if (!_annHTouched && _ann?['hours'] != null) _annH.text = '${_ann!['hours']}';
    });
    _tick = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _tick?.cancel();
    _deb?.cancel();
    _search.dispose();
    _annT.dispose();
    _annH.dispose();
    super.dispose();
  }

  // ---- işlemler ----

  void _maintToggle() {
    final on = _maint?['on'] == true;
    _ask(
      context,
      on ? 'Bakım modu kapatılsın mı?' : 'Site bakıma alınsın mı?',
      on ? 'Uygulama herkese yeniden açılır.' : 'Sen hariç herkese bakım ekranı gösterilir, kimse giriş yapamaz. Kapatana kadar böyle kalır.',
      on ? 'Bakımı kapat' : 'Bakıma al',
      () => _db
          .collection('config')
          .doc('maintenance')
          .set({'on': !on, 'at': _now(), 'by': _me})
          .then((_) => _toast(context, on ? 'Uygulama herkese açıldı ✓' : 'Uygulama bakıma alındı 🛠'))
          .catchError((e) => _toast(context, _err(e))),
    );
  }

  void _chatToggle() {
    final on = _chat?['locked'] == true;
    _ask(
      context,
      on ? 'Sohbet kilidi açılsın mı?' : 'Genel sohbet kilitlensin mi?',
      on ? 'Herkes yeniden mesaj yazabilir.' : 'Sen hariç kimse mesaj yazamaz, mesajlar okunmaya devam eder. Açana kadar böyle kalır.',
      on ? 'Kilidi aç' : 'Kilitle',
      () => _db
          .collection('config')
          .doc('chat')
          .set({'locked': !on, 'at': _now(), 'by': _me})
          .then((_) => _toast(context, on ? 'Sohbet açıldı ✓' : 'Sohbet kilitlendi 🔒'))
          .catchError((e) => _toast(context, _err(e))),
    );
  }

  Future<void> _annPublish() async {
    final text = _annT.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final h = double.tryParse(_annH.text.trim().replaceAll(',', '.'));
    if (text.isEmpty) return _toast(context, 'Duyuru metni yaz.');
    if (h == null || h <= 0 || h > 720) return _toast(context, 'Süre 0 ile 720 saat arasında olmalı.');
    try {
      await _db.collection('shop').doc('announce').set({
        'text': text.length > 300 ? text.substring(0, 300) : text,
        'active': true,
        'hours': h,
        'until': _now() + (h * 3600000).round(),
        'at': _now(),
        'by': _me,
      });
      _annTouched = false;
      if (mounted) _toast(context, '📢 Duyuru yayında');
    } catch (e) {
      if (mounted) _toast(context, _err(e));
    }
  }

  Future<void> _annStop() async {
    try {
      await _db.collection('shop').doc('announce').update({'active': false});
      if (mounted) _toast(context, 'Duyuru durduruldu');
    } catch (e) {
      if (mounted) _toast(context, _err(e));
    }
  }

  void _unban(String uid) {
    final u = _users[uid] ?? {};
    _ask(context, 'Yasağı kaldır', '${u['name'] ?? 'Kullanıcı'} için yasak kaldırılsın mı?', 'Kaldır',
        () => _db.collection('bans').doc(uid).delete().then((_) => _toast(context, 'Yasak kaldırıldı')).catchError((e) => _toast(context, _err(e))));
  }

  void _restore(String uid) {
    final b = _bans[uid] ?? {};
    _ask(
      context,
      'Yasağı kaldır: ${b['name'] ?? 'Kullanıcı'}',
      'Silinen hesabın kalıcı yasağı kaldırılır. Kullanıcı aynı e-posta ve şifreyle tekrar girebilir; yeni, boş bir profil açılır (eski paylaşımlar ve puanlar geri gelmez).',
      'Yasağı kaldır',
      () => _db.collection('bans').doc(uid).delete().then((_) => _toast(context, '${b['name'] ?? 'Kullanıcı'} tekrar girebilir')).catchError((e) => _toast(context, _err(e))),
    );
  }

  Future<void> _ban(String uid) async {
    final u = _users[uid] ?? {};
    final c = AppColors.of(context);
    const opts = [('1 Saat', 3600000), ('1 Gün', 86400000), ('7 Gün', 7 * 86400000), ('30 Gün', 30 * 86400000), ('Kalıcı', 0)];
    var dur = 86400000;
    var delPosts = false;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: c.sf,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text('Yasakla: ${u['name'] ?? ''}', textAlign: TextAlign.center, style: jakarta(17, FontWeight.w800, c.tx)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Text('Yasak süresi', style: jakarta(13.5, FontWeight.w600, c.mu))),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in opts) _chip(c, o.$1, dur == o.$2, () => setS(() => dur = o.$2)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: reason,
                maxLength: 120,
                style: jakarta(14, FontWeight.w600, c.tx),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Sebep (isteğe bağlı)',
                  hintStyle: jakarta(14, FontWeight.w500, c.mu),
                  filled: true,
                  fillColor: c.sf2,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                activeColor: c.ac,
                value: delPosts,
                onChanged: (v) => setS(() => delPosts = v == true),
                title: Text('Paylaşımlarını da sil', style: jakarta(13.5, FontWeight.w700, c.tx)),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Vazgeç', style: jakarta(14, FontWeight.w800, c.mu))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Yasakla', style: jakarta(14, FontWeight.w800, c.red))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await _db.collection('bans').doc(uid).set({
        'until': dur == 0 ? 0 : _now() + dur,
        'reason': reason.text.trim(),
        'by': _me,
        'at': _now(),
        'name': u['name'] ?? '',
        'handle': u['handle'] ?? '',
      });
      if (delPosts) {
        final q = await _db.collection('posts').where('uid', isEqualTo: uid).get();
        if (q.docs.isNotEmpty) {
          final b = _db.batch();
          for (final d in q.docs) {
            b.delete(d.reference);
          }
          await b.commit();
        }
      }
      if (mounted) _toast(context, '${u['name'] ?? 'Kullanıcı'} yasaklandı');
    } catch (e) {
      if (mounted) _toast(context, _err(e));
    }
  }

  void _delete(String uid) {
    if (uid == _me) return;
    final u = _users[uid] ?? {};
    final name = '${u['name'] ?? 'Kullanıcı'}';
    _ask(
      context,
      'Hesabı sil: $name',
      'Profili, kullanıcı adı, paylaşımları, yorumları, beğenileri, sohbet mesajları, bildirimleri ve takip kayıtları silinir. Aynı hesapla bir daha giriş yapamaz. Bu işlem geri alınamaz. Emin misin?',
      'Hesabı sil',
      () async {
        try {
          final ops = <_Op>[];
          final seen = <String>{};
          void del(DocumentReference r) {
            if (seen.add(r.path)) ops.add(_Op.del(r));
          }

          // 0) önce yasak kaydı: işlem yarıda kesilse bile hesap hemen kapanır
          ops.add(_Op.set(_db.collection('bans').doc(uid), {
            'until': 0,
            'reason': 'Hesap yönetici tarafından silindi',
            'deleted': true,
            'by': _me,
            'at': _now(),
            'name': u['name'] ?? '',
            'handle': u['handle'] ?? '',
          }));
          // 1) paylaşımlar + başkalarının kuponlarındaki yorum ve beğeniler
          for (final d in (await _db.collection('posts').get()).docs) {
            final r = d.data();
            if ('${r['uid']}' == uid) {
              del(d.reference);
              continue;
            }
            final x = <String, dynamic>{};
            final cm = ((r['comments'] as List?) ?? const []);
            if (cm.any((e) => e is Map && e['uid'] == uid)) x['comments'] = cm.where((e) => !(e is Map && e['uid'] == uid)).toList();
            final lk = ((r['likedBy'] as List?) ?? const []);
            if (lk.contains(uid)) x['likedBy'] = lk.where((e) => e != uid).toList();
            if (x.isNotEmpty) ops.add(_Op.upd(d.reference, x));
          }
          // 2) sohbet mesajları ve bildirimler
          for (final q in [
            _db.collection('chat').where('uid', isEqualTo: uid),
            _db.collection('notifs').where('from', isEqualTo: uid),
            _db.collection('notifs').where('to', isEqualTo: uid),
          ]) {
            for (final d in (await q.get()).docs) {
              del(d.reference);
            }
          }
          final h = '${u['handle'] ?? ''}'.replaceFirst(RegExp(r'^@'), '').toLowerCase();
          if (h.isNotEmpty) del(_db.collection('handles').doc(h));
          // 3) diğer kullanıcıların takip listesi
          for (final d in (await _db.collection('users').get()).docs) {
            if (d.id == uid) continue;
            final fl = ((d.data()['following'] as List?) ?? const []);
            if (fl.contains(uid)) {
              ops.add(_Op.upd(d.reference, {'following': FieldValue.arrayRemove([uid]), 'fts.$uid': FieldValue.delete()}));
            }
          }
          // 4) profil ve yan kayıtlar
          for (final c in ['userMeta', 'grants', 'mods', 'users']) {
            del(_db.collection(c).doc(uid));
          }
          for (var i = 0; i < ops.length; i += 400) {
            final b = _db.batch();
            for (final o in ops.skip(i).take(400)) {
              if (o.kind == 0) {
                b.set(o.ref, o.data!);
              } else if (o.kind == 1) {
                b.update(o.ref, o.data!);
              } else {
                b.delete(o.ref);
              }
            }
            await b.commit();
          }
          if (mounted) _toast(context, '$name hesabı ve tüm verileri silindi');
        } catch (e) {
          if (mounted) _toast(context, _err(e));
        }
      },
      danger: true,
    );
  }

  // ---- arayüz ----

  Widget _chip(AppColors c, String label, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(color: on ? c.ac : Colors.transparent, borderRadius: BorderRadius.circular(14)),
          child: Text(label, style: jakarta(14, FontWeight.w800, on ? c.on : c.mu)),
        ),
      );

  Widget _toggleCard(AppColors c, String emoji, String title, String badge, bool on, String sub, String btn, VoidCallback tap) {
    final bg = on ? Color.alphaBlend(c.red.withAlpha(23), c.sf) : c.sf2;
    final bd = on ? Color.alphaBlend(c.red.withAlpha(115), c.ln) : c.ln;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: bd)),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: (on ? c.red : c.ac).withAlpha(36), borderRadius: BorderRadius.circular(13)),
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 7, children: [
              Text(title, style: jakarta(14, FontWeight.w800, c.tx)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: on ? c.red : c.ac, borderRadius: BorderRadius.circular(99)),
                child: Text(badge, style: jakarta(10.5, FontWeight.w800, on ? Colors.white : c.on)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(sub, style: jakarta(11.5, FontWeight.w600, c.mu)),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: on ? c.ac : null,
              gradient: on ? null : const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(btn, style: jakarta(12.5, FontWeight.w800, on ? c.on : Colors.white)),
          ),
        ),
      ]),
    );
  }

  Widget _annCard(AppColors c) {
    final on = annLive(_ann);
    final field = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: c.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ac)),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('📢 Duyuru', style: jakarta(14, FontWeight.w800, c.tx)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: on ? const Color(0xFFDC2626) : c.mu.withAlpha(204), borderRadius: BorderRadius.circular(99)),
            child: Text(on ? 'Yayında' : 'Kapalı', style: jakarta(10.5, FontWeight.w800, Colors.white)),
          ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _annT,
          maxLength: 300,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => _annTouched = true,
          style: jakarta(14, FontWeight.w500, c.tx),
          decoration: field.copyWith(hintText: 'Kayan yazıda görünecek duyuru…', hintStyle: jakarta(14, FontWeight.w500, c.mu), counterText: ''),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('Süre (saat)', style: jakarta(12, FontWeight.w800, c.mu)),
          SizedBox(
            width: 72,
            child: TextField(
              controller: _annH,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => _annHTouched = true,
              style: jakarta(14, FontWeight.w700, c.tx),
              decoration: field,
            ),
          ),
          for (final n in [1, 3, 6, 12, 24])
            GestureDetector(
              onTap: () => setState(() {
                _annH.text = '$n';
                _annHTouched = true;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.ln)),
                child: Text('$n sa', style: jakarta(12, FontWeight.w800, c.tx)),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _annPublish,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFB91C1C), Color(0xFFEF4444)]), borderRadius: BorderRadius.circular(12)),
                child: Text(on ? 'Güncelle ve yayınla' : 'Yayınla', style: jakarta(14, FontWeight.w800, Colors.white)),
              ),
            ),
          ),
          if (on) ...[
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: _annStop,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(12)),
                  child: Text('Durdur', style: jakarta(14, FontWeight.w800, Colors.white)),
                ),
              ),
            ),
          ],
        ]),
        if (on) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Kalan süre: ${_leftTxt(_i(_ann!['until']) - _now())}', style: jakarta(12, FontWeight.w700, c.mu))),
      ]),
    );
  }

  Widget _pill(AppColors c, String t, Color col) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: col.withAlpha(38), borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: jakarta(10.5, FontWeight.w800, col)),
      );

  Widget _kv(AppColors c, String k, String v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(), style: jakarta(10, FontWeight.w800, c.mu, ls: 0.3)),
          const SizedBox(height: 1),
          Text(v, style: jakarta(12.5, FontWeight.w700, c.tx)),
        ]),
      );

  Widget _btn(AppColors c, String t, VoidCallback tap, {Color? bg, Color? fg, Color? border}) => Expanded(
        child: GestureDetector(
          onTap: tap,
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg ?? c.sf2, borderRadius: BorderRadius.circular(11), border: Border.all(color: border ?? bg ?? c.ln, width: 1.5)),
            child: Text(t, style: jakarta(12.5, FontWeight.w800, fg ?? c.tx)),
          ),
        ),
      );

  Widget _giftBtn(AppColors c, String uid, String name, bool targetAdmin) => GestureDetector(
        onTap: () => showDialog(context: context, builder: (_) => _GiftDialog(uid: uid, name: name, targetAdmin: targetAdmin, parent: context)),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFFDB2777)]), borderRadius: BorderRadius.circular(11)),
          child: Text('🎁 Puan / Hediye çerçeve', style: jakarta(12.5, FontWeight.w800, Colors.white)),
        ),
      );

  Widget _userRow(AppColors c, Map<String, dynamic> x) {
    final uid = x['uid'] as String;
    final u = x['u'] as Map<String, dynamic>;
    final m = x['m'] as Map<String, dynamic>;
    final b = x['b'] as Map<String, dynamic>?;
    final ba = x['ba'] as bool, on = x['on'] as bool;
    final me = uid == _me;
    final now = _now();
    Widget? pill;
    if (ba) {
      pill = _pill(c, _i(b!['until']) == 0 ? 'Kalıcı yasak' : '${_leftTxt(_i(b['until']) - now)} yasak', c.red);
    } else if (on) {
      pill = _pill(c, 'Çevrimiçi', c.ac);
    }
    final bg = ba ? Color.alphaBlend(c.red.withAlpha(13), c.sf) : c.sf;
    final bd = ba ? Color.alphaBlend(c.red.withAlpha(115), c.ln) : c.ln;
    final name = '${u['name'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: bd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () {
              final nav = Navigator.of(context);
              nav.pop(); // yönetim panelini kapat
              nav.push(MaterialPageRoute(builder: (_) => ProfileRoute(uid: uid)));
            },
            child: Avatar(profile: Profile.fromMap(uid, u), size: 50),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: me
                    ? null
                    : () => showUserAdminMenu(context, uid: uid, name: name, targetAdmin: u['isAdmin'] == true, onProfile: () {
                          final nav = Navigator.of(context);
                          nav.pop();
                          nav.push(MaterialPageRoute(builder: (_) => ProfileRoute(uid: uid)));
                        }),
                child: Text('$name${me ? ' (sen)' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(16, FontWeight.w800, c.tx)),
              ),
              Text('@${u['handle'] ?? ''}${'${m['email'] ?? ''}'.isNotEmpty ? ' · ${m['email']}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13, FontWeight.w600, c.mu)),
            ]),
          ),
          if (pill != null) pill,
        ]),
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          padding: const EdgeInsets.only(top: 9),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
          child: Column(children: [
            Row(children: [
              _kv(c, 'Kayıt', _i(u['createdAt']) > 0 ? fmtStamp(_i(u['createdAt'])) : '—'),
              _kv(c, 'Son giriş', _agoTxt(_i(m['lastLogin']))),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              _kv(c, 'Son görülme', on ? 'Şu an' : _agoTxt(_i(m['lastSeen']))),
              _kv(c, 'Son çıkış', _agoTxt(_i(m['lastLogout']))),
            ]),
          ]),
        ),
        if (ba && '${b!['reason'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('Sebep: ${b['reason']}', style: jakarta(12, FontWeight.w700, c.red))),
        if (!me)
          Row(children: [
            ba ? _btn(c, 'Yasağı kaldır', () => _unban(uid), bg: c.ac, fg: c.on) : _btn(c, 'Yasakla', () => _ban(uid), bg: c.red, fg: Colors.white),
            const SizedBox(width: 8),
            _btn(c, 'Hesabı sil', () => _delete(uid), bg: Colors.transparent, fg: c.red, border: c.red),
          ]),
        Padding(padding: const EdgeInsets.only(top: 8), child: _giftBtn(c, uid, name.isEmpty ? 'Kullanıcı' : name, u['isAdmin'] == true)),
      ]),
    );
  }

  Widget _deletedRow(AppColors c, String uid, Map<String, dynamic> b) {
    final name = '${b['name'] ?? 'Kullanıcı'}';
    final h = '${b['handle'] ?? ''}'.replaceFirst(RegExp(r'^@'), '');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: Color.alphaBlend(c.red.withAlpha(13), c.sf), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color.alphaBlend(c.red.withAlpha(115), c.ln))),
      child: Column(children: [
        Row(children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.sf2, shape: BoxShape.circle),
            child: Text(_initials(name), style: jakarta(15, FontWeight.w800, c.mu)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(16, FontWeight.w800, c.tx)),
              Text('${h.isNotEmpty ? '@$h · ' : ''}silindi ${_agoTxt(_i(b['at']))}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13, FontWeight.w600, c.mu)),
            ]),
          ),
          _pill(c, 'Silinmiş', c.red),
        ]),
        const SizedBox(height: 10),
        Row(children: [_btn(c, 'Yasağı kaldır · tekrar girebilsin', () => _restore(uid), bg: c.ac, fg: c.on)]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final now = _now();
    final all = _users.keys.map((uid) {
      final m = _meta[uid] ?? <String, dynamic>{};
      final b = _bans[uid];
      final ls = _i(m['lastSeen']);
      return <String, dynamic>{
        'uid': uid,
        'u': _users[uid]!,
        'm': m,
        'b': b,
        'ba': banActive(b),
        'on': ls > 0 && now - ls < 240000 && _i(m['lastLogout']) < ls,
        'seen': ls > 0 ? ls : _i(m['lastLogin']),
      };
    }).toList();
    final q = _q.trim().toLowerCase();
    bool hit(List<dynamic> f) => q.isEmpty || f.any((t) => '${t ?? ''}'.toLowerCase().contains(q));
    var list = all.where((x) => hit([(x['u'] as Map)['name'], (x['u'] as Map)['handle'], (x['m'] as Map)['email']])).toList();
    if (_f == 'on') list = list.where((x) => x['on'] == true).toList();
    if (_f == 'ban') list = list.where((x) => x['ba'] == true).toList();
    list.sort((a, b) {
      final o = ((b['on'] as bool) ? 1 : 0) - ((a['on'] as bool) ? 1 : 0);
      if (o != 0) return o;
      final s = (b['seen'] as int).compareTo(a['seen'] as int);
      if (s != 0) return s;
      return _i((b['u'] as Map)['createdAt']).compareTo(_i((a['u'] as Map)['createdAt']));
    });
    final delList = _bans.entries.where((e) => e.value['deleted'] == true && !_users.containsKey(e.key) && hit([e.value['name'], e.value['handle']])).toList()
      ..sort((a, b) => _i(b.value['at']).compareTo(_i(a.value['at'])));
    final maintOn = _maint?['on'] == true, lockOn = _chat?['locked'] == true;

    Widget box(String n, String l, {Color? col}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.ln)),
            child: Column(children: [
              Text(n, style: jakarta(22, FontWeight.w800, col ?? c.tx)),
              Text(l, style: jakarta(12, FontWeight.w700, c.mu)),
            ]),
          ),
        );

    final filters = [('all', 'Tümü'), ('on', 'Çevrimiçi'), ('ban', 'Yasaklı'), ('del', 'Silinenler${delList.isNotEmpty ? ' (${delList.length})' : ''}')];

    final rows = <Widget>[
      if (_f == 'del')
        for (final e in delList) _deletedRow(c, e.key, e.value)
      else
        for (final x in list) _userRow(c, x),
    ];

    return Container(
      decoration: BoxDecoration(color: c.sf, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
          child: Row(children: [
            Text('Yönetim Paneli', style: jakarta(22, FontWeight.w800, c.tx)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: 44, height: 44, decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(14)), child: Icon(Icons.close, color: c.tx)),
            ),
          ]),
        ),
        Expanded(
          child: !_loaded
              ? Center(child: CircularProgressIndicator(color: c.ac))
              : KbInset(child: ListView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  children: [
                    Row(children: [
                      box('${all.length}', 'Kayıtlı'),
                      const SizedBox(width: 8),
                      box('${all.where((x) => x['on'] == true).length}', 'Çevrimiçi', col: c.ac),
                      const SizedBox(width: 8),
                      box('${all.where((x) => x['ba'] == true).length}', 'Yasaklı', col: c.red),
                    ]),
                    const SizedBox(height: 10),
                    _toggleCard(c, '🛠', 'Bakım modu', maintOn ? 'Açık' : 'Kapalı', maintOn,
                        maintOn ? 'Uygulama herkese kapalı. Sen yönetici olarak girebiliyorsun.' : 'Site herkese açık.', maintOn ? 'Bakımı kapat' : 'Siteyi bakıma al', _maintToggle),
                    _toggleCard(c, '🔒', 'Genel sohbet', lockOn ? 'Kilitli' : 'Açık', lockOn,
                        lockOn ? 'Sadece yönetici yazabilir, herkes okuyabilir.' : 'Herkes mesaj yazabilir.', lockOn ? 'Kilidi aç' : 'Sohbeti kilitle', _chatToggle),
                    _annCard(c),
                    TextField(
                      controller: _search,
                      onChanged: (v) {
                        _deb?.cancel();
                        _deb = Timer(const Duration(milliseconds: 180), () {
                          if (mounted) setState(() => _q = v);
                        });
                      },
                      style: jakarta(14.5, FontWeight.w600, c.tx),
                      decoration: InputDecoration(
                        hintText: 'Ad, kullanıcı adı veya e-posta ara…',
                        hintStyle: jakarta(14.5, FontWeight.w500, c.mu),
                        filled: true,
                        fillColor: c.sf2,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.ln)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.ln)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.ac)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [for (final f in filters) Padding(padding: const EdgeInsets.only(right: 6), child: _chip(c, f.$2, _f == f.$1, () => setState(() => _f = f.$1)))]),
                    ),
                    const SizedBox(height: 8),
                    if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(_f == 'del' ? 'Silinmiş hesap yok.' : 'Kullanıcı bulunamadı.', style: jakarta(14, FontWeight.w600, c.mu))),
                      )
                    else
                      ...rows,
                  ],
                )),
        ),
      ]),
    );
  }
}

class _Op {
  final int kind; // 0 set, 1 update, 2 delete
  final DocumentReference ref;
  final Map<String, dynamic>? data;
  _Op(this.kind, this.ref, this.data);
  factory _Op.set(DocumentReference r, Map<String, dynamic> d) => _Op(0, r, d);
  factory _Op.upd(DocumentReference r, Map<String, dynamic> d) => _Op(1, r, d);
  factory _Op.del(DocumentReference r) => _Op(2, r, null);
}

/* ---------------- Puan / moderatör (hediye) penceresi ---------------- */

class _GiftDialog extends StatefulWidget {
  final String uid, name;
  final bool targetAdmin;
  final BuildContext parent;
  const _GiftDialog({required this.uid, required this.name, required this.targetAdmin, required this.parent});
  @override
  State<_GiftDialog> createState() => _GiftDialogState();
}

class _GiftDialogState extends State<_GiftDialog> {
  final _db = FirebaseFirestore.instance;
  final _pts = TextEditingController();
  final _set = TextEditingController();
  double? _total;
  double _manual = 0;
  bool _mod = false, _zArm = false, _busy = false;
  bool _star = false;
  int _every = 0; // saniye
  Set<String> _have = {};
  Timer? _zT;

  String get _me => profileNotifier.value?.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _zT?.cancel();
    _pts.dispose();
    _set.dispose();
    super.dispose();
  }

  void _t(String s) => _toast(widget.parent, s);

  Future<({double raw, double manual})> _calc() async {
    final uid = widget.uid;
    final ud = await _db.collection('users').doc(uid).get();
    final pq = await _db.collection('posts').where('uid', isEqualTo: uid).limit(300).get();
    final g = await _db.collection('grants').doc(uid).get();
    final gd = g.data() ?? {};
    final manual = (gd['pts'] as num?)?.toDouble() ?? 0;
    final bonus = manual + ((gd['keep'] as num?)?.toDouble() ?? 0);
    final posts = pq.docs.map((d) => Post(d.id, d.data())).toList();
    final s = scoreOf(uid, posts, ud.data()?['hist'] as Map?, bonus);
    return (raw: s.pts, manual: manual);
  }

  Future<void> _load() async {
    try {
      final r = await _calc();
      final m = await _db.collection('mods').doc(widget.uid).get();
      final gs = await _db.collection('grants').doc(widget.uid).get();
      final us = await _db.collection('users').doc(widget.uid).get();
      final owned = ((us.data()?['shop'] as Map?)?['owned'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _have = {
          for (final i in ((gs.data()?['frames'] as List?) ?? const [])) '$i',
          for (final i in owned) '$i',
        };
        _total = r.raw;
        _manual = r.manual;
        _mod = m.exists;
        _star = us.data()?['star'] == true;
        _every = (us.data()?['starSec'] as num?)?.toInt() ?? (((us.data()?['starEvery'] as num?)?.toInt() ?? 0) * 60);
      });
    } catch (e) {
      if (mounted) _t(_err(e));
    }
  }

  Future<void> _refresh() async {
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      final r = await _calc();
      if (mounted) setState(() => _total = r.raw);
    } catch (_) {}
  }

  double? _num(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '.');
    final n = double.tryParse(raw);
    if (raw.isEmpty || n == null || n.abs() > 1000000) return null;
    return (n * 100).round() / 100;
  }

  Future<void> _delta(int sign) async {
    final n = _num(_pts);
    if (n == null || n <= 0) return _t('Geçerli bir puan yaz.');
    final v = n * sign;
    setState(() => _busy = true);
    try {
      await _db.collection('grants').doc(widget.uid).set({
        'pts': FieldValue.increment(v),
        'at': _now(),
        'note': 'Yönetici sana ${v > 0 ? '+' : ''}${fmtPts(v)} puan ${v > 0 ? 'ekledi' : 'düşürdü'}',
      }, SetOptions(merge: true));
      _t('${widget.name}: ${v > 0 ? '+' : ''}${fmtPts(v)} puan');
      _pts.clear();
      _refresh();
    } catch (e) {
      _t(_err(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setTotal(double t, String msg) async {
    setState(() => _busy = true);
    try {
      final r = await _calc();
      final val = ((t - (r.raw - r.manual)) * 100).round() / 100;
      await _db.collection('grants').doc(widget.uid).set({'pts': val, 'at': _now(), 'note': msg}, SetOptions(merge: true));
      _t('${widget.name}: toplam puan ${fmtPts(t)}');
      _refresh();
    } catch (e) {
      _t(_err(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _setStar(int v) async {
    try {
      await _db.collection('users').doc(widget.uid).update(v == -1 ? {'star': false} : {'star': true, 'starSec': v, 'starEvery': FieldValue.delete()});
      if (!mounted) return;
      setState(() {
        _star = v != -1;
        if (v != -1) _every = v;
      });
      _t(v == -1 ? '${widget.name}: kupon şeridi kapatıldı' : '${widget.name}: kupon şeridi açıldı');
    } catch (e) {
      _t(_err(e));
    }
  }

  Widget _starChip(AppColors c, String t, int v) {
    final on = v == -1 ? !_star : (_star && _every == v);
    return GestureDetector(
      onTap: () => _setStar(v),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(color: on ? c.ac : c.sf2, borderRadius: BorderRadius.circular(12)),
        child: Text(t, style: jakarta(13, FontWeight.w800, on ? c.on : c.tx)),
      ),
    );
  }

  Future<void> _toggleMod() async {
    try {
      if (_mod) {
        await _db.collection('mods').doc(widget.uid).delete();
      } else {
        await _db.collection('mods').doc(widget.uid).set({'at': _now(), 'by': _me, 'name': widget.name});
      }
      if (!mounted) return;
      setState(() => _mod = !_mod);
      _t(_mod ? '${widget.name} artık moderatör' : '${widget.name}: moderatörlük kaldırıldı');
    } catch (e) {
      _t(_err(e));
    }
  }

  Future<void> _giveFrame(FrameDef f) async {
    if (_have.contains(f.id)) return;
    try {
      await _db.collection('grants').doc(widget.uid).set({
        'frames': FieldValue.arrayUnion([f.id]),
      }, SetOptions(merge: true));
      // Mağaza kullanıcıya kapalı olduğu için çerçeveyi doğrudan hesabına işle ve tak
      await _db.collection('users').doc(widget.uid).update({
        'shop.owned': FieldValue.arrayUnion([f.id]),
        'shop.eq': f.id,
        'frame': f.id,
      });
      if (mounted) setState(() => _have = {..._have, f.id});
      _t('${f.name} → ${widget.name}');
    } catch (e) {
      _t(_err(e));
    }
  }

  Future<void> _takeFrame(FrameDef f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = AppColors.of(ctx);
        return Dialog(
          backgroundColor: c.sf,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Çerçeveyi geri al', textAlign: TextAlign.center, style: jakarta(20, FontWeight.w800, c.tx)),
              const SizedBox(height: 10),
              Text('${widget.name} kullanıcısından ${f.name} çerçevesi alınacak.', textAlign: TextAlign.center, style: jakarta(14.5, FontWeight.w500, c.mu).copyWith(height: 1.35)),
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
                      child: Text('Geri al', style: jakarta(15, FontWeight.w800, Colors.white)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    );
    if (ok != true) return;
    try {
      final ur = _db.collection('users').doc(widget.uid);
      final us = await ur.get();
      final sh = (us.data()?['shop'] as Map?) ?? const {};
      final wasEq = '${sh['eq'] ?? ''}' == f.id || '${us.data()?['frame'] ?? ''}' == f.id;
      // hediye kaydından da silinmeli, yoksa mağaza açılınca geri eklenir
      await _db.collection('grants').doc(widget.uid).set({'frames': FieldValue.arrayRemove([f.id])}, SetOptions(merge: true));
      await ur.update({
        'shop.owned': FieldValue.arrayRemove([f.id]),
        if (wasEq) 'shop.eq': '',
        if (wasEq) 'frame': '',
      });
      if (mounted) setState(() => _have = {..._have}..remove(f.id));
      _t('${f.name} geri alındı: ${widget.name}');
    } catch (e) {
      _t(_err(e));
    }
  }

  Widget _frameGrid(AppColors c) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in kFrames)
          GestureDetector(
            onTap: () => _have.contains(f.id) ? _takeFrame(f) : _giveFrame(f),
            child: Opacity(
              opacity: 1,
              child: Container(
                width: 92,
                padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
                decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(14), border: Border.all(color: _have.contains(f.id) ? c.ac : c.ln, width: 1.5)),
                child: Column(children: [
                  Avatar(profile: Profile(uid: widget.uid, name: widget.name, handle: '', frame: f.id), size: 46, forceFrame: f.id),
                  const SizedBox(height: 6),
                  Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(11.5, FontWeight.w800, c.tx)),
                  Text(_have.contains(f.id) ? 'Geri al' : 'Gönder', style: jakarta(11, FontWeight.w800, _have.contains(f.id) ? c.red : c.mu)),
                ]),
              ),
            ),
          ),
      ]);

  Widget _sec(AppColors c, String title, List<Widget> kids) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: jakarta(12, FontWeight.w800, c.mu)),
          const SizedBox(height: 6),
          ...kids,
        ]),
      );

  Widget _input(AppColors c, TextEditingController ctl, String hint) => TextField(
        controller: ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: jakarta(14.5, FontWeight.w700, c.tx),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: jakarta(14, FontWeight.w500, c.mu),
          filled: true,
          fillColor: c.sf2,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
        ),
      );

  Widget _b(AppColors c, String t, VoidCallback? tap, {Color? bg, Color? fg}) => Expanded(
        child: GestureDetector(
          onTap: _busy ? null : tap,
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg ?? c.ac, borderRadius: BorderRadius.circular(12)),
            child: Text(t, style: jakarta(13.5, FontWeight.w800, fg ?? c.on)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Dialog(
      backgroundColor: c.sf,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14), // Dialog klavye boşluğunu zaten kendisi veriyor
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Text('🎁 ${widget.name}', style: jakarta(18, FontWeight.w800, c.tx))),
            const SizedBox(height: 6),
            Center(
              child: Text.rich(TextSpan(style: jakarta(14, FontWeight.w600, c.mu), children: [
                const TextSpan(text: 'Toplam puan: '),
                TextSpan(text: _total == null ? '…' : fmtPts(_total!), style: jakarta(14, FontWeight.w800, c.tx)),
              ])),
            ),
            const SizedBox(height: 14),
            _sec(c, 'Puan artır / azalt', [
              _input(c, _pts, 'Miktar (örn. 5)'),
              const SizedBox(height: 8),
              Row(children: [
                _b(c, '− Azalt', () => _delta(-1), bg: c.sf2, fg: c.tx),
                const SizedBox(width: 8),
                _b(c, '+ Artır', () => _delta(1)),
              ]),
            ]),
            _sec(c, 'Puanı doğrudan belirle', [
              Row(children: [
                Expanded(child: _input(c, _set, 'Yeni toplam puan')),
                const SizedBox(width: 8),
                SizedBox(
                  width: 96,
                  child: Row(children: [
                    _b(c, 'Belirle', () {
                      final n = _num(_set);
                      if (n == null || n < 0) return _t('Geçerli bir puan yaz (0 veya üstü).');
                      _setTotal(n, 'Yönetici puanını ${fmtPts(n)} yaptı');
                      _set.clear();
                    }),
                  ]),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _b(c, _zArm ? 'Emin misin? Tekrar dokun' : 'Tüm puanı sil (sıfırla)', () {
                  if (!_zArm) {
                    setState(() => _zArm = true);
                    _zT?.cancel();
                    _zT = Timer(const Duration(milliseconds: 3500), () {
                      if (mounted) setState(() => _zArm = false);
                    });
                    return;
                  }
                  setState(() => _zArm = false);
                  _setTotal(0, 'Yönetici puanını sıfırladı');
                }, bg: c.sf2, fg: c.red),
              ]),
            ]),
            if (!widget.targetAdmin)
              _sec(c, 'Yetki', [
                Row(children: [_b(c, _mod ? '🛡️ Moderatör yetkisini kaldır' : '🛡️ Moderatör yap (sadece yasaklama)', _toggleMod, bg: _mod ? c.sf2 : c.ac, fg: _mod ? c.red : c.on)]),
                const SizedBox(height: 6),
                Text('Moderatör sadece kullanıcıları yasaklayabilir ve yasağı kaldırabilir. Başka yetkisi olmaz.', style: jakarta(12, FontWeight.w500, c.mu)),
              ]),
            _sec(c, 'Kupon şeridi', [
              Text('Bu kişi kupon paylaşınca herkesin üstünden şerit kayar (ilk koşu saatine kadar). Ne sıklıkla tekrar etsin?', style: jakarta(12, FontWeight.w500, c.mu)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _starChip(c, 'Kapalı', -1),
                _starChip(c, 'Bir kez', 0),
                _starChip(c, '10 sn', 10),
                _starChip(c, '20 sn', 20),
                _starChip(c, '2 dk', 120),
                _starChip(c, '5 dk', 300),
                _starChip(c, '10 dk', 600),
                _starChip(c, '15 dk', 900),
              ]),
            ]),
            _sec(c, 'Hediye çerçeve', [_frameGrid(c)]),
            Row(children: [_b(c, 'Kapat', () => Navigator.pop(context), bg: c.sf2, fg: c.tx)]),
          ]),
        ),
      ),
    );
  }
}


/* =====================================================================
   HIZLI YÖNETİM (profil ve akıştan): moderatör / yönetici menüsü, yasakla, yasağı kaldır
   (sitedeki admUserMenu / admBan / admToggleBan ile aynı)
   ===================================================================== */

bool canBanNow() => isAdminNotifier.value || isModNotifier.value;

/// Yönetici herkesi (kendi hariç), moderatör ise yönetici ve moderatör olmayanları yönetebilir.
bool canManageUser(String uid, {required bool targetAdmin, required bool targetMod}) {
  final me = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty || uid == me) return false;
  if (isAdminNotifier.value) return true;
  return isModNotifier.value && !(targetAdmin || targetMod);
}

Widget _bnChip(AppColors c, String label, bool on, VoidCallback tap) => GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(color: on ? c.ac : Colors.transparent, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? c.ac : c.ln)),
        child: Text(label, style: jakarta(14, FontWeight.w800, on ? c.on : c.mu)),
      ),
    );

Future<void> showBanDialog(BuildContext context, String uid) async {
  final db = FirebaseFirestore.instance;
  final me = FirebaseAuth.instance.currentUser?.uid ?? '';
  Map<String, dynamic> u = {};
  try {
    u = (await db.collection('users').doc(uid).get()).data() ?? {};
  } catch (_) {}
  if (!context.mounted) return;
  final c = AppColors.of(context);
  final isA = isAdminNotifier.value;
  const opts = [('1 Saat', 3600000), ('1 Gün', 86400000), ('7 Gün', 7 * 86400000), ('30 Gün', 30 * 86400000), ('Kalıcı', 0)];
  var dur = 86400000;
  var delPosts = false;
  final reason = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        backgroundColor: c.sf,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Yasakla: ${u['name'] ?? ''}', textAlign: TextAlign.center, style: jakarta(17, FontWeight.w800, c.tx)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Text('Yasak süresi', style: jakarta(13.5, FontWeight.w600, c.mu))),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final o in opts) _bnChip(c, o.$1, dur == o.$2, () => setS(() => dur = o.$2))]),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 120,
              style: jakarta(14, FontWeight.w600, c.tx),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Sebep (isteğe bağlı)',
                hintStyle: jakarta(14, FontWeight.w500, c.mu),
                filled: true,
                fillColor: c.sf2,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
              ),
            ),
            if (isA)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                activeColor: c.ac,
                value: delPosts,
                onChanged: (v) => setS(() => delPosts = v == true),
                title: Text('Paylaşımlarını da sil', style: jakarta(13.5, FontWeight.w700, c.tx)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Vazgeç', style: jakarta(14, FontWeight.w800, c.mu))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Yasakla', style: jakarta(14, FontWeight.w800, c.red))),
        ],
      ),
    ),
  );
  final reasonTxt = reason.text.trim();
  reason.dispose();
  if (ok != true) return;
  try {
    await db.collection('bans').doc(uid).set({
      'until': dur == 0 ? 0 : _now() + dur,
      'reason': reasonTxt,
      'by': me,
      'at': _now(),
      'name': u['name'] ?? '',
      'handle': u['handle'] ?? '',
    });
    if (delPosts && isA) {
      final q = await db.collection('posts').where('uid', isEqualTo: uid).get();
      if (q.docs.isNotEmpty) {
        final b = db.batch();
        for (final d in q.docs) {
          b.delete(d.reference);
        }
        await b.commit();
      }
    }
    if (context.mounted) _toast(context, '${u['name'] ?? 'Kullanıcı'} yasaklandı');
  } catch (e) {
    if (context.mounted) _toast(context, _err(e));
  }
}

Future<void> unbanUser(BuildContext context, String uid, String name) {
  return _ask(context, 'Yasağı kaldır', '${name.isEmpty ? 'Kullanıcı' : name} için yasak kaldırılsın mı?', 'Kaldır',
      () => FirebaseFirestore.instance.collection('bans').doc(uid).delete().then((_) {
            if (context.mounted) _toast(context, 'Yasak kaldırıldı');
          }).catchError((e) {
            if (context.mounted) _toast(context, _err(e));
          }));
}

/// Yasaklıysa yasağı kaldırır, değilse yasaklama penceresini açar.
Future<void> toggleBanUser(BuildContext context, String uid, String name) async {
  Map<String, dynamic>? b;
  try {
    b = (await FirebaseFirestore.instance.collection('bans').doc(uid).get()).data();
  } catch (_) {}
  if (!context.mounted) return;
  if (banActive(b)) {
    await unbanUser(context, uid, name);
  } else {
    await showBanDialog(context, uid);
  }
}

/// Kullanıcı adına / avatara dokununca yönetici ve moderatöre açılan menü.
Future<void> showUserAdminMenu(BuildContext context, {required String uid, required String name, bool targetAdmin = false, VoidCallback? onProfile}) async {
  Map<String, dynamic>? b;
  Profile? pr;
  bool star = false;
  int starEvery = 0; // saniye
  try {
    final r = await Future.wait([
      FirebaseFirestore.instance.collection('bans').doc(uid).get(),
      AuthService.loadProfile(uid),
      FirebaseFirestore.instance.collection('users').doc(uid).get(),
    ]);
    b = (r[0] as DocumentSnapshot<Map<String, dynamic>>).data();
    pr = r[1] as Profile?;
    final ud = (r[2] as DocumentSnapshot<Map<String, dynamic>>).data();
    star = ud?['star'] == true;
    starEvery = (ud?['starSec'] as num?)?.toInt() ?? (((ud?['starEvery'] as num?)?.toInt() ?? 0) * 60);
  } catch (_) {}
  if (!context.mounted) return;
  final banned = banActive(b);
  final c = AppColors.of(context);
  const red = Color(0xFFEF4444);
  const blue = Color(0xFF2563EB);

  Widget tile(IconData ic, String title, String sub, List<Color> g, VoidCallback tap, {bool danger = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: danger ? red.withAlpha(18) : c.sf2,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: tap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: danger ? red.withAlpha(60) : c.ln)),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: g),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: g.last.withAlpha(90), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Icon(ic, size: 21, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: jakarta(14.5, FontWeight.w800, danger ? red : c.tx)),
                    const SizedBox(height: 1),
                    Text(sub, style: jakarta(11.5, FontWeight.w600, c.mu)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, size: 22, color: c.mu),
              ]),
            ),
          ),
        ),
      );

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      decoration: BoxDecoration(color: c.sf, borderRadius: const BorderRadius.vertical(top: Radius.circular(28)), border: Border.all(color: c.ln)),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + MediaQuery.paddingOf(ctx).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 44, height: 5, decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(3))),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: c.ac, width: 2)),
            child: Avatar(profile: pr, size: 52),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(18, FontWeight.w800, c.tx)),
              const SizedBox(height: 4),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: c.ac.withAlpha(24), borderRadius: BorderRadius.circular(9)),
                  child: Text('@${pr?.handle ?? ''}', style: jakarta(12, FontWeight.w700, c.ac)),
                ),
                if (banned) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: red.withAlpha(24), borderRadius: BorderRadius.circular(9)),
                    child: Text('Yasaklı', style: jakarta(12, FontWeight.w800, red)),
                  ),
                ],
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 12, bottom: 10), child: Text('YÖNETİM İŞLEMLERİ', style: jakarta(11, FontWeight.w800, c.mu).copyWith(letterSpacing: 1.2)))),
        if (onProfile != null)
          tile(Icons.person_rounded, 'Profili aç', 'Paylaşımlarını ve puanını gör', [const Color(0xFF34D399), const Color(0xFF059669)], () {
            Navigator.pop(ctx);
            onProfile();
          }),
        if (isAdminNotifier.value)
          tile(Icons.diamond_rounded, 'Puan / Hediye çerçeve', 'Puan ver, çerçeve hediye et, moderatör yap, kupon şeridi', [const Color(0xFFA855F7), const Color(0xFFDB2777)], () {
            Navigator.pop(ctx);
            showDialog(context: context, builder: (_) => _GiftDialog(uid: uid, name: name, targetAdmin: targetAdmin, parent: context));
          }),
        if (isAdminNotifier.value)
          tile(Icons.toll_rounded, 'Kredi ver', 'Kupon paylaşma kredisi ekle veya düş', [const Color(0xFFFBBF24), const Color(0xFFF59E0B)], () {
            Navigator.pop(ctx);
            adminGiveCreditDialog(context, uid, name);
          }),
        if (isAdminNotifier.value)
          tile(
            star ? Icons.star_rounded : Icons.star_border_rounded,
            'Kupon şeridi',
            star ? (starEvery > 0 ? 'Açık · her ${starEvery >= 60 ? '${starEvery ~/ 60} dk' : '$starEvery sn'} bir gösterilir' : 'Açık · bir kez gösterilir') : 'Kapalı · kupon paylaşınca şerit çıkmaz',
            [const Color(0xFFFBBF24), const Color(0xFFF59E0B)],
            () async {
              Navigator.pop(ctx);
              final v = await showDialog<int>(
                context: context,
                builder: (dctx) {
                  final dc = AppColors.of(dctx);
                  Widget opt(String t, int val) => ListTile(
                        title: Text(t, style: jakarta(14.5, FontWeight.w700, dc.tx)),
                        trailing: (val == -1 ? !star : (star && starEvery == val)) ? Icon(Icons.check_rounded, color: dc.ac) : null,
                        onTap: () => Navigator.pop(dctx, val),
                      );
                  return Dialog(
                    backgroundColor: dc.sf,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Kupon şeridi: $name', style: jakarta(16, FontWeight.w800, dc.tx)),
                        const SizedBox(height: 4),
                        Text('Ne sıklıkla gösterilsin? (ilk koşu saatine kadar)', style: jakarta(11.5, FontWeight.w600, dc.mu)),
                        const SizedBox(height: 6),
                        opt('Kapalı', -1),
                        opt('Bir kez', 0),
                        opt('Her 10 saniyede bir', 10),
                        opt('Her 20 saniyede bir', 20),
                        opt('Her 2 dakikada bir', 120),
                        opt('Her 5 dakikada bir', 300),
                        opt('Her 10 dakikada bir', 600),
                        opt('Her 15 dakikada bir', 900),
                      ]),
                    ),
                  );
                },
              );
              if (v == null) return;
              try {
                await FirebaseFirestore.instance.collection('users').doc(uid).update(v == -1 ? {'star': false} : {'star': true, 'starSec': v, 'starEvery': FieldValue.delete()});
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(v == -1 ? '$name: kupon şeridi kapatıldı' : '$name: kupon şeridi açıldı')));
                }
              } catch (_) {}
            },
          ),
        tile(
          banned ? Icons.lock_open_rounded : Icons.block_rounded,
          banned ? 'Yasağı kaldır' : 'Yasakla',
          banned ? 'Kullanıcı tekrar giriş yapabilsin' : 'Süre seç, sebep yaz',
          banned ? [const Color(0xFF60A5FA), blue] : [const Color(0xFFF87171), const Color(0xFFD92D20)],
          () {
            Navigator.pop(ctx);
            if (banned) {
              unbanUser(context, uid, name);
            } else {
              showBanDialog(context, uid);
            }
          },
          danger: !banned,
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: TextButton(
            style: TextButton.styleFrom(backgroundColor: c.sf2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Vazgeç', style: jakarta(14, FontWeight.w800, c.mu)),
          ),
        ),
      ]),
    ),
  );
}


/// Puan / hediye çerçeve penceresi (yönetici): liderlik tablosu ve menüden açılır.
Future<void> showGiftDialog(BuildContext context, {required String uid, required String name, bool targetAdmin = false}) {
  return showDialog<void>(context: context, builder: (_) => _GiftDialog(uid: uid, name: name, targetAdmin: targetAdmin, parent: context));
}
