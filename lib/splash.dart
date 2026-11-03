import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'auth_page.dart';
import 'preload.dart';

/// Orijinal görünüm, ağır kısımlar yok: harf düşüşü, süzülen küreler, ticker ve zorunlu bekleme kaldırıldı.
/// Yükleme biter bitmez (en çok 4 sn) akışa geçer.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  bool _left = false, _loaded = false;

  // Harf düşüşü: tek controller, 1,1 sn, sadece logo satırı yeniden çizilir.
  static const _introMs = 1100.0;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..forward();

  @override
  void initState() {
    super.initState();
    Preload.start().timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(() {
      _loaded = true;
      _leave();
    });
    _intro.addStatusListener((st) {
      if (st == AnimationStatus.completed) _leave();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  static double _drop(double t) {
    if (t < .4) {
      final u = t / .4;
      return -140 * (1 - u * u);
    }
    if (t < .74) {
      final u = (t - .4) / .34;
      return -20 * (4 * u * (1 - u));
    }
    if (t < 1) {
      final u = (t - .74) / .26;
      return -6 * (4 * u * (1 - u));
    }
    return 0;
  }

  Widget _letter(String ch, int i, Color col, double ms) {
    final t = ((ms - i * 35) / 700).clamp(0.0, 1.0);
    final fall = (t / .4).clamp(0.0, 1.0);
    return Opacity(
      opacity: fall,
      child: Transform.translate(
        offset: Offset(0, _drop(t)),
        child: Transform.rotate(
          angle: -0.14 * (1 - fall),
          child: Text(ch, style: jakarta(48, FontWeight.w800, col, ls: -1.8).copyWith(height: 1.05)),
        ),
      ),
    );
  }

  void _leave() {
    if (!mounted || _left || !_loaded || !_intro.isCompleted) return;
    _left = true;
    // geçişte solma yok: şeffaf/silik görüntü olmasın
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) => const AuthGate(),
    ));
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
                    // logo: harfler yukarıdan düşer (1,1 sn)
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _intro,
                        builder: (_, __) {
                          final ms = _intro.value * _introMs;
                          const word = 'GanyanSosyal';
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
                      valueListenable: Preload.progress,
                      builder: (_, real, __) {
                        final p = real.clamp(0.02, 1.0);
                        return Column(children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: LayoutBuilder(builder: (_, box) {
                              final w = box.maxWidth;
                              // sadece çubuk 300 ms yumuşak dolar (tek küçük animasyon)
                              return TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.02, end: p),
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                                builder: (_, v, __) => SizedBox(
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
                                        width: w * v,
                                        height: 14,
                                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [gold2, gold])),
                                      ),
                                    ),
                                    Positioned(
                                      left: w * v - 13,
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
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('Yükleniyor', style: jakarta(15, FontWeight.w500, const Color(0xE0F4FFF9))),
                                Text('%${(real.clamp(0.0, 1.0) * 100).round()}',
                                    style: jakarta(30, FontWeight.w800, gold, ls: -.6).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                              ],
                            ),
                          ),
                          const SizedBox(height: 34),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _tag('Tahmin et', real >= .45),
                              const SizedBox(width: 10),
                              _tag('Paylaş', real >= .82),
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
