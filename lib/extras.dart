import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'scoring.dart';
import 'shell.dart' show IconBox;
import 'theme.dart';

export 'shop.dart' show ShopPage;

Widget _scaffold(BuildContext context, String title, Widget body) {
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
            Text(title, style: jakarta(20, FontWeight.w800, c.tx)),
          ]),
        ),
        Expanded(child: body),
      ]),
    ),
  );
}

Widget _card(AppColors c, String title, List<Widget> rows, {String? note}) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: softCard(c, radius: 20.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: jakarta(16, FontWeight.w800, c.tx)),
        const SizedBox(height: 8),
        ...rows,
        if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note, style: jakarta(12.5, FontWeight.w500, c.mu))),
      ]),
    );

Widget _row(AppColors c, String a, String b) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Flexible(child: Text(a, style: jakarta(14, FontWeight.w600, c.tx))),
        Text(b, style: jakarta(14, FontWeight.w800, c.ac)),
      ]),
    );

Widget _notice(AppColors c) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.red.withAlpha(24), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.red.withAlpha(90))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.info_outline_rounded, size: 20, color: c.red),
          const SizedBox(width: 8),
          Text('Önemli bilgilendirme', style: jakarta(16, FontWeight.w800, c.red)),
        ]),
        const SizedBox(height: 8),
        Text('GanyanSosyal bir bahis veya kumar uygulaması değildir. Burada gerçek para ile bahis oynatılmaz, para yatırılmaz ve para çekilmez.', style: jakarta(13.5, FontWeight.w600, c.tx).copyWith(height: 1.4)),
        const SizedBox(height: 8),
        for (final t in const [
          'Kuponlar tamamen sanaldır. Resmi bir bahis kuponu değildir ve geçerliliği yoktur.',
          'Tutan kuponlar için ikramiye, ödül veya para talep edilemez. Sonuçlar sadece uygulama içi puan ve sıralamada gösterilir.',
          'Puanlar ve krediler eğlence ve tahmin amaçlıdır. Gerçek bir parasal değeri yoktur, paraya veya başka bir ürüne çevrilemez.',
          'Uygulama kumarı ve bahis oynamayı teşvik etmez.',
          'Kullanmak için 18 yaşını doldurmuş olman gerekir.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('•  ', style: jakarta(13.5, FontWeight.w800, c.red)),
              Expanded(child: Text(t, style: jakarta(13.5, FontWeight.w500, c.tx).copyWith(height: 1.4))),
            ]),
          ),
      ]),
    );

/* ---------------- Kurallar ---------------- */

class RulesPage extends StatelessWidget {
  const RulesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    const sira = ["7'li Ganyan", "6'lı Ganyan", 'Sıralı Beşli', "5'li Ganyan", "7'li Plase", 'Tabela Bahis', "4'lü Ganyan", 'Sıralı Üçlü', "3'lü Ganyan", 'Çifte Bahis', 'Sıralı İkili', 'İkili Bahis', 'Plase İkili', 'Ganyan', 'Ganyan & Plase', 'Plase'];
    return _scaffold(
      context,
      'Kurallar',
      ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        _notice(c),
        Text('Puan sadece paylaştığın kuponlardan gelir. Sonuçlar TJK\'dan otomatik alınır ve kuponlar kendiliğinden değerlendirilir.', style: jakarta(14, FontWeight.w500, c.mu)),
        const SizedBox(height: 12),
        _card(c, 'Kupon tutarsa kaç puan', [for (final t in sira) _row(c, t, '${fmtPts(typePts(t))} puan')],
            note: 'Puan bahsin zorluğuna göre verilir. Tutmayan kupon puan getirmez.'),
        _card(c, 'Kupon tam tutmasa da puan', [
          for (var n = 1; n <= 5; n++) _row(c, '$n ayak tuttu', '$n puan'),
          _row(c, '6 ayak tuttu (kupon tam tuttu)', '${fmtPts(typePts("6'lı Ganyan"))} puan'),
        ], note: "Sadece 6'lı Ganyan'da kısmi puan vardır: tutan her ayak 1 puan getirir."),
        _card(c, 'Kupon silme', [
          _row(c, 'Paylaşılan kupon', 'Kilitli'),
          _row(c, 'Tutmayan kupon', 'Gece 00:00 silinir'),
        ], note: 'Kupon paylaşıldıktan sonra silinemez. Sadece kuponsuz paylaşımlarını silebilirsin.'),
        _card(c, 'Tahmin limiti', [
          _row(c, 'Tek koşuluk bahisler', 'Koşu başına 2'),
          _row(c, 'Çok ayaklı bahisler', 'Şehir başına 2'),
          _row(c, 'Günlük puan tavanı', '${gunlukTavan.toInt()} puan'),
        ], note: 'Aynı koşuya aynı bahisten en fazla 2 kupon yapabilirsin. Bir günde en fazla ${gunlukTavan.toInt()} puan toplarsın.'),
      ]),
    );
  }
}

/* ---------------- Yönetim paneli ---------------- */

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _db = FirebaseFirestore.instance;
  String _q = '';

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _grant(String uid, String name) async {
    final ctl = TextEditingController();
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$name · puan ver/al'),
        content: TextField(controller: ctl, keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true), decoration: const InputDecoration(hintText: 'Örn: 5 veya -2')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          TextButton(onPressed: () => Navigator.pop(ctx, double.tryParse(ctl.text.replaceAll(',', '.'))), child: const Text('Uygula')),
        ],
      ),
    );
    if (v == null || v == 0) return;
    try {
      await _db.collection('grants').doc(uid).set({'pts': FieldValue.increment(v)}, SetOptions(merge: true));
      _toast('Uygulandı: ${v > 0 ? '+' : ''}$v puan');
    } catch (e) {
      _toast(AuthService.errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return _scaffold(
      context,
      'Yönetim paneli',
      ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.collection('config').doc('chat').snapshots(),
          builder: (context, s) {
            final locked = s.data?.data()?['locked'] == true;
            return _card(c, 'Sohbet', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Sohbeti kilitle', style: jakarta(14.5, FontWeight.w700, c.tx)),
                value: locked,
                onChanged: (v) => _db.collection('config').doc('chat').set({'locked': v, 'at': DateTime.now().millisecondsSinceEpoch, 'by': profileNotifier.value?.uid ?? ''}).catchError((e) => _toast(AuthService.errorText(e))),
              ),
            ]);
          },
        ),
        TextField(
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Kullanıcı ara', filled: true, fillColor: c.sf, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _db.collection('users').limit(300).snapshots(),
          builder: (context, s) {
            if (!s.hasData) return Padding(padding: const EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: c.ac)));
            final l = s.data!.docs.where((d) => _q.isEmpty || '${d.data()['name']}'.toLowerCase().contains(_q) || '${d.data()['handle']}'.toLowerCase().contains(_q)).toList();
            return Column(children: [
              for (final d in l)
                ListTile(
                  leading: Avatar(profile: Profile.fromMap(d.id, d.data()), size: 40),
                  title: Text('${d.data()['name']}', style: jakarta(15, FontWeight.w800, c.tx)),
                  subtitle: Text('@${d.data()['handle']}${d.data()['isAdmin'] == true ? ' · yönetici' : ''}', style: jakarta(12.5, FontWeight.w600, c.mu)),
                  trailing: TextButton(onPressed: () => _grant(d.id, '${d.data()['name']}'), child: Text('Puan', style: jakarta(13, FontWeight.w800, c.ac))),
                ),
            ]);
          },
        ),
      ]),
    );
  }
}
