import 'package:cloud_firestore/cloud_firestore.dart';

/* =====================================================================
   KREDİ SİSTEMİ
   users/{uid}.credits = int   (kupon paylaşma hakkı)
   Yeni kullanıcıya ilk girişte [welcome] kredi verilir.
   Kredi paraya çevrilmez, sadece uygulama içinde kullanılır.
   ===================================================================== */
class Credits {
  static const int welcome = 3; // ilk kredi hediyesi
  static const int perKupon = 1; // bir kupon paylaşmanın bedeli
  static const int videoReward = 50; // her video izlemeye verilen kredi
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

  /// Kredi ekler (video izleyince çağrılacak).
  static Future<void> add(String uid, {int n = videoReward}) {
    final ref = _db.collection('users').doc(uid);
    return _db.runTransaction<void>((t) async {
      final cur = _read((await t.get(ref)).data());
      t.set(ref, {'credits': cur + n}, SetOptions(merge: true));
    });
  }
}
