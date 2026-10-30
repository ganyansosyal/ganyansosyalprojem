import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'feed.dart' show Post;
import 'frames.dart';
import 'scoring.dart';
import 'settle.dart' show isAdminNotifier;
import 'shell.dart' show IconBox;
import 'theme.dart';

/* =====================================================================
   MAĞAZA: profil çerçeveleri (puanla alınır) — sitedeki js/06-account.js ile aynı veriler
   users/{uid}.shop = {owned[], eq, spent}   users/{uid}.frame = eq
   shop/prices = {prices:{id: puan}}         grants/{uid}.frames[] = yönetici hediyesi
   ===================================================================== */

String _priceTxt(double n) => n == 0 ? 'Ücretsiz' : '${fmtPts(n)} puan';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});
  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final _db = FirebaseFirestore.instance;
  final _subs = <StreamSubscription>[];
  Map<String, dynamic> _u = {}, _grant = {};
  List<Post> _posts = [];
  Map<String, double> _prices = {};
  bool _uLoaded = false, _gLoaded = false, _edit = false, _busy = false, _syncing = false;
  final _ctl = <String, TextEditingController>{};

  String get _me => FirebaseAuth.instance.currentUser?.uid ?? '';
  bool get _admin => isAdminNotifier.value;

  // ---- durum ----
  List<String> get _owned {
    final o = ((_u['shop'] as Map?)?['owned'] as List?) ?? const [];
    return [for (final i in o) if (frameById('$i') != null) '$i'];
  }

  String get _eq {
    final e = '${(_u['shop'] as Map?)?['eq'] ?? ''}';
    return _owned.contains(e) ? e : '';
  }

  double get _spent => (((_u['shop'] as Map?)?['spent']) as num?)?.toDouble() ?? 0;

  double _price(FrameDef f) => _prices[f.id] ?? f.price;

  double get _bal {
    final bonus = ((_grant['pts'] as num?)?.toDouble() ?? 0) + ((_grant['keep'] as num?)?.toDouble() ?? 0);
    final pts = scoreOf(_me, _posts, _u['hist'] as Map?, bonus).pts;
    return (((pts - _spent) * 100).round() / 100).clamp(0, double.infinity).toDouble();
  }

  Profile get _meProfile => Profile.fromMap(_me, _u);

  @override
  void initState() {
    super.initState();
    final me = _me;
    _subs.add(_db.collection('users').doc(me).snapshots().listen((s) {
      if (!mounted) return;
      setState(() {
        _u = s.data() ?? {};
        _uLoaded = true;
      });
      _syncGifts();
    }, onError: (_) {}));
    _subs.add(_db.collection('grants').doc(me).snapshots().listen((s) {
      if (!mounted) return;
      setState(() {
        _grant = s.data() ?? {};
        _gLoaded = true;
      });
      _syncGifts();
    }, onError: (_) {}));
    _subs.add(_db.collection('posts').where('uid', isEqualTo: me).limit(300).snapshots().listen((s) {
      if (mounted) setState(() => _posts = s.docs.map((d) => Post(d.id, d.data())).where((p) => !p.hidden).toList());
    }, onError: (_) {}));
    _subs.add(_db.collection('shop').doc('prices').snapshots().listen((s) {
      final raw = (s.data()?['prices'] as Map?) ?? const {};
      final r = <String, double>{};
      for (final f in kFrames) {
        final v = raw[f.id];
        if (v is num && v >= 0 && v <= 1000000) r[f.id] = (v * 100).round() / 100;
      }
      if (mounted) setState(() => _prices = r);
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(t, style: jakarta(13.5, FontWeight.w700, Colors.white)), behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xEE111827)));
  }

  Future<void> _save(List<String> owned, String eq, double spent) async {
    await _db.collection('users').doc(_me).update({
      'shop': {'owned': owned, 'eq': eq, 'spent': spent},
      'frame': eq,
    });
    final p = profileNotifier.value;
    if (p != null) profileNotifier.value = p.copyWith(frame: eq);
  }

  // Yönetici hediyesi çerçeveler otomatik eklenir ve takılır
  Future<void> _syncGifts() async {
    if (!_uLoaded || !_gLoaded || _syncing) return;
    final have = _owned;
    final gifted = [for (final i in ((_grant['frames'] as List?) ?? const [])) if (frameById('$i') != null && !have.contains('$i')) '$i'];
    if (gifted.isEmpty) return;
    _syncing = true;
    try {
      await _save([...have, ...gifted], gifted.last, _spent);
    } catch (_) {} finally {
      _syncing = false;
    }
  }

  // ---- işlemler ----
  ({String t, bool dis, bool alt, VoidCallback? fn}) _act(FrameDef f) {
    final bal = _bal, pr = _price(f);
    final own = _owned.contains(f.id), eq = _eq == f.id;
    if (eq) return (t: 'Çıkar', dis: false, alt: true, fn: () => _equip(''));
    if (own) return (t: 'Kuşan', dis: false, alt: false, fn: () => _equip(f.id));
    if (_admin) return (t: 'Al · ücretsiz', dis: false, alt: false, fn: () => _buy(f));
    final need = pr - bal;
    if (need > 0.0001) return (t: '${fmtPts(need)} puan eksik', dis: true, alt: false, fn: null);
    return (t: pr == 0 ? 'Al · Ücretsiz' : 'Satın al', dis: false, alt: false, fn: () => _buy(f));
  }

  Future<void> _buy(FrameDef f) async {
    if (_busy || _owned.contains(f.id)) return;
    final pr = _price(f);
    if (!_admin && _bal < pr) {
      _snack('Puanın yetmiyor.');
      return;
    }
    setState(() => _busy = true);
    try {
      final spent = _admin ? _spent : ((_spent + pr) * 100).round() / 100;
      await _save([..._owned, f.id], f.id, spent);
      _snack('${f.name} çerçevesi alındı ve takıldı.');
    } catch (e) {
      _snack(AuthService.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _equip(String id) async {
    if (_busy || (id.isNotEmpty && !_owned.contains(id))) return;
    setState(() => _busy = true);
    try {
      await _save(_owned, id, _spent);
    } catch (e) {
      _snack(AuthService.errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePrices() async {
    final out = <String, double>{};
    for (final f in kFrames) {
      final t = (_ctl[f.id]?.text ?? '').trim().replaceAll(',', '.');
      final v = double.tryParse(t);
      if (v == null || v < 0 || v > 1000000) {
        _snack('${f.name} için geçerli bir fiyat yaz.');
        return;
      }
      out[f.id] = (v * 100).round() / 100;
    }
    try {
      await _db.collection('shop').doc('prices').set({'prices': out, 'by': _me, 'ts': DateTime.now().millisecondsSinceEpoch});
      setState(() => _edit = false);
      _snack('Fiyatlar kaydedildi, herkese yansıdı.');
    } catch (e) {
      _snack('Kaydedilemedi: ${AuthService.errorText(e)}');
    }
  }

  void _startEdit() {
    for (final f in kFrames) {
      (_ctl[f.id] ??= TextEditingController()).text = fmtPts(_price(f)).replaceAll(',', '.');
    }
    setState(() => _edit = true);
  }

  // ---- arayüz ----
  Widget _avatar(FrameDef? f, double size) => Avatar(profile: _meProfile.copyWith(frame: f?.id ?? ''), size: size);

  Widget _btn(AppColors c, String t, VoidCallback? tap, {bool alt = false, bool dis = false}) => Expanded(
        child: GestureDetector(
          onTap: dis ? null : tap,
          child: Opacity(
            opacity: dis ? 0.5 : 1,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: alt ? c.sf : c.ac, borderRadius: BorderRadius.circular(12), border: alt ? Border.all(color: c.ln) : null),
              child: Text(t, style: jakarta(13, FontWeight.w800, alt ? c.tx : c.on)),
            ),
          ),
        ),
      );

  Widget _row(AppColors c, FrameDef f) {
    final pr = _price(f), own = _owned.contains(f.id), eq = _eq == f.id;
    if (_edit) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
        decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.ln, width: 1.5)),
        child: Row(children: [
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 10, 0), child: _avatar(f, 52)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.name, style: jakarta(14.5, FontWeight.w800, c.tx)),
              Text('varsayılan ${fmtPts(f.price)} puan', style: jakarta(12, FontWeight.w600, c.mu)),
            ]),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _ctl[f.id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: jakarta(15, FontWeight.w800, c.tx),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: c.sf,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c.ln)),
              ),
            ),
          ),
        ]),
      );
    }
    final a = _act(f);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
      decoration: BoxDecoration(
        color: eq ? Color.alphaBlend(c.ac.withAlpha(22), c.sf2) : c.sf2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: eq ? c.ac : c.ln, width: 1.5),
      ),
      child: Column(children: [
        Row(children: [
          GestureDetector(onTap: () => _preview(f), child: Padding(padding: const EdgeInsets.fromLTRB(14, 0, 10, 0), child: _avatar(f, 52))),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.name, style: jakarta(16, FontWeight.w800, c.tx)),
              const SizedBox(height: 2),
              if (own)
                Text(eq ? '✓ Kuşanıldı' : 'Sende var', style: jakarta(12.5, FontWeight.w600, c.mu))
              else
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${f.desc} · ', style: jakarta(12.5, FontWeight.w600, c.mu)),
                  TextSpan(text: _priceTxt(pr), style: jakarta(12.5, FontWeight.w800, c.ac)),
                ])),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _btn(c, 'Önizle', () => _preview(f), alt: true),
          const SizedBox(width: 8),
          _btn(c, a.t, a.fn, alt: a.alt, dis: a.dis || _busy),
        ]),
      ]),
    );
  }

  Widget _heading(AppColors c, String t, {int? n}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
        child: Row(children: [
          Text(t, style: jakarta(16, FontWeight.w800, c.tx)),
          if (n != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              decoration: BoxDecoration(color: c.ac.withAlpha(30), borderRadius: BorderRadius.circular(999)),
              child: Text('$n', style: jakarta(12, FontWeight.w800, c.ac)),
            ),
          ],
        ]),
      );

  void _preview(FrameDef start) {
    var i = kFrames.indexWhere((f) => f.id == start.id);
    final c = AppColors.of(context);
    final me = _meProfile;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final f = kFrames[i];
          final a = _act(f);
          Widget nav(String ch, int d) => GestureDetector(
                onTap: () => setS(() => i = (i + d + kFrames.length) % kFrames.length),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.ln)),
                  child: Text(ch, style: jakarta(24, FontWeight.w800, c.tx)),
                ),
              );
          return Dialog(
            backgroundColor: c.sf,
            insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  nav('‹', -1),
                  Expanded(
                    child: Column(children: [
                      Text(f.name, style: jakarta(17, FontWeight.w800, c.tx)),
                      Text(_priceTxt(_price(f)), style: jakarta(12.5, FontWeight.w800, c.ac)),
                    ]),
                  ),
                  nav('›', 1),
                ]),
                const SizedBox(height: 12),
                Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.ln)),
                  child: Column(children: [
                    Container(
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [c.ac.withAlpha(40), c.sf2])),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: 'Ganyan', style: jakarta(19, FontWeight.w800, c.tx)),
                        TextSpan(text: 'Sosyal', style: jakarta(19, FontWeight.w800, c.ac)),
                      ])),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -30),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 34),
                        child: Avatar(profile: me.copyWith(frame: f.id), size: 86),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -18),
                      child: Column(children: [
                        Text(me.name, style: jakarta(18, FontWeight.w800, c.tx)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: c.ac.withAlpha(24), borderRadius: BorderRadius.circular(10)),
                          child: Text('@${me.handle}', style: jakarta(12.5, FontWeight.w700, c.ac)),
                        ),
                        if (me.bio.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 0), child: Text(me.bio, textAlign: TextAlign.center, style: jakarta(13, FontWeight.w600, c.mu))),
                      ]),
                    ),
                    const SizedBox(height: 0),
                  ]),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 24, 12, 12),
                  decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
                  child: Row(children: [
                    Padding(padding: const EdgeInsets.only(left: 6, right: 6), child: Avatar(profile: me.copyWith(frame: f.id), size: 40)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(me.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(14, FontWeight.w800, c.tx)),
                        Text('Akışta böyle görünür', style: jakarta(11.5, FontWeight.w600, c.mu)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  _btn(c, 'Kapat', () => Navigator.pop(ctx), alt: true),
                  const SizedBox(width: 8),
                  _btn(c, a.t, () {
                    Navigator.pop(ctx);
                    a.fn?.call();
                  }, dis: a.dis || _busy),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final own = [for (final f in kFrames) if (_owned.contains(f.id)) f];
    final store = [for (final f in kFrames) if (!_owned.contains(f.id)) f];
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(children: [
              IconBox(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 12),
              Expanded(child: Text('Mağaza · Profil çerçeveleri', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(19, FontWeight.w800, c.tx))),
            ]),
          ),
          Expanded(
            child: !_uLoaded
                ? Center(child: CircularProgressIndicator(color: c.ac))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(children: [
                          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                            Text(fmtPts(_bal), style: jakarta(34, FontWeight.w800, c.ac)),
                            const SizedBox(width: 6),
                            Text('PUAN BAKİYE', style: jakarta(12.5, FontWeight.w800, c.mu)),
                          ]),
                          const SizedBox(height: 6),
                          Text('Sıralaman toplam puanına göre belirlenir, çerçeve almak onu düşürmez.', textAlign: TextAlign.center, style: jakarta(12.5, FontWeight.w600, c.mu)),
                        ]),
                      ),
                      if (_edit) ...[
                        for (final f in kFrames) _row(c, f),
                        Row(children: [
                          _btn(c, 'Fiyatları kaydet', _savePrices),
                          const SizedBox(width: 8),
                          _btn(c, 'Varsayılana dön', () {
                            for (final f in kFrames) {
                              _ctl[f.id]?.text = fmtPts(f.price).replaceAll(',', '.');
                            }
                          }, alt: true),
                        ]),
                        const SizedBox(height: 8),
                        Row(children: [_btn(c, 'Vazgeç', () => setState(() => _edit = false), alt: true)]),
                      ] else ...[
                        if (own.isNotEmpty) ...[_heading(c, 'Satın aldıklarım', n: own.length), for (final f in own) _row(c, f)],
                        if (store.isNotEmpty) ...[_heading(c, 'Mağaza'), for (final f in store) _row(c, f)] else Padding(padding: const EdgeInsets.all(24), child: Center(child: Text('Tüm çerçeveler sende 🎉', style: jakarta(14, FontWeight.w700, c.mu)))),
                        if (_admin) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [_btn(c, 'Fiyatları düzenle (yönetici)', _startEdit, alt: true)])),
                      ],
                    ],
                  ),
          ),
        ]),
      ),
    );
  }
}
