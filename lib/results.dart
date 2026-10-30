import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'film.dart';
import 'predict.dart' show NoBadge, isoLabel, isoTag;
import 'theme.dart';
import 'tjk.dart';

const _renk = <int, List<Color>>{
  7: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
  6: [Color(0xFF10B981), Color(0xFF34D399)],
  5: [Color(0xFF2563EB), Color(0xFF60A5FA)],
  4: [Color(0xFFEA580C), Color(0xFFFB923C)],
  3: [Color(0xFFBE185D), Color(0xFFF472B6)],
};

class ResultsPage extends StatefulWidget {
  const ResultsPage({super.key});
  @override
  State<ResultsPage> createState() => _ResultsPageState();
}

class _ResultsPageState extends State<ResultsPage> {
  final s = TjkStore.i;
  String _city = '';
  Timer? _t;

  @override
  void initState() {
    super.initState();
    s.addListener(_u);
    s.ensureLoaded().then((_) => s.refreshResults());
    _t = Timer.periodic(const Duration(seconds: 60), (_) => s.refreshResults());
    if (s.cities.isNotEmpty) s.refreshResults();
  }

  @override
  void dispose() {
    _t?.cancel();
    s.removeListener(_u);
    super.dispose();
  }

  void _u() {
    if (!mounted) return;
    setState(() {
      if (_city.isEmpty || !s.cities.any((c) => c.name == _city)) _city = s.cities.isNotEmpty ? s.cities.first.name : '';
    });
  }

  void _day(int d) {
    final n = isoAdd(s.iso, d);
    if (n.compareTo(isoAdd(isoToday(), 1)) > 0 || n.compareTo(isoAdd(isoToday(), -14)) < 0) return;
    _city = '';
    s.load(n);
  }

  Bahis? _odeme(String city, int ord, int n, String tur, int bitis) {
    final list = s.results[city]?[bitis]?.bahis ?? const <Bahis>[];
    final re = RegExp("^(?:\\d+\\. )?$n'li $tur\$");
    final m = list.where((x) => re.hasMatch(x.tur)).toList();
    if (ord > 0) {
      final o = m.where((x) => x.tur.startsWith('$ord. ')).toList();
      if (o.isNotEmpty) return o.first;
    }
    return m.length == 1 ? m.first : null;
  }

  Future<void> _open(String u) => launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);

  bool _filmBusy = false;

  Future<void> _play(String city, int r, String vid) async {
    if (_filmBusy) return;
    _filmBusy = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Video yükleniyor…'), duration: Duration(seconds: 8)));
    try {
      final mp4 = await getVideoMp4(vid, s.iso);
      messenger.hideCurrentSnackBar();
      if (!mounted) return;
      if (mp4 == null) {
        await _open(vid);
        return;
      }
      final res = s.resOf(city, r) ?? const <int>[];
      final race = s.race(city, r);
      final rows = <FilmRow>[];
      for (final no in res.take(4)) {
        Horse? h;
        if (race != null) {
          for (final x in race.atlar) {
            if (x.no == no) h = x;
          }
        }
        rows.add(FilmRow(no, h?.name ?? '', s.results[city]?[r]?.gny[no]));
      }
      final p = s.iso.split('-');
      await showRaceFilm(context, url: mp4, race: r, city: city, dateLabel: '${p[2]}.${p[1]}.${p[0]}', rows: rows);
    } catch (_) {
      messenger.hideCurrentSnackBar();
      await _open(vid);
    } finally {
      _filmBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (s.loading && s.cities.isEmpty) return Center(child: CircularProgressIndicator(color: c.ac));
    final city = _city.isEmpty && s.cities.isNotEmpty ? s.cities.first.name : _city;
    final races = s.races(city);
    final done = races.where((k) => s.raceDone(city, k.no)).length;
    final cards = <({int ord, int n, int st})>[];
    for (final k in races) {
      for (final b in k.baslar) {
        if (b.tur == 'GANYAN' && b.n >= 3) cards.add((ord: b.ord, n: b.n, st: k.no));
      }
    }
    cards.sort((a, b) => b.n != a.n ? b.n.compareTo(a.n) : a.ord.compareTo(b.ord));
    final i7 = cards.indexWhere((x) => x.n == 7);
    if (i7 > -1 && cards.length > 1) {
      final x = cards.removeAt(i7);
      cards.insert(cards.length < 3 ? cards.length : 2, x);
    }
    final last = races.where((k) => (s.results[city]?[k.no]?.bahis ?? const []).isNotEmpty).map((k) => k.no).toList();
    
    return RefreshIndicator(
      onRefresh: () => s.refreshResults(force: true),
      child: ListView(
        // Ekranın dışındaki kutuları önceden hazırla: kaydırırken yeni kutu girince takılma olmasın
        cacheExtent: 3000,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
        children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
          child: Row(children: [
            _arrow(c, Icons.chevron_left, () => _day(-1)),
            Expanded(child: Column(children: [
              if (isoTag(s.iso).isNotEmpty) Text(isoTag(s.iso), style: jakarta(10, FontWeight.w800, c.ac)),
              Text(isoLabel(s.iso), style: jakarta(14.5, FontWeight.w800, c.tx)),
            ])),
            _arrow(c, Icons.chevron_right, () => _day(1)),
          ]),
        ),
        const SizedBox(height: 8),
        if (s.cities.isEmpty)
          Padding(padding: const EdgeInsets.all(20), child: Text(s.error ?? 'Sonuçlar yükleniyor…', textAlign: TextAlign.center, style: jakarta(13, FontWeight.w600, c.mu)))
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final ct in s.cities)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _city = ct.name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(color: ct.name == city ? c.ac : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                      child: Text(ct.name, style: jakarta(12, FontWeight.w800, ct.name == city ? c.on : c.mu)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Text('$done/${races.length} koşu tamamlandı', style: jakarta(11, FontWeight.w600, c.mu)),
          const SizedBox(height: 8),
          for (final cd in cards) _card(c, city, cd),
          ..._odemeler(c, city, races),
          if (last.isNotEmpty) _bahisOdemeleri(c, city, last.last),
          if (cards.isEmpty && last.isEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Text('Henüz sonuç yok. Koşular bitip ödemeler yayınlanınca burada görünecek.', textAlign: TextAlign.center, style: jakarta(13, FontWeight.w600, c.mu))),
        ],
      ]),
    );
  }

  Widget _arrow(AppColors c, IconData ic, VoidCallback f) => GestureDetector(
        onTap: f,
        child: Container(width: 34, height: 34, decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(12)), child: Icon(ic, color: c.tx, size: 18)),
      );

  Widget _head(List<Color> k, String a, String b) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(gradient: LinearGradient(colors: k), borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(a, style: jakarta(13, FontWeight.w800, Colors.white))),
          Text(b, style: jakarta(11, FontWeight.w800, Colors.white)),
        ]),
      );

  // RepaintBoundary: sitedeki 'contain: paint' gibi, her kutu kendi katmanında çizilir
  Widget _box(AppColors c, List<Color> k, String a, String b, List<Widget> rows) => RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.ln)),
          child: Column(children: [_head(k, a, b), ...rows]),
        ),
      );

  Widget _card(AppColors c, String city, ({int ord, int n, int st}) cd) {
    final rows = <Widget>[];
    var all = true;
    for (var i = 0; i < cd.n; i++) {
      final r = cd.st + i;
      final res = s.resOf(city, r);
      final no = (res != null && res.isNotEmpty) ? res[0] : null;
      if (no == null) all = false;
      final race = s.race(city, r);
      Horse? h;
      if (no != null && race != null) {
        for (final x in race.atlar) {
          if (x.no == no) h = x;
        }
      }
      final vid = s.results[city]?[r]?.video ?? '';
      rows.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
        child: Row(children: [
          SizedBox(width: 20, child: Text('${i + 1}', style: jakarta(12, FontWeight.w800, c.mu))),
          if (h != null) ...[
            NoBadge(h.no, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12.5, FontWeight.w800, c.tx)),
              Row(children: [
                if (h.agf != null) Text('%${h.agf}', style: jakarta(10.5, FontWeight.w600, c.mu)),
                if (h.agf != null && s.results[city]?[r]?.gny[no] != null) Text('  ·  ', style: jakarta(10.5, FontWeight.w600, c.mu)),
                if (s.results[city]?[r]?.gny[no] != null) Text('Gny ${s.results[city]![r]!.gny[no]}', style: jakarta(11, FontWeight.w800, c.ac)),
              ]),
            ])),
            if (vid.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _play(city, r, vid),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.play_circle_fill_rounded, color: c.red, size: 34),
                ),
              ),
          ] else
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$r. koşu', style: jakarta(12.5, FontWeight.w800, c.mu)),
              Text(s.raceDone(city, r) ? 'Sonuç alınıyor…' : 'Henüz koşulmadı', style: jakarta(10.5, FontWeight.w600, c.mu)),
            ])),
        ]),
      ));
    }
    final od = all ? _odeme(city, cd.ord, cd.n, 'Ganyan', cd.st + cd.n - 1) : null;
    final ok = od != null && RegExp(r',\d{1,2}$').hasMatch(od.tutar);
    rows.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: c.gold.withAlpha(30), border: Border(top: BorderSide(color: c.ln)), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('İkramiye', style: jakarta(13, FontWeight.w800, c.tx)),
        Text(ok ? '${od!.tutar} ₺' : 'Bekleniyor', style: jakarta(13, FontWeight.w800, ok ? c.ac : c.mu)),
      ]),
    ));
    return _box(c, _renk[cd.n] ?? _renk[6]!, "${cd.ord > 0 ? '${cd.ord}. ' : ''}${cd.n}'${cd.n == 6 ? 'lı' : cd.n == 4 ? 'lü' : cd.n == 3 ? 'lü' : 'li'} Ganyan".toUpperCase().replaceAll('İ', 'İ'), '${cd.st}.–${cd.st + cd.n - 1}. KOŞU', rows);
  }

  List<Widget> _odemeler(AppColors c, String city, List<Race> races) {
    final seen = <String>{};
    final list = <Bahis>[];
    for (final k in races) {
      for (final x in s.results[city]?[k.no]?.bahis ?? const <Bahis>[]) {
        if (!RegExp(r"'li (Ganyan|Plase)$|Çifte$").hasMatch(x.tur) || !seen.add(x.tur) || !RegExp(r',\d{1,2}$').hasMatch(x.tutar)) continue;
        list.add(x);
      }
    }
    if (list.isEmpty) return [];
    return [
      _box(c, const [Color(0xFF1E3A8A), Color(0xFF6366F1)], 'Bahis türü', 'İkramiyeler', [
        for (final x in list)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(x.tur, style: jakarta(12.5, FontWeight.w800, c.tx)),
              Text('${x.tutar} ₺', style: jakarta(12.5, FontWeight.w800, c.ac)),
            ]),
          ),
      ])
    ];
  }

  Widget _bahisOdemeleri(AppColors c, String city, int no) {
    final l = s.results[city]?[no]?.bahis ?? const <Bahis>[];
    return _box(c, const [Color(0xFF0F766E), Color(0xFF2DD4BF)], 'Bahis ödemeleri', '$no. koşu', [
      for (final x in l)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
          child: Row(children: [
            Expanded(child: Text(x.tur, style: jakarta(12.5, FontWeight.w700, c.tx))),
            if (x.detay.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 10), child: Text(x.detay, style: jakarta(11, FontWeight.w600, c.mu))),
            Text('${x.tutar} ₺', style: jakarta(12.5, FontWeight.w800, c.gold)),
          ]),
        ),
    ]);
  }
}
