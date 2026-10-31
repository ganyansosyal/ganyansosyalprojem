import 'dart:io' show Platform;

import 'package:in_app_update/in_app_update.dart';

/// Google Play'de yeni sürüm varsa uygulama açılınca güncelleme penceresi çıkarır.
/// Sadece Play'den yüklenen uygulamada çalışır (APK ile yüklenende sessizce geçer).
class UpdateCheck {
  static bool _done = false;

  static Future<void> run() async {
    if (_done || !Platform.isAndroid) return;
    _done = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable) return;
      if (info.immediateUpdateAllowed) {
        // Tam ekran, kullanıcı güncellemeden devam edemez
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {}
  }
}
