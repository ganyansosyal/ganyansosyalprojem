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
      await prefs.setString(_key, _today());
      if (!context.mounted) return;

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Günlük bonus',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (ctx, _, __) => const PopScope(canPop: false, child: _BonusCard()),
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
  const _BonusCard();
  @override
  State<_BonusCard> createState() => _BonusCardState();
}

class _BonusCardState extends State<_BonusCard> {
  bool _loading = false;

  Future<void> _watch() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await watchVideoForCredit(context, reward: Credits.dailyBonus);
    } finally {
      // Reklam kapanınca (ya da açılamayınca) pencere kaybolur.
      if (mounted) Navigator.of(context).pop();
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
                    'Kısa bir video izle, hemen kredi kazan.',
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
                  const SizedBox(height: 22),
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
                                Icon(Icons.play_arrow_rounded, color: c.on),
                                const SizedBox(width: 6),
                                Text('Videoyu izle', style: jakarta(16, FontWeight.w800, c.on)),
                              ],
                            ),
                    ),
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
