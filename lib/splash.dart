import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'theme.dart';
import 'auth_page.dart';
import 'preload.dart';

/// Açılış ekranı (demo videosundaki zamanlamayla birebir):
///   0–1100 ms   logo harfleri + kartlar + "+3" rozeti belirir
///   1100–1450   alt grup (yüzde çubuğu, slogan, çipler) yukarı kayarak açılır
///   1610 ms     dolum başlar (hızlı başlar, sona doğru yavaşlar)
///   %30/%60/%90 "Tahmin et" / "Paylaş" / "Yarış" çipleri sırayla yanar
///   3005 ms     %100 → bekleme yok, hemen akışa 340 ms'lik yumuşak geçiş
/// Çubuk gerçek yüklemeye (Preload.progress) bağlıdır: video zamanlaması en hızlı durumdur,
/// veri geç gelirse çubuk gerçek ilerlemeyi geçmeden bekler (en çok %95), veri gelince %100'e tamamlanır.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  bool _left = false, _loaded = false, _finishing = false;

  // Gösterilen dolum değeri (0..1)
  final ValueNotifier<double> _shown = ValueNotifier(0.0);
  late final Ticker _tick;
  Duration _last = Duration.zero;

  // ---- zamanlama (ms) ----
  static const _introMs = 1450.0; // alt grup 1100–1450 arasında biter
  static const _loadAt = 1610.0; // dolum başlangıcı
  static const _fadeMs = 340; // akışa geçiş süresi
  static const _holdAt = 0.95; // veri gelmediyse çubuğun çıkabileceği en üst seviye

  // Videodan ölçülen dolum eğrisi: [dolum başlangıcından ms, oran]
  static const _curve = <List<double>>[
    [0, .02],
    [25, .068],
    [92, .173],
    [192, .315],
    [293, .435],
    [393, .532],
    [493, .611],
    [593, .678],
    [727, .745],
    [827, .831],
    [927, .913],
    [1028, .956],
    [1120, .977],
    [1220, .991],
    [1395, 1.0], // 1610 + 1395 = 3005 ms
  ];

  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1450))..forward();

  @override
  void initState() {
    super.initState();
    _tick = createTicker(_onTick)..start();
    Preload.start().timeout(const Duration(seconds: 4), onTimeout: () {}).whenComplete(() => _loaded = true);
  }

  double _demo(double ms) {
    final x = ms - _loadAt;
    if (x <= 0) return 0.0;
    for (var i = 1; i < _curve.length; i++) {
      final a = _curve[i - 1], b = _curve[i];
      if (x <= b[0]) {
        final k = (x - a[0]) / (b[0] - a[0]);
        return a[1] + (b[1] - a[1]) * k;
      }
    }
    return 1.0;
  }

  void _onTick(Duration t) {
    if (_finishing) return;
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = t;
    final ms = t.inMicroseconds / 1000.0;
    // Çubuk iki şeye bağlı: (1) videodaki en hızlı pace, (2) GERÇEK yükleme ilerlemesi (Preload.progress).
    // Veri hızlı gelirse tam video zamanlaması; geç gelirse çubuk gerçek ilerlemeyi geçmez, bekler.
    final demoV = _demo(ms);
    final limit = _loaded ? 1.0 : (Preload.progress.value + 0.12).clamp(0.0, _holdAt);
    final target = demoV < limit ? demoV : limit;
    var v = _shown.value;
    if (target > v) {
      // video hızında ilerlerken birebir izle; gerçek ilerlemeye takılıp sonra açılınca zıplamasın diye yumuşak yaklaş
      v = (target - v) < 0.05 ? target : v + (target - v) * (1 - math.exp(-12 * dt));
      _shown.value = v.clamp(0.0, 1.0).toDouble();
    }
    if (_loaded && _shown.value >= 0.999) {
      _shown.value = 1.0;
      _finishing = true;
      _leave(); // %100'de bekleme yok: hemen akışa geç
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
    _intro.dispose();
    _shown.dispose();
    super.dispose();
  }

  static const _mint = Color(0xFF8DF5CD), _gold = Color(0xFFF5C451), _white = Color(0xFFF4FFF9), _ink = Color(0xFF0B3B2D), _soft = Color(0xFF5F7A6E);

  Widget _orb(double size, Color col) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: col));

  Widget _chip(String text, bool on) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
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

  Widget _logo() => AnimatedBuilder(
        animation: _intro,
        builder: (_, __) {
          const txt = 'GanyanSosyal';
          final ms = _intro.value * _introMs;
          return Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < txt.length; i++)
              () {
                final t = ((ms - i * 30) / 450).clamp(0.0, 1.0);
                final e = const Cubic(.2, 1.2, .4, 1).transform(t);
                Widget w = Transform.scale(scale: 1 + 0.5 * (1 - e), child: Text(txt[i], style: jakarta(36, FontWeight.w800, i < 6 ? _white : _mint, ls: -1)));
                final blur = 6 * (1 - e);
                if (blur > 0.1) w = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: w);
                return Opacity(opacity: e.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, -34 * (1 - e)), child: w));
              }(),
          ]);
        },
      );

  Widget _cards() {
    return SizedBox(
      width: 300,
      height: 270,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 112,
          top: 36,
          child: _Anim(
            _intro,
            at: 0,
            dur: 500,
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
              at: 100,
              dur: 600,
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
          child: _Anim(
            _intro,
            at: 650,
            dur: 450,
            s0: .5,
            rot0: -0.5,
            curve: Curves.easeOut,
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
                _PopPercent(v),
              ]),
              const SizedBox(height: 12),
              LayoutBuilder(builder: (_, c) {
                return SizedBox(
                  height: 12,
                  child: Stack(children: [
                    Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(color: const Color(0x1FFFFFFF), borderRadius: BorderRadius.circular(12)))),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: c.maxWidth * p,
                      child: DecoratedBox(decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(12))),
                    ),
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
                      at: 1100,
                      dur: 350,
                      dy: 22,
                      curve: Curves.easeOut,
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
        ]),
      ),
    );
  }
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

/// Yüzde sayacı ("Zıpla"): üç haneli sabit genişlikli yuva. Bir hane değişince yeni rakam büyük (1.55x) ve
/// 8 px yukarıdan gelip yerine oturur (150 ms, easeOut). Animasyon bitmeden aynı hane yeniden başlatılmaz,
/// böylece sayı hızlı akarken titremez; genişlik hiç değişmediği için çubuk da oynamaz.
class _PopPercent extends StatefulWidget {
  final double v; // 0..1
  const _PopPercent(this.v);

  @override
  State<_PopPercent> createState() => _PopPercentState();
}

class _PopPercentState extends State<_PopPercent> with TickerProviderStateMixin {
  static const _w = 14.0, _h = 26.0;
  late final List<AnimationController> _c =
      List.generate(3, (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 150), value: 1.0));
  late List<String> _d = _digits(widget.v);

  static List<String> _digits(double v) {
    final t = (v.clamp(0.0, 1.0) * 100).floor().toString();
    final d = ['', '', ''];
    for (var i = 0; i < t.length; i++) {
      d[2 - i] = t[t.length - 1 - i];
    }
    return d;
  }

  @override
  void didUpdateWidget(covariant _PopPercent old) {
    super.didUpdateWidget(old);
    final nd = _digits(widget.v);
    final n = (widget.v * 100).floor();
    for (var i = 0; i < 3; i++) {
      if (nd[i] != _d[i] && nd[i].isNotEmpty && n > 0 && !_c[i].isAnimating) _c[i].forward(from: 0);
    }
    _d = nd;
  }

  @override
  void dispose() {
    for (final c in _c) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = jakarta(22, FontWeight.w800, const Color(0xFFF5C451), ls: -.4)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()], height: 1.0);
    return RepaintBoundary(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          SizedBox(
            width: _w,
            height: _h,
            child: AnimatedBuilder(
              animation: _c[i],
              builder: (_, __) {
                final e = Curves.easeOut.transform(_c[i].value);
                return Transform.translate(
                  offset: Offset(0, -8 * (1 - e)),
                  child: Transform.scale(scale: 1.55 - .55 * e, child: Center(child: Text(_d[i], style: st))),
                );
              },
            ),
          ),
        Text('%', style: st),
      ]),
    );
  }
}
