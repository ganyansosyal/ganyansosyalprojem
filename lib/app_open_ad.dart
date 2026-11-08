import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'levelplay_ads.dart';

/// AdMob "Uygulama açıkken" (App Open) reklam birimi.
const String kAppOpenUnitId = 'ca-app-pub-1340335815297540/8668048148';

/// Uygulama açıldıktan sonra, her açılışta SADECE BİR KEZ gösterilir.
/// Açılışı geciktirmesin diye uygulama tamamen açıldıktan sonra yüklenir.
class AppOpenAds {
  static bool _started = false;

  static Future<void> showOnceSoon() async {
    if (_started) return;
    _started = true;
    try {
      await Future.delayed(const Duration(seconds: 2));
      await startAds(); // AdMob SDK'sı hazır olsun (zaten başladıysa tekrar başlatmaz)

      final c = Completer<AppOpenAd?>();
      var gaveUp = false;
      AppOpenAd.load(
        adUnitId: kAppOpenUnitId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            if (gaveUp) {
              ad.dispose(); // geç geldi, gösterme
            } else if (!c.isCompleted) {
              c.complete(ad);
            }
          },
          onAdFailedToLoad: (e) {
            debugPrint('AppOpen yüklenemedi: ${e.code} ${e.message}');
            if (!c.isCompleted) c.complete(null);
          },
        ),
      );

      final ad = await c.future.timeout(const Duration(seconds: 10), onTimeout: () {
        gaveUp = true;
        return null;
      });
      if (ad == null) return;

      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (a) => a.dispose(),
        onAdFailedToShowFullScreenContent: (a, e) => a.dispose(),
      );
      ad.show();
    } catch (e) {
      debugPrint('AppOpen hata: $e');
    }
  }
}
