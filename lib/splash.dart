import 'dart:math' as math;
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';
import 'auth_page.dart';
import 'preload.dart';

/// Hafif açılış ekranı: sabit küreler, harfler yerinde hafif dalgalanır, çubuk akıcı dolar.
/// Yükleme biter bitmez (en çok 4 sn) akışa geçer; geçişte solma yok.
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

  static const _introMs = 1100.0;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void initState() {
    super.initState();
    _tick = createTicker(_onTick)..start();
    Preload.start().timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(() => _loaded = true);
  }

  void _onTick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = t;
    final real = Preload.progress.value;
    // bitmediyse: gerçek ilerleme + küçük pay, en çok %95; bitince hızlıca %100.
    // Üstel yumuşatma: hız hedefe yaklaştıkça yavaşlar, adım atlayınca zıplamaz, hiç geri gitmez.
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

  void _leave() {
    if (!mounted || _left) return;
    _left = true;
    // geçişte solma yok
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const AuthGate(),
    ));
  }

  @override
  void dispose() {
    _tick.dispose();
    _intro.dispose();
    _shown.dispose();
    super.dispose();
  }

  // Harfler yerinde belirir, hafifçe dalgalanıp durur (yukarıdan düşme yok).
  Widget _letter(String ch, int i, Color col, double ms) {
    final t = ((ms - i * 35) / 650).clamp(0.0, 1.0);
    final dy = 5 * math.sin(t * 2 * math.pi) * (1 - t);
    final a = (t / .3).clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(0, dy),
      child: Text(ch, style: jakarta(48, FontWeight.w800, col.withAlpha((a * 255).round()), ls: -1.8).copyWith(height: 1.05)),
    );
  }

  Widget _orb(double size, Color col) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [col.withAlpha(120), col.withAlpha(0)])),
      );

  Widget _tag(String text, bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        transform: Matrix4.translationValues(0, on ? -3 : 0, 0),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFF5C451) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? const Color(0xFFF5C451) : const Color(0x59FFFFFF)),
        ),
        child: Text(text, style: jakarta(14, FontWeight.w700, on ? const Color(0xFF3A2900) : const Color(0xD9F4FFF9))),
      );

  @override
  Widget build(BuildContext context) {
    const mint = Color(0xFF8DF5CD), gold = Color(0xFFF5C451), gold2 = Color(0xFFFFE29A);
    const word = 'GanyanSosyal';
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
              Positioned(left: -75, top: 57, child: _orb(300, const Color(0xFF1FBF8B))),
              Positioned(right: -95, bottom: 103, child: _orb(260, const Color(0xFF0D7A56))),
            ]),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (_, __) {
                          final ms = _intro.value * _introMs;
                          return FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (var i = 0; i < word.length; i++) _letter(word[i], i, i < 6 ? const Color(0xFFF4FFF9) : mint, ms),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 46),
                    ValueListenableBuilder<double>(
                      valueListenable: _shown,
                      builder: (_, v, __) {
                        final p = v.clamp(0.02, 1.0);
                        return Column(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: LayoutBuilder(builder: (_, box) {
                              final w = box.maxWidth;
                              return SizedBox(
                                height: 26,
                                child: Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
                                  Container(
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: const Color(0x17FFFFFF),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: const Color(0x1AFFFFFF)),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    child: Container(
                                      width: w * p,
                                      height: 14,
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [gold2, gold])),
                                    ),
                                  ),
                                  Positioned(
                                    left: w * p - 13,
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: gold2,
                                        boxShadow: [BoxShadow(color: Color(0x40F5C451), spreadRadius: 5)],
                                      ),
                                    ),
                                  ),
                                ]),
                              );
                            }),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('Yükleniyor', style: jakarta(15, FontWeight.w500, const Color(0xE0F4FFF9))),
                                _RollingPercent(v),
                              ],
                            ),
                          ),
                          const SizedBox(height: 34),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _tag('Tahmin et', v >= .45),
                              const SizedBox(width: 10),
                              _tag('Paylaş', v >= .82),
                            ],
                          ),
                        ]);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}


/// Yüzde sayacı: her hane sabit genişlikli bir sütun, rakamlar kayarak döner (kilometre sayacı gibi).
/// Genişlik hiç değişmediği için sayı ve çubuk titremez.
class _RollingPercent extends StatelessWidget {
  final double v; // 0..1
  const _RollingPercent(this.v);

  static const _w = 19.0, _h = 34.0;
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
    final st = jakarta(30, FontWeight.w800, const Color(0xFFF5C451), ls: -.6)
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
