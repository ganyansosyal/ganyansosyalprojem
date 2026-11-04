import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'preload.dart';
import 'levelplay_ads.dart';
import 'splash.dart';
import 'auth_page.dart';

const _barGreen = Color(0xFF0E7C5B);
const _barStyle = SystemUiOverlayStyle(
  statusBarColor: _barGreen,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: _barGreen,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarDividerColor: _barGreen,
  systemStatusBarContrastEnforced: false,
  systemNavigationBarContrastEnforced: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache
    ..maximumSize = 1000
    ..maximumSizeBytes = 200 << 20; // avatarlar bellekten düşmesin
  SystemChrome.setSystemUIOverlayStyle(_barStyle);
  // Açılışta siyah ekran uzamasın: yazı tipleri, Firebase ve yenileme hızı art arda değil AYNI ANDA hazırlanır.
  // (Telefon 90/120 Hz destekliyorsa uygulamayı en yüksek yenileme hızında çalıştır.)
  await Future.wait<void>([
    preloadFonts(),
    initFirebase(),
    if (Platform.isAndroid)
      () async {
        try {
          await FlutterDisplayMode.setHighRefreshRate();
        } catch (_) {}
      }(),
  ]);
  // Reklam SDK'ları açılışta BAŞLATILMAZ (siyah ekranı uzatıyordu): splash bitince splash.dart başlatır.
  runApp(const GanyanApp());
  Future.delayed(const Duration(seconds: 20), startAds); // yedek: splash hiç bitmezse bile reklamlar hazır olsun
  // Akış verisi, ilk kare çizildikten SONRA başlar (splash splash'ın ilk karesini geciktirmesin)
  WidgetsBinding.instance.addPostFrameCallback((_) => Preload.start());
}

class GanyanApp extends StatelessWidget {
  const GanyanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (_, mode, __) => ValueListenableBuilder<bool>(
       valueListenable: perfOverlay,
       builder: (_, perf, __) => MaterialApp(
        title: 'GanyanSosyal',
        debugShowCheckedModeBanner: false,
        showPerformanceOverlay: perf,
        themeMode: mode,
        themeAnimationDuration: Duration.zero, // tema değişince ara renk geçişi (gri titreme) olmasın, anında değişsin
        scrollBehavior: const NoBounceScroll(),
        // Ekran küçültme (FittedBox) kaldırıldı: her kare ayrıca ölçeklenmesin, kaydırma akıcı olsun.
        // Site 445 genişliğe göre tasarlandı; dar telefonlarda sadece yazı boyutu orantılı küçülür.
        builder: (ctx, child) {
          final pad = MediaQuery.paddingOf(ctx);
          uiScale = (MediaQuery.sizeOf(ctx).width / 445.0).clamp(0.8, 1.0).toDouble();
          return MediaQuery.withNoTextScaling(
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: _barStyle,
              child: Stack(fit: StackFit.expand, children: [
                child!,
                // Durum ve gezinme çubuğu yeşil
                Positioned(left: 0, right: 0, top: 0, height: pad.top, child: const IgnorePointer(child: ColoredBox(color: _barGreen))),
                Positioned(left: 0, right: 0, bottom: 0, height: pad.bottom, child: const IgnorePointer(child: ColoredBox(color: _barGreen))),
              ]),
            ),
          );
        },
        theme: buildTheme(AppColors.light, Brightness.light),
        darkTheme: buildTheme(AppColors.dark, Brightness.dark),
        // giriş yapılmamışsa splash'ı atla, doğrudan giriş ekranı
        home: (firebaseReady && FirebaseAuth.instance.currentUser == null) ? const AuthGate() : const SplashPage(),
      ),
      ),
    );
  }
}
