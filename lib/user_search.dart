import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'auth_service.dart';
import 'preload.dart';
import 'profile.dart';
import 'theme.dart';

/// Instagram tarzı tam ekran kullanıcı arama:
/// - kendi hafif sayfası (ağır sekmeler klavyeyle yeniden ölçülmez)
/// - anında açılan, yumuşak geçişli sayfa; klavye otomatik çıkar
/// - boşken "Son aramalar", yazdıkça anlık sıralı sonuç
/// - sonuca dokununca klavye kapanır, profil açılır, geri gelince klavye kendiliğinden açılmaz
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  static Route<void> route() => PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 170),
        reverseTransitionDuration: const Duration(milliseconds: 130),
        pageBuilder: (_, __, ___) => const UserSearchPage(),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      );

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _U {
  final String id, name, handle, nName, nHandle;
  final Profile profile;
  _U(this.id, this.name, this.handle, this.nName, this.nHandle, this.profile);
}

/// Türkçe harfleri sadeleştir: "Şükrü" ile "sukru" eşleşsin.
String _norm(String t) {
  const from = 'çğıöşü';
  const to = 'cgiosu';
  final b = StringBuffer();
  for (final r in t.replaceAll('İ', 'i').replaceAll('I', 'i').toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}

class _UserSearchPageState extends State<UserSearchPage> {
  // Son aramalar (uygulama açık kaldığı sürece saklanır)
  static final List<String> _recent = [];

  final TextEditingController _ctl = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<_U> _all = const [];
  List<_U> _res = const [];
  bool _loading = true;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = Preload.users;
    if (docs.isEmpty) {
      try {
        docs = (await FirebaseFirestore.instance.collection('users').limit(300).get()).docs;
      } catch (_) {
        docs = const [];
      }
    }
    final me = profileNotifier.value?.uid ?? '';
    final l = <_U>[];
    for (final d in docs) {
      if (d.id == me) continue;
      final m = d.data();
      final n = (m['name'] ?? '').toString();
      final h = (m['handle'] ?? '').toString().replaceFirst('@', '');
      l.add(_U(d.id, n, h, _norm(n), _norm(h), Profile.fromMap(d.id, m)));
    }
    if (!mounted) return;
    setState(() {
      _all = l;
      _loading = false;
      _res = _filter(_q);
    });
  }

  List<_U> _filter(String raw) {
    final q = _norm(raw.trim().replaceFirst('@', ''));
    if (q.isEmpty) return const [];
    final scored = <(int, _U)>[];
    for (final u in _all) {
      int sc;
      if (u.nName.startsWith(q) || u.nHandle.startsWith(q)) {
        sc = 0;
      } else if (u.nName.split(RegExp(r'\s+')).any((w) => w.startsWith(q))) {
        sc = 1;
      } else if (u.nName.contains(q) || u.nHandle.contains(q)) {
        sc = 2;
      } else {
        continue;
      }
      scored.add((sc, u));
    }
    scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.nName.compareTo(b.$2.nName));
    return [for (final e in scored.take(40)) e.$2];
  }

  void _onChanged(String v) {
    setState(() {
      _q = v;
      _res = _filter(v);
    });
  }

  Future<void> _open(String id) async {
    _recent
      ..remove(id)
      ..insert(0, id);
    if (_recent.length > 12) _recent.removeLast();
    // Klavyeyi hemen indir; geri dönünce kutu odağı geri almasın (Instagram gibi)
    _focus.canRequestFocus = false;
    _focus.unfocus();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileRoute(uid: id)));
    if (!mounted) return;
    _focus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focus.canRequestFocus = true;
        setState(() {}); // son aramalar güncellensin
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final empty = _q.trim().isEmpty;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: c.tx),
                  onPressed: () {
                    _focus.unfocus();
                    Navigator.maybePop(context);
                  },
                ),
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.only(left: 12),
                    decoration: softCard(c, radius: 14.0),
                    child: Row(children: [
                      Icon(Icons.search, size: 20, color: c.mu),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _ctl,
                          focusNode: _focus,
                          autofocus: true,
                          onChanged: _onChanged,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _focus.unfocus(),
                          autocorrect: false,
                          enableSuggestions: false,
                          style: jakarta(15, FontWeight.w600, c.tx),
                          cursorColor: c.ac,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: 'Kullanıcı ara',
                            hintStyle: jakarta(15, FontWeight.w600, c.mu),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (!empty)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _ctl.clear();
                            _onChanged('');
                            _focus.requestFocus();
                          },
                          child: Padding(padding: const EdgeInsets.all(12), child: Icon(Icons.close, size: 18, color: c.mu)),
                        ),
                    ]),
                  ),
                ),
              ]),
            ),
            Expanded(child: empty ? _recentList(c) : _results(c)),
          ],
        ),
      ),
    );
  }

  Widget _row(AppColors c, _U u, {Widget? trailing}) => InkWell(
        onTap: () => _open(u.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Avatar(profile: u.profile, size: 46),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(15, FontWeight.w800, c.tx)),
                Text('@${u.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(13, FontWeight.w600, c.mu)),
              ]),
            ),
            if (trailing != null) trailing,
          ]),
        ),
      );

  Widget _results(AppColors c) {
    if (_loading) return Center(child: CircularProgressIndicator(color: c.ac, strokeWidth: 2.5));
    if (_res.isEmpty) {
      return Center(child: Text('Kullanıcı bulunamadı.', style: jakarta(14, FontWeight.w600, c.mu)));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: _res.length,
      itemBuilder: (_, i) => _row(c, _res[i]),
    );
  }

  Widget _recentList(AppColors c) {
    final byId = {for (final u in _all) u.id: u};
    final items = [for (final id in _recent) if (byId[id] != null) byId[id]!];
    if (items.isEmpty) {
      return Center(child: Text(_loading ? '' : 'Bir ad veya @kullanıcı adı yaz.', style: jakarta(14, FontWeight.w600, c.mu)));
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(children: [
            Expanded(child: Text('Son aramalar', style: jakarta(15, FontWeight.w800, c.tx))),
            TextButton(
              onPressed: () => setState(_recent.clear),
              child: Text('Tümünü temizle', style: jakarta(13, FontWeight.w700, c.ac)),
            ),
          ]),
        ),
        for (final u in items)
          _row(
            c,
            u,
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _recent.remove(u.id)),
              child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.close, size: 18, color: c.mu)),
            ),
          ),
      ],
    );
  }
}
