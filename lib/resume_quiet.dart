import 'package:flutter/widgets.dart';

/// Uygulama arkadan öne gelirken (sistem geçiş animasyonu ~1 sn) ağır işler (ağ, yeniden çizim)
/// animasyonla yarışıp takılma yapmasın diye geri dönüşten sonra kısa süre "sakin" tutulur.
/// Hiçbir veri akışı durdurulmaz; işler yalnızca biraz ertelenir.
class ResumeQuiet with WidgetsBindingObserver {
  ResumeQuiet._();
  static final ResumeQuiet i = ResumeQuiet._();

  static const quietFor = Duration(milliseconds: 1200);
  DateTime _until = DateTime.fromMillisecondsSinceEpoch(0);
  bool _on = false;

  /// main() içinde, diğer gözlemcilerden ÖNCE çağrılır (sıra önemli).
  void init() {
    if (_on) return;
    _on = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _until = DateTime.now().add(quietFor);
  }

  /// Sakin süre bitene kadar (+ [extra]) bekler. Sakin süre yoksa hemen döner.
  static Future<void> settled([Duration extra = Duration.zero]) async {
    final left = i._until.difference(DateTime.now()) + extra;
    if (left > Duration.zero) await Future<void>.delayed(left);
  }
}
