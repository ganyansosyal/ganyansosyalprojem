import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:google_fonts/google_fonts.dart';

final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.light);

/// Temayı bir sonraki karede değiştir: dokunma tepkisi önce çizilsin, ağır yeniden çizim takılma gibi hissettirmesin.
void setThemeMode(ThemeMode m) {
  WidgetsBinding.instance.addPostFrameCallback((_) => themeMode.value = m);
  WidgetsBinding.instance.scheduleFrame();
}

class AppColors {
  final Color bg, sf, sf2, tx, mu, ln, ac, on, gold, red;
  const AppColors({
    required this.bg,
    required this.sf,
    required this.sf2,
    required this.tx,
    required this.mu,
    required this.ln,
    required this.ac,
    required this.on,
    required this.gold,
    required this.red,
  });

  static const light = AppColors(
    bg: Color(0xFFEDF1F7),
    sf: Color(0xFFFFFFFF),
    sf2: Color(0xFFF1F4F9),
    tx: Color(0xFF0E1B2C),
    mu: Color(0xFF5E6B80),
    ln: Color(0xFFE1E6EE),
    ac: Color(0xFF0E9F73),
    on: Color(0xFFFFFFFF),
    gold: Color(0xFFB87F00),
    red: Color(0xFFE0305A),
  );

  static const dark = AppColors(
    bg: Color(0xFF0A0F1E),
    sf: Color(0xFF131A2E),
    sf2: Color(0xFF1B2440),
    tx: Color(0xFFF3F6FC),
    mu: Color(0xFF8E9AB8),
    ln: Color(0xFF252F4D),
    ac: Color(0xFF2DD4A0),
    on: Color(0xFF05281D),
    gold: Color(0xFFFFB627),
    red: Color(0xFFFF5A7A),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Kaydırma sonunda hafif yaylanma (iOS tarzı) var.
/// Performans ölçümü: logoya uzun basınca açılır/kapanır (ekrandaki çubuklar kare süresini gösterir)
final ValueNotifier<bool> perfOverlay = ValueNotifier<bool>(false);

/// Parmak bırakınca kayma daha uzun sürsün (tarayıcıdaki ataletli kaydırma gibi)
class GlideScrollPhysics extends BouncingScrollPhysics {
  const GlideScrollPhysics({super.parent});
  @override
  GlideScrollPhysics applyTo(ScrollPhysics? ancestor) => GlideScrollPhysics(parent: buildParent(ancestor));
  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) => super.createBallisticSimulation(position, velocity);
}

class NoBounceScroll extends MaterialScrollBehavior {
  const NoBounceScroll();
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const GlideScrollPhysics();
}

ThemeData buildTheme(AppColors c, Brightness b) {
  final base = ThemeData(brightness: b, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: c.bg,
    // Tema değişince butonlar 200 ms'lik ara renk animasyonu yapmasın (bir kare eski çerçeve kalıyordu)
    outlinedButtonTheme: OutlinedButtonThemeData(style: ButtonStyle(animationDuration: Duration.zero)),
    filledButtonTheme: FilledButtonThemeData(style: ButtonStyle(animationDuration: Duration.zero)),
    textButtonTheme: TextButtonThemeData(style: ButtonStyle(animationDuration: Duration.zero)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ButtonStyle(animationDuration: Duration.zero)),
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    colorScheme: ColorScheme.fromSeed(seedColor: c.ac, brightness: b)
        .copyWith(primary: c.ac, surface: c.sf),
    textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme)
        .apply(bodyColor: c.tx, displayColor: c.tx),
  );
}

final Map<int, TextStyle> _jakartaCache = {};

/// Telefon genişliği / 445 (site tasarım genişliği). main.dart'ta ayarlanır.
double uiScale = 1.0;

TextStyle jakarta(double size, FontWeight w, Color color, {double? ls}) {
  size = size * uiScale;
  ls = ls == null ? null : ls * uiScale;
  final key = Object.hash(size, w.index, color.toARGB32(), ls);
  return _jakartaCache.putIfAbsent(
    key,
    () => GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: w,
      color: color,
      letterSpacing: ls,
    ),
  );
}

/// Yazı tiplerini ilk çizimden ÖNCE yükle. Yüklenmeden çizilen metin sonradan
/// font değişince yeniden dizilir (kaydırırken "yeniden yazıyor" hissinin sebebi).
Future<void> preloadFonts() async {
  for (final w in const [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) {
    GoogleFonts.plusJakartaSans(fontWeight: w);
  }
  try {
    await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 6));
  } catch (_) {}
}

class Brand extends StatelessWidget {
  final double size;
  final AppColors? colors;
  const Brand({super.key, this.size = 22, this.colors});

  @override
  Widget build(BuildContext context) {
    final c = colors ?? AppColors.of(context);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Ganyan', style: jakarta(size, FontWeight.w800, c.tx, ls: -size * 0.04)),
        TextSpan(text: 'Sosyal', style: jakarta(size, FontWeight.w800, c.ac, ls: -size * 0.04)),
      ]),
      maxLines: 1,
    );
  }
}


/// Klavyeye uyumlu alt pencere: yükseklik klavye açılırken kesintisiz (zıplamadan) küçülür.
/// Sadece bu widget MediaQuery'yi dinler; içindeki içerik her karede yeniden çizilmez.
class KbSheet extends StatelessWidget {
  final double fraction;
  final Widget child;
  const KbSheet({super.key, required this.child, this.fraction = 0.7});
  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final safe = MediaQuery.viewPaddingOf(context).bottom;
    final h = MediaQuery.sizeOf(context).height;
    final bottom = kb > safe ? kb : safe;
    final avail = h - bottom - 8;
    final want = h * fraction;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SizedBox(height: want < avail ? want : avail, child: child),
    );
  }
}

/// Klavye boşluğunu sadece kendisi dinler: içindeki ağır içerik yeniden kurulmaz, yalnızca alan kısalır/uzar.
/// Tam ekran formlarda ve uzun listelerde `viewInsets`'i build içinde okumak yerine bunu kullan.
class KbInset extends StatelessWidget {
  final Widget child;
  const KbInset({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), child: child);
}
