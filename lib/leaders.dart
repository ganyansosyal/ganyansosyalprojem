import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin.dart' show showGiftDialog;
import 'auth_service.dart';
import 'feed.dart';
import 'profile.dart';
import 'scoring.dart';
import 'settle.dart' show isAdminNotifier;
import 'theme.dart';
import 'tjk.dart' show liveResTick;

class LeadersPage extends StatefulWidget {
  const LeadersPage({super.key});
  @override
  State<LeadersPage> createState() => _LeadersPageState();
}

class _LeadersPageState extends State<LeadersPage> {
  final _subs = <StreamSubscription>[];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _users = [];
  Map<String, double> _bonus = {};
  List<Post> _posts = [];
  bool _ready = false;
  String? _err;
  List<({QueryDocumentSnapshot<Map<String, dynamic>> d, Score s})> _rows = const [];
  Timer? _deb;

  // Üç stream peş peşe gelince tabloyu bir kez hesapla
  void _touch() {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final me = profileNotifier.value?.uid ?? '';
      final meDoc = _users.where((d) => d.id == me).toList();
      final admin = meDoc.isNotEmpty && meDoc.first.data()['isAdmin'] == true;
      final rows = _users
          .map((d) => (d: d, s: scoreOf(d.id, _posts, d.data()['hist'] as Map?, _bonus[d.id] ?? 0)))
          .where((x) => admin || x.s.pts > 0)
          .toList()
        ..sort((a, b) {
          final k = b.s.pts.compareTo(a.s.pts);
          if (k != 0) return k;
          final r = b.s.pct.compareTo(a.s.pct);
          if (r != 0) return r;
          return (a.d.data()['name'] ?? '').toString().compareTo((b.d.data()['name'] ?? '').toString());
        });
      setState(() {
        _rows = rows.take(admin ? 100 : 50).toList();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    liveResTick.addListener(_touch);
    final db = FirebaseFirestore.instance;
    void err(Object e) => setState(() => _err = AuthService.errorText(e));
    _subs.add(db.collection('users').limit(300).snapshots().listen((s) {
      _users = s.docs;
      _ready = true;
      _touch();
    }, onError: err));
    _subs.add(db.collection('grants').limit(500).snapshots().listen((s) {
      _bonus = {
        for (final d in s.docs) d.id: ((d.data()['pts'] as num?)?.toDouble() ?? 0) + ((d.data()['keep'] as num?)?.toDouble() ?? 0)
      };
      _touch();
    }, onError: (_) {}));
    _subs.add(db.collection('posts').orderBy('ts', descending: true).limit(100).snapshots().listen((s) {
      _posts = s.docs.map((d) => Post(d.id, d.data())).toList();
      _touch();
    }, onError: (_) {}));
  }

  @override
  void dispose() {
    liveResTick.removeListener(_touch);
    _deb?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    if (_err != null) return Center(child: Text(_err!, style: jakarta(14, FontWeight.w600, c.mu)));
    if (!_ready) return Center(child: CircularProgressIndicator(color: c.ac));
    if (_rows.isEmpty && _deb?.isActive == true) return Center(child: CircularProgressIndicator(color: c.ac));
    final me = profileNotifier.value?.uid ?? '';
    final top = _rows;
    final head = <Widget>[
      Text('Puan sıralaması', style: jakarta(20, FontWeight.w800, c.tx)),
      const SizedBox(height: 2),
      Text('Puana göre sıralanır. Puan eşitse isabet oranı yüksek olan öne geçer.', style: jakarta(12.5, FontWeight.w500, c.mu)),
      const SizedBox(height: 10),
      if (top.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(children: [
            const Text('🏆', style: TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text('Henüz puan alan yok', style: jakarta(18, FontWeight.w800, c.tx)),
            const SizedBox(height: 6),
            Text('Kuponunu tutturan ilk kişi burada görünecek.', style: jakarta(14, FontWeight.w500, c.mu)),
          ]),
        ),
    ];
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      cacheExtent: 600,
      itemCount: head.length + top.length,
      itemBuilder: (context, i) => i < head.length ? head[i] : RepaintBoundary(child: _row(c, i - head.length, top[i - head.length], me)),
    );
  }

  Widget _row(AppColors c, int i, ({QueryDocumentSnapshot<Map<String, dynamic>> d, Score s}) x, String me) {
    final u = Profile.fromMap(x.d.id, x.d.data());
    final isMe = x.d.id == me;
    final medal = i == 0 ? '🥇' : i == 1 ? '🥈' : i == 2 ? '🥉' : '${i + 1}';
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileRoute(uid: x.d.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: softCard(c).copyWith(border: isMe ? Border.all(color: c.ac, width: 2) : null),
        child: Row(children: [
          SizedBox(
            width: 28,
            child: Text(x.s.pts > 0 ? medal : '–', textAlign: TextAlign.center, style: jakarta(i < 3 ? 19 : 15, FontWeight.w800, c.mu)),
          ),
          const SizedBox(width: 4),
          Avatar(profile: u, size: 52),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(15, FontWeight.w800, c.tx)),
              Text('@${u.handle}${x.s.tot > 0 ? ' · %${x.s.pct} isabet' : ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12, FontWeight.w600, c.mu)),
            ]),
          ),
          Column(children: [
            Text(fmtPts(x.s.pts), style: jakarta(20, FontWeight.w800, c.ac)),
            Text('puan', style: jakarta(11, FontWeight.w600, c.mu)),
          ]),
          ValueListenableBuilder<bool>(
            valueListenable: isAdminNotifier,
            builder: (context, adm, _) => !adm
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: GestureDetector(
                      onTap: () => showGiftDialog(context, uid: x.d.id, name: u.name, targetAdmin: u.isAdmin),
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA855F7), Color(0xFFDB2777)]),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(color: Color(0x40A855F7), blurRadius: 6, offset: Offset(0, 2))],
                        ),
                        child: const Text('🎁', style: TextStyle(fontSize: 20)),
                      ),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
