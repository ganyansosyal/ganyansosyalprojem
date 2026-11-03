import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';
import 'auth_page.dart';
import 'preload.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // Gösterilen değer: gerçek yükleme ilerlemesine (Preload.progress) yumuşakça yaklaşır.
  // Bir adım uzun sürse bile çubuk bir sonraki adıma doğru yavaşça akar, %90'da takılı kalmaz.
  final ValueNotifier<double> _shown = ValueNotifier(0.0);
  late final Ticker _tick;
  Duration _last = Duration.zero;
  bool _finished = false, _leaving = false;

  // Giriş animasyonu: harfler yukarıdan düşer (1,9 sn). Yükleme bitse bile bu bitmeden çıkılmaz.
  static const _introMs = 1900.0;
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900))..forward();
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 9))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _tick = createTicker(_onTick)..start();
    Preload.start().timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(() => _finished = true);
  }

  void _onTick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = t;
    final real = Preload.progress.value;
    // bitti: hızlıca %100'e; bitmediyse: gerçek ilerleme + küçük pay (adım arası akış), en çok %97
    final limit = _finished ? 1.0 : (real + 0.10).clamp(0.0, 0.97);
    var v = _shown.value;
    if (v < limit) {
      final hiz = _finished ? 1.6 : ((limit - v) * 1.4 + 0.02);
      v = (v + hiz * dt).clamp(0.0, limit);
      _shown.value = v;
    }
    if (_finished && v >= 1.0 && _intro.isCompleted && !_leaving) {
      _leaving = true;
      _tick.stop();
      _leave();
    }
  }

  Future<void> _leave() async {
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => const AuthGate(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _tick.dispose();
    _intro.dispose();
    _float.dispose();
    _shown.dispose();
    super.dispose();
  }

  // Harf düşüşü: t 0..1 -> dikey kayma (px). İki zıplamalı sönümlenen düşüş.
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
    final t = ((ms - (150 + i * 55)) / 1000).clamp(0.0, 1.0);
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

  Widget _orb(double size, Color col) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [col.withAlpha(120), col.withAlpha(0)])),
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
          // yumuşak ışık küreleri
          AnimatedBuilder(
            animation: _float,
            builder: (_, __) {
              final f = Curves.easeInOut.transform(_float.value);
              return Stack(children: [
                Positioned(left: -90 + 30 * f, top: 70 - 26 * f, child: _orb(300, const Color(0xFF1FBF8B))),
                Positioned(right: -80 - 30 * f, bottom: 90 + 26 * f, child: _orb(260, const Color(0xFF0D7A56))),
              ]);
            },
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: AnimatedBuilder(
                  animation: _intro,
                  builder: (_, __) {
                    final ms = _intro.value * _introMs;
                    final lane = ((ms - 1200) / 500).clamp(0.0, 1.0);
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 0; i < word.length; i++) _letter(word[i], i, i < 6 ? const Color(0xFFF4FFF9) : mint, ms),
                            ],
                          ),
                        ),
                        const SizedBox(height: 46),
                        Opacity(
                          opacity: lane,
                          child: ValueListenableBuilder<double>(
                            valueListenable: _shown,
                            builder: (_, v, __) => Column(
                              children: [
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
                                            width: w * v.clamp(0.02, 1.0),
                                            height: 14,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(14),
                                              gradient: const LinearGradient(colors: [gold2, gold]),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: w * v.clamp(0.02, 1.0) - 13,
                                          child: Container(
                                            width: 26,
                                            height: 26,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: gold2,
                                              boxShadow: [
                                                BoxShadow(color: Color(0x40F5C451), spreadRadius: 5),
                                                BoxShadow(color: Color(0xB3F5C451), blurRadius: 24, spreadRadius: 4),
                                              ],
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
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text('Yükleniyor', style: jakarta(15, FontWeight.w500, const Color(0xE0F4FFF9))),
                                      Text('%${(v * 100).round()}',
                                          style: jakarta(30, FontWeight.w800, gold, ls: -.6).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 34),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < 2; i++) ...[
                                      if (i > 0) const SizedBox(width: 10),
                                      _tag(i == 0 ? 'Tahmin et' : 'Paylaş', v >= (i + 1) / 2 - .02),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tag(String text, bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        transform: Matrix4.translationValues(0, on ? -3 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: on ? const Color(0xFFF5C451) : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: on ? const Color(0xFFF5C451) : const Color(0x59FFFFFF)),
        ),
        child: Text(text, style: jakarta(14, FontWeight.w700, on ? const Color(0xFF3A2900) : const Color(0xD9F4FFF9))),
      );
}
