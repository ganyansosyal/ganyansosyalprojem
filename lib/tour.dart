import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// Test için true yap: rehber her uygulama açılışında çıkar (yayında false kalmalı).
const bool kTourAlwaysShow = false;

/// Rehber adımları (sıra önemli).
enum TourStep { credit, fab, star, menu, drawer }

/// Kayıt sonrası ilk açılışta çalışan, zorunlu spot ışıklı rehber.
///
/// 1) Kredi / video izle  (bilgi)
/// 2) Tahmin Yap butonuna dokun
/// 3) Bir atın yıldızına dokun (takip atı penceresi açılır, kapanınca devam)
/// 4) Menüyü aç
/// 5) Menüde "Takip atları" (bilgi, rehber biter)
class Tour {
  Tour._();

  // Hedef anahtarları: ilgili widget'lara `key:` olarak verilir.
  static final kCredit = GlobalKey(debugLabel: 'tourCredit');
  static final kFab = GlobalKey(debugLabel: 'tourFab');
  static final kStar = GlobalKey(debugLabel: 'tourStar');
  static final kMenu = GlobalKey(debugLabel: 'tourMenu');
  static final kHorses = GlobalKey(debugLabel: 'tourHorses');

  static final ValueNotifier<TourStep?> step = ValueNotifier<TourStep?>(null);

  /// Başka bir pencere (ör. takip atı sayfası) açıkken rehber geçici olarak gizlenir.
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

  /// Tahmin Yap sayfasının ana listesi (yıldız henüz çizilmediyse rehber listeyi aşağı kaydırır).
  static ScrollController? scroll;

  static OverlayEntry? _entry;
  static String _uid = '';
  static bool get active => step.value != null;

  static String _k(String uid) => 'tour_pending_$uid';

  /// Yeni kayıt olan kullanıcı için rehberi sıraya al (kayıttan hemen sonra çağrılır).
  static Future<void> markPending(String uid) async {
    if (uid.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_k(uid), true);
    } catch (_) {}
  }

  /// Ana ekran açılınca çağrılır: bu kullanıcının rehberi bekliyorsa başlatır.
  static Future<void> maybeStart(BuildContext context, String uid) async {
    if (_entry != null || uid.isEmpty) return;
    var go = kTourAlwaysShow;
    if (!go) {
      try {
        final sp = await SharedPreferences.getInstance();
        go = sp.getBool(_k(uid)) ?? false;
      } catch (_) {}
    }
    if (!go) return;
    // Ana sayfa çizilsin, kredi hapı yerine otursun
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!context.mounted || _entry != null) return;
    _uid = uid;
    hidden.value = false;
    step.value = TourStep.credit;
    _entry = OverlayEntry(builder: (_) => const _TourOverlay());
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  /// Sonraki adıma geç. [from] verilirse yalnızca o adımdaysak geçer.
  static void advance([TourStep? from]) {
    final s = step.value;
    if (s == null || (from != null && from != s)) return;
    hidden.value = false;
    final n = s.index + 1;
    if (n >= TourStep.values.length) {
      finish();
    } else {
      step.value = TourStep.values[n];
    }
  }

  /// Rehber tamamlandı: bir daha çıkmasın.
  static Future<void> finish() async {
    final uid = _uid;
    abort();
    if (uid.isEmpty) return;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_k(uid), false);
    } catch (_) {}
  }

  /// Rehberi kapat (kayıtlı durumu değiştirmez: uygulama kapanırsa yeniden başlar).
  static void abort() {
    _entry?.remove();
    _entry = null;
    step.value = null;
    hidden.value = false;
  }
}

class _StepInfo {
  final IconData icon;
  final String title, body, hint, button;
  final bool tap, circle;
  final double pad, radius;
  const _StepInfo({
    required this.icon,
    required this.title,
    required this.body,
    this.hint = '',
    this.button = '',
    this.tap = false,
    this.circle = false,
    this.pad = 6,
    this.radius = 20,
  });
}

const Map<TourStep, _StepInfo> _infos = {
  TourStep.credit: _StepInfo(
    icon: Icons.play_circle_fill_rounded,
    title: 'Video izle, kredi kazan',
    body: 'Her video izleyişinde 300 kredi kazanırsın. Kazandığın kredilerle istediğin kadar kupon hazırlayabilirsin.',
    button: 'Anladım',
    pad: 7,
    radius: 24,
  ),
  TourStep.fab: _StepInfo(
    icon: Icons.confirmation_number_rounded,
    title: 'Kuponunu burada hazırla',
    body: 'Ortadaki Tahmin Yap butonuna dokun, koşuları gör ve tahminlerini seç.',
    hint: 'Parlayan butona dokun',
    tap: true,
    circle: true,
    pad: 7,
  ),
  TourStep.star: _StepInfo(
    icon: Icons.star_rounded,
    title: 'Favori atını takip et',
    body: 'Yıldıza dokun. Takip ettiğin at koşmaya hazır olunca sana bildirim gönderelim.',
    hint: 'Yıldıza dokun',
    tap: true,
    circle: true,
    pad: 12,
  ),
  TourStep.menu: _StepInfo(
    icon: Icons.menu_rounded,
    title: 'Menüyü aç',
    body: 'Takip ettiğin atlar ve diğer bölümler menüde. Menü düğmesine dokun.',
    hint: 'Parlayan butona dokun',
    tap: true,
    pad: 6,
    radius: 18,
  ),
  TourStep.drawer: _StepInfo(
    icon: Icons.celebration_rounded,
    title: 'Hepsi hazır!',
    body: 'Takip ettiğin atlar burada toplanır. Artık hazırsın, bol şans!',
    button: 'Hadi başlayalım',
    pad: 6,
    radius: 26,
  ),
};

class _Conf {
  final double x, delay, speed, sway, rot, w, h;
  final Color color;
  const _Conf(this.x, this.delay, this.speed, this.sway, this.rot, this.w, this.h, this.color);
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay();
  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> with TickerProviderStateMixin {
  late final Ticker _tick;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();
  late final AnimationController _conf = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400));
  late final List<_Conf> _parts;

  Rect? _cur; // ekranda gösterilen (yumuşatılmış) delik
  double _rad = 20;
  double _vis = 0; // 0..1 perde görünürlüğü
  Duration _last = Duration.zero, _stepAt = Duration.zero, _lastScroll = Duration.zero;
  TourStep? _shown;
  bool _confStarted = false;
  bool _midDone = false; // yıldız aranırken ilk kaydırma (sayfa ortası) yapıldı mı
  Offset? _down;

  @override
  void initState() {
    super.initState();
    final r = math.Random(11);
    const cols = [Color(0xFF8DF5CD), Color(0xFFF5C451), Color(0xFFFFFFFF), Color(0xFF34D399), Color(0xFFFF7A9A)];
    _parts = List.generate(
      84,
      (i) => _Conf(r.nextDouble(), r.nextDouble() * .35, .65 + r.nextDouble() * .55, 1 + r.nextDouble() * 2.2, r.nextDouble() * 6.28, 6 + r.nextDouble() * 6, 9 + r.nextDouble() * 8, cols[i % cols.length]),
    );
    _tick = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _tick.dispose();
    _pulse.dispose();
    _conf.dispose();
    super.dispose();
  }

  GlobalKey _keyOf(TourStep s) {
    switch (s) {
      case TourStep.credit:
        return Tour.kCredit;
      case TourStep.fab:
        return Tour.kFab;
      case TourStep.star:
        return Tour.kStar;
      case TourStep.menu:
        return Tour.kMenu;
      case TourStep.drawer:
        return Tour.kHorses;
    }
  }

  Rect? _rectOf(GlobalKey k) {
    final ctx = k.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  void _onTick(Duration t) {
    final dt = ((t - _last).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
    _last = t;
    final s = Tour.step.value;
    if (s == null || !mounted) return;
    if (s != _shown) {
      _shown = s;
      _stepAt = t;
      _lastScroll = Duration.zero;
    }
    if (Tour.hidden.value) _stepAt = t; // başka pencere açıkken zaman aşımı işlemesin
    final size = MediaQuery.sizeOf(context);
    final info = _infos[s]!;

    final r = _rectOf(_keyOf(s));
    var ready = r != null && r.width > 1 && r.height > 1;
    if (ready && s == TourStep.star) {
      // Yıldız görünür bölgede değilse oraya kaydır
      final inView = r!.top > 150 && r.bottom < size.height - 290;
      if (!inView) {
        ready = false;
        if (t - _lastScroll > const Duration(milliseconds: 900)) {
          _lastScroll = t;
          final ctx = Tour.kStar.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
          }
        }
      }
    }
    // Koşu bitince listenin üstüne sonuç kartı eklenir, ilk atın yıldızı ekran dışında kalıp çizilmez:
    // hedef yoksa listeyi aşağı kaydır ki yıldız çizilsin.
    if (r == null && s == TourStep.star && t - _lastScroll > const Duration(milliseconds: 700)) {
      _lastScroll = t;
      final sc = Tour.scroll;
      if (sc != null && sc.hasClients) {
        final pos = sc.position;
        final max = pos.maxScrollExtent;
        double to;
        if (!_midDone) {
          _midDone = true;
          to = max / 2; // önce sayfanın ortasına git
        } else if (pos.pixels < max - 1) {
          to = pos.pixels + 450; // bulunamazsa aşağı doğru ilerle
        } else {
          to = 0; // sona geldiyse başa dön, tekrar dene
        }
        sc.animateTo(to.clamp(0.0, max).toDouble(), duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    }
    // Hedef 10 sn bulunamazsa rehber kilitlenmesin: adımı atla
    if (!ready && t - _stepAt > const Duration(seconds: 10)) {
      Tour.advance(s);
      return;
    }

    var changed = false;
    if (ready) {
      var target = r!.inflate(info.pad);
      if (info.circle) {
        final side = math.max(target.width, target.height);
        target = Rect.fromCenter(center: target.center, width: side, height: side);
      }
      final targetRad = info.circle ? target.shortestSide / 2 : info.radius;
      if (_cur == null) {
        _cur = target;
        _rad = targetRad;
        changed = true;
      } else {
        final k = 1 - math.exp(-dt * 16);
        final n = Rect.lerp(_cur, target, k)!;
        final nr = _rad + (targetRad - _rad) * k;
        if ((n.center - _cur!.center).distance > .05 || (n.width - _cur!.width).abs() > .05 || (nr - _rad).abs() > .05) {
          _cur = n;
          _rad = nr;
          changed = true;
        }
      }
    }
    final want = (ready && !Tour.hidden.value) ? 1.0 : 0.0;
    final nv = _vis + (want - _vis) * (1 - math.exp(-dt * 9));
    if ((nv - _vis).abs() > .002) {
      _vis = nv;
      changed = true;
    }
    if (s == TourStep.drawer && !_confStarted && _vis > .7) {
      _confStarted = true;
      _conf.forward(from: 0);
    }
    if (changed) setState(() {});
  }

  void _holeTapped(TourStep s) {
    switch (s) {
      case TourStep.fab:
        Tour.advance(TourStep.fab);
        break;
      case TourStep.menu:
        Tour.advance(TourStep.menu);
        break;
      case TourStep.star:
        // Takip atı penceresi açılır; kapanınca predict.dart rehberi devam ettirir.
        Tour.hidden.value = true;
        break;
      default:
        break;
    }
  }

  Widget _blk(double l, double t, double r, double b) {
    if (r - l <= 0 || b - t <= 0) return const SizedBox.shrink();
    return Positioned(
      left: l,
      top: t,
      width: r - l,
      height: b - t,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, onVerticalDragStart: (_) {}, child: const SizedBox.expand()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Tour.step, Tour.hidden]),
      builder: (context, _) {
        final s = Tour.step.value;
        final hole = _cur;
        if (s == null || hole == null || _vis < .01 || Tour.hidden.value) return const SizedBox.shrink();
        final info = _infos[s]!;
        final size = MediaQuery.sizeOf(context);
        final c = AppColors.of(context);
        return Material(
          type: MaterialType.transparency,
          child: SizedBox.expand(
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: _vis,
                    child: CustomPaint(painter: _ScrimPainter(hole, _rad, _pulse)),
                  ),
                ),
              ),
              if (!info.tap)
                Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: const SizedBox.expand()))
              else ...[
                // Deliğin dışı kapalı: kullanıcı yalnızca vurgulanan yere dokunabilir (zorunlu geçiş)
                _blk(0, 0, size.width, hole.top),
                _blk(0, hole.bottom, size.width, size.height),
                _blk(0, hole.top, hole.left, hole.bottom),
                _blk(hole.right, hole.top, size.width, hole.bottom),
                // Delik: dokunuşu yalnızca dinler, alttaki butona da geçirir
                Positioned.fromRect(
                  rect: hole,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) => _down = e.position,
                    onPointerUp: (e) {
                      final d = _down;
                      _down = null;
                      if (d != null && (e.position - d).distance < 24) _holeTapped(s);
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, clipBehavior: Clip.none, children: [...prev, if (cur != null) cur]),
                  child: _group(c, size, hole, s, info),
                ),
              ),
              Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _ConfettiPainter(_conf, _parts)))),
            ]),
          ),
        );
      },
    );
  }

  Widget _group(AppColors c, Size size, Rect hole, TourStep s, _StepInfo info) {
    final w = math.min(size.width - 32, 380.0);
    final left = (size.width - w) / 2;
    final below = hole.center.dy < size.height * 0.52;
    final ax = hole.center.dx.clamp(left + 30, left + w - 30).toDouble();
    const gap = 20.0;
    final dy = (1 - _vis) * (below ? 16.0 : -16.0);
    return Stack(
      key: ValueKey<TourStep>(s),
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: left,
          width: w,
          top: below ? hole.bottom + gap : null,
          bottom: below ? null : size.height - hole.top + gap,
          child: Opacity(
            opacity: _vis,
            child: Transform.translate(
              offset: Offset(0, dy),
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: _card(c, s, info)),
            ),
          ),
        ),
        Positioned(
          left: ax - 8,
          top: below ? hole.bottom + gap - 8 : null,
          bottom: below ? null : size.height - hole.top + gap - 8,
          child: Opacity(
            opacity: _vis,
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(width: 16, height: 16, decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(3))),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(AppColors c, TourStep s, _StepInfo info) {
    final idx = s.index, n = TourStep.values.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: c.sf,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.ln.withAlpha(150)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 38, offset: Offset(0, 14))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF34D399), Color(0xFF0E9F73)]),
              boxShadow: const [BoxShadow(color: Color(0x660E9F73), blurRadius: 14, offset: Offset(0, 5))],
            ),
            child: Icon(info.icon, color: Colors.white, size: 25),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: c.ac.withAlpha(26), borderRadius: BorderRadius.circular(99)),
            child: Text('ADIM ${idx + 1}/$n', style: jakarta(10.5, FontWeight.w800, c.ac, ls: .6)),
          ),
        ]),
        const SizedBox(height: 14),
        Text(info.title, style: jakarta(19, FontWeight.w800, c.tx, ls: -.3)),
        const SizedBox(height: 6),
        Text(info.body, style: jakarta(13.5, FontWeight.w500, c.mu).copyWith(height: 1.45)),
        const SizedBox(height: 16),
        Row(children: [
          for (var i = 0; i < n; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(right: 5),
              width: i == idx ? 26 : 8,
              height: 5,
              decoration: BoxDecoration(color: i <= idx ? c.ac : c.ln, borderRadius: BorderRadius.circular(3)),
            ),
        ]),
        const SizedBox(height: 16),
        if (info.tap) _hint(c, info.hint) else _primary(info.button, () => Tour.advance(s)),
      ]),
    );
  }

  Widget _hint(AppColors c, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: c.ac.withAlpha(26),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.ac.withAlpha(100)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) => Transform.translate(
            offset: Offset(0, math.sin(_pulse.value * 2 * math.pi) * 3),
            child: Icon(Icons.touch_app_rounded, size: 21, color: c.ac),
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: jakarta(13, FontWeight.w800, c.ac)),
      ]),
    );
  }

  Widget _primary(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [Color(0xFF34D399), Color(0xFF0E9F73)]),
          boxShadow: const [BoxShadow(color: Color(0x660E9F73), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: jakarta(15, FontWeight.w800, Colors.white)),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 19),
        ]),
      ),
    );
  }
}

/// Koyu perde + delik + yanıp sönen parlak halka.
class _ScrimPainter extends CustomPainter {
  final Rect hole;
  final double radius;
  final Animation<double> pulse;
  _ScrimPainter(this.hole, this.radius, this.pulse) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(hole, Radius.circular(radius));
    final path = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rr));
    canvas.drawPath(path, Paint()..color = const Color(0xE6051A13));
    // yumuşak parlama
    canvas.drawRRect(
      rr.inflate(2),
      Paint()
        ..color = const Color(0x808DF5CD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
    // net çerçeve
    canvas.drawRRect(
      rr,
      Paint()
        ..color = const Color(0xFF8DF5CD)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    // dışa yayılan iki dalga
    for (final ph in const [0.0, 0.5]) {
      final t = (pulse.value + ph) % 1.0;
      final a = (1 - t) * .6;
      canvas.drawRRect(
        rr.inflate(4 + t * 26),
        Paint()
          ..color = Color.fromRGBO(141, 245, 205, a)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter old) => old.hole != hole || old.radius != radius;
}

/// Son adımda yağan konfeti.
class _ConfettiPainter extends CustomPainter {
  final Animation<double> t;
  final List<_Conf> ps;
  _ConfettiPainter(this.t, this.ps) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value;
    if (v <= 0 || v >= 1) return;
    for (final p in ps) {
      final tt = ((v - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (tt <= 0) continue;
      final x = p.x * size.width + math.sin(tt * p.sway * math.pi * 2) * 28;
      final y = -24 + tt * size.height * 0.95 * p.speed;
      final a = tt > .82 ? (1 - (tt - .82) / .18) : 1.0;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rot + tt * 9 * p.sway);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h), const Radius.circular(2)),
        Paint()..color = p.color.withAlpha((a * 255).round().clamp(0, 255)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => false;
}
