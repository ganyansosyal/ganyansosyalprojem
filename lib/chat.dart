import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth_service.dart';
import 'feed.dart' show fmtStamp;
import 'profile.dart' show ProfileRoute;
import 'settle.dart';
import 'theme.dart';

final Map<String, Profile?> _pv = {};
final Map<String, Future<Profile?>> _pf = {};
Future<Profile?> _chatProfile(String uid) {
  if (uid.isEmpty) return Future.value(null);
  return _pf.putIfAbsent(uid, () => AuthService.loadProfile(uid).then((p) {
        _pv[uid] = p;
        return p;
      }).catchError((_) {
        _pf.remove(uid); // hata kalıcı olmasın, sonraki çizimde tekrar dene
        return null;
      }));
}

void openChat(BuildContext context) {
  final c = AppColors.of(context);
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => const _ChatSheet(),
  );
}

class _ChatSheet extends StatefulWidget {
  const _ChatSheet();
  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final _ctl = TextEditingController();
  Map<String, dynamic>? _reply;
  String? _editId;
  int _last = 0;
  final _db = FirebaseFirestore.instance;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _s = _db.collection('chat').orderBy('ts', descending: true).limit(150).snapshots();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _lock = _db.collection('config').doc('chat').snapshots();
  String get _me => profileNotifier.value?.uid ?? '';
  late final Widget _listW = _list();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _send() async {
    final t = _ctl.text.trim();
    final me = profileNotifier.value;
    if (t.isEmpty || me == null) return;
    final txt = t.length > 300 ? t.substring(0, 300) : t;
    try {
      if (_editId != null) {
        final id = _editId!;
        setState(() => _editId = null);
        _ctl.clear();
        await _db.collection('chat').doc(id).update({'t': txt, 'ed': true});
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _last < 1500) {
        _toast('Biraz yavaş yaz.');
        return;
      }
      _last = now;
      final rp = _reply;
      _ctl.clear();
      setState(() => _reply = null);
      await _db.collection('chat').add({
        'uid': me.uid,
        'n': me.name,
        't': txt,
        'ts': now,
        if (rp != null) 'r': {'id': rp['id'], 'n': rp['n'], 't': (rp['t'] ?? '').toString().length > 120 ? (rp['t'] as String).substring(0, 120) : rp['t']},
      });
    } catch (e) {
      _toast(AuthService.errorText(e));
    }
  }

  void _menu(String id, Map<String, dynamic> m, bool admin) {
    final c = AppColors.of(context);
    final mine = m['uid'] == _me;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.bg,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Yanıtla'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _reply = {'id': id, 'n': m['n'], 't': m['t']});
            },
          ),
          ListTile(leading: const Icon(Icons.copy), title: const Text('Kopyala'), onTap: () {
            Clipboard.setData(ClipboardData(text: '${m['t'] ?? ''}'));
            Navigator.pop(ctx);
          }),
          if (mine)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Düzenle'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _editId = id;
                  _reply = null;
                  _ctl.text = '${m['t'] ?? ''}';
                });
              },
            ),
          if (mine || admin)
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.red),
              title: Text('Sil', style: TextStyle(color: c.red)),
              onTap: () {
                Navigator.pop(ctx);
                _db.collection('chat').doc(id).delete().catchError((e) => _toast(AuthService.errorText(e)));
              },
            ),
        ]),
      ),
    );
  }

  Widget _avatar(Map<String, dynamic> m) {
    final uid = '${m['uid'] ?? ''}';
    final nm = '${m['n'] ?? ''}';
    return FutureBuilder<Profile?>(
      future: _chatProfile(uid),
      initialData: _pv[uid],
      builder: (context, s) {
        final pr = s.data ?? Profile(uid: uid, name: nm, handle: '');
        return GestureDetector(
          onTap: () {
            if (uid.isNotEmpty) Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileRoute(uid: uid)));
          },
          child: Avatar(profile: pr, size: 32),
        );
      },
    );
  }

  // Yönetici: tüm sohbet mesajlarını sil
  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = AppColors.of(ctx);
        return Dialog(
          backgroundColor: c.sf,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(color: c.red.withAlpha(30), shape: BoxShape.circle),
                child: Icon(Icons.delete_sweep_rounded, size: 30, color: c.red),
              ),
              const SizedBox(height: 16),
              Text('Sohbet temizlensin mi?', textAlign: TextAlign.center, style: jakarta(19, FontWeight.w800, c.tx)),
              const SizedBox(height: 8),
              Text('Tüm mesajlar herkes için silinecek. Bu işlem geri alınamaz.', textAlign: TextAlign.center, style: jakarta(14, FontWeight.w500, c.mu).copyWith(height: 1.4)),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, false),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(16)),
                      child: Text('Vazgeç', style: jakarta(15, FontWeight.w800, c.tx)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx, true),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: c.red, borderRadius: BorderRadius.circular(16)),
                      child: Text('Temizle', style: jakarta(15, FontWeight.w800, Colors.white)),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        );
      },
    );
    if (ok != true) return;
    try {
      while (true) {
        final q = await _db.collection('chat').limit(400).get();
        if (q.docs.isEmpty) break;
        final b = _db.batch();
        for (final d in q.docs) {
          b.delete(d.reference);
        }
        await b.commit();
        if (q.docs.length < 400) break;
      }
      _toast('Sohbet temizlendi');
    } catch (e) {
      _toast(AuthService.errorText(e));
    }
  }

  Widget _list() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _s,
      builder: (context, snap) {
        final c = AppColors.of(context);
        if (snap.hasError) return Center(child: Text(AuthService.errorText(snap.error!), style: jakarta(14, FontWeight.w600, c.mu)));
        if (!snap.hasData) return Center(child: CircularProgressIndicator(color: c.ac));
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Center(child: Text('Henüz mesaj yok. İlk mesajı sen yaz!', style: jakarta(14, FontWeight.w600, c.mu)));
        final maxW = MediaQuery.sizeOf(context).width * 0.70;
        return ValueListenableBuilder<bool>(
          valueListenable: isAdminNotifier,
          builder: (context, admin, _) => ListView.builder(
            reverse: true,
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              final m = d.data();
              final mine = m['uid'] == _me;
              final rp = m['r'] is Map ? Map<String, dynamic>.from(m['r'] as Map) : null;
              // Liste ters: i-1 daha yeni, i+1 daha eski mesaj
              final lastOfGroup = i == 0 || docs[i - 1].data()['uid'] != m['uid'];
              final firstOfGroup = i == docs.length - 1 || docs[i + 1].data()['uid'] != m['uid'];
              final bubble = GestureDetector(
                onLongPress: () => _menu(d.id, m, admin),
                child: Container(
                  constraints: BoxConstraints(maxWidth: maxW),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: mine ? c.ac.withAlpha(40) : c.sf, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!mine && firstOfGroup) Text('${m['n'] ?? 'Kullanıcı'}', style: jakarta(12.5, FontWeight.w800, c.ac)),
                    if (rp != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(8)),
                        child: Text('${rp['n'] ?? ''}: ${rp['t'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: jakarta(12, FontWeight.w600, c.mu)),
                      ),
                    Text('${m['t'] ?? ''}', style: jakarta(14.5, FontWeight.w600, c.tx)),
                    Text('${fmtStamp(((m['ts'] as num?) ?? 0).toInt())}${m['ed'] == true ? ' · düzenlendi' : ''}', style: jakarta(10.5, FontWeight.w500, c.mu)),
                  ]),
                ),
              );
              return Padding(
                padding: EdgeInsets.only(top: firstOfGroup ? 6 : 0, bottom: 2),
                child: mine
                    ? Align(alignment: Alignment.centerRight, child: bubble)
                    : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        SizedBox(width: 32, child: lastOfGroup ? _avatar(m) : null),
                        const SizedBox(width: 6),
                        Flexible(child: bubble),
                      ]),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return KbSheet(
      fraction: 0.62,
      child: Column(children: [
        const SizedBox(height: 12),
        Row(children: [
          const SizedBox(width: 16),
          Text('Sohbet', style: jakarta(18, FontWeight.w800, c.tx)),
          const Spacer(),
          ValueListenableBuilder<bool>(
            valueListenable: isAdminNotifier,
            builder: (context, admin, _) => admin
                ? TextButton.icon(
                    onPressed: _clearAll,
                    icon: Icon(Icons.delete_sweep_rounded, size: 20, color: c.red),
                    label: Text('Temizle', style: jakarta(13, FontWeight.w800, c.red)),
                  )
                : const SizedBox.shrink(),
          ),
          IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close, color: c.mu)),
        ]),
        Expanded(child: _listW),
        if (_reply != null || _editId != null)
          Container(
            width: double.infinity,
            color: c.sf2,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(children: [
              Expanded(child: Text(_editId != null ? 'Mesaj düzenleniyor' : '${_reply!['n']}: ${_reply!['t']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12.5, FontWeight.w600, c.mu))),
              GestureDetector(onTap: () => setState(() {
                    _reply = null;
                    if (_editId != null) _ctl.clear();
                    _editId = null;
                  }), child: Icon(Icons.close, size: 18, color: c.mu)),
            ]),
          ),
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _lock,
          builder: (context, ls) {
            final locked = ls.data?.data()?['locked'] == true && !isAdminNotifier.value;
            return Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ctl,
                    enabled: !locked,
                    maxLength: 300,
                    minLines: 1,
                    maxLines: 4,
                    style: jakarta(14.5, FontWeight.w600, c.tx),
                    decoration: InputDecoration(border: InputBorder.none, counterText: '', hintText: locked ? 'Sohbet kilitli' : 'Mesaj yaz...', hintStyle: jakarta(14, FontWeight.w500, c.mu)),
                  ),
                ),
                IconButton(onPressed: locked ? null : _send, icon: Icon(Icons.send_rounded, color: c.ac)),
              ]),
            );
          },
        ),
      ]),
    );
  }
}
