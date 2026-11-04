import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';
import 'auth_page.dart';
import 'preload.dart';

/// Açılış ekranı: logo harfleri tek tek düşer (blur + parıltı), kartlar sırayla açılır (kupon satırları ✓ alır),
/// kartlar gelince yarış pisti şeklinde dolum çubuğu + slogan + çipler belirir. %100'de konfeti, sonra akışa geçilir.
/// Arkada yavaş dönen ışık huzmeleri ve 26 süzülen parçacık vardır.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _P {
  double x, y, vx, vy, r, a, g, v;
  final int cr, cg, cb;
  final bool burst;
  _P({required this.x, required this.y, this.vx = 0, this.vy = 0, required this.r, required this.a, this.g = 0, this.v = 0, required this.cr, required this.cg, required this.cb, this.burst = false});
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  bool _left = false, _loaded = false, _finishing = false;

  // Gösterilen değer: gerçek ilerlemeye yumuşakça yaklaşır, adım adım zıplamaz.
  final ValueNotifier<double> _shown = ValueNotifier(0.0);
  late final Ticker _tick;
  Duration _last = Duration.zero;

  static const _introMs = 1800.0; // kartlar 0-1600, alt grup 1250-1800
  static const _loadAt = 1700.0; // dolum: her şey göründükten sonra başlar
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..forward();
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final AnimationController _rays = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);

  final _rnd = math.Random();
  final List<_P> _parts = [];
  final ValueNotifier<int> _frame = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 26; i++) {
      final mint = i.isEven;
      _parts.add(_P(
        x: _rnd.nextDouble(),
        y: _rnd.nextDouble(),
        r: 1 + _rnd.nextDouble() * 2.2,
        v: .02 + _rnd.nextDouble() * .05,
        a: .15 + _rnd.nextDouble() * .35,
        cr: mint ? 141 : 245,
        cg: mint ? 245 : 196,
        cb: mint ? 205 : 81,
      ));
    }
    _tick = createTicker(_onTick)..start();
    Preload.start().timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(() => _loaded = true);
  }

  void _step(double dt) {
    for (var i = _parts.length - 1; i >= 0; i--) {
      final p = _parts[i];
      if (p.burst) {
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vy += p.g * dt;
        p.a -= dt * .55;
        if (p.a <= 0) _parts.removeAt(i);
      } else {
        p.y -= p.v * dt;
        if (p.y < -.02) {
          p.y = 1.02;
          p.x = _rnd.nextDouble();
        }
      }
    }
  }

  void _confetti() {
    const cols = [(245, 196, 81), (141, 245, 205), (255, 255, 255), (255, 224, 138)];
    for (var i = 0; i < 90; i++) {
      final an = _rnd.nextDouble() * 6.283, sp = .4 + _rnd.nextDouble() * 1.1;
      final c = cols[i % 4];
      _parts.add(_P(x: .5, y: .62, vx: math.cos(an) * sp, vy: math.sin(an) * sp - .5, r: 2 + _rnd.nextDouble() * 3, a: 1, g: 1.1, cr: c.$1, cg: c.$2, cb: c.$3, burst: true));
    }
  }

  void _onTick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = t;
    _step(dt);
    _frame.value++;
    // dolum, her şey görünür olunca başlar
    if (_intro.value * _introMs >= _loadAt && !_finishing) {
      final real = Preload.progress.value;
      final limit = _loaded ? 1.0 : (real + 0.12).clamp(0.0, 0.95);
      var v = _shown.value;
      if (v < limit) {
        final k = _loaded ? 6.0 : 2.0;
        v = (v + ((limit - v) * k + 0.03) * dt).clamp(0.0, limit);
        _shown.value = v;
      }
      if (_loaded && v >= 1.0 && _intro.isCompleted) {
        _finishing = true;
        _confetti();
        _flash.forward();
        Future.delayed(const Duration(milliseconds: 900), _leave);
      }
    }
  }

  void _leave() {
    if (!mounted || _left) return;
    _left = true;
    _tick.stop();
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
    _flash.dispose();
    _rays.dispose();
    _pulse.dispose();
    _shown.dispose();
    _frame.dispose();
    super.dispose();
  }

  static const _mint = Color(0xFF8DF5CD), _gold = Color(0xFFF5C451), _white = Color(0xFFF4FFF9), _ink = Color(0xFF0B3B2D), _soft = Color(0xFF5F7A6E);

  Widget _orb(double size, Color col) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: col));

  Widget _chip(String text, bool on) => AnimatedScale(
        scale: on ? 1.06 : 1.0,
        duration: const Duration(milliseconds: 250),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: on ? _gold : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: on ? _gold : const Color(0x59FFFFFF)),
            boxShadow: on ? const [BoxShadow(color: Color(0x80F5C451), blurRadius: 14)] : const [],
          ),
          child: Text(text, style: jakarta(13, FontWeight.w700, on ? const Color(0xFF3A2900) : const Color(0xD9F4FFF9))),
        ),
      );

  Widget _row(String a, String b, int i) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFD5E6DE), width: .6))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: jakarta(14, FontWeight.w600, _ink)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(b, style: jakarta(14, FontWeight.w800, _ink)),
            const SizedBox(width: 8),
            _Anim(
              _intro,
              at: 700.0 + 220 * i,
              dur: 350,
              s0: 0,
              curve: const Cubic(.2, 1.6, .4, 1),
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1FBF8B)),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ),
          ]),
        ]),
      );

  Widget _logo() => AnimatedBuilder(
        animation: Listenable.merge([_intro, _flash]),
        builder: (_, __) {
          const txt = 'GanyanSosyal';
          final ms = _intro.value * _introMs;
          final pulse = 1 + 0.12 * math.sin(math.pi * _flash.value);
          final sw = ((ms - 900) / 1100).clamp(0.0, 1.0);
          return Transform.scale(
            scale: pulse,
            child: Stack(alignment: Alignment.center, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < txt.length; i++)
                  () {
                    final t = ((ms - i * 45) / 600).clamp(0.0, 1.0);
                    final e = const Cubic(.2, 1.2, .4, 1).transform(t);
                    Widget w = Transform.scale(scale: 1 + 0.5 * (1 - e), child: Text(txt[i], style: jakarta(36, FontWeight.w800, i < 6 ? _white : _mint, ls: -1)));
                    final blur = 6 * (1 - e);
                    if (blur > 0.1) w = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: w);
                    return Opacity(opacity: e.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, -34 * (1 - e)), child: w));
                  }(),
              ]),
              // parıltı: harflerin üstünden soldan sağa geçen ışık
              if (sw > 0 && sw < 1)
                IgnorePointer(
                  child: ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (r) => LinearGradient(
                      colors: const [Color(0x00FFFFFF), Color(0xBFFFFFFF), Color(0x00FFFFFF)],
                      stops: const [.25, .5, .75],
                      transform: _Slide(-.8 + 1.6 * Curves.easeInOut.transform(sw)),
                    ).createShader(r),
                    child: Text(txt, style: jakarta(36, FontWeight.w800, Colors.white, ls: -1)),
                  ),
                ),
            ]),
          );
        },
      );

  Widget _cards() {
    return SizedBox(
      width: 300,
      height: 270,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          top: -15,
          child: IgnorePointer(
            child: _Anim(
              _intro,
              at: 700,
              dur: 400,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (_, ch) {
                  final k = Curves.easeInOut.transform(_pulse.value);
                  return Opacity(opacity: .25 + .35 * k, child: Transform.scale(scale: .9 + .2 * k, child: ch));
                },
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x59F5C451), Color(0x00F5C451)], stops: [0, .65])),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 112,
          top: 36,
          child: _Anim(
            _intro,
            at: 0,
            dur: 700,
            dx: 60,
            dy: 30,
            s0: .8,
            child: Transform.rotate(
              angle: 0.12,
              child: Container(
                width: 170,
                height: 206,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0F8460), Color(0xFF0A5A43)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x598DF5CD)),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 22,
          top: 16,
          child: Transform.rotate(
            angle: -0.07,
            child: _Anim(
              _intro,
              at: 200,
              dur: 800,
              dy: 40,
              flip: true,
              child: Container(
                width: 210,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(color: _white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x4D000000), blurRadius: 30, offset: Offset(0, 14))]),
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
                  _row('1. Koşu', '5', 0),
                  _row('2. Koşu', '3', 1),
                  _row('3. Koşu', '8', 2),
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
          child: _Anim(
            _intro,
            at: 1000,
            dur: 600,
            s0: 0,
            rot0: -0.7,
            curve: const Cubic(.2, 1.8, .4, 1),
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(center: Alignment(-.3, -.4), colors: [Color(0xFFFFE08A), Color(0xFFF5C451), Color(0xFFD9A62E)], stops: [0, .6, 1]),
              ),
              child: Text('+3', style: jakarta(16, FontWeight.w800, const Color(0xFF3A2900))),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _bar() => Padding(
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
              const SizedBox(height: 12),
              LayoutBuilder(builder: (_, c) {
                final w = c.maxWidth;
                return SizedBox(
                  height: 12,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(12)))),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: w * p,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [_gold, Color(0xFFFFE08A)]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Color(0xB3F5C451), blurRadius: 14)],
                        ),
                      ),
                    ),
                    if (v > 0)
                      Positioned(
                        left: w * p - 11,
                        top: -13,
                        child: Transform(alignment: Alignment.center, transform: Matrix4.diagonal3Values(-1, 1, 1), child: const Text('🏇', style: TextStyle(fontSize: 22, height: 1))),
                      ),
                    const Positioned(right: -4, top: -11, child: Text('🏁', style: TextStyle(fontSize: 16, height: 1))),
                  ]),
                );
              }),
            ]);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF073B2D),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -.25), radius: 1.1, colors: [Color(0xFF0E7A58), Color(0xFF073B2D), Color(0xFF042A20)], stops: [0, .6, 1]),
        ),
        child: Stack(children: [
          // yavaş dönen ışık huzmeleri (ortası parlak, kenarlara doğru solar)
          Positioned.fill(
            child: IgnorePointer(
              child: LayoutBuilder(builder: (_, c) {
                return Stack(children: [
                  Positioned(
                    left: c.maxWidth / 2 - 450,
                    top: c.maxHeight * .38 - 450,
                    width: 900,
                    height: 900,
                    child: RepaintBoundary(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (r) => const RadialGradient(colors: [Color(0xFF000000), Color(0x00000000)], stops: [0, .62], radius: .7071).createShader(r),
                        child: AnimatedBuilder(
                          animation: _rays,
                          builder: (_, __) => Transform.rotate(angle: _rays.value * 2 * math.pi, child: const CustomPaint(size: Size(900, 900), painter: _RayPainter())),
                        ),
                      ),
                    ),
                  ),
                ]);
              }),
            ),
          ),
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
                    _logo(),
                    const Spacer(flex: 10),
                    RepaintBoundary(child: _cards()),
                    const SizedBox(height: 16),
                    _Anim(
                      _intro,
                      at: 1250,
                      dur: 550,
                      dy: 22,
                      child: Column(children: [
                        _bar(),
                        const SizedBox(height: 24),
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
                            _chip('Tahmin et', v >= .30),
                            const SizedBox(width: 8),
                            _chip('Paylaş', v >= .60),
                            const SizedBox(width: 8),
                            _chip('Yarış', v >= .90),
                          ]),
                        ),
                      ]),
                    ),
                    const Spacer(flex: 17),
                    const SizedBox(height: 30),
                  ]),
                ),
              );
            }),
          ),
          // ambiyans parçacıkları + bitiş konfetisi (en üstte, dokunmayı engellemez)
          Positioned.fill(child: IgnorePointer(child: RepaintBoundary(child: CustomPaint(painter: _PartPainter(_parts, _frame))))),
          // bitişte kısa parlama
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _flash,
                builder: (_, __) {
                  final t = _flash.value;
                  final o = t < .25 ? t / .25 : (1 - t) / .75;
                  if (o <= 0) return const SizedBox.shrink();
                  return Opacity(
                    opacity: o.clamp(0.0, 1.0),
                    child: const DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(center: Alignment(0, -.1), radius: .85, colors: [Color(0xE6FFF0BE), Color(0x00FFF0BE)], stops: [0, .7]))),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PartPainter extends CustomPainter {
  final List<_P> parts;
  final Paint _paint = Paint();
  _PartPainter(this.parts, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in parts) {
      _paint.color = Color.fromRGBO(p.cr, p.cg, p.cb, p.a.clamp(0.0, 1.0));
      canvas.drawCircle(Offset(p.x * size.width, p.y * size.height), p.r, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PartPainter old) => true;
}

class _RayPainter extends CustomPainter {
  const _RayPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0x128DF5CD);
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.width / 2);
    for (var k = 0; k < 15; k++) {
      canvas.drawArc(r, k * 24 * math.pi / 180, 8 * math.pi / 180, true, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Slide extends GradientTransform {
  final double dx;
  const _Slide(this.dx);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(bounds.width * dx, 0, 0);
}

/// Parça, kendi zamanında açılır: solma + (isteğe bağlı) kayma / büyüme / dönme / 3B devrilme.
class _Anim extends StatelessWidget {
  final Animation<double> a;
  final double at, dur, dx, dy, s0, rot0;
  final bool flip;
  final Curve curve;
  final Widget child;
  const _Anim(this.a, {required this.at, required this.dur, required this.child, this.dx = 0, this.dy = 0, this.s0 = 1, this.rot0 = 0, this.flip = false, this.curve = const Cubic(.2, .9, .3, 1)});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: a,
        child: child,
        builder: (_, ch) {
          final lin = ((a.value * _SplashPageState._introMs - at) / dur).clamp(0.0, 1.0);
          final e = curve.transform(lin);
          final o = e.clamp(0.0, 1.0);
          final m = Matrix4.identity();
          if (flip) {
            m.setEntry(3, 2, 0.001);
            m.rotateX(-1.4 * (1 - e));
          }
          m.translate(dx * (1 - e), dy * (1 - e));
          final sc = s0 + (1 - s0) * e;
          m.scale(sc, sc, 1.0);
          if (rot0 != 0) m.rotateZ(rot0 * (1 - e));
          return Opacity(opacity: o, child: Transform(alignment: flip ? Alignment.bottomCenter : Alignment.center, transform: m, child: ch));
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
