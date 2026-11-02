import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'tjk.dart';

/// Seçili hipodromdaki atların "son yarış / son galibiyet" bilgisini arka planda, sırayla önceden çeker.
/// - Seçili koşunun atları en önde gelir.
/// - Parmak ekrana değiyorsa bekler (kaydırma kasmasın); uygulama arka plandaysa çekmez.
/// - Tek tek, aralarında kısa bekleyerek çeker (TJK'yı yormaz).
/// - Bir kez çekilen at tekrar çekilmez (bellek + telefon önbelleği).
class AtHistPrefetch {
  AtHistPrefetch._() {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }
  static final AtHistPrefetch i = AtHistPrefetch._();

  /// Liste kayarken true (predict.dart ayarlar). Kayarken ve bitişten sonra kısa süre hiçbir şey çekilmez.
  static bool scrolling = false;
  static DateTime scrollEnd = DateTime.fromMillisecondsSinceEpoch(0);

  final List<String> _q = [];
  final Map<String, DateTime> _fail = {};
  DateTime _touch = DateTime.fromMillisecondsSinceEpoch(0);
  bool _run = false;

  void _onPointer(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerMoveEvent) _touch = DateTime.now();
  }

  /// Kuyruğu seçili hipodrom için yeniden kurar (seçili koşu önde) ve ekran boşalınca çekmeye başlar.
  void start(String city, int firstRace, {bool galop = true, bool others = false}) {
    if (city.isEmpty) return;
    final rs = TjkStore.i.races(city).toList()
      ..sort((a, b) => a.no == firstRace ? -1 : (b.no == firstRace ? 1 : a.no.compareTo(b.no)));
    final now = DateTime.now();
    final seen = <String>{};
    final ids = <String>[];
    final galopIds = <String>[];
    for (final r in rs) {
      for (final h in r.atlar) {
        final id = h.atId;
        if (h.kosmaz || id.isEmpty) continue;
        // Galop sadece seçili koşu için hemen istenir (diğer koşular koşu açılınca gelir)
        if (galop && r.no == firstRace && !atGalopHazir(id) && !galopIds.contains(id)) galopIds.add(id);
        if ((atHistHazir(id) && atPastHazir(id)) || !seen.add(id)) continue;
        final f = _fail[id];
        if (f != null && now.difference(f) < const Duration(minutes: 10)) continue;
        ids.add(id);
      }
    }
    // Diğer hipodromların atları da sıranın sonuna eklenir (Beraber koşular hepsinde hızlı açılsın)
    if (others) {
      for (final c in TjkStore.i.cities) {
        if (c.name == city) continue;
        for (final r in TjkStore.i.races(c.name)) {
          for (final h in r.atlar) {
            final id = h.atId;
            if (h.kosmaz || id.isEmpty) continue;
            if ((atHistHazir(id) && atPastHazir(id)) || !seen.add(id)) continue;
            final f = _fail[id];
            if (f != null && now.difference(f) < const Duration(minutes: 10)) continue;
            ids.add(id);
          }
        }
      }
    }
    // Galop: tüm atlar için hemen, 6'şar atlık paketlerle (seçili koşu önde)
    for (final id in galopIds) {
      getAtGalop(id).then((_) {}, onError: (Object _) {});
    }
    _q
      ..clear()
      ..addAll(ids);
    if (_q.isEmpty) return;
    Future<void>.delayed(const Duration(milliseconds: 400), _pump);
  }

  Future<void> _pump() async {
    if (_run) return;
    _run = true;
    try {
      await Future.wait([for (var i = 0; i < 5; i++) _worker()]); // 5 at aynı anda
    } finally {
      _run = false;
    }
  }

  Future<void> _worker() async {
    while (_q.isNotEmpty) {
      final life = WidgetsBinding.instance.lifecycleState;
      if (life != null && life != AppLifecycleState.resumed) {
        await Future<void>.delayed(const Duration(seconds: 3));
        continue;
      }
      final now = DateTime.now();
      if (scrolling ||
          now.difference(_touch) < const Duration(milliseconds: 800) ||
          now.difference(scrollEnd) < const Duration(milliseconds: 800)) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        continue;
      }
      if (_q.isEmpty) break;
      final id = _q.removeAt(0);
      if (atHistHazir(id) && atPastHazir(id)) continue;
      try {
        // Önce "Beraber koşular" için geçmiş koşular (sayfa bir kez iner, telefona kaydedilir), sonra son yarış/galibiyet özeti
        await getAtPast(id).timeout(const Duration(seconds: 30));
        await getAtHist(id).timeout(const Duration(seconds: 30));
      } catch (_) {
        _fail[id] = DateTime.now();
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }
}
