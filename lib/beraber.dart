import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'athist_prefetch.dart';
import 'film.dart';
import 'firebase_options.dart' show firebaseReady;
import 'shell.dart' show IconBox;
import 'theme.dart';
import 'tjk.dart';

/// Seçili koşudaki atların daha önce BERABER koştuğu koşular.
/// Performans: istekler 3'erli paketle gider, sonuçlar geldikçe liste dolar,
/// her koşu kartı kendi durumunu tutar (sayfa baştan çizilmez), hesaplanan koşular önbellekte kalır.
class TogetherPage extends StatefulWidget {
  const TogetherPage({super.key});
  @override
  State<TogetherPage> createState() => _TogetherPageState();
}

class _Row {
  final String name;
  final AtPast p;
  const _Row(this.name, this.p);
}

class _Grp {
  final String key;
  final List<_Row> rows;
  _Grp(this.key, this.rows);
  AtPast get f => rows.first.p;
}

final Map<String, List<_Grp>> _cache = {};

DateTime _date(String t) {
  final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(t);
  if (m == null) return DateTime(1970);
  return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
}

class _TogetherPageState extends State<TogetherPage> {
  final s = TjkStore.i;
  String _city = '';
  int _no = 1;
  int _gen = 0;
  // Liste ve yükleniyor bilgisi ayrı dinlenir: sadece liste alanı yeniden çizilir, üst çubuklar değil
  final _groups = ValueNotifier<List<_Grp>?>(null);
  final _busy = ValueNotifier<bool>(false);
  final _prog = ValueNotifier<String>(''); // "6/14" gibi yükleme ilerlemesi
  // Tahmin Yap ile aynı kural: parmak ekrandayken / kayarken ağır iş ve liste güncellemesi yok
  DateTime _touch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _scrolling = false;
  List<_Grp>? _pending;
  DateTime _lastPub = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (s.cities.isNotEmpty) _city = s.cities.first.name;
    // Sayfa açılış animasyonu bitsin, sonra ağır işe başla
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _gen++;
    AtHistPrefetch.scrolling = false;
    _groups.dispose();
    _busy.dispose();
    _prog.dispose();
    super.dispose();
  }

  bool get _idle => !_scrolling && DateTime.now().difference(_touch) > const Duration(milliseconds: 600);

  List<_Grp> _build(Map<String, List<AtPast>> data) {
    final by = <String, List<_Row>>{};
    data.forEach((name, l) {
      for (final p in l) {
        if (p.key.isNotEmpty) (by[p.key] ??= []).add(_Row(name, p));
      }
    });
    final g = [
      for (final e in by.entries)
        if (e.value.map((r) => r.name).toSet().length >= 2)
          _Grp(e.key, e.value..sort((a, b) => (int.tryParse(a.p.s) ?? 99).compareTo(int.tryParse(b.p.s) ?? 99)))
    ]..sort((a, b) => _date(b.f.t).compareTo(_date(a.f.t)));
    return g.length > 12 ? g.sublist(0, 12) : g;
  }

  /// Listeyi günceller; kaydırma/dokunma varsa bekletir (titreme olmasın), en fazla 0,5 sn'de bir.
  void _publish(List<_Grp> g, {bool force = false}) {
    _pending = g;
    if (!force && (!_idle || DateTime.now().difference(_lastPub) < const Duration(milliseconds: 500))) return;
    _flush();
  }

  void _flush() {
    final g = _pending;
    if (g == null || !mounted) return;
    _pending = null;
    _lastPub = DateTime.now();
    _groups.value = g;
  }

  /// GitHub'ın önceden hazırladığı sonuç (beraber/{tarih}_{şehirId}_{koşu}). Yoksa/erişilemezse null → telefonda hesaplanır.
  Future<List<_Grp>?> _fromServer(List<Horse> hs) async {
    if (!firebaseReady) return null;
    try {
      final city = s.cities.firstWhere((c) => c.name == _city);
      final ref = FirebaseFirestore.instance.collection('beraber').doc('${s.iso}_${city.id}_$_no');
      DocumentSnapshot<Map<String, dynamic>> d;
      try {
        d = await ref.get(const GetOptions(source: Source.cache));
        final ts = d.data()?['ts'];
        // Telefondaki kopya 3 saatten eskiyse sunucudan yenisine bak
        if (!d.exists || ts is! Timestamp || DateTime.now().difference(ts.toDate()) > const Duration(hours: 3)) {
          final old = d;
          try {
            d = await ref.get().timeout(const Duration(seconds: 4));
          } catch (_) {
            d = old;
          }
        }
      } catch (_) {
        d = await ref.get().timeout(const Duration(seconds: 5));
      }
      if (!d.exists) return null;
      final names = {for (final h in hs) h.atId: h.name};
      final out = <_Grp>[];
      for (final g in (d.data()?['groups'] as List? ?? const [])) {
        if (g is! Map) continue;
        final rows = <_Row>[];
        for (final r in (g['rows'] as List? ?? const [])) {
          if (r is! Map) continue;
          final n = names['${r['id']}'];
          if (n == null) continue;
          rows.add(_Row(n, AtPast.fromJson(r)));
        }
        if (rows.map((r) => r.name).toSet().length >= 2) out.add(_Grp('${g['key']}', rows));
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final ck = '${s.iso}|$_city|$_no';
    final gen = ++_gen;
    _pending = null;
    // Liste kayarken kaldırılırsa ScrollEnd hiç gelmez; "kaydırıyor" takılı kalıp liste hiç gösterilmezdi
    _scrolling = false;
    AtHistPrefetch.scrolling = false;
    final cached = _cache[ck];
    if (cached != null) {
      _busy.value = false;
      _groups.value = cached;
      return;
    }
    final race = s.race(_city, _no);
    if (race == null) {
      _busy.value = false;
      _groups.value = const [];
      return;
    }
    _busy.value = true;
    _groups.value = null;
    final hs = [for (final h in race.atlar) if (!h.kosmaz && h.atId.isNotEmpty) h];
    // Hazır sonuç varsa tek okumayla göster (TJK'ya hiç gitmeden)
    final srv = await _fromServer(hs);
    if (!mounted || gen != _gen) return;
    if (srv != null) {
      _cache[ck] = srv;
      _busy.value = false;
      _groups.value = srv;
      AtHistPrefetch.i.start(_city, _no, galop: false);
      return;
    }
    final data = <String, List<AtPast>>{};
    // Önce telefondaki kayıtlar (anında), eksikler TJK'dan hep birlikte çekilir (en fazla 14 at aynı anda)
    var next = 0, done = 0;
    _prog.value = '0/${hs.length}';
    Future<void> worker() async {
      while (true) {
        if (!mounted || gen != _gen) return;
        final i = next++;
        if (i >= hs.length) return;
        final h = hs[i];
        final life = WidgetsBinding.instance.lifecycleState;
        if (life != null && life != AppLifecycleState.resumed) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        try {
          data[h.name] = await getAtPast(h.atId).timeout(const Duration(seconds: 30));
        } catch (_) {
          data[h.name] = const [];
        }
        if (!mounted || gen != _gen) return;
        _prog.value = '${++done}/${hs.length}';
        final g = _build(data);
        if (g.isNotEmpty) _publish(g, force: done == 1 || done == hs.length);
      }
    }

    await Future.wait([for (var i = 0; i < (hs.length < 14 ? hs.length : 14); i++) worker()]);
    if (!mounted || gen != _gen) return;
    final g = _build(data);
    _cache[ck] = g;
    _busy.value = false;
    // Bu koşu hazır: diğer koşuların atlarını arka planda önceden indir (aynı TJK sayfası, önbelleğe girer; sonraki koşular anında açılır)
    AtHistPrefetch.i.start(_city, _no, galop: false);
    if (_idle) {
      _pending = g;
      _flush();
    } else {
      _pending = g;
      _waitIdleFlush(gen);
    }
  }

  Future<void> _waitIdleFlush(int gen) async {
    // En fazla ~3 sn bekle, sonra yine de göster (takılı kalmasın)
    for (var i = 0; i < 12 && mounted && gen == _gen && !_idle; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (mounted && gen == _gen) _flush();
  }

  Widget _pill(AppColors c, String t, bool on, VoidCallback f, {double w = 44}) => GestureDetector(
        onTap: f,
        child: Container(
          constraints: BoxConstraints(minWidth: w),
          height: 44,
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? c.ac : c.sf, borderRadius: BorderRadius.circular(14), border: Border.all(color: on ? c.ac : c.ln, width: 1.5)),
          child: Text(t, style: jakarta(15, FontWeight.w800, on ? c.on : c.tx)),
        ),
      );

  Widget _list(AppColors c, List<_Grp>? g, bool busy) {
    Widget loading() => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: c.ac),
            const SizedBox(height: 14),
            ValueListenableBuilder<String>(
              valueListenable: _prog,
              builder: (_, p, __) => Text(p.isEmpty ? 'Yükleniyor…' : 'Atlar yükleniyor $p', style: jakarta(13, FontWeight.w700, c.mu)),
            ),
          ]),
        );
    if (g == null) return loading();
    if (g.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: busy
              ? loading()
              : Text('Bu koşuda, atların daha önce beraber koştuğu bir koşu bulunamadı.', textAlign: TextAlign.center, style: jakarta(14, FontWeight.w600, c.mu)),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification) {
          _scrolling = true;
          AtHistPrefetch.scrolling = true;
        } else if (n is ScrollEndNotification) {
          _scrolling = false;
          AtHistPrefetch.scrolling = false;
          AtHistPrefetch.scrollEnd = DateTime.now();
          _touch = DateTime.now();
          if (_pending != null) Future<void>.delayed(const Duration(milliseconds: 650), () => mounted && _idle ? _flush() : null);
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: g.length,
        addAutomaticKeepAlives: false,
        itemBuilder: (_, i) => RepaintBoundary(
          child: _GroupCard(key: ValueKey(g[i].key), g: g[i], raceNo: _no, iso: s.iso, initiallyOpen: i == 0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final races = s.races(_city);
    return Scaffold(
      backgroundColor: c.bg,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touch = DateTime.now(),
        onPointerMove: (_) => _touch = DateTime.now(),
        onPointerUp: (_) => _touch = DateTime.now(),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(children: [
                IconBox(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                const SizedBox(width: 12),
                Text('Beraber koşular', style: jakarta(20, FontWeight.w800, c.tx)),
              ]),
            ),
            if (s.cities.length > 1)
              SizedBox(
                height: 52,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 4, 8, 4), children: [
                  for (final k in s.cities)
                    _pill(c, k.name, k.name == _city, () {
                      if (k.name == _city) return;
                      setState(() {
                        _city = k.name;
                        _no = 1;
                      });
                      _load();
                    }, w: 64),
                ]),
              ),
            SizedBox(
              height: 52,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 4, 8, 4), children: [
                for (final r in races)
                  _pill(c, '${r.no}', r.no == _no, () {
                    if (r.no == _no) return;
                    setState(() => _no = r.no);
                    _load();
                  }),
              ]),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (_, b, __) => ValueListenableBuilder<List<_Grp>?>(
                valueListenable: _groups,
                builder: (_, g, __) => (b && g != null && g.isNotEmpty)
                    ? Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Diğer atlar yükleniyor…', style: jakarta(11.5, FontWeight.w700, c.mu)))
                    : const SizedBox(height: 3),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: _busy,
                builder: (_, b, __) => ValueListenableBuilder<List<_Grp>?>(
                  valueListenable: _groups,
                  builder: (_, g, __) => _list(c, g, b),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Tek bir ortak koşu. Aç/kapa sadece bu kartı yeniden çizer.
class _GroupCard extends StatefulWidget {
  final _Grp g;
  final int raceNo;
  final String iso;
  final bool initiallyOpen;
  const _GroupCard({super.key, required this.g, required this.raceNo, required this.iso, required this.initiallyOpen});
  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  late bool _open = widget.initiallyOpen;
  bool _loading = false;

  String get _video => widget.g.rows.map((r) => r.p.v).firstWhere((x) => x.isNotEmpty, orElse: () => '');

  Future<void> _watch() async {
    final v = _video;
    if (v.isEmpty || _loading) return;
    setState(() => _loading = true);
    String? mp4;
    try {
      mp4 = await getVideoMp4(v, widget.iso);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    final f = widget.g.f;
    if (mp4 != null) {
      await showRaceFilm(context, url: mp4, race: widget.raceNo, city: f.sh, dateLabel: f.t, rows: const [], title: '${f.sh} · ${f.t}', subtitle: 'Beraber koştukları koşu', badge: '▶');
    } else {
      launchUrl(Uri.parse(v), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = widget.g;
    final f = g.f;
    final hasV = _video.isNotEmpty;
    final pm = [f.msf.isEmpty ? '' : '${f.msf}m', f.pist].where((e) => e.isNotEmpty).join(' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(22), border: Border.all(color: c.ln)),
      child: Column(children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f.t, style: jakarta(14, FontWeight.w800, c.tx)),
                  Text([f.sh, pm].where((e) => e.isNotEmpty).join(' · '), style: jakarta(12.5, FontWeight.w600, c.mu)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: c.ac.withAlpha(30), borderRadius: BorderRadius.circular(12)),
                child: Text('${g.rows.length} at', style: jakarta(12, FontWeight.w800, c.ac)),
              ),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: c.mu),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(children: [
              for (final r in g.rows) _RowTile(r: r, c: c),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: hasV ? _watch : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: hasV ? c.ac : c.sf2, borderRadius: BorderRadius.circular(14)),
                  child: _loading
                      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.on))
                      : Text(hasV ? '▶  Koşuyu izle' : 'Bu koşunun videosu yok', style: jakarta(14, FontWeight.w800, hasV ? c.on : c.mu)),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _RowTile extends StatelessWidget {
  final _Row r;
  final AppColors c;
  const _RowTile({required this.r, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = r.p;
    final win = p.s == '1';
    final tk = (p.tk == '?' || p.tk.isEmpty) ? const <String>[] : p.tk.split(',');
    final sub = [p.j, if (p.kg.isNotEmpty) '${p.kg} kg', if (p.hp.isNotEmpty) 'HP ${p.hp}'].where((e) => e.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: win ? const Color(0xFFF3D36B) : c.sf2, borderRadius: BorderRadius.circular(10)),
          child: Text(p.s.isEmpty ? '-' : p.s, style: jakarta(14, FontWeight.w800, win ? const Color(0xFF5C4300) : c.tx)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.name, style: jakarta(14.5, FontWeight.w800, c.tx)),
            if (sub.isNotEmpty) Text(sub, style: jakarta(12.5, FontWeight.w600, c.mu)),
            if (tk.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Wrap(spacing: 5, runSpacing: 4, children: [
                  for (final k in tk)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                      decoration: BoxDecoration(color: c.ac.withAlpha(22), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.ac.withAlpha(90))),
                      child: Text(k, style: jakarta(11, FontWeight.w800, c.ac)),
                    ),
                ]),
              ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(p.d, style: jakarta(13.5, FontWeight.w800, c.tx)),
          if (p.g.isNotEmpty) Text('Gny ${p.g}', style: jakarta(12, FontWeight.w600, c.mu)),
        ]),
      ]),
    );
  }
}
