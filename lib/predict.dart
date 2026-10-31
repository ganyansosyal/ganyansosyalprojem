import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'athist_prefetch.dart';
import 'bets.dart';
import 'credits.dart';
import 'film.dart';
import 'live.dart';
import 'settle.dart';
import 'horse_watch.dart';
import 'theme.dart';
import 'tjk.dart';

const _gun = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
const _ay = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];

final ValueNotifier<({String city, int race, String? iso})?> predictJump = ValueNotifier(null);

String isoLabel(String iso) {
  final p = iso.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2]);
  return '${_gun[d.weekday - 1]}, ${d.day} ${_ay[d.month - 1]}';
}

String isoTag(String iso) {
  final t = isoToday();
  return iso == t ? 'BUGÜN' : iso == isoAdd(t, -1) ? 'DÜN' : iso == isoAdd(t, 1) ? 'YARIN' : '';
}

class NoBadge extends StatelessWidget {
  final int no;
  final double size;
  const NoBadge(this.no, {super.key, this.size = 34});
  static const _c = [
    [Color(0xFFD7263D), Colors.white],
    [Colors.white, Color(0xFF111111)],
    [Color(0xFF1D4ED8), Colors.white],
    [Color(0xFFF5C518), Color(0xFF111111)],
    [Color(0xFF1E8449), Colors.white],
    [Color(0xFF111111), Colors.white],
  ];
  @override
  Widget build(BuildContext context) {
    final k = _c[(no - 1) % 6];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: k[0], borderRadius: BorderRadius.circular(size * 0.3), border: Border.all(color: Colors.black12)),
      child: Text('$no', style: jakarta(size * 0.5, FontWeight.w800, k[1])),
    );
  }
}

class _Sel {
  final int r, no;
  int slot;
  _Sel(this.r, this.slot, this.no);
}

class PredictPage extends StatefulWidget {
  final VoidCallback onShared;
  final bool active; // Tahmin Yap sekmesi şu an açık mı
  const PredictPage({super.key, required this.onShared, this.active = true});
  @override
  State<PredictPage> createState() => _PredictPageState();
}

class _PredictPageState extends State<PredictPage> {
  final s = TjkStore.i;
  BetType _t = kTypes.firstWhere((t) => t.k == 'g6');
  String _city = '';
  int _race = 1, _slot = 0, _misli = 1;
  final List<_Sel> _sel = [];
  final Map<String, int> _legSel = {};
  bool _busy = false;
  final Set<String> _detOpen = {}, _orOpen = {};
  bool _idmBusy = false;

  bool get _admin => isAdminNotifier.value;
  bool _open(int r) => _admin || s.isPast || !s.raceDone(_city, r);

  @override
  void initState() {
    super.initState();
    s.addListener(_onStore);
    isAdminNotifier.addListener(_onStore);
    predictJump.addListener(_onJump);
    if (s.cities.isEmpty) {
      s.ensureLoaded();
    } else {
      _initCity();
    }
  }

  @override
  void didUpdateWidget(covariant PredictPage old) {
    super.didUpdateWidget(old);
    // Sekmeden ayrılınca açık kalan Detay bölümleri kapansın
    if (old.active && !widget.active) _detOpen.clear();
  }

  @override
  void dispose() {
    s.removeListener(_onStore);
    isAdminNotifier.removeListener(_onStore);
    predictJump.removeListener(_onJump);
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(t)));
  }

  void _initCity() {
    if (s.cities.isEmpty) return;
    if (_city.isEmpty || !s.cities.any((c) => c.name == _city)) {
      _city = s.cities.first.name;
      _race = _nextRace(_city);
      _autoFix(silent: true);
      _goFirstLeg();
    }
    _applyJump();
    _prefetch();
  }

  // Seçili hipodromun atlarının geçmiş bilgisini arka planda önceden çek (detay açılınca hazır olsun)
  void _prefetch() => AtHistPrefetch.i.start(_city, _race);

  // Sekme canlı kaldığı için 'koşuya git' isteğini burada yakalıyoruz
  void _onJump() {
    if (mounted && predictJump.value != null) setState(_applyJump);
  }

  bool _jumpLoading = false;

  void _applyJump() {
    final j = predictJump.value;
    if (j == null || s.cities.isEmpty) return;
    // Koşu başka bir günün bülteninde (ör. yarın): önce o günü yükle, sonra koşuya git
    if (j.iso != null && j.iso!.isNotEmpty && j.iso != s.iso) {
      if (!_jumpLoading) {
        _jumpLoading = true;
        s.load(j.iso!).whenComplete(() {
          _jumpLoading = false;
          final k = predictJump.value;
          if (mounted && k != null) predictJump.value = (city: k.city, race: k.race, iso: s.iso);
        });
      }
      return;
    }
    predictJump.value = null;
    if (!s.cities.any((c) => c.name == j.city)) return;
    _city = j.city;
    _race = j.race;
    _slot = 0;
    if (_t.mode == 'legs' && !_lr.contains(j.race)) {
      _t = kTypes.firstWhere((t) => t.k == 'g1');
      _sel.clear();
    } else if (_t.mode == 'race' && _sel.any((x) => x.r != j.race)) {
      _sel.clear();
    }
  }

  void _onStore() {
    if (!mounted) return;
    setState(_initCity);
  }

  int _nextRace(String c) {
    final rs = s.races(c);
    if (rs.isEmpty) return 1;
    if (!s.isToday) return rs.first.no;
    final now = DateTime.now();
    for (final k in rs) {
      final st = s.raceStart(c, k.no);
      if (st != null && st.isAfter(now)) return k.no;
    }
    return rs.first.no;
  }

  List<int> get _lr => legRaces(_t, _city, picked: _legSel['${_t.k}|$_city'], admin: _admin);

  void _goFirstLeg() {
    final lr = _lr;
    if (lr.isEmpty) return;
    if (_t.mode == 'legs') {
      _race = lr.firstWhere(_open, orElse: () => lr.first);
      return;
    }
    // Tek koşuluk bahis (Tabela, Sıralı Üçlü…): bu bahsin oynandığı koşuya geç; koşu bittiyse sıradaki koşuya geç
    final key = oyunKey[_t.k];
    if (key != null && key != 'g1') {
      final ks = allRaces(_city).where((r) => oyunMusait(_t, _city, r) && _open(r)).toList();
      if (ks.isNotEmpty && !ks.contains(_race)) {
        _race = ks.firstWhere((r) => r >= _race, orElse: () => ks.first);
        return;
      }
    }
    if (!lr.contains(_race) || !_open(_race)) _race = _nextRace(_city);
  }

  void _autoFix({bool silent = false}) {
    if (_city.isEmpty) return;
    final m = typeMusait(_t, _city, admin: _admin, picked: _legSel['${_t.k}|$_city']);
    if (m.ok) return;
    BetType? alt;
    for (final t in kTypes) {
      if (t.k != _t.k && t.mode == 'legs' && t.rule == _t.rule && t.n == _t.n && typeMusait(t, _city, admin: _admin).ok) {
        alt = t;
        break;
      }
    }
    alt ??= kTypes.firstWhere((t) => t.k == (_t.rule == 'place' ? 'pl' : 'g1'));
    if (!silent) _toast('${_t.name} oynanamaz (${m.why}). ${alt.name} seçildi.');
    _t = alt;
    _sel.clear();
    _slot = 0;
    _misli = 1;
  }

  void _setType(BetType t) {
    setState(() {
      if (t.k != _t.k) {
        if (_sel.isNotEmpty) _toast('Bahis türü değişti, seçimler temizlendi.');
        _t = t;
        _sel.clear();
        _slot = 0;
        _misli = 1;
      }
      _autoFix();
      final onceki = _race;
      _goFirstLeg();
      if (_t.mode == 'race' && _race != onceki && oyunKey[_t.k] != null && oyunKey[_t.k] != 'g1') {
        _toast('${_t.name} $_race. koşuda oynanıyor, oraya geçildi.');
      }
    });
  }

  void _setCityTo(String c) {
    if (c == _city) return;
    setState(() {
      if (_sel.isNotEmpty) {
        _sel.clear();
        _misli = 1;
        _toast('Şehir değişti, seçimler temizlendi.');
      }
      _city = c;
      _slot = 0;
      _race = _nextRace(c);
      _autoFix();
      _goFirstLeg();
    });
    _prefetch();
  }

  List<int> _picks(int r, int slot) => (_sel.where((x) => x.r == r && x.slot == slot).map((x) => x.no).toList()..sort());

  void _tap(Horse h) {
    if (h.kosmaz) return;
    if (!_open(_race)) {
      _toast('$_race. koşu başladı, seçime kapalı.');
      return;
    }
    setState(() {
      final t = _t;
      if (t.mode == 'race' && _sel.any((x) => x.r != _race)) _sel.clear();
      if (t.vir) {
        final i = _sel.indexWhere((x) => x.no == h.no);
        if (i >= 0) {
          _sel.removeAt(i);
          for (var j = 0; j < _sel.length; j++) {
            _sel[j].slot = j;
          }
        } else {
          _sel.add(_Sel(_race, _sel.length, h.no));
        }
        return;
      }
      final slot = t.mode == 'legs' ? 0 : _slot;
      final i = _sel.indexWhere((x) => x.r == _race && x.slot == slot && x.no == h.no);
      if (t.per) {
        _sel.removeWhere((x) => x.r == _race && x.slot == slot);
        if (i < 0) _sel.add(_Sel(_race, slot, h.no));
        return;
      }
      if (i >= 0) {
        _sel.removeAt(i);
      } else {
        if (t.exact > 0 && t.tabs == 0 && _picks(_race, slot).length >= t.exact) {
          _toast('En fazla ${t.exact} at seçebilirsin.');
          return;
        }
        _sel.add(_Sel(_race, slot, h.no));
      }
    });
  }

  String _saat(int r) => s.race(_city, r)?.saat ?? '';

  Map<String, dynamic>? _build() {
    if (_sel.isEmpty) return null;
    final t = _t;
    final base = <String, dynamic>{'city': _city, 'type': t.name, 'rule': t.rule, 'date': 'Bugün', 'misli': _misli, 'iso': s.iso};
    Map<String, dynamic> leg(int r, List<int> p, [int? slot]) => {'r': r, 't': _saat(r), 'picks': p, 'win': null, if (slot != null) 'slot': slot};
    if (t.mode == 'legs') {
      final st = legStarts(t, _city);
      final ilk = legStart(t, _city, picked: _legSel['${t.k}|$_city'], admin: _admin);
      if (st.length > 1 && ilk != null) {
        final k = s.race(_city, ilk);
        final mp = k?.baslar.where((x) => x.tur == (t.rule == 'place' ? 'PLASE' : (t.n == 2 ? 'CIFTE' : 'GANYAN')) && x.n == t.n).toList() ?? [];
        base['ord'] = (mp.isNotEmpty && mp.first.ord > 0) ? mp.first.ord : st.indexOf(ilk) + 1;
      }
      return {...base, 'legs': _lr.map((r) => leg(r, _picks(r, 0))).toList()};
    }
    final r = _sel.first.r;
    if (t.vir) {
      final n = _sel.where((x) => x.r == r).length;
      return {...base, 'vir': t.slots, 'legs': List.generate(n, (i) => leg(r, _picks(r, i), i))};
    }
    if (t.slots > 0) return {...base, 'legs': List.generate(t.slots, (i) => leg(r, _picks(r, i), i))};
    if (t.tabs > 0) {
      final sets = List.generate(t.tabs, (i) => _picks(r, i));
      final all = {for (final p in sets) ...p}.toList()..sort();
      return {
        ...base,
        'legs': [
          {...leg(r, all), if (!t.per) 'sets': sets.map((p) => {'p': p}).toList()}
        ]
      };
    }
    return {...base, 'legs': [leg(r, _picks(r, 0))]};
  }

  Future<String?> _limit(Map<String, dynamic> c) async {
    if (_admin) return null;
    final me = profileNotifier.value;
    if (me == null) return null;
    final n = DateTime.now();
    final from = DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
    final snap = await FirebaseFirestore.instance.collection('posts').where('uid', isEqualTo: me.uid).limit(200).get();
    String fam(String t) => t.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '').trim();
    bool tek(Map k) => ((k['legs'] as List).length == 1) || (k['legs'] as List).any((l) => l is Map && l['slot'] != null);
    final legs = c['legs'] as List;
    final t1 = tek(c);
    final f = fam(c['type'].toString());
    final r = (legs[0] as Map)['r'];
    var cnt = 0;
    for (final d in snap.docs) {
      final m = d.data();
      if (((m['ts'] as num?) ?? 0) < from) continue;
      final k = m['coupon'];
      if (k is! Map || k['city'] != c['city']) continue;
      if (fam(k['type'].toString()) != f || tek(k) != t1) continue;
      if (!t1 && (k['ord'] ?? 0) != (c['ord'] ?? 0)) continue;
      if (t1 && ((k['legs'] as List)[0] as Map)['r'] != r) continue;
      cnt++;
    }
    if (cnt < tahminLimit) return null;
    return t1 ? '$r. koşu için $f en fazla $tahminLimit kez oynanabilir.' : '${c['city']} için bugün en fazla $tahminLimit adet ${c['ord'] != null ? '${c['ord']}. ' : ''}$f oynanabilir.';
  }

  Future<Map<String, dynamic>?> _check() async {
    final c = _build();
    if (c == null) return null;
    if (s.isPast && !_admin) {
      _toast('Geçmiş günlere kupon yapılamaz.');
      return null;
    }
    final m = typeMusait(_t, _city, admin: _admin, picked: _legSel['${_t.k}|$_city']);
    if (!m.ok) {
      _toast('${m.why} · bu kupon artık oynanamaz.');
      return null;
    }
    if (_t.mode == 'race' && !oyunMusait(_t, _city, (c['legs'] as List)[0]['r'] as int)) {
      _toast('${_t.name} ${(c['legs'] as List)[0]['r']}. koşuda oynanmıyor.');
      return null;
    }
    final lm = await _limit(c);
    if (lm != null) {
      _toast(lm);
      return null;
    }
    final legs = (c['legs'] as List).cast<Map>();
    final slotted = legs.any((l) => l['slot'] != null);
    if (_t.tabs > 0) {
      final emp = List.generate(_t.tabs, (i) => i).where((i) => _picks(legs[0]['r'] as int, i).isEmpty).toList();
      if (emp.isNotEmpty) {
        _toast('Eksik sıra: ${emp.map((i) => '${i + 1}. At').join(', ')}');
        return null;
      }
    }
    final miss = legs.where((l) => (l['picks'] as List).isEmpty).toList();
    if (miss.isNotEmpty) {
      _toast(slotted ? 'Eksik sıra: ${miss.map((l) => '${(l['slot'] as int) + 1}. At').join(', ')}' : 'Eksik ayak: ${miss.map((l) => '${l['r']}.').join(', ')} koşu');
      return null;
    }
    if (c['vir'] != null && legs.length < (c['vir'] as int)) {
      _toast('En az ${c['vir']} at seç (şu an ${legs.length}).');
      return null;
    }
    if (kolon(c) < 1) {
      _toast((slotted || _t.tabs > 0) ? 'Her sırada farklı bir at olmalı.' : 'Seçimini tamamla: en az ${_t.rule == 'any4' ? 4 : 2} at seç.');
      return null;
    }
    final tut = couponCost(c);
    if (tut < asgari) {
      _toast('Asgari kupon bedeli ${money(asgari)} · şu an ${money(tut)}, misli artır.');
      return null;
    }
    if (limitliMi(c['type'].toString()) && !_admin && tut > altiliMax) {
      _toast("${c['type']} kuponu en fazla ${money(altiliMax)} olabilir · şu an ${money(tut)}. Seçimini azalt.");
      return null;
    }
    return c;
  }
  Future<void> _share() async {
  if (_busy) return;
  final me = profileNotifier.value;
  if (me == null) return;
  setState(() => _busy = true);
  try {
    final c = await _check();
    if (c == null || !mounted) return;
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final col = AppColors.of(ctx);
        return Dialog(
          backgroundColor: col.sf,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: col.ac.withAlpha(30), shape: BoxShape.circle),
                child: Icon(Icons.share_rounded, color: col.ac, size: 26),
              ),
              const SizedBox(height: 14),
              Text('Kuponu paylaş', textAlign: TextAlign.center, style: jakarta(20, FontWeight.w800, col.tx)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(color: col.ac.withAlpha(24), borderRadius: BorderRadius.circular(999)),
                child: Text('${c['city']} · ${c['type']} · ${kolon(c)} kolon · ${money(couponCost(c))}', textAlign: TextAlign.center, style: jakarta(12.5, FontWeight.w800, col.ac)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctl,
                maxLength: 300,
                maxLines: 3,
                style: jakarta(14.5, FontWeight.w500, col.tx),
                decoration: InputDecoration(
                  hintText: 'Yorum ekle (isteğe bağlı)',
                  hintStyle: jakarta(14.5, FontWeight.w500, col.mu),
                  filled: true,
                  fillColor: col.sf2,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col.ln, width: 1.4)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col.ln, width: 1.4)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: col.ac, width: 1.6)),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: col.red.withAlpha(24), borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, color: col.red, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_admin ? 'Paylaşılan kupon silinemez.' : 'Paylaşılan kupon silinemez · 1 kredi harcanır.', style: jakarta(12.5, FontWeight.w700, col.red))),
                ]),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: col.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: col.ln, width: 1.4)),
                      child: Text('Vazgeç', style: jakarta(15, FontWeight.w800, col.tx)),
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
                      decoration: BoxDecoration(color: col.ac, borderRadius: BorderRadius.circular(16)),
                      child: Text('Paylaş', style: jakarta(15, FontWeight.w800, col.on)),
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
    if (!_admin && !await Credits.spend(me.uid)) {
      _toast('Krediniz bitti. Video izleyip kredi kazanın.');
      return;
    }
    final db = FirebaseFirestore.instance;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final id = '${ts}_${me.uid}';
    await db.collection('posts').doc(id).set({
      'uid': me.uid,
      'authorName': me.name,
      'handle': me.handle,
      'ts': ts,
      'text': ctl.text.trim(),
      'coupon': c,
      'likedBy': <String>[],
      'comments': <Map<String, dynamic>>[],
    });
    try {
      final fl = await db.collection('users').where('following', arrayContains: me.uid).limit(300).get();
      final now = DateTime.now();
      final exp = Timestamp.fromMillisecondsSinceEpoch(DateTime(now.year, now.month, now.day + 1).millisecondsSinceEpoch);
      final b = db.batch();
      for (final u in fl.docs) {
        if (u.id == me.uid) continue;
        b.set(db.collection('notifs').doc('nc_${id}_${u.id}'), {
          'to': u.id, 'from': me.uid, 'fn': me.name, 'type': 'newcoupon', 'pid': ts, 'pd': id, 'ts': ts, 'exp': exp, 'tx': '${c['type']}',
        });
      }
      await b.commit();
    } catch (_) {}
    setState(() {
      _sel.clear();
      _misli = 1;
      _slot = 0;
    });
    _toast('Kupon paylaşıldı.');
    widget.onShared();
  } catch (e) {
    _toast(AuthService.errorText(e));
  } finally {
    if (mounted) setState(() => _busy = false);
  }
}

@override
Widget build(BuildContext context) {
  final c = AppColors.of(context);
  if (s.loading && s.cities.isEmpty) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      CircularProgressIndicator(color: c.ac),
      const SizedBox(height: 12),
      Text('Bülten yükleniyor…', style: jakarta(13, FontWeight.w600, c.mu)),
    ]));
  }
  if (s.cities.isEmpty) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      _dateBar(c),
      const SizedBox(height: 30),
      Center(child: Text(s.error ?? 'Program alınamadı.', textAlign: TextAlign.center, style: jakarta(13, FontWeight.w600, c.mu))),
      const SizedBox(height: 12),
      Center(child: FilledButton(onPressed: () => s.load(s.iso), style: FilledButton.styleFrom(backgroundColor: c.ac), child: Text('Tekrar dene', style: jakarta(13, FontWeight.w800, c.on)))),
    ]);
  }
  final race = s.race(_city, _race);
  final lr = _lr;
  final st = _t.mode == 'legs' ? legStarts(_t, _city) : <int>[];
  final tabRaces0 = _t.mode == 'race' ? lr.where((r) => oyunMusait(_t, _city, r)).toList() : lr;
  final tabRaces = tabRaces0.isEmpty ? lr : tabRaces0;

  return Column(children: [
    Expanded(
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0) return false;
          if (n is ScrollStartNotification) {
            AtHistPrefetch.scrolling = true;
          } else if (n is ScrollEndNotification) {
            AtHistPrefetch.scrolling = false;
            AtHistPrefetch.scrollEnd = DateTime.now();
          }
          return false;
        },
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), children: [
        _dateBar(c),
        const SizedBox(height: 8),
        _typeBox(c),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('TJK · ${s.cities.length} hipodrom · ${s.cities.fold<int>(0, (a, b) => a + s.races(b.name).length)} koşu',
              style: jakarta(10.5, FontWeight.w600, c.mu))),
          GestureDetector(onTap: () => s.load(s.iso), child: Text('Yenile', style: jakarta(11.5, FontWeight.w800, c.ac))),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => showLive(context),
            child: Text('● Canlı yayın', style: jakarta(11.5, FontWeight.w800, c.red)),
          ),
        ]),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [for (final ct in s.cities) _chip(c, ct.name, ct.name == _city, () => _setCityTo(ct.name))]),
        ),
        if (st.length > 1) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < st.length; i++)
                _chip(c, '${i + 1}. ${_t.name.split(' ').last == 'Ganyan' ? 'grup' : 'grup'} · ${st[i]}.–${st[i] + _t.n - 1}.', st[i] == (lr.isNotEmpty ? lr.first : -1), () {
                  setState(() {
                    if (_sel.isNotEmpty) {
                      _sel.clear();
                      _toast('Ayak grubu değişti, seçimler temizlendi.');
                    }
                    _legSel['${_t.k}|$_city'] = st[i];
                    _race = st[i];
                    _slot = 0;
                  });
                }),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < tabRaces.length; i++) _legTab(c, i, tabRaces[i]),
          ]),
        ),
        const SizedBox(height: 8),
        if (race != null) _raceCard(c, race),
        if (race != null) _raceResult(c, race),
        if (_t.mode == 'race' && (_t.slots > 0 || _t.tabs > 0) && !_t.vir) ...[
          const SizedBox(height: 6),
          Row(children: [
            for (var i = 0; i < (_t.slots > 0 ? _t.slots : _t.tabs); i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _chip(c, '${i + 1}. At${_picks(_race, i).isNotEmpty ? ' (${_picks(_race, i).length})' : ''}', _slot == i, () => setState(() => _slot = i)),
              ),
          ]),
        ],
        if (_t.mode == 'race' && !oyunMusait(_t, _city, _race))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${_t.name} bu koşuda oynanmıyor${(tekKosular(_t, _city, admin: _admin) ?? []).isNotEmpty ? ' · oynanan: ${fmtKos(tekKosular(_t, _city, admin: _admin)!)}' : ''}',
              style: jakarta(11.5, FontWeight.w800, c.red),
            ),
          ),
        if (_t.hint.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_t.hint, style: jakarta(11, FontWeight.w500, c.mu))),
        const SizedBox(height: 8),
        if (race != null) for (final h in race.atlar) RepaintBoundary(child: _horseCard(c, h)),
      ]),
      ),
    ),
    _couponBar(c),
  ]);
}

Widget _dateBar(AppColors c) {
  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
    child: Row(children: [
      _arrow(c, Icons.chevron_left, () => _day(-1)),
      Expanded(
        child: Column(children: [
          if (isoTag(s.iso).isNotEmpty) Text(isoTag(s.iso), style: jakarta(10, FontWeight.w800, c.ac)),
          Text(isoLabel(s.iso), style: jakarta(14.5, FontWeight.w800, c.tx)),
        ]),
      ),
      _arrow(c, Icons.chevron_right, () => _day(1)),
    ]),
  );
}

void _day(int d) {
  final n = isoAdd(s.iso, d);
  if (n.compareTo(isoAdd(isoToday(), 1)) > 0 || n.compareTo(isoAdd(isoToday(), -14)) < 0) return;
  setState(() {
    _sel.clear();
    _city = '';
    _slot = 0;
  });
  s.load(n);
}

Widget _arrow(AppColors c, IconData ic, VoidCallback f) => GestureDetector(
      onTap: f,
      child: Container(width: 34, height: 34, decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(12)), child: Icon(ic, color: c.tx, size: 18)),
    );

Widget _chip(AppColors c, String t, bool on, VoidCallback f) => Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: on ? c.ac : c.sf, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? c.ac : c.ln, width: 1)),
          child: Text(t, style: jakarta(12, FontWeight.w800, on ? c.on : c.tx)),
        ),
      ),
    );

Widget _legTab(AppColors c, int i, int r) {
  final on = r == _race;
  final has = _sel.any((x) => x.r == r);
  final legs = _t.mode == 'legs';
  final fin = s.raceDone(_city, r);
  final fg = on ? c.on : c.tx;
  return Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Opacity(
      opacity: fin && !on ? 0.6 : 1,
      child: GestureDetector(
        onTap: () => setState(() {
          _race = r;
          if (_t.mode == 'race' && _sel.any((x) => x.r != r)) {
            _sel.clear();
            _toast('Yeni koşu için seçimler temizlendi.');
          }
          _slot = 0;
        }),
        child: Stack(children: [
          Container(
            constraints: const BoxConstraints(minWidth: 60),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            decoration: BoxDecoration(color: on ? c.ac : c.sf, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? c.ac : c.ln, width: 1)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (legs && fin) Text('✓', style: jakarta(12, FontWeight.w800, fg)),
              if (legs) Text('${i + 1}. Ayak', style: jakarta(12, FontWeight.w800, fg))
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${fin ? '✓ ' : ''}$r. Koşu', style: jakarta(12, FontWeight.w800, fg)),
                  if (fin) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: on ? const Color(0x3DFFFFFF) : const Color(0x241A9B5C), borderRadius: BorderRadius.circular(5)),
                      child: Text('Bitti', style: jakarta(8.5, FontWeight.w800, on ? c.on : const Color(0xFF1A9B5C))),
                    ),
                  ],
                ]),
              Text(legs ? '$r. Koşu' : _saat(r), style: jakarta(10, FontWeight.w600, on ? c.on : c.mu)),
            ]),
          ),
          if (has)
            Positioned(
              top: 5,
              right: 5,
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle)),
            ),
        ]),
      ),
    ),
  );
}

Widget _typeBox(AppColors c) {
  final st = _t.mode == 'legs' ? legStarts(_t, _city) : <int>[];
  final ord = (st.length > 1 && _lr.isNotEmpty && st.contains(_lr.first)) ? '${st.indexOf(_lr.first) + 1}. ' : '';
  return Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    decoration: BoxDecoration(color: c.ac.withAlpha(20), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ac)),
    child: Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BAHİS TÜRÜ', style: jakarta(9.5, FontWeight.w800, c.ac)),
          Text('$ord${_t.name}', style: jakarta(16, FontWeight.w800, c.tx)),
        ]),
      ),
      FilledButton.icon(
        onPressed: _pickType,
        style: FilledButton.styleFrom(
          backgroundColor: c.ac, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
        ),
        icon: Icon(Icons.keyboard_arrow_down, color: c.on, size: 16),
        label: Text('Değiştir', style: jakarta(12, FontWeight.w800, c.on)),
      ),
    ]),
  );
}

void _pickType() {
  final c = AppColors.of(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      final list = kTypes.where((t) {
        if (t.si == 1) return legStarts(t, _city).length > 1;
        return true;
      }).toList();
      return SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: Column(children: [
          const SizedBox(height: 12),
          Text('Bahis türü seç', style: jakarta(15, FontWeight.w800, c.tx)),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(10), children: [
              for (final t in list)
                Builder(builder: (_) {
                  final m = typeMusait(t, _city, admin: _admin);
                  final on = t.k == _t.k;
                  return Opacity(
                    opacity: m.ok ? 1 : 0.45,
                    child: GestureDetector(
                      onTap: m.ok
                          ? () {
                              Navigator.pop(ctx);
                              _setType(t);
                            }
                          : () => _toast('${t.name}: ${m.why}'),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: on ? c.ac.withAlpha(24) : c.sf, borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? c.ac : c.ln)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${t.si == 1 ? '2. ' : t.si == 0 && legStarts(t, _city).length > 1 ? '1. ' : ''}${t.name}', style: jakarta(13, FontWeight.w800, c.tx)),
                              Text(m.ok ? [if (t.desc.isNotEmpty) t.desc else t.sub, if (tekSub(t, _city, admin: _admin) != null) tekSub(t, _city, admin: _admin)!].join(' · ') : m.why, style: jakarta(11, FontWeight.w500, c.mu)),
                            ]),
                          ),
                          Text(money(birimFiyat(t.name, _city)), style: jakarta(11, FontWeight.w700, c.ac)),
                        ]),
                      ),
                    ),
                  );
                }),
            ]),
          ),
        ]),
      );
    },
  );
}

bool _resFilmBusy = false;

Future<void> _openRaceFilm(Race r, RaceResult rr) async {
  if (_resFilmBusy || rr.video.isEmpty) return;
  _resFilmBusy = true;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Video yükleniyor…'), duration: Duration(seconds: 8)));
  try {
    final mp4 = await getVideoMp4(rr.video, s.iso);
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    if (mp4 == null) {
      await launchUrl(Uri.parse(rr.video), mode: LaunchMode.externalApplication);
      return;
    }
    final rows = <FilmRow>[];
    for (final no in rr.sira.take(4)) {
      String nm = '';
      for (final x in r.atlar) {
        if (x.no == no) nm = x.name;
      }
      rows.add(FilmRow(no, nm, rr.gny[no]));
    }
    final p = s.iso.split('-');
    await showRaceFilm(context, url: mp4, race: r.no, city: _city, dateLabel: '${p[2]}.${p[1]}.${p[0]}', rows: rows);
  } catch (_) {
    messenger.hideCurrentSnackBar();
    _toast('Video açılamadı.');
  } finally {
    _resFilmBusy = false;
  }
}

Widget _raceResult(AppColors c, Race r) {
  final rr = s.results[_city]?[r.no];
  if (rr == null || (rr.sira.isEmpty && rr.bahis.isEmpty)) return const SizedBox.shrink();
  Horse? at(int no) {
    for (final h in r.atlar) {
      if (h.no == no) return h;
    }
    return null;
  }

  Widget head(String t) => Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), child: Text(t, style: jakarta(12, FontWeight.w800, c.mu, ls: 0.5)));
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(top: 8),
    decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
    clipBehavior: Clip.antiAlias,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (rr.sira.isNotEmpty) ...[
        head('KOŞU BİTTİ'),
        for (var i = 0; i < rr.sira.length && i < 4; i++)
          Builder(builder: (_) {
            final no = rr.sira[i];
            final h = at(no);
            final win = i == 0;
            final g = rr.gny[no] ?? '';
            final pc = win ? const Color(0xFF7C3AED) : const Color(0xFF2563EB);
            return Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: win ? const Color(0xFFD97706).withAlpha(30) : c.sf2, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                NoBadge(no, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(h?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(14, FontWeight.w800, c.tx)),
                    if ((h?.jockey ?? '').isNotEmpty) Text(h!.jockey, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(11.5, FontWeight.w600, c.mu)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(win ? 'Kazandı' : '${i + 1}. oldu', style: jakarta(12, FontWeight.w800, win ? const Color(0xFFD97706) : c.mu)),
                  if (g.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                      decoration: BoxDecoration(color: pc.withAlpha(28), borderRadius: BorderRadius.circular(10), border: Border.all(color: pc.withAlpha(60))),
                      child: Text('Ganyan $g', style: jakarta(11.5, FontWeight.w800, pc)),
                    ),
                ]),
              ]),
            );
          }),
      ],
      if (rr.bahis.isNotEmpty) ...[
        head('BAHİS ÖDEMELERİ'),
        for (final x in rr.bahis)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
            child: Row(children: [
              Expanded(child: Text(x.tur, style: jakarta(12.5, FontWeight.w700, c.tx))),
              if (x.detay.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 10), child: Text(x.detay, style: jakarta(11, FontWeight.w600, c.mu))),
              Text('${x.tutar} ₺', style: jakarta(12.5, FontWeight.w800, c.gold)),
            ]),
          ),
      ],
      if (rr.video.isNotEmpty)
        GestureDetector(
          onTap: () => _openRaceFilm(r, rr),
          child: Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF0F1420), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE0305A).withAlpha(120))),
            child: Row(children: [
              Container(width: 34, height: 34, decoration: const BoxDecoration(color: Color(0xFFE0305A), shape: BoxShape.circle), child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text('Koşu videosunu izle', style: jakarta(14, FontWeight.w800, Colors.white))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFE0305A), borderRadius: BorderRadius.circular(8)), child: Text('VİDEO', style: jakarta(11, FontWeight.w800, Colors.white))),
            ]),
          ),
        ),
    ]),
  );
}

Widget _raceCard(AppColors c, Race r) {
  final done = !_open(r.no);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: c.ac.withAlpha(14), borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$_city ${r.no}. Koşu • ${r.saat}', style: jakarta(15, FontWeight.w800, c.tx)),
      if (r.bilgi.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(r.bilgi, style: jakarta(11, FontWeight.w500, c.mu))),
      Text('${r.atlar.length} at', style: jakarta(11, FontWeight.w500, c.mu)),
      if (done)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Koşu başladı / bitti · seçime kapalı', style: jakarta(10.5, FontWeight.w800, c.red))),
      // TJK'daki gibi: "1. ÇİFTE, 7'Lİ PLASE, ... bu koşudan başlar, GANYAN, İKİLİ, ..."
      Builder(builder: (_) {
        final bs = baslarYazi(_city, r.no);
        if (bs.isEmpty) return const SizedBox.shrink();
        return Padding(padding: const EdgeInsets.only(top: 8), child: Text(bs, style: jakarta(13, FontWeight.w700, c.tx)));
      }),
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 4),
          dense: true,
          visualDensity: const VisualDensity(vertical: -3),
          title: Text('ⓘ ${_t.name} nasıl oynanır?', style: jakarta(13, FontWeight.w700, c.tx)),
          children: [Align(alignment: Alignment.centerLeft, child: Text(kuralMetni(_t, _city), style: jakarta(12, FontWeight.w500, c.mu)))],
        ),
      ),
    ]),
  );
}
  Color _pill(double v) => v < 2 ? const Color(0xFF16A34A) : v < 5 ? const Color(0xFF2563EB) : v < 10 ? const Color(0xFFD97706) : v < 25 ? const Color(0xFFEA580C) : const Color(0xFFDC2626);

String _kgsTxt(String k) {
  final n = int.tryParse(k.trim());
  if (n == null) return k;
  return n == 0 ? 'Bugün' : n == 1 ? 'Dün' : '$n gün önce';
}

Widget _statCell(AppColors c, String lab, String val, {Color? col, bool right = true, bool bottom = true}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 6, 6, 6),
        decoration: BoxDecoration(border: Border(right: right ? BorderSide(color: c.ln) : BorderSide.none, bottom: bottom ? BorderSide(color: c.ln) : BorderSide.none)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lab, style: jakarta(10.5, FontWeight.w600, c.mu)),
          Text(val, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(14, FontWeight.w800, col ?? c.tx)),
        ]),
      ),
    );

Future<void> _playIdman(Horse h) async {
  if (_idmBusy) return;
  _idmBusy = true;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Video yükleniyor…'), duration: Duration(seconds: 8)));
  try {
    final mp4 = await getIdmanMp4(h, s.iso);
    messenger.hideCurrentSnackBar();
    if (!mounted) return;
    if (mp4 == null) {
      _toast('İdman videosu bulunamadı.');
      return;
    }
    await showRaceFilm(context, url: mp4, race: _race, city: _city, dateLabel: '', rows: const [], title: h.name, subtitle: 'İdman videosu', badge: '${h.no}');
  } catch (_) {
    messenger.hideCurrentSnackBar();
    _toast('İdman videosu açılamadı.');
  } finally {
    _idmBusy = false;
  }
}

String _nkey(String x) => x.toUpperCase().replaceAll('İ', 'I').replaceAll('Ğ', 'G').replaceAll('Ü', 'U').replaceAll('Ş', 'S').replaceAll('Ö', 'O').replaceAll('Ç', 'C').replaceAll(RegExp(r'[^A-Z0-9]'), '');

// Atın o yarışının ilk 4'ünü getirir (şehir + tarih + koşu no ile)
Future<List<FilmRow>> _sonucYukle(AtRow row) async {
  final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(row.t);
  final kn = int.tryParse(row.kn);
  if (m == null || kn == null || row.sh.isEmpty) throw 'eksik';
  final iso = '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
  final hedef = _nkey(row.sh);
  City? c;
  for (final x in await getCities(iso)) {
    final a = _nkey(x.name);
    if (a.startsWith(hedef) || hedef.startsWith(a)) {
      c = x;
      break;
    }
  }
  if (c == null) throw 'sehir yok';
  final races = await getProgram(c, iso);
  final res = await getResults(c, iso, races);
  final rr = res[kn];
  if (rr == null || rr.sira.isEmpty) throw 'sonuc yok';
  Race? race;
  for (final k in races) {
    if (k.no == kn) race = k;
  }
  final rows = <FilmRow>[];
  for (final no in rr.sira.take(4)) {
    var nm = '';
    for (final h in race?.atlar ?? const <Horse>[]) {
      if (h.no == no) nm = h.name;
    }
    rows.add(FilmRow(no, nm, rr.gny[no]));
  }
  return rows;
}

// "05.04.2026" -> "7 ay önce" (webdeki galipGun ile aynı)
String _gunOnce(String t) {
  final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(t.trim());
  if (m == null) return '';
  final now = DateTime.now();
  final d0 = DateTime(now.year, now.month, now.day);
  final d1 = DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  final n = d0.difference(d1).inDays;
  if (n < 0) return '';
  if (n == 0) return 'Bugün';
  if (n == 1) return 'Dün';
  if (n < 60) return '$n gün önce';
  if (n < 730) return '${(n / 30).round()} ay önce';
  return '${n ~/ 365} yıl önce';
}

// Son yarışta atın numarasını, o koşunun programından kulvara göre bulur (webdeki NO rozeti)
final Map<String, String> _yarNoMem = {};
Future<String> _yarNoBul(AtRow row) async {
  if (row.no.isNotEmpty) return row.no;
  final key = '${row.sh}|${row.t}|${row.kn}|${row.st}';
  final hit = _yarNoMem[key];
  if (hit != null) return hit;
  try {
    final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(row.t);
    final kn = int.tryParse(row.kn);
    final st = int.tryParse(row.st);
    if (m == null || kn == null || st == null || row.sh.isEmpty) return '';
    final iso = '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
    final hedef = _nkey(row.sh);
    City? c;
    for (final x in await getCities(iso)) {
      final a = _nkey(x.name);
      if (a.startsWith(hedef) || hedef.startsWith(a)) {
        c = x;
        break;
      }
    }
    if (c == null) return '';
    for (final k in await getProgram(c, iso)) {
      if (k.no != kn) continue;
      for (final h in k.atlar) {
        if (int.tryParse(h.st) == st) return _yarNoMem[key] = '${h.no}';
      }
    }
  } catch (_) {}
  return '';
}

Future<void> _playVideo(String url, String title, String horseName, [AtRow? row]) async {
  if (url.isEmpty) return;
  final mp4 = await getVideoMp4(url, s.iso);
  if (mp4 != null && mounted) {
    final lab = title == 'Son Galibiyet' ? 'Son galibiyet' : 'Son yarış';
    if (row != null) {
      await showRaceFilm(
        context,
        url: mp4,
        race: _race,
        city: _city,
        dateLabel: '',
        rows: const [],
        title: horseName,
        subtitle: '$lab · ${row.t}',
        badge: '▶',
        meName: horseName,
        meSub: '$lab · ${row.sh} ${row.kn}. Koşu',
        loader: () => _sonucYukle(row),
      );
    } else {
      await showRaceFilm(context, url: mp4, race: _race, city: _city, dateLabel: '', rows: const [], title: title, subtitle: horseName, badge: '▶');
    }
  } else {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

// Son 6 koşu bitiş sırası (üstte pist harfi: Ç çim, K kum, S sentetik) + takı çipleri
Widget _son6Row(AppColors c, Horse h) {
  Color pc(String p) => p == 'Ç' ? const Color(0xFF1A9B5C) : p == 'K' ? const Color(0xFFA8793D) : const Color(0xFF3B6FD8);
  Widget chip(String n) {
    final v = int.tryParse(n);
    Color bg = const Color(0x24788296), fg = c.mu;
    if (n == '1') { bg = const Color(0x38D4A000); fg = const Color(0xFF9A7000); }
    else if (n == '2') { bg = const Color(0x3D7887A0); fg = const Color(0xFF566274); }
    else if (n == '3') { bg = const Color(0x33B06432); fg = const Color(0xFF8A4B1F); }
    else if (n == '0' || (v != null && v >= 6)) { bg = const Color(0x26E5484D); fg = const Color(0xFFC53030); }
    return Container(
      constraints: const BoxConstraints(minWidth: 24),
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(n, style: jakarta(14, FontWeight.w800, fg)),
    );
  }
  return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
    if (h.son6.isNotEmpty) ...[
      Padding(padding: const EdgeInsets.only(bottom: 6, right: 8), child: Text('SON 6', style: jakarta(11, FontWeight.w800, c.mu).copyWith(letterSpacing: 0.4))),
      for (var i = 0; i < h.son6.length; i++)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: 14, child: Text(i < h.son6p.length ? h.son6p[i] : '', style: jakarta(10, FontWeight.w800, i < h.son6p.length && h.son6p[i].isNotEmpty ? pc(h.son6p[i]) : c.mu))),
            chip(h.son6[i]),
          ]),
        ),
    ],
    const Spacer(),
    for (final t in h.taki.take(4))
      Builder(
        builder: (ctx) => GestureDetector(
          // kartın "kupona ekle" dokunuşuna düşmesin: takıya basınca açıklama açılır
          behavior: HitTestBehavior.opaque,
          onTap: () => _takiInfo(ctx, c, t.k, t.a),
          child: Container(
            margin: const EdgeInsets.only(left: 4, bottom: 2),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.ac.withAlpha(22), borderRadius: BorderRadius.circular(12), border: Border.all(color: c.ac.withAlpha(80))),
            child: Text(t.k, style: jakarta(11.5, FontWeight.w800, c.ac)),
          ),
        ),
      ),
  ]);
}

void _takiInfo(BuildContext context, AppColors c, String kod, String aciklama) {
  showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: c.sf,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(color: c.ac.withAlpha(22), borderRadius: BorderRadius.circular(14), border: Border.all(color: c.ac.withAlpha(80))),
            child: Text(kod, style: jakarta(20, FontWeight.w800, c.ac)),
          ),
          const SizedBox(height: 14),
          Text(aciklama.isNotEmpty ? aciklama : 'Bu takı için açıklama bulunamadı.', textAlign: TextAlign.center, style: jakarta(15, FontWeight.w600, c.tx).copyWith(height: 1.35)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              height: 48,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.ac, borderRadius: BorderRadius.circular(16)),
              child: Text('Tamam', style: jakarta(15, FontWeight.w800, c.on)),
            ),
          ),
        ]),
      ),
    ),
  );
}

Widget _horseDetail(AppColors c, Horse h, String key) {
  final sik = h.siklet == null ? '' : h.siklet!.toStringAsFixed(h.siklet! % 1 == 0 ? 0 : 1).replaceAll('.', ',');
  final kgsN = int.tryParse(h.kgs.trim());
  final kgsCol = kgsN == null ? null : (kgsN <= 14 ? const Color(0xFF16A34A) : (kgsN >= 36 ? const Color(0xFFEA580C) : null));
  final cells = <(String, String, Color?)>[
    if (h.yas.isNotEmpty) ('Yaş', h.yas, null),
    if (sik.isNotEmpty) ('Sıklet', sik, null),
    if (h.st.isNotEmpty) ('Kulvar', h.st, null),
    if (h.hp != null) ('HP', '${h.hp}', const Color(0xFFD97706)),
    if (h.kgs.isNotEmpty) ('Son koşu', _kgsTxt(h.kgs), kgsCol),
    if (h.s20.isNotEmpty) ('S20', h.s20, null),
  ];
  final rows = <Widget>[];
  for (var i = 0; i < cells.length; i += 3) {
    final part = cells.sublist(i, (i + 3).clamp(0, cells.length));
    final last = i + 3 >= cells.length;
    rows.add(Row(children: [
      for (var j = 0; j < 3; j++)
        j < part.length
            ? _statCell(c, part[j].$1, part[j].$2, col: part[j].$3, right: j < 2, bottom: !last)
            : const Expanded(child: SizedBox()),
    ]));
  }
  final eid = RegExp(r'\d{1,2}\.\d{2}\.\d{2}').firstMatch(h.eid)?.group(0) ?? '';
  final em = RegExp(r'Bu derece\s+(.+?)\s+Hipodromu.{0,3}nda,?\s*([\d.]+)', caseSensitive: false).firstMatch(h.eid);
  final eidSub = em != null ? '${em.group(1)!.replaceAll(RegExp(r'\s+'), ' ')} · ${em.group(2)}' : '';
  final ek = s.races(_city).where((r) => r.no == _race).expand((r) => r.atlar).where((x) => x.no != h.no && !x.kosmaz && h.sahip.isNotEmpty && x.sahip.toUpperCase() == h.sahip.toUpperCase()).toList();
  final orOpen = _orOpen.contains(key);
  
  Widget line(String lab, String val) => val.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 60, child: Text(lab, style: jakarta(10, FontWeight.w700, c.mu))),
              Expanded(child: Text(val, style: jakarta(12, FontWeight.w700, c.tx))),
            ],
          ),
        );

  Widget vidBtn(String url, String title, [AtRow? row]) => GestureDetector(
    onTap: () => _playVideo(url, title, h.name, row),
    child: Container(
      padding: const EdgeInsets.fromLTRB(2, 2, 9, 2),
      decoration: BoxDecoration(color: const Color(0xFF0F1A30), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 16, decoration: const BoxDecoration(color: Color(0xFFEF4444), shape: BoxShape.circle), child: const Icon(Icons.play_arrow, color: Colors.white, size: 11)),
        const SizedBox(width: 5),
        Text('Videoyu izle', style: jakarta(10, FontWeight.w800, Colors.white)),
      ]),
    ),
  );

  // Webdeki .hgal kartı: küçük başlık + büyük satır solda, sağda ek bilgi + buton
  Widget hCard(Color col, String small, String big, {String right = '', Widget? btn, Widget? lead, String below = '', bool center = false}) {
    final left = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(small, style: jakarta(10.5, FontWeight.w700, col)),
      const SizedBox(height: 1),
      Text(big, style: jakarta(15, FontWeight.w800, col).copyWith(height: 1.25)),
      if (below.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(below, style: jakarta(12, FontWeight.w600, col))),
    ]);
    final hasRight = right.isNotEmpty || btn != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: col.withAlpha(28), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
        if (lead != null) ...[lead, const SizedBox(width: 10)],
        Expanded(child: left),
        if (hasRight) ...[
          const SizedBox(width: 8),
          // Sağ sütun içeriği kadar yer kaplar ve hep sağ kenara yaslanır: kartlar arasında kayma olmaz
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              if (right.isNotEmpty) Text(right, textAlign: TextAlign.right, style: jakarta(12, FontWeight.w600, col)),
              if (right.isNotEmpty && btn != null) const SizedBox(height: 6),
              if (btn != null) btn,
            ]),
          ),
        ],
      ]),
    );
  }

  Widget noBox(String no) => Container(
        constraints: const BoxConstraints(minWidth: 34),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: const Color(0xFF7C3AED), borderRadius: BorderRadius.circular(9)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('NO', style: jakarta(8, FontWeight.w700, Colors.white70)),
          Text(no, style: jakarta(16, FontWeight.w800, Colors.white).copyWith(height: 1)),
        ]),
      );

  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    if (rows.isNotEmpty) Container(decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))), child: Column(children: rows)),
    
    if (h.idmK.isNotEmpty)
      GestureDetector(
        onTap: () => _playIdman(h),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: c.red.withAlpha(24), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Container(width: 26, height: 26, decoration: BoxDecoration(color: c.red, shape: BoxShape.circle), child: const Icon(Icons.play_arrow, color: Colors.white, size: 16)),
            const SizedBox(width: 8),
            Expanded(child: Text('İdman videosunu izle', style: jakarta(12, FontWeight.w800, c.red))),
            Text('İzle ›', style: jakarta(10.5, FontWeight.w800, c.red)),
          ]),
        ),
      ),

    FutureBuilder<AtHist>(
      future: getAtHist(h.atId),
      builder: (context, snapshot) {
        final yaris = snapshot.data?.yaris;
        if (yaris == null) return const SizedBox.shrink();
        final gun = _gunOnce(yaris.t);
        return FutureBuilder<String>(
          future: _yarNoBul(yaris),
          initialData: yaris.no,
          builder: (context, ns) {
            final no = ns.data ?? '';
            return hCard(const Color(0xFF7C3AED), 'Son yarış${gun.isEmpty ? '' : ' · $gun'}', yaris.d.isNotEmpty ? yaris.d : yaris.t,
                right: yaris.y, btn: yaris.v.isNotEmpty ? vidBtn(yaris.v, 'Son Yarış', yaris) : null, lead: no.isNotEmpty ? noBox(no) : null);
          },
        );
      },
    ),

    if (eid.isNotEmpty) hCard(const Color(0xFF16A34A), 'En iyi derece', eid, right: eidSub, center: true),

    FutureBuilder<AtHist>(
      future: getAtHist(h.atId),
      builder: (context, snapshot) {
        final gal = snapshot.data?.galibiyet;
        if (gal == null) return const SizedBox.shrink();
        final gun = _gunOnce(gal.t);
        return hCard(const Color(0xFFE8890C), 'Son galibiyet${gun.isEmpty ? '' : ' · $gun'}', gal.d.isNotEmpty ? '${gal.t} · ${gal.d}' : gal.t,
            right: gal.y, btn: gal.v.isNotEmpty ? vidBtn(gal.v, 'Son Galibiyet', gal) : null);
      },
    ),

    FutureBuilder<AtRow?>(
      future: getAtGalop(h.atId),
      builder: (context, snapshot) {
        final gop = snapshot.data;
        if (gop == null) return const SizedBox.shrink();
        final gun = _gunOnce(gop.t);
        return hCard(const Color(0xFF2563EB), 'Son galop${gun.isEmpty ? '' : ' · $gun'}', gop.d.isNotEmpty ? '${gop.t} · ${gop.d}' : gop.t, below: gop.y);
      },
    ),

    if (ek.isNotEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Ekürü: ${ek.map((x) => '${x.no} ${x.name}').join(' · ')}', style: jakarta(10, FontWeight.w700, c.mu)),
      ),

    if (h.orijin.isNotEmpty || h.sahip.isNotEmpty || h.antrenor.isNotEmpty)
      GestureDetector(
        onTap: () => setState(() => orOpen ? _orOpen.remove(key) : _orOpen.add(key)),
        child: Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Orijin, sahip, antrenör', style: jakarta(11, FontWeight.w700, c.mu))),
              Icon(orOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: c.mu, size: 18),
            ]),
            if (orOpen) ...[line('Orijin', h.orijin), line('Sahip', h.sahip), line('Antrenör', h.antrenor)],
          ]),
        ),
      ),
  ]);
}
    Widget _horseCard(AppColors c, Horse h) {
    final slot = _t.mode == 'legs' ? 0 : (_t.vir ? _sel.indexWhere((x) => x.no == h.no) : _slot);
    final on = _t.vir ? _sel.any((x) => x.no == h.no && x.r == _race) : _sel.any((x) => x.r == _race && x.slot == slot && x.no == h.no);
    final order = _t.vir && on ? _sel.indexWhere((x) => x.no == h.no) + 1 : 0;
    final odds = (h.gny ?? 0) > 1 ? h.gny : (h.agf != null && h.agf! > 0 ? (75 / h.agf!).clamp(1.1, 999.0) : null);
    final est = (h.gny ?? 0) <= 1;
    
    // Özet metni
    final sum = [
      if (h.yas.isNotEmpty) h.yas,
      if (h.siklet != null) '${h.siklet!.toStringAsFixed(h.siklet! % 1 == 0 ? 0 : 1)} kg',
      if (h.hp != null) 'HP ${h.hp}',
      if (h.kgs.isNotEmpty) _kgsTxt(h.kgs)
    ].join(' · ');

    return Opacity(
      opacity: h.kosmaz ? 0.4 : 1,
      child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: on ? c.ac.withAlpha(24) : c.sf, 
            borderRadius: BorderRadius.circular(16), 
            border: Border.all(color: on ? c.ac : c.ln, width: on ? 2 : 1)
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              NoBadge(h.no, size: 32),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.name + (h.kosmaz ? ' (Koşmaz)' : ''), maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(14, FontWeight.w800, c.tx)),
                  Text(h.jockey, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(11.5, FontWeight.w600, c.mu)),
                ]),
              ),
              // Takip atı: koşmaya hazır olunca zile bildirim gelir
              ListenableBuilder(
                listenable: HorseWatch.i,
                builder: (_, __) {
                  final fw = HorseWatch.i.isFollowing(h.name);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final nowOn = await HorseWatch.i.toggle(h.name, h.atId);
                      _toast(nowOn ? '${h.name} takip edildi. Koşacağı zaman zile bildirim gelecek.' : '${h.name} takipten çıkarıldı.');
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(fw ? Icons.star_rounded : Icons.star_border_rounded, size: 22, color: fw ? c.gold : c.mu),
                    ),
                  );
                },
              ),
              if (h.agf != null) Padding(padding: const EdgeInsets.only(right: 6), child: Text('%${h.agf}', style: jakarta(11.5, FontWeight.w800, const Color(0xFFD97706)))),
              if (odds != null)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: _pill(odds.toDouble()).withAlpha(30), borderRadius: BorderRadius.circular(8), border: Border.all(color: _pill(odds.toDouble()).withAlpha(120))),
                  child: Text('${est ? '≈ ' : 'Gny '}${odds.toStringAsFixed(2).replaceAll('.', ',')}', style: jakarta(10.5, FontWeight.w800, _pill(odds.toDouble()))),
                ),
              // Kupona ekleme/çıkarma sadece yuvarlak işarete dokununca olur
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tap(h),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: on ? c.ac : Colors.transparent, border: Border.all(color: on ? c.ac : c.ln, width: 1.5)),
                    child: on ? (order > 0 ? Text('$order', style: jakarta(12, FontWeight.w800, c.on)) : Icon(Icons.check, color: c.on, size: 17)) : Icon(Icons.add, color: c.ac, size: 20),
                  ),
                ),
              ),
            ]),
            if (h.son6.isNotEmpty || h.taki.isNotEmpty) ...[
              const SizedBox(height: 8),
              _son6Row(c, h),
            ],
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final open = _detOpen.contains('$_city|$_race|${h.no}');
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(open ? 'Detay bilgileri' : sum, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(11, FontWeight.w600, c.mu))),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      final k = '$_city|$_race|${h.no}';
                      if (open) {
                        _detOpen.remove(k);
                      } else {
                        _detOpen
                          ..clear() // diğer açık detaylar kapansın
                          ..add(k);
                      }
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text('Detay ${open ? '▴' : '▾'}', style: jakarta(12, FontWeight.w800, c.ac)),
                    ),
                  ),
                ]),
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.topCenter,
                  child: open ? _horseDetail(c, h, '$_city|$_race|${h.no}') : const SizedBox(width: double.infinity),
                ),
              ]);
            }),
          ]),
      ),
    );
  }

  Widget _couponBar(AppColors c) {
    final cp = _build();
    final legs = (cp?['legs'] as List?)?.cast<Map>() ?? const [];
    final slotsMode = _t.mode == 'race' && (_t.slots > 0 || _t.tabs > 0);
    final total = _t.mode == 'legs' ? _lr.length : (_t.vir ? 0 : (_t.slots > 0 ? _t.slots : (_t.tabs > 0 ? _t.tabs : 1)));
    final chips = <Widget>[];
    if (_t.mode == 'legs') {
      for (final r in _lr) {
        final p = _picks(r, 0);
        chips.add(_miniChip(c, p.isEmpty ? '–' : p.join(','), r == _race, () => setState(() => _race = r)));
      }
    } else if (slotsMode && !_t.vir) {
      for (var i = 0; i < total; i++) {
        final p = _picks(_race, i);
        chips.add(_miniChip(c, p.isEmpty ? '–' : p.join(','), _slot == i, () => setState(() => _slot = i)));
      }
    } else {
      final p = _picks(_race, 0);
      chips.add(_miniChip(c, _t.vir ? (_sel.isEmpty ? '–' : _sel.map((x) => x.no).join('-')) : (p.isEmpty ? '–' : p.join(',')), true, () {}));
    }
    // Eksik ayak varken de seçilenlere göre "şimdilik" tutarı hesapla (web'deki kolonNow gibi)
    Map<String, dynamic>? part = cp;
    if (cp != null && _t.mode == 'legs') {
      final pl = legs.where((l) => (l['picks'] as List).isNotEmpty).toList();
      part = pl.isEmpty ? null : <String, dynamic>{...cp, 'legs': pl};
    }
    final k = part == null ? 0 : kolon(part);
    final cost = part == null ? 0.0 : couponCost(part);
    final filled = _t.mode == 'legs' ? legs.where((l) => (l['picks'] as List).isNotEmpty).length : 0;
    
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + MediaQuery.paddingOf(context).bottom * 0),
      decoration: BoxDecoration(color: c.sf, border: Border(top: BorderSide(color: c.ln)), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [...chips, if (_sel.isNotEmpty) _clearBtn(c)])),
        const SizedBox(height: 6),
        StreamBuilder<int>(
          stream: Credits.watch(profileNotifier.value?.uid ?? ''),
          builder: (context, snap) {
          final kr = snap.data ?? Credits.welcome;
          final yok = !_admin && kr < Credits.perKupon;
          return Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t.mode == 'legs' ? '$filled/${_lr.length} ayak${filled < _lr.length ? ' · ${_lr.length - filled} eksik · şimdilik' : ''}' : '$k kolon', style: jakarta(10.5, FontWeight.w600, c.mu)),
              Text(money(cost), style: jakarta(18, FontWeight.w800, c.ac)),
              Text('Kredi: $kr', style: jakarta(11, FontWeight.w800, c.gold)),
            ]),
          ),
          Container(
            height: 36,
            decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              IconButton(
                onPressed: _misli > 1 ? () => setState(() => _misli--) : null, 
                icon: const Icon(Icons.remove, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text('$_misli', style: jakarta(14, FontWeight.w800, c.tx)),
              IconButton(
                onPressed: _misli < 99 ? () => setState(() => _misli++) : null, 
                icon: const Icon(Icons.add, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: _busy || _sel.isEmpty ? null : (yok ? () => watchVideoForCredit(context) : _share),
              style: FilledButton.styleFrom(
                backgroundColor: yok ? c.gold : c.ac, 
                padding: const EdgeInsets.symmetric(horizontal: 16), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: Size.zero,
              ),
              child: Text(yok ? '▶ Video izle +${Credits.videoReward}' : (_admin ? 'Paylaş' : 'Paylaş · ${Credits.perKupon} kredi'), style: jakarta(12.5, FontWeight.w800, yok ? Colors.white : c.on)),
            ),
          ),
        ]);
          },
        ),
      ]),
    );
  }

  Widget _clearBtn(AppColors c) => GestureDetector(
        onTap: () => setState(() {
          _sel.clear();
          _misli = 1;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(8)),
          child: Text('Temizle', style: jakarta(11, FontWeight.w700, c.mu)),
        ),
      );

  Widget _miniChip(AppColors c, String t, bool on, VoidCallback f) => Padding(
        padding: const EdgeInsets.only(right: 4),
        child: GestureDetector(
          onTap: f,
          child: Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: on ? c.ac.withAlpha(30) : c.sf2, borderRadius: BorderRadius.circular(8), border: Border.all(color: on ? c.ac : c.ln)),
            child: Text(t, textAlign: TextAlign.center, style: jakarta(12, FontWeight.w800, c.tx)),
          ),
        ),
      );
}
