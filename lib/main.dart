import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'preload.dart';
import 'splash.dart';

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
  await preloadFonts();
  PaintingBinding.instance.imageCache
    ..maximumSize = 1000
    ..maximumSizeBytes = 200 << 20; // avatarlar bellekten düşmesin
  SystemChrome.setSystemUIOverlayStyle(_barStyle);
  // Telefon 90/120 Hz destekliyorsa uygulamayı da en yüksek yenileme hızında çalıştır (tarayıcı gibi akıcı olsun)
  if (Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }
  await initFirebase();
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}
  Preload.start(); // akış verisi splash sürerken arka planda gelsin
  runApp(const GanyanApp());
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
        home: const SplashPage(),
      ),
      ),
    );
  }
}
