import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding, WidgetsBindingObserver, AppLifecycleState;

import 'auth_service.dart';
import 'feed.dart';
import 'ikramiye.dart';
import 'scoring.dart';
import 'tjk.dart';

final ValueNotifier<bool> isAdminNotifier = ValueNotifier(false);
final ValueNotifier<bool> isModNotifier = ValueNotifier(false);

class _Resume with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Settler.poll(force: true);
  }
}

/// Arka planda: yönetici bilgisini izler, benim kuponlarımın sonuçlarını Firestore'a işler.
/// Sonuçlar sekmesine girilmesi gerekmez: bekleyen kuponların koşu sonuçları kendi zamanlayıcısıyla çekilir.
class Settler {
  static StreamSubscription? _a, _b, _c, _m;
  static List<Post> _mine = [], _all = [];
  static bool _busy = false, _again = false;
  static String _uid = '';
  static Timer? _poll;
  static final _resume = _Resume();

  static bool _pending(Map c) {
    final legs = ((c['legs'] as List?) ?? const []).whereType<Map>();
    return legs.any((l) => l['res'] is! List && l['win'] is! num);
  }

  /// Sonucu gelmemiş kuponların gün+şehir sonuçlarını TJK'dan ister.
  static void poll({bool force = false}) {
    final today = isoToday();
    final keys = <String>{};
    for (final p in _all) {
      final c = p.coupon;
      if (c == null || !_pending(c)) continue;
      final iso = '${c['iso'] ?? ''}', city = '${c['city'] ?? ''}';
      if (iso.isEmpty || city.isEmpty || iso.compareTo(today) > 0) continue;
      keys.add('$iso|$city');
    }
    for (final k in keys) {
      final i = k.indexOf('|');
      final iso = k.substring(0, i), city = k.substring(i + 1);
      if (iso == TjkStore.i.iso && TjkStore.i.cities.isNotEmpty) {
        TjkStore.i.refreshResults(force: force);
      } else {
        pullLiveRes(iso, city);
      }
    }
  }

  static void start(String uid) {
    if (_uid == uid) return;
    stop();
    _uid = uid;
    final db = FirebaseFirestore.instance;
    _a = db.collection('users').doc(uid).snapshots().listen((s) => isAdminNotifier.value = s.data()?['isAdmin'] == true, onError: (_) {});
    _m = db.collection('mods').doc(uid).snapshots().listen((s) => isModNotifier.value = s.exists, onError: (_) {});
    _b = db.collection('posts').where('uid', isEqualTo: uid).limit(100).snapshots().listen((s) {
      _mine = s.docs.map((d) => Post(d.id, d.data())).toList();
      _run();
      poll();
    }, onError: (_) {});
    TjkStore.i.addListener(_run);
    _c = db.collection('posts').orderBy('ts', descending: true).limit(100).snapshots().listen((s) {
      _all = s.docs.map((d) => Post(d.id, d.data())).toList();
      poll(); // herkesin kuponu: açılışta hemen
    }, onError: (_) {});
    liveResTick.addListener(_run);
    WidgetsBinding.instance.addObserver(_resume);
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => poll());
    TjkStore.i.ensureLoaded();
  }

  static void stop() {
    _a?.cancel();
    _m?.cancel();
    isModNotifier.value = false;
    _b?.cancel();
    _c?.cancel();
    TjkStore.i.removeListener(_run);
    liveResTick.removeListener(_run);
    WidgetsBinding.instance.removeObserver(_resume);
    _poll?.cancel();
    _uid = '';
  }

  static Future<void> _run() async {
    if (_busy) {
      _again = true; // çalışırken yeni sonuç geldiyse bitince bir tur daha
      return;
    }
    _busy = true;
    try {
      final db = FirebaseFirestore.instance;
      for (final p in _mine) {
        final c = p.coupon;
        if (c == null) continue;
        final legs = ((c['legs'] as List?) ?? const []).whereType<Map>().map((l) => Map<String, dynamic>.from(l)).toList();
        final m = liveRes['${c['iso']}|${c['city']}'];
        if (m != null) {
          var changed = false;
          for (final l in legs) {
            final r = (l['r'] as num?)?.toInt();
            if (l['res'] is List || r == null || m[r] == null) continue;
            l['res'] = m[r];
            changed = true;
          }
          if (changed) {
            c['legs'] = legs;
            try {
              await db.collection('posts').doc(p.id).update({'coupon.legs': legs});
              final st = couponStatus(c).k;
              if (st == 'win' || st == 'lose') {
                final ex = DateTime.now();
                await db.collection('notifs').doc('${st}_${p.id}').set({
                  'to': _uid,
                  'from': _uid,
                  'fn': profileNotifier.value?.name ?? '',
                  'type': st,
                  'pid': p.ts,
                  'pd': p.id,
                  'ts': DateTime.now().millisecondsSinceEpoch,
                  'exp': Timestamp.fromMillisecondsSinceEpoch(DateTime(ex.year, ex.month, ex.day + 1).millisecondsSinceEpoch),
                  'tx': '${c['type'] ?? ''}',
                });
              }
            } catch (_) {}
          }
        }
        // TJK ikramiyesi kesinleşince kuponun kendi kaydına yaz: gün atlayınca kaybolmasın
        try {
          if (Ikr.fromMap(c['ikrD']) == null) {
            // Bugünün kuponu: yüklü veriden; geçmiş günün kuponu: o günün sonuçları TJK'dan çekilerek
            final k = ikramiyeLive(c) ?? (ikramiyeFetchGerek(c) ? await ikramiyeFetch(c) : null);
            if (k != null && k.ready) await db.collection('posts').doc(p.id).update(ikrPatch(c, k));
          }
        } catch (_) {}
      }
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        _run();
      }
    }
  }
}
