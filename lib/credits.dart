import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'auth_service.dart';
import 'levelplay_ads.dart';
import 'theme.dart';

/* =====================================================================
   KREDİ SİSTEMİ
   users/{uid}.credits = int   (kupon paylaşma hakkı)
   Yeni kullanıcıya ilk girişte [welcome] kredi verilir.
   Kredi paraya çevrilmez, sadece uygulama içinde kullanılır.
   ===================================================================== */
class Credits {
  static const int welcome = 3; // ilk kredi hediyesi
  static const int perKupon = 1; // bir kupon paylaşmanın bedeli
  static const int videoReward = 100; // her video izlemeye verilen kredi
  static final _db = FirebaseFirestore.instance;

  /// Canlı kredi sayısı (profilde / ana sayfada göstermek için).
  static Stream<int> watch(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((d) => _read(d.data()));

  static int _read(Map<String, dynamic>? m) {
    final v = m?['credits'];
    return v is num ? v.toInt() : welcome;
  }

  /// Kredi düşer. Yetmezse false döner.
  static Future<bool> spend(String uid, {int n = perKupon}) {
    final ref = _db.collection('users').doc(uid);
    return _db.runTransaction<bool>((t) async {
      final cur = _read((await t.get(ref)).data());
      if (cur < n) return false;
      t.set(ref, {'credits': cur - n}, SetOptions(merge: true));
      return true;
    });
  }

  /// Yönetici: istediği kullanıcıya kredi ekler (eksi yazarsa düşer, 0'ın altına inmez).
  static Future<int> adminAdd(String uid, int n) {
    final ref = _db.collection('users').doc(uid);
    return _db.runTransaction<int>((t) async {
      final cur = _read((await t.get(ref)).data());
      final v = (cur + n) < 0 ? 0 : cur + n;
      t.set(ref, {'credits': v}, SetOptions(merge: true));
      return v;
    });
  }

  /// Kredi ekler (video izleyince çağrılacak).
  static Future<void> add(String uid, {int n = videoReward}) {
    final ref = _db.collection('users').doc(uid);
    return _db.runTransaction<void>((t) async {
      final cur = _read((await t.get(ref)).data());
      t.set(ref, {'credits': cur + n}, SetOptions(merge: true));
    });
  }
}

/// AdMob ödüllü reklam birimi.
/// TEST kimliği: gerçek hesaptan alınan reklam birimi kimliğiyle değiştirilecek.
const String kRewardedUnitId = 'ca-app-pub-1340335815297540/1095854500';

bool _adBusy = false;
String _admobErr = '';

/// Önce LevelPlay (ironSource + Unity Ads + AdMob mediation), reklam yoksa doğrudan AdMob.
Future<bool> _playVideo() async {
  _admobErr = '';
  final r = await LevelPlayAds.instance.playRewarded();
  if (r != null) return r;
  return _playAdMobDirect();
}

/// Doğrudan AdMob ödüllü reklamı (yedek). Kullanıcı sonuna kadar izlerse true döner.
Future<bool> _playAdMobDirect() {
  final done = Completer<bool>();
  var earned = false;
  RewardedAd.load(
    adUnitId: kRewardedUnitId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (a) {
            a.dispose();
            if (!done.isCompleted) done.complete(earned);
          },
          onAdFailedToShowFullScreenContent: (a, e) {
            a.dispose();
            if (!done.isCompleted) done.complete(false);
          },
        );
        ad.show(onUserEarnedReward: (_, __) => earned = true);
      },
      onAdFailedToLoad: (e) {
        _admobErr = 'AdMob ${e.code}: ${e.message}';
        if (!done.isCompleted) done.complete(false);
      },
    ),
  );
  return done.future.timeout(const Duration(seconds: 25), onTimeout: () => false);
}

Future<void> watchVideoForCredit(BuildContext context) async {
  final me = profileNotifier.value;
  if (me == null || _adBusy) return;
  _adBusy = true;
  final sm = ScaffoldMessenger.of(context);
  sm
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('Reklam yükleniyor...'), duration: Duration(seconds: 3)));
  try {
    final ok = await _playVideo();
    if (ok) {
      await Credits.add(me.uid);
      sm
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('+${Credits.videoReward} kredi kazandın!'), duration: const Duration(seconds: 2)));
    } else {
      sm
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 12),
          content: Text('Reklam yüklenemedi ya da sonuna kadar izlenmedi. Tekrar dene.\n[test] LevelPlay: ${LevelPlayAds.instance.lastError.isEmpty ? "-" : LevelPlayAds.instance.lastError}\n$_admobErr'),
        ));
    }
  } catch (_) {
    sm.showSnackBar(const SnackBar(content: Text('Bir hata oldu. Tekrar dene.')));
  } finally {
    _adBusy = false;
  }
}

/// Ana sayfadaki küçük kredi hapı (Öne Çıkan Tahminciler başlığının sağında).
class CreditChip extends StatelessWidget {
  const CreditChip({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final uid = profileNotifier.value?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<int>(
      stream: Credits.watch(uid),
      builder: (_, snap) => Container(
        height: 34,
        padding: const EdgeInsets.fromLTRB(4, 0, 3, 0),
        decoration: BoxDecoration(
          color: c.ac.withAlpha(30),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: c.ac.withAlpha(100), width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: c.ac, shape: BoxShape.circle),
            child: Icon(Icons.monetization_on_outlined, size: 16, color: c.on),
          ),
          const SizedBox(width: 6),
          Text('${snap.data ?? Credits.welcome}', style: jakarta(14, FontWeight.w800, c.ac)),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => watchVideoForCredit(context),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: c.ac, borderRadius: BorderRadius.circular(14)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.play_arrow_rounded, size: 15, color: c.on),
                const SizedBox(width: 2),
                Text('Video izle +${Credits.videoReward}', style: jakarta(11, FontWeight.w800, c.on)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Yönetici penceresi: kullanıcıya kredi ver.
Future<void> adminGiveCreditDialog(BuildContext context, String uid, String name) async {
  final ctl = TextEditingController();
  final n = await showDialog<int>(
    context: context,
    builder: (dctx) {
      final c = AppColors.of(dctx);
      return AlertDialog(
        backgroundColor: c.sf,
        title: Text('Kredi ver: $name', style: jakarta(16, FontWeight.w800, c.tx)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(hintText: 'Örn. 100 (eksi yazarsan düşer)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, int.tryParse(ctl.text.trim())),
            child: const Text('Kaydet'),
          ),
        ],
      );
    },
  );
  if (n == null || n == 0) return;
  try {
    final v = await Credits.adminAdd(uid, n);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$name: yeni kredi $v')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kredi verilemedi.')));
    }
  }
}
