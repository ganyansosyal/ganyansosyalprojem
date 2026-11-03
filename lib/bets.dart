import 'tjk.dart';

class BetType {
  final String k, name, mode, rule, sub, desc, hint;
  final int n, slots, tabs, exact;
  final bool one, vir, per;
  final int? si;
  const BetType(this.k, this.name, this.mode, this.rule,
      {this.n = 0, this.slots = 0, this.tabs = 0, this.exact = 0, this.one = false, this.vir = false, this.per = false, this.si, this.sub = '', this.desc = '', this.hint = ''});
}

const kTypes = <BetType>[
  BetType('p7', "7'li Plase", 'legs', 'place', n: 7, sub: '7 ayak', desc: "7 ayakta plase'ye girecek atları bul"),
  BetType('g7', "7'li Ganyan", 'legs', 'win', n: 7, sub: '7 ayak'),
  BetType('g6', "6'lı Ganyan", 'legs', 'win', n: 6, sub: '6 ayak', si: 0),
  BetType('g6b', "6'lı Ganyan", 'legs', 'win', n: 6, sub: '6 ayak', si: 1),
  BetType('g5', "5'li Ganyan", 'legs', 'win', n: 5, sub: '5 ayak', si: 0),
  BetType('g5b', "5'li Ganyan", 'legs', 'win', n: 5, sub: '5 ayak', si: 1),
  BetType('g4', "4'lü Ganyan", 'legs', 'win', n: 4, sub: '4 ayak', si: 0),
  BetType('g4b', "4'lü Ganyan", 'legs', 'win', n: 4, sub: '4 ayak', si: 1),
  BetType('g3', "3'lü Ganyan", 'legs', 'win', n: 3, sub: '3 ayak', si: 0),
  BetType('g3b', "3'lü Ganyan", 'legs', 'win', n: 3, sub: '3 ayak', si: 1),
  BetType('g1', 'Ganyan', 'race', 'win', sub: '1. gelen', desc: 'Tek koşuda kazananı bul'),
  BetType('pl', 'Plase', 'race', 'place', sub: 'plase', desc: "Seçtiğin at plase'ye girer mi?", hint: 'Bir veya daha fazla at seç. Plase: birinci veya ikinci gelen at tutar (en az 7 atlı koşu).'),
  BetType('gp', 'Ganyan & Plase', 'race', 'gp', sub: '1. + plase', desc: 'Hem ganyan hem plase oyna', hint: 'Seçtiğin her at hem ganyan hem plase oynar.'),
  BetType('si', 'Sıralı İkili', 'race', 'slots', slots: 2, sub: 'sıralı ilk 2', desc: 'İlk iki atı sırasıyla bul', hint: 'Üstteki sekmeden sırayı seç (1. At / 2. At), her sıra için at işaretle.'),
  BetType('siv', 'Sıralı İkili (Virgüllü)', 'race', 'slots', slots: 2, one: true, vir: true, sub: 'sıralı ilk 2', desc: 'En az 2 at seç, sıran önemli (virgüllü)', hint: 'Atlara sırayla dokun (en az 2). Dokunma sırası = sıralaman.'),
  BetType('ik', 'İkili Bahis', 'race', 'any2', tabs: 2, sub: 'ilk 2', desc: 'İlk iki atı sırasız bul', hint: '1. At ve 2. At sekmelerinden birer veya daha fazla at seç.'),
  BetType('ik1', 'İkili Bahis (Tek kolon)', 'race', 'any2', sub: 'tek kolon', desc: 'İlk iki at, tek kolon', hint: 'En az 2 at seç. Olası tüm ikili çiftler oynanır.'),
  BetType('c2', 'Çifte Bahis', 'legs', 'win', n: 2, sub: '2 ayak'),
  BetType('pi', 'Plase İkili', 'race', 'pl2', tabs: 2, sub: 'plase 2 at', desc: "Plase'ye girecek iki atı bul", hint: '1. At ve 2. At sekmelerinden at seç.'),
  BetType('pi1', 'Plase İkili (Tek kolon)', 'race', 'pl2', exact: 2, sub: 'tek kolon', desc: 'Plase ikili, tek kolon', hint: 'Tam 2 at seç.'),
  BetType('su', 'Sıralı Üçlü', 'race', 'slots', slots: 3, sub: 'sıralı ilk 3', desc: 'İlk üç atı sırasıyla bul', hint: 'Üstteki sekmeden sırayı seç (1. / 2. / 3. At).'),
  BetType('suv', 'Sıralı Üçlü (Virgüllü)', 'race', 'slots', slots: 3, one: true, vir: true, sub: 'sıralı ilk 3', desc: 'En az 3 at seç, sıran önemli (virgüllü)', hint: 'Atlara sırayla dokun (en az 3).'),
  BetType('tb', 'Tabela Bahis', 'race', 'any4', tabs: 4, sub: 'ilk 4', desc: 'İlk dört atı sırasız bul', hint: 'Her sekmeye bir veya daha fazla at seç (1.–4. At).'),
  BetType('tbv', 'Tabela (Virgüllü)', 'race', 'any4', sub: 'ilk 4', desc: 'İlk dört atı sırasız bul, çoklu seçim', hint: 'İlk dörde girebilecek atları seç (en az 4).'),
  BetType('s5', 'Sıralı Beşli', 'race', 'slots', slots: 5, sub: 'sıralı ilk 5', desc: 'İlk beş atı sırasıyla bul', hint: 'Üstteki sekmeden sırayı seç (1.–5. At).'),
  BetType('s5v', 'Sıralı Beşli (Virgüllü)', 'race', 'slots', slots: 5, one: true, vir: true, sub: 'sıralı ilk 5', desc: 'En az 5 at seç, sıran önemli (virgüllü)', hint: 'Atlara sırayla dokun (en az 5).'),
];

const _legMap = <String, (String, int)>{
  'p7': ('PLASE', 7), 'g7': ('GANYAN', 7), 'g6': ('GANYAN', 6), 'g6b': ('GANYAN', 6), 'g5': ('GANYAN', 5), 'g5b': ('GANYAN', 5),
  'g4': ('GANYAN', 4), 'g4b': ('GANYAN', 4), 'g3': ('GANYAN', 3), 'g3b': ('GANYAN', 3), 'c2': ('CIFTE', 2),
};

const oyunKey = <String, String>{'g1': 'g1', 'pl': 'pl', 'gp': 'gp', 'si': 'si', 'siv': 'si', 'ik': 'ik', 'ik1': 'ik', 'pi': 'pi', 'pi1': 'pi', 'su': 'su', 'suv': 'su', 'tb': 'tb', 'tbv': 'tb', 's5': 's5', 's5v': 's5'};
const oyunMin = <String, int>{'pl': 7, 'gp': 7, 'ik': 7, 'si': 4, 'pi': 10, 'su': 7, 'tb': 7, 's5': 12};

const asgari = 20.0;
const altiliMax = 1500.0;
const tahminLimit = 2;

bool limitliMi(String t) => t == "6'lı Ganyan" || t == "7'li Ganyan";

String tLabelBase(BetType t) => t.name;

List<int> legStarts(BetType t, String city) {
  final mp = _legMap[t.k];
  if (mp == null) return [];
  return TjkStore.i.races(city).where((k) => k.baslar.any((x) => x.tur == mp.$1 && x.n == mp.$2)).map((k) => k.no).toList();
}

/// Henüz başlamamış ayak grupları (admin / geçmiş gün: hepsi).
List<int> openLegStarts(BetType t, String city, {bool admin = false}) {
  final s = TjkStore.i;
  final all = legStarts(t, city);
  if (admin || s.isPast) return all;
  return all.where((r) => !s.raceDone(city, r)).toList();
}

bool _legBilgiVar(String city) => TjkStore.i.races(city).any((k) => k.baslar.isNotEmpty);

/// Ayak grubunun başlangıç koşusu (null = bu şehirde oynanamaz).
int? legStart(BetType t, String city, {int? picked, bool admin = false}) {
  final s = TjkStore.i;
  final n = s.races(city).length;
  bool open(int r) => admin || s.isPast || !s.raceDone(city, r);
  if (_legBilgiVar(city)) {
    final st0 = legStarts(t, city);
    if (picked != null && st0.contains(picked)) return picked; // başlamış grup da görüntülenebilir; oynama typeMusait'te kapanır
  }
  if (t.si != null) {
    if (_legBilgiVar(city)) {
      final st = legStarts(t, city);
      return t.si! < st.length ? st[t.si!] : null;
    }
    return t.si == 1 ? null : (n >= t.n ? n - t.n + 1 : null);
  }
  if (_legBilgiVar(city)) {
    final st = legStarts(t, city);
    if (st.isEmpty) return null;
    return st.firstWhere(open, orElse: () => st.last);
  }
  return n >= t.n ? n - t.n + 1 : null;
}

List<int> allRaces(String city) => TjkStore.i.races(city).map((k) => k.no).toList();

bool oyunMusait(BetType t, String city, int r) {
  final key = oyunKey[t.k];
  if (key == null || key == 'g1') return true;
  final k = TjkStore.i.race(city, r);
  if (k == null) return false;
  if (k.oyun != null && k.oyun!.isNotEmpty) return k.oyun!.contains(key);
  return k.atlar.where((a) => !a.kosmaz).length >= (oyunMin[key] ?? 0);
}

class Musait {
  final bool ok;
  final String why;
  const Musait(this.ok, [this.why = '']);
}

Musait typeMusait(BetType t, String city, {bool admin = false, int? picked}) {
  final s = TjkStore.i;
  final n = s.races(city).length;
  if (n == 0) return const Musait(true);
  bool open(int r) => admin || s.isPast || !s.raceDone(city, r);
  if (t.mode == 'race') {
    final key = oyunKey[t.k];
    if (key == null || key == 'g1') return const Musait(true);
    final kos = allRaces(city).where((r) => oyunMusait(t, city, r) && open(r));
    if (kos.isNotEmpty) return const Musait(true);
    return Musait(false, allRaces(city).any((r) => oyunMusait(t, city, r)) ? 'koşular bitti' : '$city programında yok');
  }
  final ilk = legStart(t, city, picked: picked, admin: admin);
  if (ilk == null) return Musait(false, _legBilgiVar(city) ? '$city programında yok' : "$city'da $n koşu var");
  if (ilk + t.n - 1 > n) return Musait(false, '$city programında yok');
  if (!admin && !s.isPast && s.raceDone(city, ilk)) return Musait(false, '$ilk. koşu başladı');
  return const Musait(true);
}

List<int> legRaces(BetType t, String city, {int? picked, bool admin = false}) {
  final n = TjkStore.i.races(city).length;
  final nos = allRaces(city);
  if (t.mode != 'legs') return nos;
  final ilk = legStart(t, city, picked: picked, admin: admin);
  if (ilk == null) {
    final m = n < t.n ? n : t.n;
    return List.generate(m, (i) => nos.isEmpty ? i + 1 : nos[n - m + i]);
  }
  final len = (n - ilk + 1) < t.n ? (n - ilk + 1) : t.n;
  return List.generate(len, (i) => ilk + i);
}

/* ---------------- Fiyat / kolon ---------------- */

double birimFiyat(String tur, String sehir) {
  if (tur.startsWith("6'lı Ganyan")) return RegExp(r'diyarbak|elaz|[sş]anl[ıi]urfa', caseSensitive: false).hasMatch(sehir) ? 1 : 1.25;
  if (tur.startsWith("5'li Ganyan")) return 1.5;
  if (tur.startsWith("4'lü Ganyan")) return 1.75;
  if (tur.startsWith("3'lü Ganyan")) return 2;
  if (RegExp(r"^7'li (Plase|Ganyan)").hasMatch(tur)) return 2;
  if (tur.startsWith('Plase İkili')) return 2;
  if (tur.startsWith('Ganyan & Plase')) return 2;
  if (tur.startsWith('Sıralı Üçlü')) return 2;
  if (tur.startsWith('Tabela')) return 1.5;
  if (tur.startsWith('Sıralı Beşli')) return 1.25;
  return 1;
}

String money(double n) {
  final p = n.toStringAsFixed(2).split('.');
  final ip = p[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => '.');
  return '$ip,${p[1]} ₺';
}

int _comb(int n, int k) {
  if (k < 0 || k > n) return 0;
  double r = 1;
  for (var i = 1; i <= k; i++) {
    r = r * (n - k + i) / i;
  }
  return r.round();
}

List<List<int>> _picksOf(Map c) =>
    ((c['legs'] as List?) ?? const []).whereType<Map>().map((l) => ((l['picks'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList()).toList();

int kolon(Map c) {
  final ps = _picksOf(c);
  if (ps.isEmpty) return 0;
  final rule = (c['rule'] ?? 'win').toString();
  final vir = c['vir'];
  if (vir is num && vir > 0) return ps.length >= vir ? _comb(ps.length, vir.toInt()) : 0;
  if (rule == 'slots') {
    var cnt = 0;
    void rec(int i, List<int> used) {
      if (i == ps.length) {
        cnt++;
        return;
      }
      for (final n in ps[i]) {
        if (!used.contains(n)) rec(i + 1, [...used, n]);
      }
    }

    rec(0, []);
    return cnt;
  }
  final legs = ((c['legs'] as List?) ?? const []).whereType<Map>().toList();
  if ((rule == 'any2' || rule == 'pl2') && legs[0]['sets'] != null) {
    final sets = ((legs[0]['sets'] as List?) ?? const []).whereType<Map>().toList();
    final a = sets.isNotEmpty ? ((sets[0]['p'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList() : <int>[];
    final b = sets.length > 1 ? ((sets[1]['p'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList() : <int>[];
    final seen = <String>{};
    for (final x in a) {
      for (final y in b) {
        if (x != y) seen.add('${x < y ? x : y}-${x < y ? y : x}');
      }
    }
    return seen.length;
  }
  if (rule == 'any2' || rule == 'pl2') {
    final m = ps[0].length;
    return m * (m - 1) ~/ 2;
  }
  if (rule == 'any4' && legs.isNotEmpty && legs[0]['sets'] != null) {
    // Sekmeli Tabela: her sekmeden bir at seçilen, birbirinden farklı dörtlü kombinasyonlar (sırasız, aynı set bir kez sayılır)
    final lists = ((legs[0]['sets'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => ((m['p'] as List?) ?? const []).whereType<num>().map((e) => e.toInt()).toList())
        .toList();
    if (lists.length < 4 || lists.any((l) => l.isEmpty)) return 0;
    final seen = <String>{};
    void rec(int i, List<int> cur) {
      if (i == lists.length) {
        seen.add(([...cur]..sort()).join('-'));
        return;
      }
      for (final n in lists[i]) {
        if (!cur.contains(n)) rec(i + 1, [...cur, n]);
      }
    }

    rec(0, []);
    return seen.length;
  }
  if (rule == 'any4') {
    final m = ps[0].length;
    return m < 4 ? 0 : m * (m - 1) * (m - 2) * (m - 3) ~/ 24;
  }
  if (rule == 'gp') return ps[0].length;
  return ps.fold<int>(1, (a, p) => a * p.length);
}

double couponCost(Map c) => kolon(c) * birimFiyat((c['type'] ?? '').toString(), (c['city'] ?? '').toString()) * ((c['misli'] as num?)?.toInt() ?? 1);

/* ---------------- TJK'daki gibi "bu koşudan başlar" satırı + oyun kuralları ---------------- */

const _baslarAd = <String, Map<int, String>>{
  'PLASE': {7: "7'Lİ PLASE"},
  'GANYAN': {3: "3'LÜ GANYAN", 4: "4'LÜ GANYAN", 5: "5'Lİ GANYAN", 6: "6'LI GANYAN", 7: "7'Lİ GANYAN"},
  'CIFTE': {2: 'ÇİFTE'},
};
const _oyunAd = <String, String>{
  'g1': 'GANYAN', 'ik': 'İKİLİ', 'si': 'SIRALI İKİLİ', 'pi': 'PLASE İKİLİ',
  'su': 'ÜÇLÜ BAHİS', 'tb': 'TABELA', 's5': "SIRALI 5'Lİ", 'pl': 'PLASE',
};

/// Örn: "1. ÇİFTE, 7'Lİ PLASE, 7'Lİ GANYAN, 1. 3'LÜ GANYAN bu koşudan başlar, GANYAN, İKİLİ, ..."
String baslarYazi(String city, int no) {
  final ki = TjkStore.i.race(city, no);
  if (ki == null) return '';
  final bas = [...ki.baslar]..sort((a, b) => (b.tur == 'CIFTE' ? 1 : 0) - (a.tur == 'CIFTE' ? 1 : 0)); // önce Çifte
  final all = TjkStore.i.races(city);
  final out = <String>[];
  for (final x in bas) {
    final ad = _baslarAd[x.tur]?[x.n];
    if (ad == null) continue;
    final st = all.where((k) => k.baslar.any((y) => y.tur == x.tur && y.n == x.n)).map((k) => k.no).toList();
    out.add('${st.length > 1 ? '${st.indexOf(no) + 1}. ' : ''}$ad');
  }
  final oy = ki.oyun == null ? <String>[] : _oyunAd.keys.where((k) => ki.oyun!.contains(k)).map((k) => _oyunAd[k]!).toList();
  if (out.isEmpty && oy.isEmpty) return '';
  return (out.isNotEmpty ? '${out.join(', ')} bu koşudan başlar' : '') + (oy.isNotEmpty ? '${out.isNotEmpty ? ', ' : ''}${oy.join(', ')}' : '');
}

String kuralMetni(BetType t, String city) {
  final ek = <String>[];
  String m;
  if (t.mode == 'legs') {
    m = t.rule == 'place'
        ? "Ardışık ${t.n} ayakta, her koşuda plase'ye girecek bir at seç. Hepsi tutarsa kazanırsın."
        : 'Ardışık ${t.n} ayakta, her koşunun kazananını bul. Hepsi tutarsa kazanırsın. Bir ayakta birden fazla at seçebilirsin.';
  } else if (t.rule == 'win') {
    m = 'Seçtiğin at birinci gelirse kazanırsın.';
  } else if (t.rule == 'place') {
    m = "Seçtiğin at plase'ye girerse kazanırsın (en az 7 atlı koşuda birinci veya ikinci gelmesi yeter).";
  } else if (t.rule == 'gp') {
    m = "Seçtiğin at hem ganyan hem plase oynar. Birinci gelirse ikisi de, sadece plase'ye girerse plase tutar.";
  } else if (t.rule == 'any2') {
    m = 'İlk iki atı sırasız bil. Hangisinin birinci, hangisinin ikinci geldiği önemli değil.';
  } else if (t.rule == 'pl2') {
    m = "Plase'ye giren iki atı sırasız bil.";
  } else if (t.rule == 'any4') {
    m = 'İlk dört atı bil (tabela). Sırasıyla bilirsen sıralı ikramiye, sırasız bilirsen sırasız ikramiye kazanırsın.';
  } else if (t.rule == 'slots' && t.vir) {
    m = 'En az ${t.slots} at seç, dokunma sırası listendeki sıra olur. İlk ${t.slots} at listende, aynı sırayla yer alırsa kazanırsın. '
        "Bahis sayısı: seçtiğin atlardan ${t.slots}'li sıralı kombinasyon sayısı (12 at seçersen ${_comb(12, t.slots)}).";
  } else if (t.rule == 'slots') {
    m = 'İlk ${t.slots} atı geliş sırasıyla bil.';
  } else {
    m = t.desc;
  }
  if (t.name.contains('Virgüllü') && !t.vir) ek.add('Her sıra için birden fazla at seçebilirsin; kolon sayısı arttıkça tutar artar.');
  if (t.name.contains('Tek kolon')) ek.add(t.exact > 0 ? 'Tek kolondur: tam olarak ${t.exact} at seçilir.' : 'Tek kolondur: en az 2 at seç, seçtiğin atlardan olası tüm ikili çiftler oynanır.');
  final kos = tekKosular(t, city);
  if (kos != null && kos.isNotEmpty) ek.add('TJK programına göre ${fmtKos(kos)} oynanır.');
  return '$m${ek.isNotEmpty ? ' ${ek.join(' ')}' : ''} Birim fiyat ${money(birimFiyat(t.name, city))} · asgari kupon ${money(asgari)}.';
}

/* ---------------- Tek koşuluk bahis: hangi koşularda oynanır? (TJK oyun listesi) ---------------- */

String fmtKos(List<int> a) => a.length <= 5 ? '${a.join('., ')}. koşu' : '${a.length} koşuda';

/// Bu bahsin oynandığı (ve henüz başlamamış) koşular. Ganyan ve çok ayaklılar için null.
List<int>? tekKosular(BetType t, String city, {bool admin = false}) {
  final key = oyunKey[t.k];
  if (t.mode != 'race' || key == null || key == 'g1') return null;
  final s = TjkStore.i;
  return allRaces(city).where((r) => oyunMusait(t, city, r) && (admin || s.isPast || !s.raceDone(city, r))).toList();
}

/// "oynanan: 5., 7. koşu" — bahis günün tüm kalan koşularında oynanıyorsa null.
String? tekSub(BetType t, String city, {bool admin = false}) {
  final kos = tekKosular(t, city, admin: admin);
  if (kos == null || kos.isEmpty) return null;
  final s = TjkStore.i;
  final kalan = allRaces(city).where((r) => admin || s.isPast || !s.raceDone(city, r)).length;
  return kos.length == kalan ? null : 'oynanan: ${fmtKos(kos)}';
}
