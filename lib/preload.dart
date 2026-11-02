import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'athist_prefetch.dart';
import 'auth_service.dart';
import 'firebase_options.dart';
import 'tjk.dart';

/// Açılış ekranı (splash) sürerken akışın verilerini (paylaşımlar, kullanıcılar, puanlar, moderatörler, ben)
/// birlikte önceden alır. Splash bitince akış hazır açılır: tahminciler satırı, sıralama ve rozetler oynamaz.
class Preload {
  static Future<void>? _f;
  static bool done = false;
  static String uid = '';
  static List<QueryDocumentSnapshot<Map<String, dynamic>>> users = const [];
  static Map<String, double> bonus = {};
  static Set<String> mods = {};
  static Map<String, dynamic>? me;

  /// Gerçek yükleme ilerlemesi (0..1): splash çubuğu buna göre dolar.
  static final ValueNotifier<double> progress = ValueNotifier(0.0);
  static void _p(double v) {
    if (v > progress.value) progress.value = v;
  }

  static Future<void> start() {
    // koşu programı da splash sırasında gelsin; bitince ilerleme çubuğuna işlenir
    TjkStore.i.ensureLoaded().whenComplete(() {
      _p(0.45);
      // Program gelince atların geçmişini arka planda önceden indir (Tahmin Yap gibi): Beraber koşular anında açılır
      final cs = TjkStore.i.cities;
      if (cs.isNotEmpty) AtHistPrefetch.i.start(cs.first.name, 1, galop: false, others: true);
    });
    return _f ??= _run().whenComplete(() => _p(1.0));
  }

  static Future<void> _run() async {
    try {
      if (!firebaseReady) return;
      final auth = FirebaseAuth.instance;
      final u = await auth.authStateChanges().first.timeout(const Duration(seconds: 4), onTimeout: () => auth.currentUser);
      _p(0.15);
      if (u == null) return; // giriş yok: beklenecek bir şey yok
      const srv = GetOptions(source: Source.server);
      final db = FirebaseFirestore.instance;
      final fu = db.collection('users').limit(300).get(srv);
      final fg = db.collection('grants').limit(500).get(srv);
      final fm = db.collection('mods').limit(100).get(srv);
      final fme = db.collection('users').doc(u.uid).get(srv);
      final fp = db.collection('posts').orderBy('ts', descending: true).limit(100).get(srv);
      // her sorgu bittikçe çubuk ilerler (15% → 60%)
      var biten = 0;
      for (final f in <Future<Object?>>[fp, fu, fg, fm, fme]) {
        f.then((_) => _p(0.15 + 0.09 * (++biten)), onError: (_) {});
      }
      await Future.wait<Object?>([fp, fu, fg, fm, fme]).timeout(const Duration(seconds: 8));
      users = (await fu).docs;
      bonus = {for (final d in (await fg).docs) d.id: ((d.data()['pts'] as num?)?.toDouble() ?? 0) + ((d.data()['keep'] as num?)?.toDouble() ?? 0)};
      mods = (await fm).docs.map((d) => d.id).toSet();
      me = (await fme).data();
      uid = u.uid;
      _p(0.62);
      // Bekleyen kuponların (herkesin) sonuçları splash sırasında çekilsin: akış açılınca durumlar hazır olur
      try {
        final today = isoToday(), keys = <String>{};
        for (final d in (await fp).docs) {
          final c = d.data()['coupon'];
          if (c is! Map) continue;
          final legs = ((c['legs'] as List?) ?? const []).whereType<Map>();
          if (!legs.any((l) => l['res'] is! List && l['win'] is! num)) continue;
          final iso = '${c['iso'] ?? ''}', city = '${c['city'] ?? ''}';
          if (iso.isEmpty || city.isEmpty || iso.compareTo(today) > 0) continue;
          keys.add('$iso|$city');
        }
        await Future.wait(keys.map((k) => pullLiveRes(k.substring(0, k.indexOf('|')), k.substring(k.indexOf('|') + 1)))).timeout(const Duration(seconds: 4), onTimeout: () => const []);
      } catch (_) {}
      _p(0.82);
      // Avatar fotoğraflarını splash sırasında çöz: akış açılınca tahminciler satırı boş/harf görünmesin
      final photos = <String>[for (final d in users) (d.data()['photo'] ?? '').toString()].where((x) => x.isNotEmpty).take(60);
      await warmAvatars(photos, const [48, 36]).timeout(const Duration(seconds: 3), onTimeout: () {});
      _p(0.97);
      done = true;
    } catch (_) {
      // alınamadıysa akış kendi yükleme yoluna döner
    }
  }
}
