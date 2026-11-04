import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';
import 'auth_page.dart';
import 'preload.dart';

/// Açılış ekranı: Splash_demo.html'in birebir karşılığı.
///   0–1100 ms     logo + arka kart + beyaz kupon + "+3" rozeti (kartlar yukarı kayıp büyüyerek belirir)
///   1100–1600 ms  yüzde çubuğu, slogan ve çipler solarak açılır
///   1600 ms       dolum başlar (gerçek yükleme ilerlemesine bağlı, veri gelmediyse en çok %95)
///   %30/%60/%90   "Tahmin et" / "Paylaş" / "Yarış" çipleri sırayla sarı olur
///   %100          bekleme yok, akışa 320 ms'lik yumuşak geçiş
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  static const _introMs = 1600.0, _loadAt = 1600.0, _fadeMs = 320;

  bool _left = false, _loaded = false, _finishing = false;
  final ValueNotifier<double> _iv = ValueNotifier(0.0); // giriş animasyonu zamanı (ms)
  final ValueNotifier<double> _shown = ValueNotifier(0.0); // gösterilen dolum (0..1)
  late final Ticker _tick;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick = createTicker(_onTick)..start();
    Preload.start().timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(() => _loaded = true);
  }

  void _onTick(Duration t) {
    if (_finishing) return;
    final ms = t.inMicroseconds / 1000.0;
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = t;
    if (_iv.value < _introMs) _iv.value = math.min(ms, _introMs);
    if (ms < _loadAt) return;
    final lim = _loaded ? 1.0 : (Preload.progress.value + .12).clamp(0.0, .95).toDouble();
    var s = _shown.value;
    if (s < lim) {
      final k = _loaded ? 6.0 : 2.0;
      s = math.min(math.max(s + ((lim - s) * k + .03) * dt, 0.0), lim);
      _shown.value = s;
    }
    if (_loaded && s >= 1.0 && ms >= _introMs) {
      _finishing = true;
      _leave();
    }
  }

  void _leave() {
    if (!mounted || _left) return;
    _left = true;
    _tick.stop();
    // Splash altta opak kalır, uygulama üstüne yavaşça belirir (araya siyah/açık renk girmez)
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: _fadeMs),
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const AuthGate(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    ));
  }

  @override
  void dispose() {
    _tick.dispose();
    _iv.dispose();
    _shown.dispose();
    super.dispose();
  }

  static const _mint = Color(0xFF8DF5CD), _gold = Color(0xFFF5C451), _white = Color(0xFFF4FFF9), _ink = Color(0xFF0B3B2D), _soft = Color(0xFF5F7A6E);

  Widget _orb(double size, Color col) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: col));

  // ---- giriş animasyonları (demo ile aynı eğriler) ----
  Widget _fade(double at, Widget child) => ValueListenableBuilder<double>(
        valueListenable: _iv,
        child: child,
        builder: (_, v, ch) {
          final u = ((v - at) / 500).clamp(0.0, 1.0);
          return Opacity(opacity: 1 - math.pow(1 - u, 2).toDouble(), child: ch);
        },
      );

  Widget _pop(double at, Widget child) => ValueListenableBuilder<double>(
        valueListenable: _iv,
        child: child,
        builder: (_, v, ch) {
          final t = ((v - at) / 700).clamp(0.0, 1.0);
          final o = t < .5 ? 2 * t * t : 1 - math.pow(-2 * t + 2, 2) / 2;
          final e = 1 - math.pow(1 - t, 3).toDouble();
          return Opacity(
            opacity: o.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(offset: Offset(0, (1 - e) * 28), child: Transform.scale(scale: .88 + .12 * e, child: ch)),
          );
        },
      );

  Widget _logo() => _fade(
        0,
        Text.rich(
          TextSpan(children: [
            TextSpan(text: 'Ganyan', style: jakarta(34, FontWeight.w800, _white, ls: -1)),
            TextSpan(text: 'Sosyal', style: jakarta(34, FontWeight.w800, _mint, ls: -1)),
          ]),
          maxLines: 1,
        ),
      );

  Widget _row(String a, String b) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD5E6DE), width: .6))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: jakarta(14, FontWeight.w600, _ink)),
          Text(b, style: jakarta(14, FontWeight.w800, _ink)),
        ]),
      );

  Widget _cards() => SizedBox(
        width: 300,
        height: 270,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            left: 112,
            top: 36,
            child: _pop(
              0,
              Transform.rotate(
                angle: .12,
                child: Container(
                  width: 170,
                  height: 206,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B6A4E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0x4D8DF5CD)),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 22,
            top: 16,
            child: _pop(
              200,
              Transform.rotate(
                angle: -.07,
                child: Container(
                  width: 210,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(color: _white, borderRadius: BorderRadius.circular(20)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF0B6A4E), borderRadius: BorderRadius.circular(99)),
                        child: Text('Kupon', style: jakarta(12, FontWeight.w700, _white)),
                      ),
                      Text('Bugün', style: jakarta(12, FontWeight.w600, _soft)),
                    ]),
                    const SizedBox(height: 4),
                    _row('1. Koşu', '5'),
                    _row('2. Koşu', '3'),
                    _row('3. Koşu', '8'),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text('♡ 128', style: jakarta(13, FontWeight.w600, _soft)),
                      const SizedBox(width: 16),
                      Text('💬 24', style: jakarta(13, FontWeight.w600, _soft)),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
          Positioned(
            right: 4,
            top: 0,
            child: _pop(
              400,
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: _gold),
                child: Text('+3', style: jakarta(16, FontWeight.w800, const Color(0xFF3A2900))),
              ),
            ),
          ),
        ]),
      );

  Widget _chip(String text, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? _gold : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? _gold : const Color(0x59FFFFFF)),
        ),
        child: Text(text, style: jakarta(13, FontWeight.w700, on ? const Color(0xFF3A2900) : const Color(0xD9F4FFF9))),
      );

  Widget _bar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: ValueListenableBuilder<double>(
          valueListenable: _shown,
          builder: (_, v, __) => Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text('Yükleniyor', style: jakarta(14, FontWeight.w500, const Color(0xE0F4FFF9))),
              _Pct(v),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 10,
                color: const Color(0x1FFFFFFF),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(widthFactor: math.max(v, .02).clamp(0.0, 1.0).toDouble(), child: const ColoredBox(color: _gold, child: SizedBox.expand())),
              ),
            ),
          ]),
        ),
      );

  Widget _lower() => _fade(
        1100,
        Column(children: [
          _bar(),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Tahminini paylaş, ', style: jakarta(24, FontWeight.w800, _white, ls: -.6)),
                  TextSpan(text: 'yarışa katıl', style: jakarta(24, FontWeight.w800, _mint, ls: -.6)),
                ]),
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
          const SizedBox(height: 14),
          ValueListenableBuilder<double>(
            valueListenable: _shown,
            builder: (_, v, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _chip('Tahmin et', v >= .3),
              const SizedBox(width: 8),
              _chip('Paylaş', v >= .6),
              const SizedBox(width: 8),
              _chip('Yarış', v >= .9),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF073B2D),
      body: LayoutBuilder(builder: (context, full) {
        // CSS: radial-gradient(circle at 50% 37%, #0b6a4e 0, #073b2d 75%) — en uzak köşeye göre yarıçap
        final w = full.maxWidth, h = full.maxHeight;
        final cx = w / 2, cy = h * .37;
        final r = math.sqrt(math.pow(math.max(cx, w - cx), 2) + math.pow(math.max(cy, h - cy), 2)) / math.min(w, h);
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(center: const Alignment(0, -.26), radius: r, colors: const [Color(0xFF0B6A4E), Color(0xFF073B2D)], stops: const [0, .75]),
          ),
          child: Stack(children: [
            // sabit ışık küreleri (hareket yok)
            RepaintBoundary(
              child: Stack(children: [
                Positioned(left: -90, top: 70, child: _orb(300, const Color(0x291FBF8B))),
                Positioned(right: -100, bottom: 110, child: _orb(260, const Color(0x730D7A56))),
              ]),
            ),
            SafeArea(
              // Kısa ekranlarda taşma olmasın: içerik en az 620 yükseklikte kurulur, ekran kısaysa bütün olarak küçülür.
              child: LayoutBuilder(builder: (context, cons) {
                final hh = cons.maxHeight < 620 ? 620.0 : cons.maxHeight;
                return FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: cons.maxWidth,
                    height: hh,
                    child: Column(children: [
                      SizedBox(height: cons.maxWidth * .09),
                      _logo(),
                      const Spacer(flex: 10),
                      RepaintBoundary(child: _cards()),
                      const SizedBox(height: 18),
                      _lower(),
                      const Spacer(flex: 17),
                    ]),
                  ),
                );
              }),
            ),
          ]),
        );
      }),
    );
  }
}

/// Yüzde sayacı: üç haneli, her hane dikey rakam şeridi (demodaki gibi yumuşak kayar).
class _Pct extends StatelessWidget {
  final double v; // 0..1
  const _Pct(this.v);

  static const _h = 26.0;

  double _ease(double f) => f * f * (3 - 2 * f);

  Widget _col(List<String> items, double pos, TextStyle st) => SizedBox(
        width: 14,
        height: _h,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: 0,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(0, -pos * _h),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final s in items) SizedBox(height: _h, child: Center(child: Text(s, style: st))),
              ]),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final st = jakarta(22, FontWeight.w800, const Color(0xFFF5C451), ls: -.4).copyWith(fontFeatures: const [FontFeature.tabularFigures()], height: 1.0);
    final x = v.clamp(0.0, 1.0) * 100;
    final fl = x.floor();
    final e = _ease(x - fl);
    final ones = (fl % 10) + e;
    final tens = (fl ~/ 10) + (fl % 10 == 9 ? e : 0.0);
    final hund = (fl ~/ 100) + (fl % 100 == 99 ? e : 0.0);
    return RepaintBoundary(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _col(const ['', '1'], hund, st),
        _col(const ['', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'], tens, st),
        _col(const ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'], ones, st),
        SizedBox(height: _h, child: Center(child: Text('%', style: st))),
      ]),
    );
  }
}
