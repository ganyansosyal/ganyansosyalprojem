import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'credits.dart';

/// Uygulama açılınca günde bir kez "günlük bonus" penceresi.
/// Kullanıcı "İzle"ye basarsa mevcut ödüllü video akışı çalışır (+100 kredi).
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

      final watch = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Günlük bonus'),
            content: Text('Uygulamayı kullanmak için günde bir kez kısa bir video izle. ${Credits.dailyBonus} kredi kazan.'),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Videoyu izle')),
            ],
          ),
        ),
      );
      if (watch == true && context.mounted) {
        await watchVideoForCredit(context, reward: Credits.dailyBonus);
      }
    } catch (_) {}
  }
}
