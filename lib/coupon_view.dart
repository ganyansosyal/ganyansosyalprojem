import 'package:flutter/material.dart';

import 'bets.dart' show kolon, birimFiyat, money;
import 'ikramiye.dart';
import 'scoring.dart';
import 'theme.dart';
import 'tjk.dart' show TjkStore;

const _ay = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];

String _stamp(int ts) {
  if (ts <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.day} ${_ay[d.month - 1]} · ${two(d.hour)}:${two(d.minute)}';
}

List<Map> _maps(dynamic v) => ((v as List?) ?? const []).whereType<Map>().toList();

/// Web'deki kupon kartının aynısı: oyun türüne göre sütunlar, geliş sırası, tuttu/yattı işaretleri,
/// kolon × tutar × misli satırı ve ikramiye çubuğu.
class CouponView extends StatelessWidget {
  final Map<String, dynamic> cp;
  final int ts;
  final AppColors? colors;
  const CouponView(this.cp, {super.key, this.ts = 0, this.colors});

  Widget _chip(AppColors c, int n, String st, double s) {
    Color bg, fg, bd;
    switch (st) {
      case 'win':
        bg = c.ac;
        fg = c.on;
        bd = c.ac;
        break;
      case 'pl':
        bg = Color.alphaBlend(c.ac.withAlpha(51), c.sf);
        fg = c.ac;
        bd = c.ac.withAlpha(115);
        break;
      case 'dim':
        bg = c.sf;
        fg = c.mu;
        bd = c.ln;
        break;
      case 'miss':
        bg = Color.alphaBlend(c.red.withAlpha(36), c.sf);
        fg = c.red;
        bd = c.red.withAlpha(90);
        break;
      default:
        bg = c.sf;
        fg = c.tx;
        bd = c.ln;
    }
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9), border: Border.all(color: bd, width: 1.2)),
      child: Text('$n', style: jakarta(s * 0.46, FontWeight.w800, fg)),
    );
  }

  Widget _mark(AppColors c, String st) {
    if (st == 'p') return const SizedBox(height: 26);
    final ok = st == 'h';
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: ok ? c.ac : c.red, shape: BoxShape.circle),
      child: Icon(ok ? Icons.check_rounded : Icons.close_rounded, size: 17, color: ok ? c.on : Colors.white),
    );
  }

  Widget _label(AppColors c, String top, String sub, String st) {
    Color bg, fg;
    if (st == 'h') {
      bg = c.ac;
      fg = c.on;
    } else if (st == 'm') {
      bg = Color.alphaBlend(c.red.withAlpha(209), c.sf);
      fg = Colors.white;
    } else {
      bg = c.ln;
      fg = c.tx;
    }
    return Container(
      width: 74,
      color: bg,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        FittedBox(fit: BoxFit.scaleDown, child: Text(top, maxLines: 1, style: jakarta(12, FontWeight.w800, fg))),
        if (sub.isNotEmpty) FittedBox(fit: BoxFit.scaleDown, child: Text(sub, maxLines: 1, style: jakarta(10, FontWeight.w600, fg.withAlpha(220)))),
      ]),
    );
  }

  /// Yatay satır: solda koşu/at etiketi, yanında numaralar yan yana (sığmazsa alta kıvrılır), sağda tuttu/yattı işareti.
  Widget _row(AppColors c, String top, String sub, String st, List<int> picks, String Function(int) chipSt, double chipS, {Widget? extra, bool showMark = false}) {
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.ln))),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _label(c, top, sub, st),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                picks.isEmpty
                    ? Text('—', style: jakarta(13, FontWeight.w700, c.mu))
                    : Wrap(spacing: 5, runSpacing: 5, children: [for (final n in picks) _chip(c, n, chipSt(n), chipS)]),
                if (extra != null) extra,
              ]),
            ),
          ),
          if (showMark) Padding(padding: const EdgeInsets.only(right: 8), child: Center(child: _mark(c, st))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = colors ?? AppColors.of(context);
    final legs = _maps(cp['legs']);
    final cols = legs.length;
    final slotted = legs.any((l) => l['slot'] != null);
    final virN = (cp['vir'] is num && (cp['vir'] as num) > 0) ? (cp['vir'] as num).toInt() : 0;
    final ord = (cp['ord'] ?? '').toString();
    final head = '${cp['city'] ?? ''} · ${ord.isNotEmpty && ord != '0' ? '$ord. ' : ''}${cp['type'] ?? ''}';
    final st = couponStatus(cp).k;
    final stCol = st == 'win' ? const Color(0xFF16A34A) : st == 'lose' ? c.red : c.mu;
    final stTxt = st == 'win' ? 'Tuttu' : st == 'lose' ? 'Yattı' : st == 'live' ? 'Sürüyor' : 'Bekliyor';
    final k = kolon(cp);
    final misli = ((cp['misli'] as num?) ?? 1).toInt();
    final bf = birimFiyat((cp['type'] ?? '').toString(), (cp['city'] ?? '').toString());
    final dense = cols >= 5;
    final sts = [for (final l in legs) legSt(cp, l)];
    final settled = sts.any((x) => x != 'p');
    final res0 = legs.isNotEmpty ? legResOf(cp, legs.first) : null;
    final rule = ruleOf(cp);
    final showOrder = res0 != null && res0.isNotEmpty && (slotted || rule == 'any4');
    final orderN = slotted ? (virN > 0 ? virN : legs.length) : 4;
    final ik = ikramiyeOf(cp);

    Widget body = const SizedBox.shrink();
    if (virN > 0) {
      final top = res0 == null ? const <int>[] : res0.take(virN).toList();
      body = Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var i = 0; i < legs.length; i++) ...[
            Builder(builder: (_) {
              final pk = ((legs[i]['picks'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList();
              final n = pk.isNotEmpty ? pk.first : 0;
              return _chip(c, n, res0 == null ? 'p' : (top.contains(n) ? 'win' : 'dim'), 28);
            }),
            if (i < legs.length - 1) Text('›', style: jakarta(14, FontWeight.w700, c.mu)),
          ],
        ]),
      );
    } else if (cols == 1 && _maps(legs[0]['sets']).length >= 2) {
      // İkili / Plase İkili / Tabela: her "n. AT" ayrı satır, numaralar yan yana
      final l = legs[0];
      final sets0 = _maps(l['sets']);
      final lists = [for (final m in sets0) ((m['p'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList()];
      final top = legTop(cp, l);
      final pend = sts[0] == 'p';
      final hit = sts[0] == 'h';
      String chipSt(int n) {
        if (pend) return 'p';
        if (top.contains(n)) return (rule == 'gp' && res0 != null && res0.isNotEmpty && res0.first != n) ? 'pl' : 'win';
        return hit ? 'dim' : 'miss';
      }

      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < lists.length; i++)
          _row(c, '${i + 1}. AT', i == 0 ? '${l['r'] ?? ''}. Koşu' : '', sts[0], lists[i], chipSt, 28, showMark: !pend && i == 0),
      ]);
    } else if (cols > 0) {
      // Her koşu bir satır: "2. Koşu  [1] [3] [4] ..." — çok at olsa da kart uzamaz
      final chipS = dense ? 26.0 : 28.0;
      final showReal = virN == 0 && !slotted && settled && cols > 1;
      final realN = rule == 'win' ? 1 : rule == 'any2' ? 2 : rule == 'any4' ? 4 : rule == 'pl2' ? 3 : 2;
      final sameDay = (cp['iso'] ?? '').toString() == TjkStore.i.iso;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < cols; i++)
          Builder(builder: (_) {
            final l = legs[i];
            final picks = ((l['picks'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList();
            final top = legTop(cp, l);
            final res = legResOf(cp, l);
            final pend = sts[i] == 'p';
            String chipSt(int n) {
              if (pend) return 'p';
              if (top.contains(n)) return (rule == 'gp' && res != null && res.isNotEmpty && res.first != n) ? 'pl' : 'win';
              return sts[i] == 'h' ? 'dim' : 'miss';
            }

            Widget? extra;
            if (showReal && res != null && res.isNotEmpty) {
              final rn = (l['r'] as num?)?.toInt() ?? 0;
              String? g;
              if (rule == 'win' && sameDay) {
                final byRace = TjkStore.i.results[(cp['city'] ?? '').toString()];
                final rr = byRace == null ? null : byRace[rn];
                if (rr != null) g = rr.gny[res.first];
              }
              extra = Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Sıralama: ${res.take(realN).join(' · ')}${g != null && g.isNotEmpty ? '  ($g)' : ''}', style: jakarta(11, FontWeight.w700, c.mu)),
              );
            }
            final top1 = slotted ? '${((l['slot'] as num?) ?? 0).toInt() + 1}. At' : '${l['r'] ?? ''}. Koşu';
            final sub1 = slotted ? '${l['r'] ?? ''}. Koşu' : '${l['t'] ?? ''}';
            return _row(c, top1, sub1, sts[i], picks, chipSt, chipS, extra: extra, showMark: settled);
          }),
      ]);
    }

    const real = SizedBox.shrink(); // sıralama artık her koşu satırının içinde

    final order = showOrder
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: c.sf, border: Border(top: BorderSide(color: c.ln))),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: 'Geliş sırası: ', style: jakarta(12, FontWeight.w700, c.mu)),
              TextSpan(text: res0!.take(orderN).join(' · '), style: jakarta(12.5, FontWeight.w800, c.tx)),
            ])),
          )
        : const SizedBox.shrink();

    const misliCol = Color(0xFF4F46E5);
    final money1 = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(color: c.sf, border: Border(top: BorderSide(color: c.ln))),
      child: Row(children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '$k kolon', style: jakarta(12, FontWeight.w800, c.ac)),
              TextSpan(text: '  ×  ', style: jakarta(11, FontWeight.w600, c.mu)),
              TextSpan(text: money(bf), style: jakarta(12, FontWeight.w800, c.tx)),
              TextSpan(text: '  ×  ', style: jakarta(11, FontWeight.w600, c.mu)),
              TextSpan(text: '$misli misli', style: jakarta(12, FontWeight.w800, misliCol)),
            ])),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: stCol.withAlpha(30), borderRadius: BorderRadius.circular(9)),
          child: Text(stTxt, style: jakarta(11, FontWeight.w800, stCol)),
        ),
        const SizedBox(width: 10),
        Text(money(k * bf * misli), style: jakarta(15, FontWeight.w800, c.tx)),
      ]),
    );

    Widget ikBarFor(Ikr ik) {
      final wait = !ik.ready;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [c.ac, Color.alphaBlend(Colors.white.withAlpha(60), c.ac)])),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('İKRAMİYE', style: jakarta(10.5, FontWeight.w800, c.on.withAlpha(205), ls: 1.4)),
              const SizedBox(height: 2),
              Text(ik.ad, style: jakarta(15, FontWeight.w800, c.on)),
              if (!wait && st == 'lose') Text('kupon tutmadı', style: jakarta(11, FontWeight.w600, c.on.withAlpha(205))),
            ]),
          ),
          const SizedBox(width: 10),
          if (wait)
            Text(ik.noPub ? 'TJK yayınlamadı' : 'Bekleniyor', style: jakarta(ik.noPub ? 13 : 17, FontWeight.w700, c.on))
          else
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              for (final i in ik.items)
                Text('${i.d.isEmpty ? '' : '${i.d} · '}₺${i.t}', style: jakarta(ik.items.length == 1 ? 18 : 13.5, FontWeight.w800, c.on)),
            ]),
        ]),
      );
    }

    Widget ikBar = const SizedBox.shrink();
    if (ik != null) {
      // Geçmiş günün kuponu: o günün sonuçları TJK'dan çekilip ikramiye gösterilir (bir kez, sonra hazır kalır)
      ikBar = (!ik.ready && ikramiyeFetchGerek(cp))
          ? FutureBuilder<Ikr?>(
              future: ikramiyeFetch(cp),
              initialData: null,
              builder: (_, snap) => ikBarFor(snap.data != null && snap.data!.ready ? snap.data! : ik),
            )
          : ikBarFor(ik);
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.sf2, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.ln)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
          child: Row(children: [
            // Sol taraf kalan tüm yeri alır: başlık gereksiz yere "..." ile kısalmaz
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.ac,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [BoxShadow(color: c.ac.withAlpha(50), blurRadius: 9, offset: const Offset(0, 3))],
                  ),
                  child: Text(head, maxLines: 1, overflow: TextOverflow.ellipsis, style: jakarta(12.5, FontWeight.w800, c.on)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (ts > 0) Text(_stamp(ts), style: jakarta(11, FontWeight.w700, c.mu)),
          ]),
        ),
        body,
        real,
        order,
        money1,
        ikBar,
      ]),
    );
  }
}
