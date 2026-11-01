import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credits.dart';
import 'theme.dart';

/// Uygulama açılınca günde bir kez "günlük bonus" penceresi.
/// Arka plan bulanık ve dokunulamaz. Reklam bitene (veya açılamazsa) kadar pencere kalır.
class DailyBonus {
  static const _key = 'last_daily_bonus_day';

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static Future<void> run(BuildContext context) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_key) == _today()) return;
      if (!context.mounted) return;

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Günlük bonus',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (ctx, _, __) => PopScope(
          canPop: false,
          child: _BonusCard(onEarned: () => prefs.setString(_key, _today())),
        ),
        transitionBuilder: (ctx, anim, _, child) {
          final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: t,
            child: ScaleTransition(scale: Tween<double>(begin: 0.92, end: 1).animate(t), child: child),
          );
        },
      );
    } catch (_) {}
  }
}

class _BonusCard extends StatefulWidget {
  const _BonusCard({required this.onEarned});
  final Future<void> Function() onEarned;
  @override
  State<_BonusCard> createState() => _BonusCardState();
}

class _BonusCardState extends State<_BonusCard> {
  bool _loading = false;
  bool _failed = false;

  Future<void> _watch() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    var ok = false;
    try {
      ok = await watchVideoForCredit(context, reward: Credits.dailyBonus);
    } catch (_) {}
    if (ok) {
      // Bonus sadece ödül alınınca "bugün kullanıldı" sayılır.
      await widget.onEarned();
      if (mounted) Navigator.of(context).pop();
    } else if (mounted) {
      // Reklam gösterilemedi ya da sonuna kadar izlenmedi: tekrar dene ya da kapat.
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Stack(
      children: [
        // Bulanık, dokunulamaz arka plan
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(color: Colors.black.withOpacity(0.35)),
          ),
        ),
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              decoration: BoxDecoration(
                color: c.sf,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: c.ln),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 40, offset: const Offset(0, 16))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [c.ac, c.ac.withOpacity(0.65)],
                      ),
                      boxShadow: [BoxShadow(color: c.ac.withOpacity(0.35), blurRadius: 22, offset: const Offset(0, 8))],
                    ),
                    child: Icon(Icons.card_giftcard_rounded, size: 38, color: c.on),
                  ),
                  const SizedBox(height: 20),
                  Text('Günlük bonus', style: jakarta(22, FontWeight.w800, c.tx)),
                  const SizedBox(height: 8),
                  Text(
                    'Uygulamayı kullanabilmek için günde bir kez kısa bir video izle.',
                    textAlign: TextAlign.center,
                    style: jakarta(14, FontWeight.w500, c.mu),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: c.gold.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.monetization_on_rounded, size: 20, color: c.gold),
                        const SizedBox(width: 6),
                        Text('+${Credits.dailyBonus} kredi', style: jakarta(16, FontWeight.w800, c.gold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Video izleyince kredi hesabına eklenir',
                    style: jakarta(12, FontWeight.w600, c.mu),
                  ),
                  if (_failed) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Reklam şu an gösterilemedi ya da tamamlanmadı.',
                      textAlign: TextAlign.center,
                      style: jakarta(12.5, FontWeight.w600, c.red),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _loading ? null : _watch,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.ac,
                        disabledBackgroundColor: c.ac.withOpacity(0.6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _loading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: c.on)),
                                const SizedBox(width: 12),
                                Text('Reklam hazırlanıyor...', style: jakarta(15, FontWeight.w700, c.on)),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(_failed ? Icons.refresh_rounded : Icons.play_arrow_rounded, color: c.on),
                                const SizedBox(width: 6),
                                Text(_failed ? 'Tekrar dene' : 'Videoyu izle', style: jakarta(16, FontWeight.w800, c.on)),
                              ],
                            ),
                    ),
                  ),
                  if (_failed)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Şimdi değil', style: jakarta(13, FontWeight.w700, c.mu)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
