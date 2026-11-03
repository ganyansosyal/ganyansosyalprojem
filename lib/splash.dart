import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';
import 'auth_page.dart';
import 'preload.dart';

/// Açılış ekranı: parçalar sırayla (sadece solma ile) belirir, hepsi gelince alttaki dolum başlar.
/// Çipler dolum ilerledikçe sırayla sarıya döner (%30 / %60 / %90). Yükleme biter bitmez akışa yumuşakça geçer.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  bool _left = false, _loaded = false;

  // Gösterilen değer: gerçek ilerlemeye yumuşakça yaklaşır, adım adım zıplamaz.
  final ValueNotifier<double> _shown = ValueNotifier(0.0);
  late final Ticker _tick;
  Duration _last = Duration.zero;

  static const _introMs = 3600.0; // tüm parçaların belirme süresi (sırayla, üst üste binmeden)
  static const _loadAt = 3500.0; // dolum başlar: bloğun belirmesi (3000-3500ms) bittikten sonra
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600))..forward();

  @override
  void initState() {
    super.initState();
    _tick = createTicker(_onTick)..start();
    Preload.start().timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(() => _loaded = true);
  }

  void _onTick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = t;
    // dolum, bloğu görünür olunca başlar
    if (_intro.value * _introMs >= _loadAt) {
      final real = Preload.progress.value;
      final limit = _loaded ? 1.0 : (real + 0.12).clamp(0.0, 0.95);
      var v = _shown.value;
      if (v < limit) {
        final k = _loaded ? 6.0 : 2.0;
        v = (v + ((limit - v) * k + 0.03) * dt).clamp(0.0, limit);
        _shown.value = v;
      }
      if (_loaded && v >= 1.0 && _intro.isCompleted && !_left) {
        _tick.stop();
        _leave();
      }
    }
  }

  void _leave() {
    if (!mounted || _left) return;
    _left = true;
    // Splash altta opak kalır, uygulama üstüne yavaşça belirir (araya siyah/açık renk girmez)
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const AuthGate(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    ));
  }

  @override
  void dispose() {
    _tick.dispose();
    _intro.dispose();
    _shown.dispose();
    super.dispose();
  }

  static const _mint = Color(0xFF8DF5CD), _gold = Color(0xFFF5C451), _white = Color(0xFFF4FFF9), _ink = Color(0xFF0B3B2D), _soft = Color(0xFF5F7A6E);

  Widget _reveal(double at, Widget child) => _Reveal(_intro, at, child);

  Widget _orb(double size, Color col) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: col));

  Widget _chip(String text, bool on) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? _gold : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? _gold : const Color(0x59FFFFFF)),
        ),
        child: Text(text, style: jakarta(13, FontWeight.w700, on ? const Color(0xFF3A2900) : const Color(0xD9F4FFF9))),
      );

  Widget _row(String a, String b) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD5E6DE), width: .6))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: jakarta(14, FontWeight.w600, _ink)),
          Text(b, style: jakarta(14, FontWeight.w800, _ink)),
        ]),
      );

  Widget _cards() {
    return SizedBox(
      width: 300,
      height: 270,
      child: Stack(children: [
        Positioned(
          left: 112,
          top: 36,
          child: _reveal(
            500,
            Transform.rotate(
              angle: 0.12,
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
          child: _reveal(
            1000,
            Transform.rotate(
              angle: -0.07,
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
                    const Icon(Icons.favorite_border, size: 18, color: _soft),
                    const SizedBox(width: 5),
                    Text('128', style: jakarta(13, FontWeight.w600, _soft)),
                    const SizedBox(width: 16),
                    const Icon(Icons.chat_bubble_outline, size: 17, color: _soft),
                    const SizedBox(width: 5),
                    Text('24', style: jakarta(13, FontWeight.w600, _soft)),
                  ]),
                ]),
              ),
            ),
          ),
        ),
        Positioned(
          right: 4,
          top: 0,
          child: _reveal(
            1500,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF073B2D),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -.25), radius: 1.1, colors: [Color(0xFF0B6A4E), Color(0xFF073B2D)], stops: [0, .75]),
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
              final h = cons.maxHeight < 620 ? 620.0 : cons.maxHeight;
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: cons.maxWidth,
                  height: h,
                  child: Column(children: [
              const SizedBox(height: 64),
              _reveal(
                0,
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Ganyan', style: jakarta(34, FontWeight.w800, _white, ls: -1)),
                  Text('Sosyal', style: jakarta(34, FontWeight.w800, _mint, ls: -1)),
                ]),
              ),
              const Spacer(flex: 10),
              RepaintBoundary(child: _cards()),
              const SizedBox(height: 18),
              _reveal(
                3000,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _shown,
                    builder: (_, v, __) {
                      final p = v.clamp(0.02, 1.0);
                      return Column(children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text('Yükleniyor', style: jakarta(14, FontWeight.w500, const Color(0xE0F4FFF9))),
                          _RollingPercent(v),
                        ]),
                        const SizedBox(height: 10),
                        RepaintBoundary(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 10,
                              color: const Color(0x1FFFFFFF),
                              child: Transform(
                                alignment: Alignment.centerLeft,
                                transform: Matrix4.diagonal3Values(p, 1, 1),
                                child: Container(color: _gold),
                              ),
                            ),
                          ),
                        ),
                      ]);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 22),
              _reveal(
                2000,
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
              ),
              const SizedBox(height: 14),
              _reveal(
                2500,
                ValueListenableBuilder<double>(
                  valueListenable: _shown,
                  builder: (_, v, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _chip('Tahmin et', v >= .30),
                    const SizedBox(width: 8),
                    _chip('Paylaş', v >= .60),
                    const SizedBox(width: 8),
                    _chip('Yarış', v >= .90),
                  ]),
                ),
              ),
              const Spacer(flex: 17),
              const SizedBox(height: 30),
            ]),
                ),
              );
            }),
          ),
        ]),
      ),
    );
  }
}

/// Parça, kendi zamanı gelince hafif bir solmayla belirir (kayma/zıplama yok, sadece saydamlık).
class _Reveal extends StatelessWidget {
  final Animation<double> a;
  final double at;
  final Widget child;
  const _Reveal(this.a, this.at, this.child);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: a,
        child: child,
        builder: (_, ch) {
          final t = ((a.value * _SplashPageState._introMs - at) / 500).clamp(0.0, 1.0);
          final o = Curves.easeOut.transform(t);
          return Opacity(opacity: o, child: ch);
        },
      );
}

/// Yüzde sayacı: her hane sabit genişlikli bir sütun, rakamlar kayarak döner (kilometre sayacı gibi).
/// Genişlik hiç değişmediği için sayı ve çubuk titremez.
class _RollingPercent extends StatelessWidget {
  final double v; // 0..1
  const _RollingPercent(this.v);

  static const _w = 14.0, _h = 26.0;
  static double _ease(double f) => f * f * (3 - 2 * f);

  Widget _col(double pos, List<String> cells, TextStyle st) {
    return ClipRect(
      child: SizedBox(
        width: _w,
        height: _h,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: Transform.translate(
            offset: Offset(0, -pos * _h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [for (final c in cells) SizedBox(height: _h, child: Center(child: Text(c, style: st)))],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = jakarta(22, FontWeight.w800, const Color(0xFFF5C451), ls: -.4)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()], height: 1.0);
    final x = v.clamp(0.0, 1.0) * 100;
    final fl = x.floor();
    final e = _ease(x - fl);
    final ones = (fl % 10) + e;
    final tens = (fl ~/ 10) + (fl % 10 == 9 ? e : 0.0);
    final hund = (fl ~/ 100) + (fl % 100 == 99 ? e : 0.0);
    const d = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    return RepaintBoundary(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _col(hund, const ['', '1'], st),
        _col(tens, const ['', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0'], st),
        _col(ones, d, st),
        Text('%', style: st),
      ]),
    );
  }
}
