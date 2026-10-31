import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

/// LevelPlay (ironSource) mediation: ironSource + Unity Ads + Google AdMob.
/// Panel: Unity LevelPlay > Ganyansosyal (Android)
const String kLevelPlayAppKey = '2929a4b7d';

/// Panel > Setup > Ad units > "Rewarded Kredi" satırındaki kimlik.
/// DİKKAT: panelden bir kez daha kontrol et (ekran görüntüsünden okundu).
const String kLevelPlayRewardedAdUnitId = 'avoubet78r5s78d4';

class LevelPlayAds implements LevelPlayInitListener, LevelPlayRewardedAdListener {
  LevelPlayAds._();
  static final LevelPlayAds instance = LevelPlayAds._();

  /// Ekranda göstermek için son hata (test aşaması).
  String lastError = '';

  Completer<bool>? _init;
  LevelPlayRewardedAd? _ad;
  Completer<bool>? _load;
  Completer<bool?>? _show;
  bool _earned = false;

  /// SDK'yı başlatır. Başarılıysa true.
  Future<bool> init() {
    final existing = _init;
    if (existing != null) return existing.future;
    final c = _init = Completer<bool>();
    try {
      final req = LevelPlayInitRequest.builder(kLevelPlayAppKey).build();
      LevelPlay.init(initRequest: req, initListener: this);
    } catch (e) {
      lastError = 'init: $e';
      debugPrint('LevelPlay init hata: $e');
      if (!c.isCompleted) c.complete(false);
    }
    return c.future;
  }

  /// Ödüllü reklamı oynatır.
  /// true  = sonuna kadar izlendi
  /// false = izlendi ama ödül yok (erken kapandı)
  /// null  = reklam yüklenemedi/gösterilemedi (yedek reklama geç)
  Future<bool?> playRewarded() async {
    lastError = '';
    try {
      final ok = await init().timeout(const Duration(seconds: 10), onTimeout: () => false);
      if (!ok) {
        if (lastError.isEmpty) lastError = 'init zaman aşımı';
        return null;
      }

      _ad ??= LevelPlayRewardedAd(adUnitId: kLevelPlayRewardedAdUnitId)..setListener(this);
      final ad = _ad!;

      var ready = false;
      try {
        ready = await ad.isAdReady();
      } catch (_) {}
      if (!ready) {
        _load = Completer<bool>();
        ad.loadAd();
        ready = await _load!.future.timeout(const Duration(seconds: 12), onTimeout: () => false);
      }
      if (!ready) {
        if (lastError.isEmpty) lastError = 'yükleme zaman aşımı';
        return null;
      }

      _earned = false;
      _show = Completer<bool?>();
      ad.showAd();
      return await _show!.future.timeout(const Duration(minutes: 3), onTimeout: () => _earned);
    } catch (e) {
      lastError = 'hata: $e';
      debugPrint('LevelPlay hata: $e');
      return null;
    }
  }

  void _finishShow(bool? v) {
    final s = _show;
    if (s != null && !s.isCompleted) s.complete(v);
  }

  /* ---- init listener ---- */
  @override
  void onInitSuccess(LevelPlayConfiguration configuration) {
    final c = _init;
    if (c != null && !c.isCompleted) c.complete(true);
  }

  @override
  void onInitFailed(LevelPlayInitError error) {
    lastError = 'init başarısız: $error';
    debugPrint('LevelPlay init başarısız: $error');
    final c = _init;
    if (c != null && !c.isCompleted) c.complete(false);
    _init = null; // bir sonraki denemede tekrar dene
  }

  /* ---- rewarded listener ---- */
  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    final l = _load;
    if (l != null && !l.isCompleted) l.complete(true);
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    lastError = 'yükleme: $error';
    debugPrint('LevelPlay yükleme hatası: $error');
    final l = _load;
    if (l != null && !l.isCompleted) l.complete(false);
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdError error, LevelPlayAdInfo adInfo) {
    lastError = 'gösterim: $error';
    debugPrint('LevelPlay gösterim hatası: $error');
    _finishShow(null);
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdClosed(LevelPlayAdInfo adInfo) {
    _finishShow(_earned);
  }

  @override
  void onAdInfoChanged(LevelPlayAdInfo adInfo) {}

  @override
  void onAdRewarded(LevelPlayReward reward, LevelPlayAdInfo adInfo) {
    _earned = true;
  }
}
