import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';
import 'theme.dart';
import 'preload.dart';
import 'splash.dart';
import 'auth_page.dart';
import 'app_open_ad.dart';

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
  // Ekran HEMEN çizilsin (siyah ekran olmasın). Font/Firebase beklemesi BootGate içinde, yeşil açılış ekranı arkasında yapılır.
  runApp(const GanyanApp());
}

/// Açılışta ağır işleri (font, Firebase, yenileme hızı) paralel yapar; bitene kadar yeşil marka ekranı gösterir.
Future<void> _boot() async {
  await Future.wait<void>([
    preloadFonts(),
    initFirebase(),
    () async {
      if (Platform.isAndroid) {
        try {
          await FlutterDisplayMode.setHighRefreshRate();
        } catch (_) {}
      }
    }(),
  ]);
  // Reklam SDK'ları burada BAŞLATILMAZ: splash.dart (7 sn sonra) veya credits.dart (ilk reklam istenince) startAds() çağırır.
  Preload.start(); // akış verisi splash sürerken arka planda gelsin
}

class BootGate extends StatefulWidget {
  const BootGate({super.key});
  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  late final Future<void> _f = _boot();

  @override
  void initState() {
    super.initState();
    // Uygulama açılınca (yeşil ekran bittikten sonra) açılış reklamı: her açılışta bir kez
    _f.then((_) => AppOpenAds.showOnceSoon());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _f,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const ColoredBox(
            color: _barGreen,
            child: Center(
              child: Text('GanyanSosyal',
                  style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1, decoration: TextDecoration.none)),
            ),
          );
        }
        // giriş yapılmamışsa splash'ı atla, doğrudan giriş ekranı
        return (firebaseReady && FirebaseAuth.instance.currentUser == null) ? const AuthGate() : const SplashPage();
      },
    );
  }
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
        home: const BootGate(),
      ),
      ),
    );
  }
}
