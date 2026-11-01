import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'shell.dart' show IconBox;
import 'theme.dart';
import 'tjk.dart';

String _key(String s) => s
    .toUpperCase()
    .replaceAll('İ', 'I')
    .replaceAll('Ş', 'S')
    .replaceAll('Ğ', 'G')
    .replaceAll('Ü', 'U')
    .replaceAll('Ö', 'O')
    .replaceAll('Ç', 'C')
    .replaceAll(RegExp(r'[^A-Z0-9]'), '');

class _Resume with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) HorseWatch.i.check();
  }
}

/// Takip edilen atlar: at bültende (bugün/yarın) görününce zile bildirim yazar.
/// Aynı at için bildirim koşu saatine kadar saatte bir yenilenir; koşu saati geçince kaybolur.
class HorseWatch extends ChangeNotifier {
  HorseWatch._();
  static final HorseWatch i = HorseWatch._();

  static const _hour = 3600 * 1000;
  final _resume = _Resume();
  List<({String n, String id, String note})> follows = [];
  String _uid = '';
  Timer? _t;
  bool _busy = false;

  DocumentReference<Map<String, dynamic>> get _me => FirebaseFirestore.instance.collection('users').doc(_uid);

  Future<void> start(String uid) async {
    if (uid.isEmpty) return;
    _uid = uid;
    WidgetsBinding.instance.addObserver(_resume);
    await _load();
    _t?.cancel();
    _t = Timer.periodic(const Duration(minutes: 15), (_) => check());
    check();
  }

  void stop() {
    _t?.cancel();
    WidgetsBinding.instance.removeObserver(_resume);
    _uid = '';
    follows = [];
  }

  Future<void> _load() async {
    try {
      final d = await _me.get();
      final l = (d.data()?['fhorses'] as List?) ?? const [];
      follows = [
        for (final x in l.whereType<Map>())
          if ((x['n'] ?? '').toString().isNotEmpty) (n: x['n'].toString(), id: (x['id'] ?? '').toString(), note: (x['note'] ?? '').toString())
      ];
      notifyListeners();
    } catch (_) {}
  }

  bool isFollowing(String name) => follows.any((f) => _key(f.n) == _key(name));

  Future<void> _save() async {
    try {
      await _me.set({
        'fhorses': [for (final f in follows) {'n': f.n, 'id': f.id, 'note': f.note}]
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// true = takibe alındı, false = takipten çıkarıldı
  Future<bool> toggle(String name, String atId) async {
    final k = _key(name);
    final on = follows.any((f) => _key(f.n) == k);
    if (on) {
      follows = follows.where((f) => _key(f.n) != k).toList();
    } else {
      follows = [...follows, (n: name, id: atId, note: '')];
    }
    notifyListeners();
    await _save();
    if (!on) check();
    return !on;
  }

  String noteOf(String name) {
    final k = _key(name);
    for (final f in follows) {
      if (_key(f.n) == k) return f.note;
    }
    return '';
  }

  /// Notu kaydeder; at takipte değilse takibe de alır.
  Future<void> setNote(String name, String atId, String note) async {
    final k = _key(name);
    final t = note.trim();
    final on = follows.any((f) => _key(f.n) == k);
    if (on) {
      follows = [for (final f in follows) _key(f.n) == k ? (n: f.n, id: f.id, note: t) : f];
    } else {
      follows = [...follows, (n: name, id: atId, note: t)];
    }
    notifyListeners();
    await _save();
    if (!on) check();
  }

  DateTime? _start(String iso, String saat) {
    final m = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(saat.trim());
    if (m == null) return null;
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// Bugün ve yarının bültenini tarar; takip edilen at varsa bildirimi (saatte bir) yazar/yeniler.
  Future<void> check() async {
    if (_busy || _uid.isEmpty || follows.isEmpty) return;
    _busy = true;
    try {
      final col = FirebaseFirestore.instance.collection('notifs');
      // Zilin kullandığı sorgu: son bildirim zamanlarını buradan okuruz
      final last = <String, int>{};
      try {
        final q = await col.where('to', isEqualTo: _uid).limit(100).get();
        for (final d in q.docs) {
          last[d.id] = ((d.data()['ts'] as num?) ?? 0).toInt();
        }
      } catch (_) {}
      final keys = {for (final f in follows) _key(f.n): f.n};
      final ids = {for (final f in follows) if (f.id.isNotEmpty) f.id: f.n};
      final today = isoToday();
      for (final iso in [today, isoAdd(today, 1)]) {
        List<City> cities;
        try {
          cities = await getCities(iso);
        } catch (_) {
          continue;
        }
        for (final c in cities) {
          List<Race> races;
          try {
            races = await getProgram(c, iso);
          } catch (_) {
            continue;
          }
          for (final r in races) {
            final st = _start(iso, r.saat);
            final now = DateTime.now();
            if (st == null || !st.isAfter(now)) continue;
            for (final h in r.atlar) {
              if (h.kosmaz) continue;
              final hit = keys[_key(h.name)] ?? (h.atId.isNotEmpty ? ids[h.atId] : null);
              if (hit == null) continue;
              final id = 'fh_${_uid}_${iso}_${_key(c.name)}_${r.no}_${_key(h.name)}';
              final ms = now.millisecondsSinceEpoch;
              if (ms - (last[id] ?? 0) < _hour) continue;
              try {
                await col.doc(id).set({
                  'to': _uid,
                  'from': _uid,
                  'type': 'horse',
                  'fn': h.name,
                  'tx': '${c.name} · ${r.no}. koşu · ${r.saat}',
                  'hd': iso == today ? 'bugün' : 'yarın',
                  'hc': c.name,
                  'hr': r.no,
                  'hi': iso,
                  'ts': ms,
                  'exp': Timestamp.fromDate(st),
                });
                last[id] = ms;
              } catch (_) {}
            }
          }
        }
      }
    } finally {
      _busy = false;
    }
  }
}

/* ---------------- Not penceresi ---------------- */

/// Yıldıza dokununca açılır. Dönen metin toast olarak gösterilir (null = vazgeçildi).
Future<String?> showHorseNoteSheet(BuildContext context, String name, String atId) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NoteSheet(name: name, atId: atId),
  );
}

class _NoteSheet extends StatefulWidget {
  final String name, atId;
  const _NoteSheet({required this.name, required this.atId});
  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final TextEditingController _ctl = TextEditingController(text: HorseWatch.i.noteOf(widget.name));
  static const _quick = ['Formda', 'Pist sevmiyor', 'Kilo avantajı', 'Son dakikaya bak', 'Ganyana koy'];

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _add(String t) {
    final cur = _ctl.text.trim();
    _ctl.text = cur.isEmpty ? t : '$cur · $t';
    _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final following = HorseWatch.i.isFollowing(widget.name);
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final bottom = kb > 0 ? kb : mq.padding.bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(color: c.sf, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 42, height: 4, decoration: BoxDecoration(color: c.ln, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.gold.withAlpha(32), borderRadius: BorderRadius.circular(14)),
                child: Icon(Icons.star_rounded, color: c.gold, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(17, FontWeight.w800, c.tx)),
                  Text('Kendine not bırak, takip edilen atlarda görünür.', style: jakarta(12, FontWeight.w600, c.mu)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _ctl,
              minLines: 3,
              maxLines: 5,
              maxLength: 300,
              scrollPadding: const EdgeInsets.only(bottom: 140),
              textCapitalization: TextCapitalization.sentences,
              style: jakarta(14, FontWeight.w600, c.tx),
              decoration: InputDecoration(
                hintText: 'Örn. son koşusunda geç açıldı, pist ağırsa bak…',
                hintStyle: jakarta(14, FontWeight.w500, c.mu),
                filled: true,
                fillColor: c.sf2,
                counterStyle: jakarta(11, FontWeight.w600, c.mu),
                isDense: true,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c.ac, width: 1.6)),
              ),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final q in _quick)
                GestureDetector(
                  onTap: () => _add(q),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: c.ln)),
                    child: Text(q, style: jakarta(12, FontWeight.w700, c.tx)),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              if (following)
                TextButton(
                  onPressed: () async {
                    await HorseWatch.i.toggle(widget.name, widget.atId);
                    if (context.mounted) Navigator.pop(context, '${widget.name} takipten çıkarıldı.');
                  },
                  child: Text('Takibi bırak', style: jakarta(13.5, FontWeight.w700, c.red)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Vazgeç', style: jakarta(13.5, FontWeight.w700, c.mu)),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.ac,
                  foregroundColor: c.on,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () async {
                  await HorseWatch.i.setNote(widget.name, widget.atId, _ctl.text);
                  if (context.mounted) {
                    Navigator.pop(context, following ? 'Not kaydedildi.' : '${widget.name} takip edildi. Koşacağı zaman zile bildirim gelecek.');
                  }
                },
                child: Text('Kaydet', style: jakarta(14, FontWeight.w800, c.on)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/* ---------------- Takip atları sayfası ---------------- */

class FollowedHorsesPage extends StatelessWidget {
  const FollowedHorsesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(children: [
              IconBox(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
              const SizedBox(width: 12),
              Text('Takip atları', style: jakarta(20, FontWeight.w800, c.tx)),
            ]),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: HorseWatch.i,
              builder: (_, __) {
                final l = HorseWatch.i.follows;
                if (l.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Henüz takip ettiğin at yok.\nTahmin Yap sayfasında atın yanındaki yıldıza dokun; at bültende koşmaya hazır olunca zile bildirim gelir.',
                        textAlign: TextAlign.center,
                        style: jakarta(14, FontWeight.w600, c.mu),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: l.length,
                  itemBuilder: (_, i) {
                    final f = l[i];
                    final has = f.note.isNotEmpty;
                    return GestureDetector(
                      onTap: () async {
                        final m = await showHorseNoteSheet(context, f.n, f.id);
                        if (m != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                        decoration: BoxDecoration(color: c.sf, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.ln)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(color: c.gold.withAlpha(32), borderRadius: BorderRadius.circular(12)),
                              child: Icon(Icons.star_rounded, color: c.gold, size: 21),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(f.n, style: jakarta(15, FontWeight.w800, c.tx))),
                            TextButton(
                              onPressed: () => HorseWatch.i.toggle(f.n, f.id),
                              child: Text('Takibi bırak', style: jakarta(13, FontWeight.w700, c.red)),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: BoxDecoration(
                              color: has ? c.gold.withAlpha(22) : c.sf2,
                              borderRadius: BorderRadius.circular(14),
                              border: Border(left: BorderSide(color: has ? c.gold : c.ln, width: 3.5)),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(has ? Icons.edit_note_rounded : Icons.add_rounded, size: 20, color: has ? c.gold : c.mu),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  has ? f.note : 'Not ekle',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: jakarta(13, has ? FontWeight.w600 : FontWeight.w700, has ? c.tx : c.mu),
                                ),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
