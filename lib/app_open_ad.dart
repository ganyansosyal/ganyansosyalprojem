import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'auth_service.dart';
import 'levelplay_ads.dart';

/// AdMob "Uygulama açıkken" (App Open) reklam birimi.
const String kAppOpenUnitId = 'ca-app-pub-1340335815297540/8668048148';

/// ===== SÜRE AYARLARI (buradan değiştir) =====
/// Giriş yapıp ana ekran açıldıktan kaç saniye sonra İLK reklam çıksın.
const Duration kAppOpenFirstDelay = Duration.zero;

/// Uygulama arka plandan dönünce reklam çıkması için en az ne kadar arkada kalmış olmalı.
const Duration kAppOpenMinAway = Duration(seconds: 60);

/// İki açılış reklamı arasında en az geçmesi gereken süre.
const Duration kAppOpenMinGap = Duration.zero;

/// Giriş ekranında DEĞİL, uygulamanın içinde (ana ekran açılınca) çalışır.
/// 1) Giriş yapıldıktan [kAppOpenFirstDelay] sonra bir kez.
/// 2) Sonra uygulama arka plandan dönünce ([kAppOpenMinAway] kadar arkada kaldıysa),
///    iki reklam arası en az [kAppOpenMinGap].
class AppOpenAds with WidgetsBindingObserver {
  AppOpenAds._();
  static final AppOpenAds _i = AppOpenAds._();

  bool _started = false;
  bool _showing = false;
  bool _loading = false;
  AppOpenAd? _ad;
  DateTime? _adLoadedAt;
  DateTime? _lastShown;
  DateTime? _pausedAt;

  bool _firstDone = false;

  /// Giriş yapılmış VE profil fotoğrafı ekranı geçilmiş (ana ekrandayız) mı?
  bool get _loggedIn {
    try {
      if (FirebaseAuth.instance.currentUser == null) return false;
      if (AuthService.busy.value) return false; // giriş/kayıt işlemi sürüyor
      final p = profileNotifier.value;
      return p != null && p.photo.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// main.dart'ta bir kez çağrılır. Reklam sadece giriş yapılmışsa (uygulamanın içindeyken) çıkar.
  static void start() => _i._start();

  void _start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    try {
      FirebaseAuth.instance.authStateChanges().listen((u) {
        if (u != null) _scheduleFirst();
      });
    } catch (e) {
      debugPrint('AppOpen auth hata: $e');
    }
  }

  void _scheduleFirst() {
    if (_firstDone) return;
    _firstDone = true;
    // Ana ekran gerçekten açılana kadar bekle (kayıt, fotoğraf ekranı vb. sayılmaz), sonra süreyi say.
    Timer.periodic(const Duration(seconds: 2), (t) {
      if (!_loggedIn) return;
      t.cancel();
      Future.delayed(kAppOpenFirstDelay, () => _maybeShow(force: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      if (!_showing) _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final p = _pausedAt;
      _pausedAt = null;
      if (p == null || _showing || !_loggedIn) return;
      if (DateTime.now().difference(p) >= kAppOpenMinAway) _maybeShow();
    }
  }

  bool get _adFresh {
    final t = _adLoadedAt;
    return _ad != null && t != null && DateTime.now().difference(t) < const Duration(hours: 3);
  }

  Future<void> _load() async {
    if (_loading || _adFresh) return;
    _loading = true;
    try {
      await startAds(); // AdMob SDK hazır olsun (zaten başladıysa tekrar başlatmaz)
      final c = Completer<AppOpenAd?>();
      AppOpenAd.load(
        adUnitId: kAppOpenUnitId,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            if (!c.isCompleted) {
              c.complete(ad);
            } else {
              ad.dispose();
            }
          },
          onAdFailedToLoad: (e) {
            debugPrint('AppOpen yüklenemedi: ${e.code} ${e.message}');
            if (!c.isCompleted) c.complete(null);
          },
        ),
      );
      final ad = await c.future.timeout(const Duration(seconds: 12), onTimeout: () => null);
      if (ad != null) {
        _ad?.dispose();
        _ad = ad;
        _adLoadedAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('AppOpen hata: $e');
    } finally {
      _loading = false;
    }
  }

  Future<void> _maybeShow({bool force = false}) async {
    if (_showing || !_loggedIn) return;
    final last = _lastShown;
    if (!force && last != null && DateTime.now().difference(last) < kAppOpenMinGap) {
      _load(); // sıradaki için şimdiden hazırla
      return;
    }
    if (!_adFresh) await _load();
    if (!_adFresh || _showing || !_loggedIn) return;
    final ad = _ad!;
    _ad = null;
    _showing = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showing = false;
        _lastShown = DateTime.now();
        _pausedAt = null;
        _load(); // bir sonraki için hazırla
      },
      onAdFailedToShowFullScreenContent: (a, e) {
        a.dispose();
        _showing = false;
      },
    );
    try {
      ad.show();
    } catch (e) {
      _showing = false;
      debugPrint('AppOpen gösterim hata: $e');
    }
  }
}
