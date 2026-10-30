import 'admin.dart' show Presence;
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'frames.dart';

import 'theme.dart';

const handleMin = 3, handleMax = 20, nameMax = 30;

String cleanHandle(String s) {
  const map = {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u'};
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(map[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9_]'), '');
}

class Profile {
  final String uid, name, handle, bio, photo, cover, bioColor, frame;
  final bool isAdmin;
  Profile({
    required this.uid,
    required this.name,
    required this.handle,
    this.bio = '',
    this.photo = '',
    this.cover = '',
    this.bioColor = '',
    this.frame = '',
    this.isAdmin = false,
  });

  Profile copyWith({String? frame}) => Profile(
        uid: uid,
        name: name,
        handle: handle,
        bio: bio,
        photo: photo,
        cover: cover,
        bioColor: bioColor,
        frame: frame ?? this.frame,
        isAdmin: isAdmin,
      );

  factory Profile.fromMap(String uid, Map<String, dynamic> m) => Profile(
        uid: uid,
        name: (m['name'] ?? '').toString(),
        handle: (m['handle'] ?? '').toString(),
        bio: (m['bio'] ?? '').toString(),
        photo: (m['photo'] ?? '').toString(),
        cover: (m['cover'] ?? '').toString(),
        bioColor: (m['bioColor'] ?? '').toString(),
        frame: (m['frame'] ?? '').toString(),
        isAdmin: m['isAdmin'] == true,
      );

  late final ImageProvider? image = _imageOf(photo);
}

// Aynı fotoğraf her yeniden çizimde tekrar çözülmesin (avatar titremesi/yavaşlık)
final Map<String, ImageProvider?> _imgCache = {};

ImageProvider? _imageOf(String s) {
  if (s.isEmpty) return null;
  final hit = _imgCache[s];
  if (hit != null || _imgCache.containsKey(s)) return hit;
  ImageProvider? r;
  try {
    if (s.startsWith('http')) {
      r = CachedNetworkImageProvider(s);
    } else {
      final i = s.indexOf('base64,');
      if (i >= 0) r = MemoryImage(base64Decode(s.substring(i + 7)));
    }
  } catch (_) {}
  if (_imgCache.length > 600) _imgCache.remove(_imgCache.keys.first);
  if (r != null) _imgCache[s] = r;
  return r;
}

final ValueNotifier<Profile?> profileNotifier = ValueNotifier<Profile?>(null);

// Çözülmüş (decode edilmiş) avatarlar kalıcı tutulur: Flutter'ın resim önbelleği bellek baskısında
// (uygulama arka plana gidip gelince) boşalsa bile avatar ilk karede hazır çizilir, yeniden yüklenip kaybolmaz.
final Map<String, Map<int, ui.Image>> _decoded = {};
final Map<String, Map<int, Future<ui.Image?>>> _decoding = {};

ui.Image? _decodedOf(String photo, int px) => _decoded[photo]?[px];

Future<ui.Image?> _decodeAvatar(String photo, int px) {
  final hit = _decodedOf(photo, px);
  if (hit != null) return Future.value(hit);
  final raw = _imageOf(photo);
  if (raw == null) return Future.value(null);
  return (_decoding[photo] ??= {}).putIfAbsent(px, () {
    final c = Completer<ui.Image?>();
    final stream = ResizeImage.resizeIfNeeded(px, null, raw).resolve(ImageConfiguration.empty);
    late ImageStreamListener l;
    l = ImageStreamListener((info, _) {
      final im = info.image.clone();
      final m = (_decoded[photo] ??= {});
      if (_decoded.length > 400) _decoded.remove(_decoded.keys.first);
      m[px] = im;
      stream.removeListener(l);
      if (!c.isCompleted) c.complete(im);
    }, onError: (_, __) {
      stream.removeListener(l);
      if (!c.isCompleted) c.complete(null);
    });
    stream.addListener(l);
    return c.future.whenComplete(() => _decoding[photo]?.remove(px));
  });
}

/// Avatarları önceden çöz (splash sırasında): akış açılınca fotoğraflar hazır olsun.
Future<void> warmAvatars(Iterable<String> photos, List<int> sizes) async {
  final dpr = ui.PlatformDispatcher.instance.views.isEmpty ? 2.0 : ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
  for (final ph in photos) {
    if (ph.isEmpty) continue;
    for (final sz in sizes) {
      try { await _decodeAvatar(ph, (sz * dpr).round()); } catch (_) {}
    }
  }
}

class _Bus extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// Tüm avatarlar için tek ortak canlı kaynak: users koleksiyonu dinlenir (feed/liderler ile aynı sorgu,
/// Firestore tek dinleme olarak paylaşır). Biri fotoğrafını değiştirince her yerdeki avatar anında güncellenir.
class _LiveUsers {
  static final Map<String, String> photo = {};
  static final Map<String, String> frame = {}; // canlı çerçeve: hediye/mağaza değişince anında yansır
  static final _Bus bus = _Bus();
  static StreamSubscription? _sub;

  static void start() {
    if (_sub != null) return;
    try {
      _sub = FirebaseFirestore.instance.collection('users').limit(300).snapshots().listen((s) {
        var changed = false;
        for (final d in s.docs) {
          final ph = (d.data()['photo'] ?? '').toString();
          if (photo[d.id] != ph) {
            photo[d.id] = ph;
            changed = true;
          }
          final fr = (d.data()['frame'] ?? '').toString();
          if (frame[d.id] != fr) {
            frame[d.id] = fr;
            changed = true;
          }
        }
        if (changed) bus.ping();
      }, onError: (_) {
        _sub?.cancel();
        _sub = null; // çıkış/izin hatası: sonraki avatarda yeniden dene
      });
    } catch (_) {
      _sub = null;
    }
  }
}

class Avatar extends StatefulWidget {
  final Profile? profile;
  final double size;
  /// Verilirse canlı/profil çerçevesi yerine bu çerçeve çizilir (önizleme için).
  final String? forceFrame;
  const Avatar({super.key, required this.profile, this.size = 40, this.forceFrame});

  @override
  State<Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<Avatar> {
  ui.Image? _img;
  String _photo = '';
  int _px = 0;

  // Canlı fotoğraf varsa o, yoksa verilen profilin fotoğrafı
  String _eff() {
    final uid = widget.profile?.uid ?? '';
    final live = uid.isEmpty ? null : _LiveUsers.photo[uid];
    return live ?? (widget.profile?.photo ?? '');
  }

  String _liveFrame = '';

  String _effFrame() {
    if (widget.forceFrame != null) return widget.forceFrame!;
    final uid = widget.profile?.uid ?? '';
    final live = uid.isEmpty ? null : _LiveUsers.frame[uid];
    return live ?? (widget.profile?.frame ?? '');
  }

  void _onLive() {
    if (!mounted) return;
    final f = _effFrame();
    if (_eff() == _photo && f == _liveFrame) return;
    _liveFrame = f;
    _sync();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _LiveUsers.start();
    _LiveUsers.bus.addListener(_onLive);
  }

  @override
  void dispose() {
    _LiveUsers.bus.removeListener(_onLive);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(Avatar o) {
    super.didUpdateWidget(o);
    _sync();
  }

  void _sync() {
    final photo = _eff();
    final px = (widget.size * MediaQuery.devicePixelRatioOf(context)).round();
    if (photo == _photo && px == _px && (_img != null || photo.isEmpty)) return;
    final changedPhoto = photo != _photo;
    _photo = photo;
    _px = px;
    final hit = photo.isEmpty ? null : _decodedOf(photo, px);
    if (hit != null) { _img = hit; return; }
    if (changedPhoto) _img = null;
    if (photo.isEmpty) return;
    _decodeAvatar(photo, px).then((im) {
      if (mounted && im != null && photo == _photo && px == _px) setState(() => _img = im);
    });
  }

  // Çözülmüş önbellek henüz hazır değilse / çözme başarısız olduysa fotoğrafı doğrudan çiz.
  // gaplessPlayback: aynı fotoğraf yeniden çizilirken boş kare/titreme olmaz.
  Widget _fallback(String letter, double size) {
    final txt = Text(letter, style: jakarta(size * 0.42, FontWeight.w800, const Color(0xFF7A4B00)));
    final raw = _photo.isEmpty ? null : _imageOf(_photo);
    if (raw == null) return txt;
    return Image(
      image: ResizeImage.resizeIfNeeded(_px, null, raw),
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (c, child, frame, sync) => (frame == null && !sync) ? Center(child: txt) : child,
      errorBuilder: (_, __, ___) => Center(child: txt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final name = (widget.profile?.name ?? '').trim();
    final letter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    final img = _img;
    final fr = frameById(_effFrame());
    _liveFrame = _effFrame();
    final core = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFD66B)),
      clipBehavior: Clip.antiAlias,
      child: img != null
          ? RawImage(image: img, width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium)
          : _fallback(letter, size),
    );
    return fr == null ? core : framedAvatar(core, size, fr);
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

const _badLogin = 'Kullanıcı adı / e-posta veya şifre hatalı.';

const _codes = {
  'invalid-credential': _badLogin,
  'wrong-password': _badLogin,
  'user-not-found': _badLogin,
  'email-already-in-use': 'Bu e-posta zaten kayıtlı.',
  'weak-password': 'Şifre çok zayıf.',
  'invalid-email': 'Geçerli bir e-posta adresi yaz.',
  'too-many-requests': 'Çok fazla deneme yapıldı. Biraz sonra tekrar dene.',
  'network-request-failed': 'Bağlantı kurulamadı. İnternetini kontrol et.',
  'permission-denied': 'Yetki hatası: Firestore kuralları yayınlandı mı?',
  'unavailable': 'Bağlantı kurulamadı. İnternetini kontrol et.',
};

String _taken(String h) => '@$h kullanılmakta. Başka bir kullanıcı adı dene.';

class AuthService {
  static final ValueNotifier<bool> busy = ValueNotifier<bool>(false);
  // Kayıt sürerken bootstrap beklesin (yoksa otomatik profil açıp kaydı bozuyordu)
  static bool registering = false;

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static String errorText(Object e) {
    if (e is AuthException) return e.message;
    if (e is FirebaseException) return _codes[e.code] ?? e.message ?? 'İşlem başarısız.';
    return 'İşlem başarısız.';
  }

  static Future<Profile?> loadProfile(String uid) async {
    final d = await _db.collection('users').doc(uid).get();
    final data = d.data();
    if (!d.exists || data == null) return null;
    return Profile.fromMap(uid, data);
  }

  static Future<bool> handleTaken(String handle) async {
    final d = await _db.collection('handles').doc(handle).get();
    return d.exists;
  }

  static Future<bool> _createProfile(String uid, String name, String handle, String email, String photo) {
    final hRef = _db.collection('handles').doc(handle);
    final uRef = _db.collection('users').doc(uid);
    return _db.runTransaction<bool>((t) async {
      final h = await t.get(hRef);
      if (h.exists) return false;
      t.set(hRef, {'uid': uid, 'email': email});
      t.set(uRef, {
        'name': name,
        'handle': handle,
        'bio': '',
        'photo': photo,
        'cover': '',
        'bioColor': '',
        'following': <String>[],
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      });
      return true;
    });
  }

  static Future<void> register({
    required String name,
    required String handle,
    required String email,
    required String password,
    required String photo,
  }) async {
    busy.value = true;
    registering = true;
    try {
      if (await handleTaken(handle)) throw AuthException(_taken(handle));
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      final user = cred.user!;
      try {
        final ok = await _createProfile(user.uid, name, handle, email, photo);
        if (!ok) throw AuthException(_taken(handle));
      } catch (e) {
        try {
          await user.delete();
        } catch (_) {}
        rethrow;
      }
    } catch (e) {
      throw AuthException(errorText(e));
    } finally {
      registering = false;
      busy.value = false;
    }
  }

  static bool _gInit = false;
  static const _webClientId = '871686667838-pnva3a84epi19lnbl7g35dmojr5132b6.apps.googleusercontent.com';

  /// Google ile giriş. İptal edilirse false döner.
  static Future<bool> loginWithGoogle() async {
    busy.value = true;
    registering = true; // profil oluşana kadar bootstrap beklesin
    try {
      // google_sign_in 7: Android'de Credential Manager ("Google ile oturum aç" kompakt alt pencere)
      final g = GoogleSignIn.instance;
      if (!_gInit) {
        await g.initialize(serverClientId: _webClientId);
        _gInit = true;
      }
      try { await g.signOut(); } catch (_) {} // her seferinde hesap seçici açılsın
      final GoogleSignInAccount acc;
      try {
        acc = await g.authenticate();
      } on GoogleSignInException catch (e) {
        if (e.code == GoogleSignInExceptionCode.canceled) return false; // kullanıcı kapattı
        rethrow;
      }
      final idToken = acc.authentication.idToken;
      if (idToken == null) throw const AuthException('Google kimlik doğrulaması alınamadı.');
      final cred = GoogleAuthProvider.credential(idToken: idToken);
      final uc = await _auth.signInWithCredential(cred);
      final user = uc.user!;
      if (await loadProfile(user.uid) == null) await _ensureProfile(user);
      return true;
    } catch (e) {
      throw AuthException(errorText(e));
    } finally {
      registering = false;
      busy.value = false;
    }
  }

  static Future<String> _emailOf(String id) async {
    final s = id.trim();
    if (s.contains('@')) return s;
    final hs = await _db.collection('handles').doc(cleanHandle(s)).get();
    final email = hs.data()?['email'];
    if (!hs.exists || email is! String || email.isEmpty) throw const AuthException(_badLogin);
    return email;
  }

  static Future<void> login(String id, String password) async {
    busy.value = true;
    try {
      final email = await _emailOf(id);
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      throw AuthException(errorText(e));
    } finally {
      busy.value = false;
    }
  }

  static Future<void> resetPassword(String id) async {
    try {
      final email = await _emailOf(id);
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      final m = errorText(e);
      throw AuthException(m == _badLogin ? 'Bu kullanıcı bulunamadı.' : m);
    }
  }

  static Future<Profile> bootstrap(User u) async {
    for (var i = 0; i < 100 && registering; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final p = await loadProfile(u.uid) ?? await _ensureProfile(u);
    profileNotifier.value = p;
    return p;
  }

  static Future<Profile> _ensureProfile(User u) async {
    final email = u.email ?? '';
    var base = cleanHandle(email.split('@').first);
    if (base.length < handleMin) base = 'kullanici';
    if (base.length > handleMax) base = base.substring(0, handleMax);
    var name = (u.displayName ?? base).trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.length > nameMax) name = name.substring(0, nameMax);
    if (name.length < 2) name = base;
    final rnd = Random();
    for (var i = 0; i < 6; i++) {
      final h = i == 0
          ? base
          : base.substring(0, min(base.length, handleMax - 4)) + (1000 + rnd.nextInt(9000)).toString();
      if (await _createProfile(u.uid, name, h, email, '')) {
        final p = await loadProfile(u.uid);
        if (p != null) return p;
      }
    }
    throw const AuthException('Kullanıcı adı oluşturulamadı.');
  }

  /// Profil fotoğrafını kaydeder (fotoğraf kapısı için).
  static Future<void> savePhoto(String uid, String photo) async {
    await _db.collection('users').doc(uid).update({'photo': photo});
    profileNotifier.value = await loadProfile(uid);
  }

  static Future<void> signOut() async {
    try {
      await Presence.logout();
    } catch (_) {}
    profileNotifier.value = null;
    await _auth.signOut();
  }
}

Future<void> confirmSignOut(BuildContext context) async {
  final c = AppColors.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: c.sf,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Oturumu kapat', textAlign: TextAlign.center, style: jakarta(20, FontWeight.w800, c.tx)),
          const SizedBox(height: 10),
          Text('Oturumunu kapatmak istediğine emin misin? Verilerin bu cihazda saklanır.', textAlign: TextAlign.center, style: jakarta(14.5, FontWeight.w500, c.mu).copyWith(height: 1.35)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, false),
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln, width: 1.4)),
                  child: Text('Vazgeç', style: jakarta(15, FontWeight.w800, c.tx)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.pop(ctx, true),
                child: Container(
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(16)),
                  child: Text('Çıkış Yap', style: jakarta(15, FontWeight.w800, Colors.white)),
                ),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
  if (ok == true) await AuthService.signOut();
}
