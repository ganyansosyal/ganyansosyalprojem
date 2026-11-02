import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as hp;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Worker kaldırıldı: TJK'ya doğrudan istek atılır
const _tjkHeaders = {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36',
  'Accept-Language': 'tr-TR,tr;q=0.9',
};

String isoToday() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

String isoAdd(String iso, int days) {
  final p = iso.split('-').map(int.parse).toList();
  final d = DateTime(p[0], p[1], p[2] + days);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _tjkDate(String iso) {
  final p = iso.split('-');
  return '${p[2]}/${p[1]}/${p[0]}';
}

String _era(String iso) => iso.compareTo(isoToday()) < 0 ? 'yesterday' : 'today';

final Map<String, ({DateTime t, String body})> _htmlCache = {};
Directory? _cacheDir;

// Geçmiş tarihlerin verisi değişmez → 30 gün; bugünün verisi kısa süre
int _diskTtl(String iso, int normal) => iso.compareTo(isoToday()) < 0 ? 2592000 : normal;

String _hash(String s) {
  var h = 0xcbf29ce484222325;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * 0x100000001b3) & 0x7fffffffffffffff;
  }
  return h.toRadixString(16);
}

Future<File?> _diskFile(String url) async {
  try {
    var d = _cacheDir;
    if (d == null) {
      d = Directory('${(await getApplicationSupportDirectory()).path}/tjk');
      if (!await d.exists()) await d.create(recursive: true);
      _cacheDir = d;
    }
    return File('${d.path}/${_hash(url)}.html');
  } catch (_) {
    return null;
  }
}

/// ttl: bellek önbelleği (sn), disk: disk önbelleği (sn). 0 = kullanma.
Future<String> _fetch(String url, {int sec = 20, int retry = 2, int ttl = 0, int disk = 0, bool fresh = true}) async {
  if (ttl > 0) {
    final hit = _htmlCache[url];
    if (hit != null && DateTime.now().difference(hit.t).inSeconds < ttl) return hit.body;
  }
  File? f;
  if (disk > 0) {
    f = await _diskFile(url);
    try {
      if (f != null && await f.exists() && DateTime.now().difference(await f.lastModified()).inSeconds < disk) {
        final body = await f.readAsString();
        if (body.isNotEmpty) {
          if (ttl > 0) _htmlCache[url] = (t: DateTime.now(), body: body);
          return body;
        }
      }
    } catch (_) {}
  }
  String body;
  try {
    body = await _fetchRaw(url, sec: sec, retry: retry, fresh: fresh);
  } catch (e) {
    // İnternet yok/TJK yanıt vermiyor: eski de olsa diskteki kopyayı göster
    try {
      final ff = f ?? await _diskFile(url);
      if (ff != null && await ff.exists()) {
        final old = await ff.readAsString();
        if (old.isNotEmpty) return old;
      }
    } catch (_) {}
    rethrow;
  }
  if (ttl > 0) {
    if (_htmlCache.length > 120) _htmlCache.clear();
    _htmlCache[url] = (t: DateTime.now(), body: body);
  }
  if (f != null) {
    f.writeAsString(body).catchError((_) => f!);
  }
  return body;
}

Future<String> _fetchRaw(String url, {int sec = 20, int retry = 2, bool fresh = true}) async {
  Object? last;
  for (var i = 0; i <= retry; i++) {
    try {
      final r = await http.get(Uri.parse(url), headers: _tjkHeaders).timeout(Duration(seconds: sec));
      if (r.statusCode == 200) return utf8.decode(r.bodyBytes, allowMalformed: true);
      last = 'HTTP ${r.statusCode}';
      if (r.statusCode < 500) break;
    } catch (e) {
      last = e;
    }
    if (i < retry) await Future.delayed(Duration(milliseconds: 1000 + i * 1500));
  }
  throw Exception('TJK bağlantı hatası: $last');
}

/* ---------------- Modeller ---------------- */

class City {
  final String id, name;
  final bool yd;
  City(this.id, this.name, this.yd);
}

class Horse {
  final int no;
  final String name, jockey, yas, kgs;
  final bool kosmaz;
  final int? agf, hp;
  final double? gny, siklet;
  final List<String> son6;
  final List<String> son6p; // son6 ile aynı sırada pist harfi: Ç / K / S / ''
  final List<({String k, String a})> taki;
  final String st, s20, orijin, sahip, antrenor, eid;
  final String idmHref, idmK, idmA, atId;
  Horse({
    required this.no,
    required this.name,
    this.jockey = '',
    this.yas = '',
    this.kgs = '',
    this.kosmaz = false,
    this.agf,
    this.hp,
    this.gny,
    this.siklet,
    this.son6 = const [],
    this.son6p = const [],
    this.taki = const [],
    this.st = '',
    this.s20 = '',
    this.orijin = '',
    this.sahip = '',
    this.antrenor = '',
    this.eid = '',
    this.idmHref = '',
    this.idmK = '',
    this.idmA = '',
    this.atId = '',
  });
}

class Start {
  final int ord, n;
  final String tur; // GANYAN · PLASE · CIFTE
  Start(this.ord, this.n, this.tur);
}

class Race {
  final int no;
  final String saat;
  final String? mesafe, pist;
  final String bilgi;
  final List<Horse> atlar;
  final List<Start> baslar;
  final List<String>? oyun;
  Race({
    required this.no,
    required this.saat,
    this.mesafe,
    this.pist,
    this.bilgi = '',
    required this.atlar,
    this.baslar = const [],
    this.oyun,
  });
}

class Bahis {
  final String tur, detay, tutar;
  Bahis(this.tur, this.detay, this.tutar);
}

class RaceResult {
  final List<int> sira;
  final Map<int, String> gny;
  final List<Bahis> bahis;
  final String video;
  RaceResult(this.sira, this.gny, this.bahis, this.video);
}

/* ---------------- Yardımcılar ---------------- */

String _norm(String s) => s
    .toUpperCase()
    .replaceAll('İ', 'I')
    .replaceAll('Ğ', 'G')
    .replaceAll('Ü', 'U')
    .replaceAll('Ş', 'S')
    .replaceAll('Ö', 'O')
    .replaceAll('Ç', 'C');

String _trLower(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();
String _clean(String s) => s.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
String _key(String s) => _norm(s).replaceAll(RegExp(r'[^A-Z0-9]'), '');

final _headRe = RegExp(r'^(\d+)\.\s*Koşu\s+(\d{1,2})[:.](\d{2})');
final _pistRe = RegExp(r'(\d{1,2}[.]\d{3}|\d{3,4})\s*(?:m\b\s*)?(çim|kum|sentetik)');

List<Element> _all(Document d) => d.body?.querySelectorAll('*') ?? <Element>[];

bool _isHead(Element e, {int maxLen = 60}) {
  if (e.children.length > 2) return false;
  final t = e.text.trim();
  return t.length < maxLen && _headRe.hasMatch(t);
}

/* ---------------- Şehir listesi ---------------- */

Future<List<City>> getCities(String iso) async {
  final url =
      'https://www.tjk.org/TR/yarissever/Info/Page/GunlukYarisProgrami?QueryParameter_Tarih=${Uri.encodeComponent(_tjkDate(iso))}&Era=${_era(iso)}';
  final html = await _fetch(url, ttl: 300, disk: _diskTtl(iso, 600));
  final list = await compute(_citiesIso, html);
  if (list.isEmpty) throw Exception("TJK'da bu tarih için yayınlanmış bir koşu programı bulunamadı.");
  return list;
}

// Ayrı isolate'te çalışır (UI thread'i bloklamaz)
List<City> _citiesIso(String html) {
  final doc = hp.parse(html);
  final seen = <String>{};
  final list = <City>[];
  for (final a in doc.querySelectorAll('a[href]')) {
    final href = a.attributes['href'] ?? '';
    if (!RegExp('GunlukYarisProgrami', caseSensitive: false).hasMatch(href)) continue;
    final m = RegExp(r'[?&]SehirId=(\d+)', caseSensitive: false).firstMatch(href);
    if (m == null || !seen.add(m.group(1)!)) continue;
    var adi = '';
    final ma = RegExp(r'[?&]SehirAdi=([^&]+)', caseSensitive: false).firstMatch(href);
    if (ma != null) {
      try {
        adi = Uri.decodeComponent(ma.group(1)!.replaceAll('+', ' '));
      } catch (_) {
        adi = ma.group(1)!;
      }
    }
    adi = _clean(adi.isEmpty ? a.text : adi);
    final first = _key(adi.split(' ').first);
    const yerli = {'ISTANBUL', 'ANKARA', 'IZMIR', 'BURSA', 'ADANA', 'SANLIURFA', 'ELAZIG', 'DIYARBAKIR', 'KOCAELI', 'IZMIT', 'ANTALYA', 'KARMA'};
    final yd = RegExp(r'\(YD\s*\d+\)', caseSensitive: false).hasMatch(adi) ||
        RegExp(r'\bYD\s*\d+\b', caseSensitive: false).hasMatch(a.text) ||
        (first.isNotEmpty && !yerli.contains(first));
    if (adi.isNotEmpty) list.add(City(m.group(1)!, adi, yd));
  }
  if (list.isEmpty) return list;
  final yerli = list.where((c) => !c.yd).toList();
  return yerli.isNotEmpty ? yerli : list;
}

/* ---------------- Program ---------------- */

int? _col(List<String> heads, dynamic key) {
  final keys = key is List ? key.cast<String>() : [key as String];
  for (final k in keys) {
    final i = heads.indexWhere((h) => _clean(h).toLowerCase().contains(k.toLowerCase()));
    if (i >= 0) return i;
  }
  return null;
}

// Son 6 hücresindeki her karakter ve (varsa) renginden pist harfi
String _pistHarf(String c) {
  if (c == 'g') return 'Ç';
  if (c == 'k') return 'K';
  if (c == 's') return 'S';
  if (c.isEmpty) return '';
  final t = c.trim().toLowerCase();
  int? r, g, b;
  final hx = RegExp(r'^#([0-9a-f]{3}|[0-9a-f]{6})$').firstMatch(t);
  if (hx != null) {
    var h = hx.group(1)!;
    if (h.length == 3) h = h.split('').map((x) => x + x).join();
    r = int.parse(h.substring(0, 2), radix: 16);
    g = int.parse(h.substring(2, 4), radix: 16);
    b = int.parse(h.substring(4, 6), radix: 16);
  } else {
    final rg = RegExp(r'^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)').firstMatch(t);
    if (rg != null) {
      r = int.parse(rg.group(1)!);
      g = int.parse(rg.group(2)!);
      b = int.parse(rg.group(3)!);
    } else {
      if (RegExp(r'green|lime|olive').hasMatch(t)) return 'Ç';
      if (RegExp(r'brown|maroon|sienna|chocolate|peru|tan|orange|red').hasMatch(t)) return 'K';
      if (RegExp(r'blue|navy|teal|cyan').hasMatch(t)) return 'S';
      return '';
    }
  }
  final mx = [r, g, b].reduce((x, y) => x > y ? x : y);
  final mn = [r, g, b].reduce((x, y) => x < y ? x : y);
  final d = mx - mn;
  if (d < 25) return '';
  double hue = mx == r ? ((g - b) / d) % 6 : mx == g ? (b - r) / d + 2 : (r - g) / d + 4;
  hue = (hue * 60 + 360) % 360;
  if (hue >= 75 && hue < 170) return 'Ç';
  if (hue >= 170 && hue < 270) return 'S';
  return 'K';
}

List<({String s, String c})> _son6Ayir(Element? hucre) {
  final out = <({String s, String c})>[];
  if (hucre == null) return out;
  String renk(Element el) {
    final sc = (el.attributes['class'] ?? '').toLowerCase();
    if (RegExp('cim|çim|green|yesil').hasMatch(sc)) return 'g';
    if (RegExp('kum|sand|brown|kahve').hasMatch(sc)) return 'k';
    if (RegExp('sentetik|synth|blue').hasMatch(sc)) return 's';
    final st = RegExp(r'color\s*:\s*([^;]+)', caseSensitive: false).firstMatch(el.attributes['style'] ?? '');
    return (st?.group(1) ?? el.attributes['color'] ?? '').trim();
  }

  void walk(Node n, String c) {
    if (n is Text) {
      for (final m in RegExp(r'[0-9A-Za-z\-]').allMatches(n.data)) {
        out.add((s: m.group(0)!, c: c));
      }
    } else if (n is Element) {
      final rc = renk(n);
      for (final k in n.nodes) {
        walk(k, rc.isNotEmpty ? rc : c);
      }
    }
  }

  walk(hucre, '');
  return out.length > 6 ? out.sublist(out.length - 6) : out;
}

/// TJK'dan okunan takı açıklamaları (kod -> anlam). Çıkarılan takılarda da kullanılır.
final Map<String, String> takiAnlamCache = {};
Timer? _takiKaydetT;
bool _takiYuklendi = false;

/// Daha önce görülen takı açıklamalarını telefondan yükler (bir kez).
Future<void> takiAnlamYukle() async {
  if (_takiYuklendi) return;
  _takiYuklendi = true;
  try {
    final p = await SharedPreferences.getInstance();
    final j = p.getString('taki_anlam');
    if (j != null) {
      (jsonDecode(j) as Map).forEach((k, v) => takiAnlamCache.putIfAbsent('$k', () => '$v'));
    }
  } catch (_) {}
}

void _takiKaydet() {
  _takiKaydetT?.cancel();
  _takiKaydetT = Timer(const Duration(seconds: 2), () async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('taki_anlam', jsonEncode(takiAnlamCache));
    } catch (_) {}
  });
}

final _takiKod = RegExp(r'^[A-ZÇĞİÖŞÜ]{1,4}$');
const _takiBilinen = ['KGK', 'KDB', 'ÖDB', 'SKG', 'GKR', 'DB', 'KG', 'SK', 'ÖG', 'K'];

List<({String k, String a})> _takiCikar(Element? hucre, String isimHam, Element? atLinki) {
  final out = <({String k, String a})>[];
  void ekle(String k, String a) {
    k = k.replaceAll(RegExp(r'\s+'), '');
    if (!_takiKod.hasMatch(k)) return;
    a = a.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (a.isNotEmpty && takiAnlamCache[k] != a) {
      takiAnlamCache[k] = a;
      _takiKaydet();
    }
    final i = out.indexWhere((x) => x.k == k);
    if (i >= 0) {
      if (out[i].a.isEmpty && a.isNotEmpty) out[i] = (k: k, a: a);
      return;
    }
    out.add((k: k, a: a));
  }

  if (hucre != null) {
    final linkMetin = atLinki == null ? '' : _clean(atLinki.text);
    for (final el in hucre.querySelectorAll('[title],[data-original-title],[data-title],[data-content],[data-tooltip],[aria-label],[class*="taki"],[class*="ekipman"],[class*="tooltip"],sup,sub')) {
      if (identical(el, atLinki)) continue;
      var inLink = false;
      for (Element? p = el.parent; p != null; p = p.parent) {
        if (identical(p, atLinki)) {
          inLink = true;
          break;
        }
      }
      if (inLink) continue;
      var ta = '';
      for (final n in ['title', 'data-original-title', 'data-title', 'data-content', 'data-tooltip', 'aria-label']) {
        final v = (el.attributes[n] ?? '').trim();
        if (v.isNotEmpty) {
          ta = v;
          break;
        }
      }
      final t = _clean(el.text);
      if (t.isEmpty || t == linkMetin) continue;
      if (_takiKod.hasMatch(t)) {
        ekle(t, ta);
        continue;
      }
      final m = RegExp(r'^([A-ZÇĞİÖŞÜ]+)([A-ZÇĞİÖŞÜ][a-zçğıöşü][\s\S]*)$').firstMatch(t);
      if (m != null && _takiKod.hasMatch(m.group(1)!)) ekle(m.group(1)!, ta.isNotEmpty ? ta : m.group(2)!);
    }
  }
  // Hücrenin kendisi (veya düz metin kodları) anlamı taşıyorsa: geçmiş koşu tablosu böyle olabilir
  if (hucre != null && out.isEmpty) {
    var hta = '';
    for (final n in ['title', 'data-original-title', 'data-title', 'data-content', 'data-tooltip', 'aria-label']) {
      final v = (hucre.attributes[n] ?? '').trim();
      if (v.isNotEmpty) {
        hta = v;
        break;
      }
    }
    final kodlar = _clean(hucre.text).split(RegExp(r'[\s,;/]+')).where((w) => _takiKod.hasMatch(w)).toList();
    for (final w in kodlar) {
      ekle(w, kodlar.length == 1 ? hta : '');
    }
  }
  if (out.isEmpty && isimHam.isNotEmpty) {
    var t = isimHam.replaceAll('\u00a0', ' ');
    if (atLinki != null) t = t.replaceAll(atLinki.text.trim(), ' ');
    t = t.replaceAll(RegExp(r'\(\s*\d+\s*\)'), ' ').replaceAll(RegExp(r'\(\s*Ko[şs]maz\s*\)', caseSensitive: false), ' ');
    for (final w in t.split(RegExp(r'\s+'))) {
      if (_takiBilinen.contains(w)) ekle(w, '');
    }
  }
  return out;
}

List<Horse> _parseHorses(Element table) {
  final rows = table.querySelectorAll('tr');
  if (rows.length < 2) return [];
  var bi = rows.indexWhere((tr) => RegExp(r'At\s*İsmi', caseSensitive: false).hasMatch(tr.text) && RegExp('Jokey', caseSensitive: false).hasMatch(tr.text));
  if (bi < 0) bi = 0;
  final heads = rows[bi].querySelectorAll('th,td').map((e) => e.text.trim()).toList();
  int? exact(String k) {
    final i = heads.indexWhere((h) => _clean(h) == k);
    return i >= 0 ? i : null;
  }

  final iN = exact('N') ?? _col(heads, 'N');
  final iIsim = _col(heads, 'At İsmi');
  final iYas = _col(heads, 'Yaş');
  final iSik = _col(heads, 'Sıklet');
  final iJok = _col(heads, 'Jokey');
  final iHp = _col(heads, 'HP');
  final iS6 = _col(heads, 'Son 6');
  final iKgs = _col(heads, 'KGS');
  final iGny = _col(heads, 'Gny');
  final iAgf = _col(heads, 'AGF');
  final iSt = exact('St') ?? _col(heads, 'St');
  final iOri = _col(heads, 'Orijin');
  final iSah = _col(heads, 'Sahip');
  final iAnt = _col(heads, ['Antrenör', 'Antrenor', 'Antr.']);
  final iS20 = _col(heads, 's20');
  final iEid = _col(heads, 'En İyi D');
  final iIdm = _col(heads, ['İdm', 'Idm']);
  final out = <Horse>[];
  for (var i = bi + 1; i < rows.length; i++) {
    final tds = rows[i].querySelectorAll('td');
    if (tds.length < 4) continue;
    String? al(int? idx) => idx != null && idx < tds.length ? tds[idx].text.trim() : null;
    String tek(int? idx) => _clean(al(idx) ?? '').replaceAll(RegExp(r'^-$'), '');
    final isimHam = al(iIsim);
    if (isimHam == null || isimHam.isEmpty) continue;
    final rowText = rows[i].outerHtml;
    final kosmaz = RegExp(r'ko[sş]maz|kosmaz|cekil|çekil|iptal|withdraw|scratch', caseSensitive: false).hasMatch(rows[i].className + rows[i].querySelectorAll('[class]').map((e) => e.className).join(' ')) ||
        RegExp(r'\(\s*K\s*\)').hasMatch(isimHam) ||
        RegExp(r'\bko[şs]maz\b', caseSensitive: false).hasMatch(rows[i].text) ||
        rows[i].querySelector('s, strike, del, [style*="line-through"]') != null ||
        rowText.contains('line-through');
    final isim = isimHam.split('\n').first.replaceAll(RegExp(r'\s{2,}.*$'), '').trim();
    final no = int.tryParse((al(iN) ?? '').replaceAll(RegExp(r'[^0-9]'), ''));
    if (no == null) continue;
    String jok = '';
    if (iJok != null && iJok < tds.length) {
      final a = tds[iJok].querySelector('a');
      jok = _clean((a?.text.trim().isNotEmpty ?? false) ? a!.text : tds[iJok].text).replaceAll(RegExp(r'\s*AP\s*Apranti.*$', caseSensitive: false), '').replaceAll(RegExp(r'\s+AP$'), '').trim();
    }
    final s6x = _son6Ayir(iS6 != null && iS6 < tds.length ? tds[iS6] : null);
    final isimHucre = iIsim != null && iIsim < tds.length ? tds[iIsim] : null;
    final atLinki = isimHucre?.querySelector('a');
    final taki = _takiCikar(isimHucre, isimHam, atLinki);

    // İdman videosu: İdm hücresindeki bağlantıdan KosuKodu + Atkodu
    var idmHref = '', idmK = '', idmA = '';
    if (iIdm != null && iIdm < tds.length) {
      final hc = tds[iIdm];
      for (final el in [hc, ...hc.querySelectorAll('*')]) {
        final v = el.attributes.values.join(' ');
        final k1 = RegExp(r'KosuKodu=(-?\d+)', caseSensitive: false).firstMatch(v);
        final a1 = RegExp(r'Atkodu=(\d+)', caseSensitive: false).firstMatch(v);
        if (k1 != null && a1 != null) {
          idmK = k1.group(1)!;
          idmA = a1.group(1)!;
          final h = el.attributes['href'] ?? '';
          if (h.isNotEmpty) idmHref = h.startsWith('http') ? h : 'https://www.tjk.org${h.startsWith('/') ? '' : '/'}$h';
          break;
        }
      }
    }
    out.add(Horse(
      no: no,
      name: isim.isEmpty ? isimHam.substring(0, isimHam.length.clamp(0, 40)) : isim,
      jockey: jok,
      yas: _clean(al(iYas) ?? ''),
      kgs: _clean(al(iKgs) ?? ''),
      kosmaz: kosmaz,
      agf: int.tryParse(RegExp(r'(\d+)').firstMatch(al(iAgf) ?? '')?.group(1) ?? ''),
      hp: int.tryParse((al(iHp) ?? '').trim()),
      gny: double.tryParse((al(iGny) ?? '').replaceAll(',', '.')),
      siklet: double.tryParse((al(iSik) ?? '').replaceAll(',', '.')),
      son6: s6x.map((e) => e.s).toList(),
      son6p: s6x.map((e) => _pistHarf(e.c)).toList(),
      taki: taki,
      st: RegExp(r'^(\d{1,2})(?!\d)').firstMatch(_clean(al(iSt) ?? ''))?.group(1) ?? '',
      s20: tek(iS20),
      orijin: tek(iOri),
      sahip: tek(iSah),
      antrenor: tek(iAnt),
      eid: tek(iEid),
      idmHref: idmHref,
      idmK: idmK,
      idmA: idmA,
      atId: RegExp(r'AtId=(\d+)', caseSensitive: false).firstMatch(atLinki?.attributes['href'] ?? '')?.group(1) ?? '',
    ));
  }
  return out;
}

String _bilgiAyikla(String ham) {
  final t = _clean(ham);
  final l = _trLower(t);
  final m = _pistRe.firstMatch(l);
  if (m == null) return '';
  var end = m.end;
  final eid = RegExp(r'^\s*,?\s*E\.?\s*[İIi]\.?\s*D\.?\s*:\s*[\d.]+').firstMatch(t.substring(end.clamp(0, t.length)));
  if (eid != null) end += eid.group(0)!.length;
  if (end > t.length) end = t.length;
  var head = t.substring(0, end).replaceFirst(RegExp(r'^[\s\S]*Koşu\s+\d{1,2}[:.]\d{2}\s*'), '');
  head = head.replaceFirst(RegExp(r'^[\s\S]*(?:Birinci Primi|Koşu İkramiyesi|İkramiye|Primi)[^,]*?(?:\d\s*TL|₺)\s*', caseSensitive: false), '').trim();
  if (head.length < 12 || head.length > 320) return '';
  final lh = _trLower(head);
  final ok = RegExp(r'yaş|\bkg\b|yukarı|araplar|ingilizler|handikap|maiden|şartlı|dişi|erkek').hasMatch(lh) || ','.allMatches(lh).length >= 2;
  return ok ? head : '';
}

List<Race> _parseRaces(Document doc, Map<int, List<Start>> bas, Map<int, List<String>> oyun) {
  final all = _all(doc);
  final idx = <Element, int>{for (var i = 0; i < all.length; i++) all[i]: i};
  final heads = all.where(_isHead).toList();
  final tables = doc.querySelectorAll('table');
  final cand = <int, List<({String saat, String bilgi, List<Horse> atlar})>>{};
  for (var h = 0; h < heads.length; h++) {
    final he = heads[h];
    final m = _headRe.firstMatch(he.text.trim())!;
    final no = int.parse(m.group(1)!);
    final saat = '${m.group(2)!.padLeft(2, '0')}:${m.group(3)}';
    final start = idx[he]!;
    final end = h + 1 < heads.length ? idx[heads[h + 1]]! : all.length;
    Element? tablo;
    for (final t in tables) {
      final ti = idx[t];
      if (ti != null && ti > start && ti < end) {
        tablo = t;
        break;
      }
    }
    var bilgi = '';
    final stop = tablo != null ? idx[tablo]! : end;
    for (var i = start + 1; i < stop && i < all.length; i++) {
      final ay = _bilgiAyikla(all[i].text);
      if (ay.isEmpty) continue;
      if (all[i].children.any((c) => _bilgiAyikla(c.text).isNotEmpty)) continue;
      bilgi = ay;
      break;
    }
    if (bilgi.isEmpty && he.parent != null) bilgi = _bilgiAyikla(he.parent!.text);
    bilgi = bilgi.replaceFirst(RegExp(r'\s*(?:Birinci Primi|Koşu İkramiyesi|İkramiye|Primi)[\s\S]*$', caseSensitive: false), '').replaceAll(RegExp(r'\s+,'), ',').replaceAll(RegExp(r'[\s,]+$'), '').trim();
    final atlar = tablo != null ? _parseHorses(tablo) : <Horse>[];
    cand.putIfAbsent(no, () => []).add((saat: saat, bilgi: bilgi, atlar: atlar));
  }
  final out = <Race>[];
  final nos = cand.keys.toList()..sort();
  for (final no in nos) {
    final c = cand[no]!;
    var pick = c.last;
    for (var i = c.length - 1; i >= 0; i--) {
      if (c[i].atlar.isNotEmpty) {
        pick = c[i];
        break;
      }
    }
    if (pick.atlar.isEmpty) continue;
    String? mesafe, pist;
    final mp = _pistRe.firstMatch(_trLower(pick.bilgi));
    if (mp != null) {
      mesafe = '${int.parse(mp.group(1)!.replaceAll('.', ''))} m';
      final p = mp.group(2)!;
      pist = p == 'çim' ? 'Çim' : p == 'kum' ? 'Kum' : 'Sentetik';
    }
    out.add(Race(no: no, saat: pick.saat, mesafe: mesafe, pist: pist, bilgi: pick.bilgi, atlar: pick.atlar, baslar: bas[no] ?? const [], oyun: oyun[no]));
  }
  return out;
}

String _pageText(Document doc) {
  var t = _norm((doc.body?.text ?? '').replaceAll('\u00a0', ' ')).replaceAll(RegExp(r"['’`]"), '').replaceAll(RegExp(r'\s+'), ' ');
  return t;
}

Map<int, List<Start>> _ayakBaslangic(Document doc) {
  final out = <int, List<Start>>{};
  var txt = _pageText(doc)
      .replaceAll(RegExp(r'\bYEDILI\b'), '7LI')
      .replaceAll(RegExp(r'\bALTILI\b'), '6LI')
      .replaceAll(RegExp(r'\bBESLI\b'), '5LI')
      .replaceAll(RegExp(r'\bDORTLU\b'), '4LI')
      .replaceAllMapped(RegExp(r'\bUCLU\b(?= (?:GANYAN|PLASE))'), (m) => '3LI');
  final heads = RegExp(r'(\d{1,2})\. KOSU\s+\d{1,2}[:.]\d{2}').allMatches(txt).toList();
  for (final m in RegExp('KOSUDAN BASLAR').allMatches(txt)) {
    final hs = heads.where((x) => x.end <= m.start).toList();
    if (hs.isEmpty) continue;
    final h = hs.last;
    final seg = txt.substring((m.start - 400).clamp(h.end, m.start), m.start);
    for (final x in RegExp(r'(?:(\d)\. ?)?(\d) ?L[IU] ?(GANYAN|PLASE)|CIFTE').allMatches(seg)) {
      final it = x.group(0) == 'CIFTE' ? Start(0, 2, 'CIFTE') : Start(x.group(1) != null ? int.parse(x.group(1)!) : 0, int.parse(x.group(2)!), x.group(3)!);
      final no = int.parse(h.group(1)!);
      final l = out.putIfAbsent(no, () => []);
      if (!l.any((y) => y.ord == it.ord && y.n == it.n && y.tur == it.tur)) l.add(it);
    }
  }
  return out;
}

Map<int, List<String>> _kosuOyunlari(Document doc) {
  final out = <int, List<String>>{};
  final txt = _pageText(doc).replaceAll(RegExp(r'\bBESLI\b'), '5LI');
  final heads = RegExp(r'(\d{1,2})\. KOSU\s+\d{1,2}[:.]\d{2}').allMatches(txt).toList();
  for (var i = 0; i < heads.length; i++) {
    final h = heads[i];
    final end = i + 1 < heads.length ? heads[i + 1].start : txt.length;
    var seg = txt.substring(h.end, end);
    if (seg.length > 900) seg = seg.substring(seg.length - 900);
    seg = ' $seg '
        .replaceAll(RegExp(r'SABIT [^,]*'), ' ')
        .replaceAll(RegExp(r'\d ?L[IU] ?(?:GANYAN|PLASE)'), ' ')
        .replaceAll('SIRALI IKILI', ' @SI ')
        .replaceAll('PLASE IKILI', ' @PI ')
        .replaceAll(RegExp(r'SIRALI (?:UCLU|3LU)'), ' @SU ')
        .replaceAll(RegExp(r'SIRALI 5 ?LI'), ' @S5 ');
    final set = <String>{};
    if (RegExp(r'\bGANYAN\b').hasMatch(seg)) set.add('g1');
    if (seg.contains('@SI')) set.add('si');
    if (seg.contains('@PI')) set.add('pi');
    if (seg.contains('@SU') || RegExp(r'\bUCLU BAHIS').hasMatch(seg)) set.add('su');
    if (seg.contains('@S5')) set.add('s5');
    if (seg.contains('TABELA')) set.add('tb');
    final rest = seg.replaceAll(RegExp(r'@\w+'), ' ');
    if (RegExp(r'\bIKILI\b').hasMatch(rest)) set.add('ik');
    if (RegExp(r'\bPLASE\b').hasMatch(rest)) {
      set.add('pl');
      set.add('gp');
    }
    if (set.contains('g1') && set.length >= 2) out[int.parse(h.group(1)!)] = set.toList();
  }
  return out;
}

Future<List<Race>> getProgram(City c, String iso) async {
  final url =
      'https://www.tjk.org/TR/yarissever/Info/Sehir/GunlukYarisProgrami?SehirId=${c.id}&QueryParameter_Tarih=${Uri.encodeComponent(_tjkDate(iso))}&SehirAdi=${Uri.encodeComponent(c.name)}&Era=${_era(iso)}';
  final html = await _fetch(url, sec: 45, ttl: 120, disk: _diskTtl(iso, 600));
  return compute(_programIso, html);
}

List<Race> _programIso(String html) {
  final doc = hp.parse(html);
  var races = _parseRaces(doc, _ayakBaslangic(doc), _kosuOyunlari(doc));
  if (races.isEmpty) {
    // yedek: tablo başlıklarından koşu numarası bul
    var sira = 0;
    for (final t in doc.querySelectorAll('table')) {
      final head = t.querySelectorAll('tr').take(3).map((e) => e.text).join(' ');
      if (!RegExp(r'At\s*İsmi', caseSensitive: false).hasMatch(head) || !RegExp('Jokey', caseSensitive: false).hasMatch(head)) continue;
      final atlar = _parseHorses(t);
      if (atlar.isEmpty) continue;
      sira++;
      races.add(Race(no: sira, saat: '—', atlar: atlar));
    }
  }
  return races;
}

/* ---------------- Sonuçlar ---------------- */

final _bahisKalip = <({RegExp re, String Function(RegExpMatch) tur, String Function(RegExpMatch) detay})>[
  (re: RegExp(r"(?:(\d+)\.\s*)?(\d+)\s*['’]?\s*L[İIÜUiıüu]\s*GANYAN\s*(.*)$", caseSensitive: false), tur: (m) => "${m.group(1) != null ? '${m.group(1)}. ' : ''}${m.group(2)}'li Ganyan", detay: (m) => m.group(3) ?? ''),
  (re: RegExp(r"(?:(\d+)\.\s*)?(\d+)\s*['’]?\s*L[İIÜUiıüu]\s*PLASE\s*(.*)$", caseSensitive: false), tur: (m) => "${m.group(1) != null ? '${m.group(1)}. ' : ''}${m.group(2)}'li Plase", detay: (m) => m.group(3) ?? ''),
  (re: RegExp(r'SIRALI\s*[İIi]K[İIi]L[İIi]\s*(.*)$', caseSensitive: false), tur: (m) => 'Sıralı İkili', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r"SIRALI\s*(?:5\s*['’]?\s*L[İIi]|BE[ŞS]L[İIi])\s*(?:BAH[İIi]S\s*)?(.*)$", caseSensitive: false), tur: (m) => 'Sıralı Beşli', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'TABELA\s*(?:BAH[İIi]S\s*)?(.*)$', caseSensitive: false), tur: (m) => 'Tabela Bahis', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'SIRALI\s*(?:ÜÇLÜ\s*)?(?:BAH[İIi]S\s*)?(.*)$', caseSensitive: false), tur: (m) => 'Sıralı Üçlü', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'PLASE\s*[İIi]K[İIi]L[İIi]\s*(.*)$', caseSensitive: false), tur: (m) => 'Plase İkili', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'ÜÇLÜ\s*BAH[İIi]S\s*(.*)$', caseSensitive: false), tur: (m) => 'Üçlü Bahis', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'(\d+)\.\s*ÇİFTE\s*(.*)$', caseSensitive: false), tur: (m) => '${m.group(1)}. Çifte', detay: (m) => m.group(2) ?? ''),
  (re: RegExp(r'SAB[İIi]T\s*GANYAN\s*(.*)$', caseSensitive: false), tur: (m) => 'Sabit Ganyan', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'PLASE\s+(.*)$', caseSensitive: false), tur: (m) => 'Plase', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'[İIi]K[İIi]L[İIi]\s*(.*)$', caseSensitive: false), tur: (m) => 'İkili', detay: (m) => m.group(1) ?? ''),
  (re: RegExp(r'GANYAN\s*(.*)$', caseSensitive: false), tur: (m) => 'Ganyan', detay: (m) => m.group(1) ?? ''),
];

List<Bahis> _bahisler(String metin) {
  metin = metin.replaceAll('\u00a0', ' ').split(RegExp(r'Son\s*800', caseSensitive: false)).first;
  final out = <Bahis>[];
  final seen = <String>{};
  Bahis? son;
  for (final parca in metin.split('₺')) {
    final prev = son;
    son = null;
    final tm = RegExp(r'([\d.,]+)\s*$').firstMatch(parca);
    if (tm == null) continue;
    final tutar = tm.group(1)!;
    if (!((double.tryParse(tutar.replaceAll('.', '').replaceAll(',', '.')) ?? 0) > 0)) continue;
    final et = parca.substring(0, parca.length - tm.group(0)!.length).replaceAll(RegExp(r'\s+'), ' ');
    if (RegExp(r'DA[ĞG]ITILACAK').hasMatch(et.toUpperCase())) continue;
    if (et.trim().isEmpty) continue;
    for (final k in _bahisKalip) {
      final mm = k.re.firstMatch(et);
      if (mm != null) {
        final detay = k.detay(mm).replaceAll(RegExp(r'\s+'), ' ').replaceFirst(RegExp(r'^[İIi]KRAM[İIi]YE(LER)?\s*', caseSensitive: false), '').trim();
        final x = Bahis(k.tur(mm), detay, tutar);
        if (seen.add('${x.tur}|${x.detay}')) {
          out.add(x);
          son = x;
        }
        break;
      }
    }
    // ignore prev (ikramiye ayrımı basitleştirildi)
    if (prev != null) {}
  }
  return out.where((x) => !RegExp(r"'li (Ganyan|Plase)$|Çifte$").hasMatch(x.tur) || RegExp(r',\d{1,2}$').hasMatch(x.tutar)).toList();
}

Future<Map<int, RaceResult>> getResults(City c, String iso, List<Race> kosular) async {
  final url =
      'https://www.tjk.org/TR/yarissever/Info/Sehir/GunlukYarisSonuclari?SehirId=${c.id}&QueryParameter_Tarih=${Uri.encodeComponent(_tjkDate(iso))}&SehirAdi=${Uri.encodeComponent(c.name)}&Era=${_era(iso)}';
  final past = iso.compareTo(isoToday()) < 0;
  final html = await _fetch(url, sec: 30, retry: 1, ttl: past ? 3600 : 0, disk: past ? _diskTtl(iso, 0) : 0);
  return compute(_resultsIso, <Object>[html, c, kosular]);
}

Map<int, RaceResult> _resultsIso(List<Object> a) {
  final html = a[0] as String;
  final c = a[1] as City;
  final kosular = (a[2] as List).cast<Race>();
  final doc = hp.parse(html);
  final all = _all(doc);
  final idx = <Element, int>{for (var i = 0; i < all.length; i++) all[i]: i};
  final heads = all.where((e) => _isHead(e, maxLen: 400)).toList();
  final out = <int, RaceResult>{};
  var sonNo = 0;
  final goruldu = <int>{};
  for (final tablo in doc.querySelectorAll('table')) {
    try {
      final trs = tablo.querySelectorAll('tr');
      final bi = trs.indexWhere((tr) => RegExp(r'At\s*İsmi', caseSensitive: false).hasMatch(tr.text));
      if (bi < 0) continue;
      final ti = idx[tablo] ?? 0;
      int? no;
      Element? bHead;
      for (final b in heads) {
        if ((idx[b] ?? 0) < ti) {
          no = int.tryParse(RegExp(r'^\d+').firstMatch(b.text.trim())?.group(0) ?? '');
          bHead = b;
        } else {
          break;
        }
      }
      var seq = false;
      if (no == null || goruldu.contains(no) || no <= sonNo) {
        no = sonNo + 1;
        bHead = null;
        seq = true;
      }
      Race? kosu;
      for (final k in kosular) {
        if (k.no == no) kosu = k;
      }
      if (kosu == null) continue;
      final bas = trs[bi].querySelectorAll('th,td').map((e) => _clean(e.text)).toList();
      var iS = bas.indexWhere((h) => RegExp(r'^(S|Sıra|Sira)$', caseSensitive: false).hasMatch(h));
      if (iS < 0) iS = 0;
      final iIsim = bas.indexWhere((h) => RegExp(r'At\s*İsmi', caseSensitive: false).hasMatch(h));
      final iGny = bas.indexWhere((h) => RegExp(r'^Gny$', caseSensitive: false).hasMatch(h));
      if (iIsim < 0) continue;
      final atlar = kosu.atlar.map((a) => (no: a.no, n: _key(a.name))).where((a) => a.n.isNotEmpty).toList();
      final sira = <({int sr, int no})>[];
      final gn = <int, String>{};
      var satir = 0;
      for (final tr in trs.skip(bi + 1)) {
        final td = tr.querySelectorAll('td');
        if (td.length <= (iS > iIsim ? iS : iIsim)) continue;
        final sr = int.tryParse(td[iS].text.trim());
        if (sr == null || sr == 0) continue;
        satir++;
        final rn = _key(td[iIsim].text.replaceAll(RegExp(r'\(\s*\d{1,2}\s*\)'), ' '));
        ({int no, String n})? best;
        for (final a in atlar) {
          if (rn.startsWith(a.n) && (best == null || a.n.length > best.n.length)) best = a;
        }
        if (best == null && rn.length >= 4) {
          for (final a in atlar) {
            if (a.n.startsWith(rn) && (best == null || a.n.length > best.n.length)) best = a;
          }
        }
        if (best == null && !seq) {
          final mN = RegExp(r'\(\s*(\d{1,2})\s*\)').firstMatch(td[iIsim].text);
          if (mN != null) {
            for (final a in atlar) {
              if (a.no == int.parse(mN.group(1)!)) best = a;
            }
          }
        }
        if (best != null) {
          sira.add((sr: sr, no: best.no));
          final g = iGny >= 0 && iGny < td.length ? td[iGny].text.trim() : '';
          if (RegExp(r'^\d+[.,]\d+$').hasMatch(g)) gn[best.no] = g;
        }
      }
      sira.sort((a, b) => a.sr.compareTo(b.sr));
      if (seq && sira.length < (satir * 0.6).ceil().clamp(2, 99)) continue;
      sonNo = no;
      goruldu.add(no);
      // tablo sonrası metin
      Element? nextB;
      for (final b in heads) {
        if ((idx[b] ?? 0) > ti) {
          nextB = b;
          break;
        }
      }
      final end = nextB != null ? idx[nextB]! : all.length;
      final sb = StringBuffer();
      final inTable = tablo.querySelectorAll('*').toSet();
      for (var i = ti + 1; i < end; i++) {
        final e = all[i];
        if (e.children.isEmpty && !inTable.contains(e)) sb.write(' ${e.text}');
      }
      final bahisler = _bahisler(sb.toString());
      var vurl = '';
      final from = bHead != null ? idx[bHead]! : ti;
      for (var i = from; i < end; i++) {
        final href = all[i].localName == 'a' ? (all[i].attributes['href'] ?? '') : '';
        final m = RegExp(r'KosuKodu=(-?\d+)', caseSensitive: false).firstMatch(href);
        if (m != null && RegExp('YarisVideo', caseSensitive: false).hasMatch(href)) {
          vurl = 'https://www.tjk.org/TR/yarissever/Info/YarisVideoKosu/Kosu?KosuKodu=${m.group(1)}';
          break;
        }
      }
      if (seq) vurl = '';
      Bahis? gk;
      for (final b in bahisler) {
        if (b.tur == 'Ganyan') gk = b;
      }
      final gno = gk != null ? int.tryParse(RegExp(r'\d+').firstMatch(gk.detay)?.group(0) ?? '') : null;
      if (gno != null && !gn.containsKey(gno)) gn[gno] = gk!.tutar;
      if (sira.isNotEmpty && sira.first.sr == 1) {
        out[no] = RaceResult(sira.map((e) => e.no).toList(), gn, bahisler, vurl);
      }
    } catch (e) {
      debugPrint('sonuç ayrıştırma: $e');
    }
  }
  return out;
}

/// 'iso|şehir' -> koşu no -> geliş sırası. Kupon değerlendirmesi buradan okur.
final Map<String, Map<int, List<int>>> liveRes = {};

/// liveRes her değiştiğinde artar: akış / profil / liderler dinleyip yeniden çizer (Sonuçlar sekmesine girmeye gerek kalmaz).
final ValueNotifier<int> liveResTick = ValueNotifier<int>(0);

final Map<String, DateTime> _pullAt = {};

/// Belirli gün + şehrin sonuçlarını, ekrandaki gün (TjkStore.iso) ne olursa olsun bağımsız çeker.
/// Kullanıcı Sonuçlar'da başka güne baksa bile bugünkü kuponların sonucu gelmeye devam eder.
Future<void> pullLiveRes(String iso, String city) async {
  final k = '$iso|$city';
  final last = _pullAt[k];
  if (last != null && DateTime.now().difference(last).inSeconds < 12) return;
  _pullAt[k] = DateTime.now();
  try {
    final cs = await getCities(iso);
    City? ct;
    for (final x in cs) {
      if (x.name == city) ct = x;
    }
    if (ct == null) return;
    final rs = await getProgram(ct, iso);
    if (rs.isEmpty) return;
    final got = await getResults(ct, iso, rs);
    if (got.isEmpty) return;
    liveRes[k] = {...?liveRes[k], for (final e in got.entries) e.key: e.value.sira};
    liveResTick.value++;
  } catch (_) {}
}

/* ---------------- Ortak durum ---------------- */

/// Bugünün bülteni + sonuçları; Tahmin Yap, Sonuçlar ve kupon değerlendirme paylaşır.
class TjkStore extends ChangeNotifier {
  static final TjkStore i = TjkStore._();
  TjkStore._();

  String iso = isoToday();
  List<City> cities = [];
  final Map<String, List<Race>> program = {};
  final Map<String, Map<int, RaceResult>> results = {};
  bool loading = false;
  String? error;
  Timer? _timer;

  bool get isToday => iso == isoToday();
  bool get isPast => iso.compareTo(isoToday()) < 0;

  List<Race> races(String city) => program[city] ?? const [];
  Race? race(String city, int no) {
    for (final r in races(city)) {
      if (r.no == no) return r;
    }
    return null;
  }

  DateTime? raceStart(String city, int no) {
    final r = race(city, no);
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(r?.saat ?? '');
    if (m == null) return null;
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  bool raceDone(String city, int no) {
    final d = raceStart(city, no);
    return d != null && !d.isAfter(DateTime.now());
  }

  List<int>? resOf(String city, int no) => results[city]?[no]?.sira;

  Future<void> load(String newIso) async {
    // Aynı gün yenileniyorsa mevcut veriyi silme: ekran boşalıp baştan çizilmesin
    final keep = newIso == iso && cities.isNotEmpty;
    iso = newIso;
    loading = !keep;
    error = null;
    if (!keep) {
      cities = [];
      program.clear();
      results.clear();
    }
    notifyListeners();
    try {
      final nc = await getCities(iso);
      if (!keep) {
        cities = nc;
        notifyListeners();
      }
      final np = <String, List<Race>>{};
      await Future.wait(nc.map((c) async {
        try {
          np[c.name] = await getProgram(c, iso);
        } catch (_) {
          np[c.name] = keep ? (program[c.name] ?? []) : [];
        }
        if (!keep) program[c.name] = np[c.name]!;
      }));
      if (keep) program.addAll(np);
      cities = nc.where((c) => (np[c.name] ?? []).isNotEmpty).toList();
      if (cities.isEmpty) error = 'Bu tarih için koşu programı bulunamadı.';
    } catch (e) {
      if (!keep) error = e.toString().replaceFirst('Exception: ', '');
    }
    loading = false;
    notifyListeners();
    refreshResults();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 3), (_) => refreshResults());
  }

  bool _refreshing = false;

  Future<void> refreshResults({bool force = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _refreshAll(force);
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshAll(bool force) async {
    for (final c in List<City>.of(cities)) {
      final rs = races(c.name);
      final need = rs.any((r) => raceDone(c.name, r.no) && (results[c.name]?[r.no] == null || force));
      if (!need && !force) continue;
      try {
        final got = await getResults(c, iso, rs);
        results[c.name] = {...?results[c.name], ...got};
        liveRes['$iso|${c.name}'] = {for (final e in results[c.name]!.entries) e.key: e.value.sira};
        liveResTick.value++;
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> ensureLoaded() async {
    if (cities.isEmpty && !loading) await load(iso);
  }
}

/* ---------------- Koşu filmi ---------------- */

/// Koşu video sayfasından (veya doğrudan mp4 bağlantısından) oynatılabilir mp4 adresini bulur.
Future<String?> getVideoMp4(String url, String iso) async {
  if (RegExp(r'\.mp4(\?|$)', caseSensitive: false).hasMatch(url)) {
    return url.startsWith('//') ? 'https:$url' : url;
  }
  final past = iso.compareTo(isoToday()) < 0;
  final html = await _fetch(url, sec: 30, retry: 1, ttl: 600, disk: past ? 2592000 : 600);
  final m = RegExp(r'(?:https?:)?//video-cdn\.tjk\.org/videoftp/[^"\s<>\\]+?\.mp4', caseSensitive: false).firstMatch(html) ??
      RegExp(r'videoftp/\d{4}/\d{2}/[\w-]+\.mp4', caseSensitive: false).firstMatch(html);
  if (m == null) return null;
  var u = m.group(0)!;
  if (u.startsWith('//')) {
    u = 'https:$u';
  } else if (!RegExp(r'^https?:', caseSensitive: false).hasMatch(u)) {
    u = 'https://video-cdn.tjk.org/$u';
  }
  return u;
}

/// İdman videosu: önce TJK'nın idman sayfasındaki bağlantıdan, olmazsa bilinen CDN adresinden (ay ±1) dener.
Future<String?> getIdmanMp4(Horse h, String iso) async {
  if (h.idmHref.isNotEmpty) {
    try {
      final u = await getVideoMp4(h.idmHref, iso);
      if (u != null) return u;
    } catch (_) {}
  }
  if (h.idmK.isEmpty || h.idmA.isEmpty) return null;
  final p = iso.split('-').map(int.parse).toList();
  for (final d in [0, -1, 1]) {
    final dt = DateTime(p[0], p[1] + d, 1);
    final u = 'https://video-cdn.tjk.org/videoftp/idmanpisti/${dt.year}/${dt.month.toString().padLeft(2, '0')}/${h.idmK}-${h.idmA}.mp4';
    try {
      final r = await http.head(Uri.parse(u)).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) return u;
    } catch (_) {}
  }
  return null;
}


/* ---------------- At geçmişi: son yarış / son galibiyet / son galop ---------------- */

class AtRow {
  final String t, d, y, k, v, no, sh, kn, st;
  /// O koşudaki takı kodları, virgülle (örn. 'KG,DB'). '' = takısız, '?' = bilinmiyor
  final String tk;
  const AtRow({this.t = '', this.d = '', this.y = '', this.k = '', this.v = '', this.no = '', this.sh = '', this.kn = '', this.st = '', this.tk = '?'});
  factory AtRow.fromMap(Map m) => AtRow(
        t: '${m['t'] ?? ''}', d: '${m['d'] ?? ''}', y: '${m['y'] ?? ''}', k: '${m['k'] ?? ''}', v: '${m['v'] ?? ''}',
        no: '${m['no'] ?? ''}', sh: '${m['sh'] ?? ''}', kn: '${m['kn'] ?? ''}', st: '${m['st'] ?? ''}', tk: '${m['tk'] ?? '?'}',
      );
  AtRow withNo(String n) => AtRow(t: t, d: d, y: y, k: k, v: v, no: n, sh: sh, kn: kn, st: st, tk: tk);
}

/// null = kayıt yok
class AtHist {
  final AtRow? yaris, galibiyet;
  const AtHist(this.yaris, this.galibiyet);
}

final Map<String, AtHist> _histMem = {};
final Map<String, Future<AtHist>> _histBusy = {};

/// Bu atın son yarış / son galibiyet bilgisi bellekte hazır mı?
bool atHistHazir(String atId) => _histMem.containsKey(atId);
final Map<String, AtRow?> _galopMem = {};
final Map<String, Future<AtRow?>> _galopBusy = {};

String _pistAd(String p) {
  final t = p.trim();
  if (RegExp(r'^K$', caseSensitive: false).hasMatch(t)) return 'Kum';
  if (RegExp(r'^[ÇC]$', caseSensitive: false).hasMatch(t)) return 'Çim';
  if (RegExp(r'^S$', caseSensitive: false).hasMatch(t)) return 'Sentetik';
  return t;
}

Future<AtHist> getAtHist(String atId) {
  final hit = _histMem[atId];
  if (hit != null) return Future.value(hit);
  return _histBusy[atId] ??= () async {
    try {
      final url = 'https://www.tjk.org/TR/yarissever/Query/ConnectedPage/AtKosuBilgileri?1=1&QueryParameter_AtId=${Uri.encodeComponent(atId)}';
      final html = await _fetch(url, sec: 25, retry: 1, ttl: 600, disk: 43200, fresh: false);
      final m = await compute(_atHistIso, <String>[html, atId]);
      final r = AtHist(m['yaris'] == null ? null : AtRow.fromMap(m['yaris']!), m['gal'] == null ? null : AtRow.fromMap(m['gal']!));
      _histMem[atId] = r;
      return r;
    } finally {
      _histBusy.remove(atId);
    }
  }();
}

Map<String, Map<String, String>?> _atHistIso(List<String> a) {
  final doc = hp.parse(a[0]);
  final atId = a[1];
  final out = <String, Map<String, String>?>{'yaris': null, 'gal': null};
  for (final tb in doc.querySelectorAll('table')) {
    if (tb.querySelector('table') != null) continue;
    final rows = tb.querySelectorAll('tr');
    final hi = rows.indexWhere((tr) {
      final t = _clean(tr.text);
      return RegExp('Tarih', caseSensitive: false).hasMatch(t) && RegExp('Derece', caseSensitive: false).hasMatch(t);
    });
    if (hi < 0) continue;
    final heads = rows[hi].querySelectorAll('th,td').map((c) => _clean(c.text).toLowerCase()).toList();
    final iT = heads.indexWhere((h) => h.startsWith('tarih'));
    final iS = heads.indexWhere((h) => h == 's' || RegExp(r'^s[ıi]ra').hasMatch(h));
    final iD = heads.indexWhere((h) => h.startsWith('derece'));
    final iH = heads.indexWhere((h) => RegExp(r'hip|şehir|sehir').hasMatch(h));
    final iM = heads.indexWhere((h) => RegExp(r'msf|mesafe').hasMatch(h));
    var iP = -1;
    for (var i = 0; i < heads.length; i++) {
      if (i != iM && RegExp(r'pist|zemin').hasMatch(heads[i])) {
        iP = i;
        break;
      }
    }
    final iJk = heads.indexWhere((h) => h.contains('jokey'));
    final iC = heads.indexWhere((h) => RegExp(r'cins|grup|grub').hasMatch(h));
    final iG = heads.indexWhere((h) => RegExp(r'^gny|ganyan').hasMatch(h));
    final iSt = heads.indexWhere((h) => h.replaceAll(RegExp(r'[^a-zçğıöşü]'), '') == 'st');
    final iK = heads.indexWhere((h) => RegExp(r'^k\.?\s*no').hasMatch(h));
    final iTk = heads.indexWhere((h) => RegExp(r'tak[ıi]|ekipman').hasMatch(h));
    if (iT < 0) continue;
    for (var i = hi + 1; i < rows.length; i++) {
      final td = rows[i].querySelectorAll('td');
      if (td.length <= iT) continue;
      String g(int idx) => idx >= 0 && idx < td.length ? _clean(td[idx].text) : '';
      if (!RegExp(r'^\d{1,2}[./]\d{1,2}[./]\d{4}$').hasMatch(g(iT))) continue;
      var pist = g(iP);
      if (pist.isEmpty && iM >= 0 && iM < td.length) {
        pist = td[iM].querySelector('[title]')?.attributes['title'] ?? td[iM].querySelector('img[alt]')?.attributes['alt'] ?? '';
      }
      pist = _pistAd(pist);
      final msf = g(iM).replaceAll(RegExp(r'[^\d]'), '');
      final rh = rows[i].outerHtml.replaceAll('&amp;', '&');
      final mp = RegExp(r'(?:https?:)?//video-cdn\.tjk\.org/videoftp/[^"\x27\s<>\\]+?\.mp4', caseSensitive: false).firstMatch(rh);
      final hv = RegExp(r'href\s*=\s*["\x27]([^"\x27]*YarisVideo[^"\x27]*)["\x27]', caseSensitive: false).firstMatch(rh);
      final kk = RegExp(r'KosuKodu\W{0,8}?(-?\d{3,})', caseSensitive: false).firstMatch(rh);
      String video(String tarih) {
        if (mp != null) {
          final u = mp.group(0)!;
          return u.startsWith('//') ? 'https:$u' : u;
        }
        if (hv != null) {
          final u = hv.group(1)!;
          return u.startsWith('http') ? u : 'https://www.tjk.org${u.startsWith('/') ? '' : '/'}$u';
        }
        if (kk != null) {
          final tm = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(tarih);
          if (tm != null) {
            final dt = DateTime(int.parse(tm.group(3)!), int.parse(tm.group(2)!), int.parse(tm.group(1)!));
            if (DateTime.now().difference(dt).inDays <= 90) {
              return 'https://www.tjk.org/TR/YarisSever/Info/YarisVideoAt/At?AtKodu=${Uri.encodeComponent(atId)}&KosuKodu=${kk.group(1)}';
            }
          }
        }
        return '';
      }

      final kn = '${int.tryParse(g(iK)) ?? ''}';
      if (out['yaris'] == null) {
        out['yaris'] = {
          't': g(iT),
          'd': [pist, if (msf.isNotEmpty) '${msf}m'].where((e) => e.isNotEmpty).join(' · '),
          'y': [g(iH), g(iT)].where((e) => e.isNotEmpty).join(' · '),
          'st': g(iSt).replaceAll(RegExp(r'[^\d]'), ''),
          'sh': g(iH),
          'kn': kn,
          'v': video(g(iT)),
          'tk': iTk >= 0 && iTk < td.length ? _takiCikar(td[iTk], '', null).map((e) => e.k).join(',') : '?',
        };
      }
      if (out['gal'] == null && iS >= 0 && RegExp(r'^1\b').hasMatch(g(iS))) {
        final gny = g(iG).replaceAll(RegExp(r'[^\d.,]'), '');
        out['gal'] = {
          't': g(iT),
          'd': g(iD),
          'y': [g(iH), msf, pist].where((e) => e.isNotEmpty).join(' · '),
          'k': [g(iC), g(iJk), if (gny.isNotEmpty) 'Gny $gny'].where((e) => e.isNotEmpty).join(' · '),
          'no': g(iSt).replaceAll(RegExp(r'[^\d]'), ''),
          'sh': g(iH),
          'kn': kn,
          'v': video(g(iT)),
        };
      }
      if (out['yaris'] != null && (out['gal'] != null || iS < 0)) break;
    }
    break;
  }
  return out;
}

/// Atın en yeni galop/sprint idmanı (İdman İstatistikleri sayfası). null = kayıt yok.
Future<AtRow?> _getAtGalopEski(String atId) {
  if (_galopMem.containsKey(atId)) return Future.value(_galopMem[atId]);
  return _galopBusy[atId] ??= () async {
    try {
      final id = Uri.encodeComponent(atId);
      final urls = [
        'https://www.tjk.org/TR/YarisSever/Query/Page/IdmanIstatistikleri?QueryParameter_AtId=$id',
        'https://www.tjk.org/TR/yarissever/Query/ConnectedPage/AtIdmanBilgileri?1=1&QueryParameter_AtId=$id',
        'https://www.tjk.org/TR/yarissever/Query/ConnectedPage/IdmanIstatistikleri?1=1&QueryParameter_AtId=$id',
      ];
      Object? last;
      for (final u in urls) {
        try {
          final html = await _fetch(u, sec: 25, retry: 1, ttl: 600, disk: 43200, fresh: false);
          final m = await compute(_galopIso, html);
          if (m != null && m['err'] != null) {
            last = m['err'];
            continue;
          }
          final r = m == null ? null : AtRow.fromMap(m);
          _galopMem[atId] = r;
          return r;
        } catch (e) {
          last = e;
        }
      }
      throw Exception('$last');
    } finally {
      _galopBusy.remove(atId);
    }
  }();
}

/* ---- Son galop: siteyle aynı yöntem (Cloudflare worker'dan 6'şar atlık toplu istek) ---- */
const _galopBackend = 'https://galop.bilyoncu001.workers.dev';
DateTime? _galopWorkerYok; // worker cevap vermezse 10 dk eski (tek tek) yönteme düşer
final Map<String, Completer<AtRow?>> _galopWait = {};
final List<String> _galopQ = [];
Timer? _galopTimer;
int _galopRun = 0;

bool atGalopHazir(String atId) => _galopMem.containsKey(atId);

Future<AtRow?> getAtGalop(String atId) {
  if (_galopMem.containsKey(atId)) return Future.value(_galopMem[atId]);
  final w = _galopWait[atId];
  if (w != null) return w.future;
  return _getAtGalopEski(atId); // worker kaldırıldı
  // ignore: dead_code
  final wy = _galopWorkerYok;
  if (wy != null && DateTime.now().difference(wy) < const Duration(minutes: 10)) return _getAtGalopEski(atId);
  final c = Completer<AtRow?>();
  _galopWait[atId] = c;
  _galopQ.add(atId);
  // Aynı anda gelen istekleri tek pakette topla
  _galopTimer ??= Timer(const Duration(milliseconds: 60), () {
    _galopTimer = null;
    _galopPump();
  });
  return c.future;
}

Future<Map<String, dynamic>> _galopToplu(List<String> ids) async {
  final u = '$_galopBackend?galop=${ids.map(Uri.encodeComponent).join(',')}';
  final r = await http.get(Uri.parse(u)).timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw Exception('Worker HTTP ${r.statusCode}');
  final j = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
  if (j is! Map || j['error'] != null) throw Exception('Worker galop yok');
  return Map<String, dynamic>.from(j);
}

void _galopPump() {
  while (_galopRun < 2 && _galopQ.isNotEmpty) {
    final n = _galopQ.length < 6 ? _galopQ.length : 6;
    final ids = _galopQ.sublist(0, n);
    _galopQ.removeRange(0, n);
    _galopRun++;
    () async {
      try {
        final m = await _galopToplu(ids);
        for (final id in ids) {
          final r = m[id];
          final c = _galopWait.remove(id);
          if (r is Map && ('${r['t'] ?? ''}'.isNotEmpty || r['n'] != null)) {
            final row = '${r['t'] ?? ''}'.isEmpty ? null : AtRow.fromMap(r);
            _galopMem[id] = row;
            c?.complete(row);
          } else {
            _getAtGalopEski(id).then((v) => c?.complete(v), onError: (Object e) => c?.completeError(e));
          }
        }
      } catch (_) {
        _galopWorkerYok = DateTime.now();
        for (final id in ids) {
          final c = _galopWait.remove(id);
          _getAtGalopEski(id).then((v) => c?.complete(v), onError: (Object e) => c?.completeError(e));
        }
      } finally {
        _galopRun--;
        if (_galopQ.isNotEmpty) _galopPump();
      }
    }();
  }
}

Map<String, String>? _galopIso(String html) {
  final doc = hp.parse(html);
  String n(String s) => _trLower(_clean(s));
  int ts(String t) {
    final m = RegExp(r'(\d{1,2})[./](\d{1,2})[./](\d{4})').firstMatch(t);
    return m == null ? 0 : DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!)).millisecondsSinceEpoch;
  }

  List<Element>? rs;
  var hi = -1;
  for (final t in doc.querySelectorAll('table')) {
    if (t.querySelector('table') != null) continue;
    final tr = t.querySelectorAll('tr');
    for (var i = 0; i < tr.length && i < 3; i++) {
      final b = n(tr[i].text);
      if (b.contains('at adı') && b.contains('i. tarihi') && b.contains('pist') && b.contains('i. türü')) {
        rs = tr;
        hi = i;
        break;
      }
    }
    if (rs != null) break;
  }
  if (rs == null) return {'err': 'İdman tablosu yok'};
  final h = rs[hi].querySelectorAll('th,td').map((c) => n(c.text)).toList();
  int ix(String a) => h.indexWhere((x) => x.contains(a));
  final iT = ix('i. tarihi'), iP = ix('pist'), iK = ix('i. türü'), iJ = ix('i. jokeyi'), iH = ix('i. hip');
  final mes = [1400, 1200, 1000, 800, 600, 400, 200].map((m) => (m, h.indexWhere((x) => x.replaceAll(RegExp(r'[^\dm]'), '') == '${m}m'))).toList();
  List<Element>? best;
  var bt = 0;
  for (var i = hi + 1; i < rs.length; i++) {
    final td = rs[i].querySelectorAll('td');
    if (td.length < 5 || td.length <= iT) continue;
    if (iK >= 0 && iK < td.length && !RegExp(r'galop|sprint', caseSensitive: false).hasMatch(n(td[iK].text))) continue;
    final t = ts(n(td[iT].text));
    if (t > bt) {
      bt = t;
      best = td;
    }
  }
  final bst = best;
  if (bst == null) return null;
  String g(int j) => j >= 0 && j < bst.length ? _clean(bst[j].text) : '';
  final pistH = g(iP).isEmpty ? '' : g(iP).substring(0, 1).toUpperCase();
  final pist = pistH == 'Ç' ? 'Çim' : pistH == 'K' ? 'Kum' : pistH == 'S' ? 'Sentetik' : '';
  final det = <String>[];
  for (final (m, j) in mes) {
    final v = g(j);
    if (v.isNotEmpty && v != '-') det.add('${m}m $v');
  }
  return {'t': g(iT), 'd': det.take(4).join(' · '), 'y': [g(iH), pist, g(iJ)].where((e) => e.isNotEmpty).join(' · ')};
}

/// Geçmiş yarışta atın numarası: o günün sonuç sayfasında (şehir, koşu no, St kapısı) ile bulunur.
final Map<String, String> _noMem = {};
Future<String> getYarisNo(String sehir, String tarih, String kn, String st) async {
  final key = '$sehir|$tarih|$kn|$st';
  if (_noMem.containsKey(key)) return _noMem[key]!;
  final m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(tarih);
  if (m == null || kn.isEmpty || st.isEmpty) return '';
  final iso = '${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}';
  final cities = await getCities(iso);
  final hedef = _key(sehir);
  City? c;
  for (final x in cities) {
    final a = _key(x.name);
    if (a.startsWith(hedef) || hedef.startsWith(a)) c = x;
  }
  if (c == null) return '';
  final url =
      'https://www.tjk.org/TR/yarissever/Info/Sehir/GunlukYarisSonuclari?SehirId=${c.id}&QueryParameter_Tarih=${Uri.encodeComponent(_tjkDate(iso))}&SehirAdi=${Uri.encodeComponent(c.name)}&Era=${_era(iso)}';
  final html = await _fetch(url, sec: 30, retry: 1, ttl: 3600, disk: 2592000);
  final no = await compute(_yarisNoIso, <String>[html, kn, st]);
  _noMem[key] = no;
  return no;
}

String _yarisNoIso(List<String> a) {
  final doc = hp.parse(a[0]);
  final kn = int.tryParse(a[1]) ?? 0, st = int.tryParse(a[2]) ?? 0;
  final all = _all(doc);
  final idx = <Element, int>{for (var i = 0; i < all.length; i++) all[i]: i};
  final heads = all.where((e) => _isHead(e, maxLen: 400)).toList();
  for (final tablo in doc.querySelectorAll('table')) {
    if (tablo.querySelector('table') != null) continue;
    final trs = tablo.querySelectorAll('tr');
    final bi = trs.indexWhere((tr) => RegExp(r'At\s*İsmi', caseSensitive: false).hasMatch(tr.text));
    if (bi < 0) continue;
    int? no;
    for (final b in heads) {
      if ((idx[b] ?? 0) < (idx[tablo] ?? 0)) {
        no = int.tryParse(RegExp(r'^\d+').firstMatch(b.text.trim())?.group(0) ?? '');
      } else {
        break;
      }
    }
    if (no != kn) continue;
    final bas = trs[bi].querySelectorAll('th,td').map((c) => _clean(c.text)).toList();
    final iIsim = bas.indexWhere((h) => RegExp(r'At\s*İsmi', caseSensitive: false).hasMatch(h));
    final iSt = bas.indexWhere((h) => RegExp(r'^St$', caseSensitive: false).hasMatch(h));
    if (iIsim < 0 || iSt < 0) return '';
    for (final tr in trs.skip(bi + 1)) {
      final td = tr.querySelectorAll('td');
      if (td.length <= iSt || td.length <= iIsim) continue;
      if (int.tryParse(td[iSt].text.trim()) == st) {
        final mN = RegExp(r'\(\s*(\d{1,2})\s*\)').firstMatch(_clean(td[iIsim].text));
        return mN?.group(1) ?? '';
      }
    }
    return '';
  }
  return '';
}


/* ---------------- Beraber koşular: atın tüm geçmiş koşu satırları ---------------- */

class AtPast {
  final String key, t, sh, pist, msf, s, j, kg, d, hp, g, tk, v;
  const AtPast({
    required this.key,
    this.t = '',
    this.sh = '',
    this.pist = '',
    this.msf = '',
    this.s = '',
    this.j = '',
    this.kg = '',
    this.d = '',
    this.hp = '',
    this.g = '',
    this.tk = '?',
    this.v = '',
  });
}

final Map<String, List<AtPast>> _pastMem = {};

final Map<String, Future<List<AtPast>>> _pastBusy = {};

/// Bu atın tüm geçmişi bellekte hazır mı?
/// Sunucudan (worker /atlar) birçok atın geçmiş sayfasını TEK istekle alıp bellek önbelleğine koyar.
/// Başarısız olursa sessizce geçer; getAtPast normal yolla çeker.
Future<void> atPastToplu(List<String> ids) async {
  return; // worker kaldırıldı; atlar tek tek (getAtPast) çekilir
  // ignore: dead_code
  final lst = [for (final id in ids) if (id.isNotEmpty && !atPastHazir(id)) id];
  if (lst.isEmpty) return;
  for (var i = 0; i < lst.length; i += 7) {
    final parca = lst.sublist(i, i + 7 > lst.length ? lst.length : i + 7);
    unawaited(_topluParca(parca));
  }
  // parçalar paralel gider; hepsinin bitmesini bekle
  await Future.wait([for (var i = 0; i < lst.length; i += 7) _topluBekle(lst.sublist(i, i + 7 > lst.length ? lst.length : i + 7))]);
}

final Map<String, Future<void>> _topluBusy = {};
Future<void> _topluBekle(List<String> p) => _topluBusy[p.join(',')] ?? Future.value();
Future<void> _topluParca(List<String> p) {
  final k = p.join(',');
  return _topluBusy[k] = () async {
    try {
      final r = await http.get(Uri.parse('https://invalid.invalid/atlar?ids=${p.join(',')}')).timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) return;
      final m = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true)) as Map;
      m.forEach((id, html) {
        if (html is String && html.length > 2000) {
          final url = 'https://www.tjk.org/TR/yarissever/Query/ConnectedPage/AtKosuBilgileri?1=1&QueryParameter_AtId=${Uri.encodeComponent('$id')}';
          _htmlCache[url] = (t: DateTime.now(), body: html);
        }
      });
    } catch (_) {}
  }();
}

bool atPastHazir(String atId) => _pastMem.containsKey(atId);

Future<List<AtPast>> getAtPast(String atId) {
  final hit = _pastMem[atId];
  if (hit != null) return Future.value(hit);
  return _pastBusy[atId] ??= _getAtPast(atId).whenComplete(() => _pastBusy.remove(atId));
}

Future<List<AtPast>> _getAtPast(String atId) async {
  final url = 'https://www.tjk.org/TR/yarissever/Query/ConnectedPage/AtKosuBilgileri?1=1&QueryParameter_AtId=${Uri.encodeComponent(atId)}';
  final html = await _fetch(url, sec: 25, retry: 1, ttl: 600, disk: 43200, fresh: false);
  final l = await compute(_atPastIso, <String>[html, atId]);
  final r = [
    for (final m in l)
      AtPast(
        key: m['key'] ?? '', t: m['t'] ?? '', sh: m['sh'] ?? '', pist: m['pist'] ?? '', msf: m['msf'] ?? '', s: m['s'] ?? '',
        j: m['j'] ?? '', kg: m['kg'] ?? '', d: m['d'] ?? '', hp: m['hp'] ?? '', g: m['g'] ?? '', tk: m['tk'] ?? '?', v: m['v'] ?? '',
      )
  ];
  _pastMem[atId] = r;
  return r;
}

List<Map<String, String>> _atPastIso(List<String> a) {
  final doc = hp.parse(a[0]);
  final atId = a[1];
  final out = <Map<String, String>>[];
  for (final tb in doc.querySelectorAll('table')) {
    if (tb.querySelector('table') != null) continue;
    final rows = tb.querySelectorAll('tr');
    final hi = rows.indexWhere((tr) {
      final t = _clean(tr.text);
      return RegExp('Tarih', caseSensitive: false).hasMatch(t) && RegExp('Derece', caseSensitive: false).hasMatch(t);
    });
    if (hi < 0) continue;
    final heads = rows[hi].querySelectorAll('th,td').map((c) => _clean(c.text).toLowerCase()).toList();
    int ix(RegExp r, [int skip = -1]) => heads.indexWhere((h) => r.hasMatch(h));
    final iT = ix(RegExp(r'^tarih'));
    final iS = heads.indexWhere((h) => h == 's' || RegExp(r'^s[ıi]ra').hasMatch(h));
    final iD = ix(RegExp(r'^derece'));
    final iH = ix(RegExp(r'hip|şehir|sehir'));
    final iM = ix(RegExp(r'msf|mesafe'));
    var iP = -1;
    for (var i = 0; i < heads.length; i++) {
      if (i != iM && RegExp(r'pist|zemin').hasMatch(heads[i])) {
        iP = i;
        break;
      }
    }
    final iJk = ix(RegExp(r'jokey'));
    final iG = ix(RegExp(r'^gny|ganyan'));
    final iK = ix(RegExp(r'^k\.?\s*no'));
    final iKg = ix(RegExp(r'siklet|^kg'));
    final iHp = ix(RegExp(r'^hp'));
    final iTk = ix(RegExp(r'tak[ıi]|ekipman'));
    if (iT < 0) continue;
    for (var i = hi + 1; i < rows.length && out.length < 40; i++) {
      final td = rows[i].querySelectorAll('td');
      if (td.length <= iT) continue;
      String g(int idx) => idx >= 0 && idx < td.length ? _clean(td[idx].text) : '';
      final tarih = g(iT);
      if (!RegExp(r'^\d{1,2}[./]\d{1,2}[./]\d{4}$').hasMatch(tarih)) continue;
      var pist = g(iP);
      if (pist.isEmpty && iM >= 0 && iM < td.length) {
        pist = td[iM].querySelector('[title]')?.attributes['title'] ?? td[iM].querySelector('img[alt]')?.attributes['alt'] ?? '';
      }
      pist = _pistAd(pist);
      final msf = g(iM).replaceAll(RegExp(r'[^\d]'), '');
      final rh = rows[i].outerHtml.replaceAll('&amp;', '&');
      final mp = RegExp(r'(?:https?:)?//video-cdn\.tjk\.org/videoftp/[^"\x27\s<>\\]+?\.mp4', caseSensitive: false).firstMatch(rh);
      final hv = RegExp(r'href\s*=\s*["\x27]([^"\x27]*YarisVideo[^"\x27]*)["\x27]', caseSensitive: false).firstMatch(rh);
      final kk = RegExp(r'KosuKodu\W{0,8}?(-?\d{3,})', caseSensitive: false).firstMatch(rh);
      var v = '';
      if (mp != null) {
        final u = mp.group(0)!;
        v = u.startsWith('//') ? 'https:$u' : u;
      } else if (hv != null) {
        final u = hv.group(1)!;
        v = u.startsWith('http') ? u : 'https://www.tjk.org${u.startsWith('/') ? '' : '/'}$u';
      } else if (kk != null) {
        final tm = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{4})$').firstMatch(tarih);
        if (tm != null) {
          final dt = DateTime(int.parse(tm.group(3)!), int.parse(tm.group(2)!), int.parse(tm.group(1)!));
          if (DateTime.now().difference(dt).inDays <= 90) {
            v = 'https://www.tjk.org/TR/YarisSever/Info/YarisVideoAt/At?AtKodu=${Uri.encodeComponent(atId)}&KosuKodu=${kk.group(1)}';
          }
        }
      }
      final kn = '${int.tryParse(g(iK)) ?? ''}';
      final key = kk != null ? 'k${kk.group(1)}' : '$tarih|${g(iH)}|$kn|$msf';
      out.add({
        'key': key,
        't': tarih,
        'sh': g(iH),
        'pist': pist,
        'msf': msf,
        's': g(iS).replaceAll(RegExp(r'[^\d]'), ''),
        'j': g(iJk),
        'kg': g(iKg),
        'd': g(iD),
        'hp': g(iHp),
        'g': g(iG).replaceAll(RegExp(r'[^\d.,]'), ''),
        'tk': iTk >= 0 && iTk < td.length ? _takiCikar(td[iTk], '', null).map((e) => e.k).join(',') : '?',
        'v': v,
      });
    }
    break;
  }
  return out;
}
