// "Beraber koşular", "son yarış / son galibiyet" ve "son galop" için veriyi önceden hazırlar ve Firestore'a (beraber/{tarih}_{şehirId}_{koşuNo}) yazar.
// Uygulama bu hazır belgeyi tek okumayla alır; hazır değilse eski yöntemle (telefonda) hesaplar.
// Çalıştırma: node beraber-prep.mjs   (DRY=1 ise veritabanına yazmaz, sadece ne yazacağını basar)
import admin from 'firebase-admin';
import * as cheerio from 'cheerio';
import { createHash } from 'node:crypto';

const DRY = process.env.DRY === '1';
const UA = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36';

admin.initializeApp({ credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)) });
const db = admin.firestore();

const todayIso = () => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Istanbul' }).format(new Date());
const addDays = (iso, n) => {
  const [y, m, d] = iso.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return t.toISOString().slice(0, 10);
};
const tjkDate = (iso) => { const [y, m, d] = iso.split('-'); return `${d}/${m}/${y}`; };
const era = (iso) => (iso < todayIso() ? 'yesterday' : 'today');
const clean = (s) => String(s || '').replace(/ /g, ' ').replace(/\s+/g, ' ').trim();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchHtml(url, tries = 4) {
  let last;
  for (let i = 0; i < tries; i++) {
    try {
      const r = await fetch(url, { headers: { 'User-Agent': UA, 'Accept-Language': 'tr-TR,tr;q=0.9' }, signal: AbortSignal.timeout(30000) });
      if (r.ok) return await r.text();
      last = 'HTTP ' + r.status;
    } catch (e) {
      last = e.message;
    }
    if (i < tries - 1) await sleep(1500 * (i + 1));
  }
  throw new Error('TJK bağlantı hatası: ' + last);
}

/* ---------- Şehirler (uygulamadaki getCities ile aynı mantık) ---------- */
const YERLI = new Set(['ISTANBUL', 'ANKARA', 'IZMIR', 'BURSA', 'ADANA', 'SANLIURFA', 'ELAZIG', 'DIYARBAKIR', 'KOCAELI', 'IZMIT', 'ANTALYA', 'KARMA']);
const norm = (s) => String(s || '').toUpperCase().replace(/İ/g, 'I').replace(/Ğ/g, 'G').replace(/Ü/g, 'U').replace(/Ş/g, 'S').replace(/Ö/g, 'O').replace(/Ç/g, 'C');
const keyOf = (s) => norm(s).replace(/[^A-Z0-9]/g, '');

async function getCities(iso) {
  const url = `https://www.tjk.org/TR/yarissever/Info/Page/GunlukYarisProgrami?QueryParameter_Tarih=${encodeURIComponent(tjkDate(iso))}&Era=${era(iso)}`;
  const $ = cheerio.load(await fetchHtml(url));
  const seen = new Set();
  const list = [];
  $('a[href]').each((_, a) => {
    const href = $(a).attr('href') || '';
    if (!/GunlukYarisProgrami/i.test(href)) return;
    const m = href.match(/[?&]SehirId=(\d+)/i);
    if (!m || seen.has(m[1])) return;
    seen.add(m[1]);
    const ma = href.match(/[?&]SehirAdi=([^&]+)/i);
    let adi = '';
    if (ma) {
      try { adi = decodeURIComponent(ma[1].replace(/\+/g, ' ')); } catch { adi = ma[1]; }
    }
    adi = clean(adi || $(a).text());
    if (!adi) return;
    const first = keyOf(adi.split(' ')[0]);
    const yd = /\(YD\s*\d+\)/i.test(adi) || /\bYD\s*\d+\b/i.test($(a).text()) || (first && !YERLI.has(first));
    list.push({ id: m[1], name: adi, yd });
  });
  const yerli = list.filter((c) => !c.yd);
  return yerli.length ? yerli : list;
}

/* ---------- Program: koşular ve atlar (uygulamadaki _parseRaces/_parseHorses ile aynı mantık) ---------- */
const HEAD_RE = /^(\d+)\.\s*Koşu\s+(\d{1,2})[:.](\d{2})/;

function parseHorses($, table) {
  const rows = $(table).find('tr').toArray();
  if (rows.length < 2) return [];
  let bi = rows.findIndex((tr) => /At\s*İsmi/i.test($(tr).text()) && /Jokey/i.test($(tr).text()));
  if (bi < 0) bi = 0;
  const heads = $(rows[bi]).find('th,td').toArray().map((e) => $(e).text().trim());
  const exact = (k) => { const i = heads.findIndex((h) => clean(h) === k); return i >= 0 ? i : null; };
  const col = (k) => { const i = heads.findIndex((h) => clean(h).toLowerCase().includes(k.toLowerCase())); return i >= 0 ? i : null; };
  const iN = exact('N') ?? col('N');
  const iIsim = col('At İsmi');
  const iIdm = col('İdm') ?? col('Idm');
  const out = [];
  for (let i = bi + 1; i < rows.length; i++) {
    const tds = $(rows[i]).find('td').toArray();
    if (tds.length < 4) continue;
    const al = (idx) => (idx != null && idx < tds.length ? $(tds[idx]).text().trim() : null);
    const isimHam = al(iIsim);
    if (!isimHam) continue;
    const row = $(rows[i]);
    const classes = (row.attr('class') || '') + row.find('[class]').toArray().map((e) => $(e).attr('class') || '').join('');
    const kosmaz =
      /ko[sş]maz|kosmaz|cekil|çekil|iptal|withdraw|scratch/i.test(classes) ||
      /\(\s*K\s*\)/.test(isimHam) ||
      /\bko[şs]maz\b/i.test(row.text()) ||
      row.find('s, strike, del, [style*="line-through"]').length > 0 ||
      ($.html(rows[i]) || '').includes('line-through');
    const no = parseInt((al(iN) || '').replace(/[^0-9]/g, ''), 10);
    if (!Number.isFinite(no)) continue;
    const isim = isimHam.split('\n')[0].replace(/\s{2,}.*$/, '').trim();
    const cell = iIsim != null && iIsim < tds.length ? $(tds[iIsim]) : null;
    const href = cell?.find('a').first().attr('href') || '';
    const atId = (href.match(/AtId=(\d+)/i) || [])[1] || '';
    // İdman videosu bağlantısı (uygulamadaki idmHref ile aynı)
    let idm = '';
    if (iIdm != null && iIdm < tds.length) {
      const hc = $(tds[iIdm]);
      for (const el of [tds[iIdm], ...hc.find('*').toArray()]) {
        const v = Object.values(el.attribs || {}).join(' ');
        if (/KosuKodu=(-?\d+)/i.test(v) && /Atkodu=(\d+)/i.test(v)) {
          const hh = $(el).attr('href') || '';
          if (hh) idm = hh.startsWith('http') ? hh : 'https://www.tjk.org' + (hh.startsWith('/') ? '' : '/') + hh;
          break;
        }
      }
    }
    out.push({ no, name: isim || isimHam.slice(0, 40), atId, kosmaz, idm });
  }
  return out;
}

async function getProgram(city, iso) {
  const url = `https://www.tjk.org/TR/yarissever/Info/Sehir/GunlukYarisProgrami?SehirId=${city.id}&QueryParameter_Tarih=${encodeURIComponent(tjkDate(iso))}&SehirAdi=${encodeURIComponent(city.name)}&Era=${era(iso)}`;
  const $ = cheerio.load(await fetchHtml(url));
  const all = $('body *').toArray();
  const idx = new Map(all.map((e, i) => [e, i]));
  const heads = all.filter((e) => {
    if ($(e).children().length > 2) return false;
    const t = $(e).text().trim();
    return t.length < 60 && HEAD_RE.test(t);
  });
  const tables = $('table').toArray();
  const cand = new Map();
  heads.forEach((he, h) => {
    const no = parseInt($(he).text().trim().match(HEAD_RE)[1], 10);
    const start = idx.get(he);
    const end = h + 1 < heads.length ? idx.get(heads[h + 1]) : all.length;
    const tablo = tables.find((t) => { const ti = idx.get(t); return ti != null && ti > start && ti < end; });
    const atlar = tablo ? parseHorses($, tablo) : [];
    if (!cand.has(no)) cand.set(no, []);
    cand.get(no).push(atlar);
  });
  const races = [];
  for (const no of [...cand.keys()].sort((a, b) => a - b)) {
    const c = cand.get(no);
    let pick = c[c.length - 1];
    for (let i = c.length - 1; i >= 0; i--) if (c[i].length) { pick = c[i]; break; }
    if (pick.length) races.push({ no, atlar: pick });
  }
  return races;
}

/* ---------- Atın geçmiş koşuları (uygulamadaki _atPastIso ile aynı mantık) ---------- */
const pistAd = (p) => {
  const t = String(p || '').trim();
  if (/^K$/i.test(t)) return 'Kum';
  if (/^[ÇC]$/i.test(t)) return 'Çim';
  if (/^S$/i.test(t)) return 'Sentetik';
  return t;
};
const TAKI_KOD = /^[A-ZÇĞİÖŞÜ]{1,4}$/;
const DATE_RE = /^(\d{1,2})[./](\d{1,2})[./](\d{4})$/;

function parsePast(html, atId) {
  const $ = cheerio.load(html);
  const out = [];
  for (const tb of $('table').toArray()) {
    if ($(tb).find('table').length) continue;
    const rows = $(tb).find('tr').toArray();
    const hi = rows.findIndex((tr) => { const t = clean($(tr).text()); return /Tarih/i.test(t) && /Derece/i.test(t); });
    if (hi < 0) continue;
    const heads = $(rows[hi]).find('th,td').toArray().map((c) => clean($(c).text()).toLowerCase());
    const ix = (re) => heads.findIndex((h) => re.test(h));
    const iT = ix(/^tarih/);
    const iS = heads.findIndex((h) => h === 's' || /^s[ıi]ra/.test(h));
    const iD = ix(/^derece/);
    const iH = ix(/hip|şehir|sehir/);
    const iM = ix(/msf|mesafe/);
    let iP = -1;
    for (let i = 0; i < heads.length; i++) if (i !== iM && /pist|zemin/.test(heads[i])) { iP = i; break; }
    const iJk = ix(/jokey/);
    const iG = ix(/^gny|ganyan/);
    const iK = ix(/^k\.?\s*no/);
    const iKg = ix(/siklet|^kg/);
    const iHp = ix(/^hp/);
    const iTk = ix(/tak[ıi]|ekipman/);
    if (iT < 0) continue;
    for (let i = hi + 1; i < rows.length && out.length < 40; i++) {
      const td = $(rows[i]).find('td').toArray();
      if (td.length <= iT) continue;
      const g = (idx) => (idx >= 0 && idx < td.length ? clean($(td[idx]).text()) : '');
      const tarih = g(iT);
      if (!DATE_RE.test(tarih)) continue;
      let pist = g(iP);
      if (!pist && iM >= 0 && iM < td.length) {
        pist = $(td[iM]).find('[title]').first().attr('title') || $(td[iM]).find('img[alt]').first().attr('alt') || '';
      }
      pist = pistAd(pist);
      const msf = g(iM).replace(/[^\d]/g, '');
      const rh = ($.html(rows[i]) || '').replace(/&amp;/g, '&');
      const mp = rh.match(/(?:https?:)?\/\/video-cdn\.tjk\.org\/videoftp\/[^"'\s<>\\]+?\.mp4/i);
      const hv = rh.match(/href\s*=\s*["']([^"']*YarisVideo[^"']*)["']/i);
      const kk = rh.match(/KosuKodu\W{0,8}?(-?\d{3,})/i);
      let v = '';
      if (mp) {
        v = mp[0].startsWith('//') ? 'https:' + mp[0] : mp[0];
      } else if (hv) {
        const u = hv[1];
        v = u.startsWith('http') ? u : 'https://www.tjk.org' + (u.startsWith('/') ? '' : '/') + u;
      } else if (kk) {
        const tm = tarih.match(DATE_RE);
        const dt = new Date(+tm[3], +tm[2] - 1, +tm[1]);
        if ((Date.now() - dt.getTime()) / 86400000 <= 90) {
          v = `https://www.tjk.org/TR/YarisSever/Info/YarisVideoAt/At?AtKodu=${encodeURIComponent(atId)}&KosuKodu=${kk[1]}`;
        }
      }
      const kn = String(parseInt(g(iK), 10) || '');
      const key = kk ? 'k' + kk[1] : `${tarih}|${g(iH)}|${kn}|${msf}`;
      const tk = iTk >= 0 && iTk < td.length
        ? clean($(td[iTk]).text()).split(/[\s,;/]+/).filter((w) => TAKI_KOD.test(w)).join(',')
        : '?';
      out.push({
        key, t: tarih, sh: g(iH), pist, msf,
        s: g(iS).replace(/[^\d]/g, ''), j: g(iJk), kg: g(iKg), d: g(iD), hp: g(iHp),
        g: g(iG).replace(/[^\d.,]/g, ''), tk, v,
      });
    }
    break;
  }
  return out;
}

/* ---------- Son yarış / son galibiyet (uygulamadaki _atHistIso ile aynı mantık) ---------- */
function parseHist(html, atId) {
  const $ = cheerio.load(html);
  const out = { yaris: null, gal: null };
  for (const tb of $('table').toArray()) {
    if ($(tb).find('table').length) continue;
    const rows = $(tb).find('tr').toArray();
    const hi = rows.findIndex((tr) => { const t = clean($(tr).text()); return /Tarih/i.test(t) && /Derece/i.test(t); });
    if (hi < 0) continue;
    const heads = $(rows[hi]).find('th,td').toArray().map((c) => clean($(c).text()).toLowerCase());
    const iT = heads.findIndex((h) => h.startsWith('tarih'));
    const iS = heads.findIndex((h) => h === 's' || /^s[ıi]ra/.test(h));
    const iD = heads.findIndex((h) => h.startsWith('derece'));
    const iH = heads.findIndex((h) => /hip|şehir|sehir/.test(h));
    const iM = heads.findIndex((h) => /msf|mesafe/.test(h));
    let iP = -1;
    for (let i = 0; i < heads.length; i++) if (i !== iM && /pist|zemin/.test(heads[i])) { iP = i; break; }
    const iJk = heads.findIndex((h) => h.includes('jokey'));
    const iC = heads.findIndex((h) => /cins|grup|grub/.test(h));
    const iG = heads.findIndex((h) => /^gny|ganyan/.test(h));
    const iSt = heads.findIndex((h) => h.replace(/[^a-zçğıöşü]/g, '') === 'st');
    const iK = heads.findIndex((h) => /^k\.?\s*no/.test(h));
    const iTk = heads.findIndex((h) => /tak[ıi]|ekipman/.test(h));
    if (iT < 0) continue;
    for (let i = hi + 1; i < rows.length; i++) {
      const td = $(rows[i]).find('td').toArray();
      if (td.length <= iT) continue;
      const g = (idx) => (idx >= 0 && idx < td.length ? clean($(td[idx]).text()) : '');
      if (!DATE_RE.test(g(iT))) continue;
      let pist = g(iP);
      if (!pist && iM >= 0 && iM < td.length) {
        pist = $(td[iM]).find('[title]').first().attr('title') || $(td[iM]).find('img[alt]').first().attr('alt') || '';
      }
      pist = pistAd(pist);
      const msf = g(iM).replace(/[^\d]/g, '');
      const rh = ($.html(rows[i]) || '').replace(/&amp;/g, '&');
      const mp = rh.match(/(?:https?:)?\/\/video-cdn\.tjk\.org\/videoftp\/[^"'\s<>\\]+?\.mp4/i);
      const hv = rh.match(/href\s*=\s*["']([^"']*YarisVideo[^"']*)["']/i);
      const kk = rh.match(/KosuKodu\W{0,8}?(-?\d{3,})/i);
      const video = (tarih) => {
        if (mp) return mp[0].startsWith('//') ? 'https:' + mp[0] : mp[0];
        if (hv) { const u = hv[1]; return u.startsWith('http') ? u : 'https://www.tjk.org' + (u.startsWith('/') ? '' : '/') + u; }
        if (kk) {
          const tm = tarih.match(DATE_RE);
          if (tm && (Date.now() - new Date(+tm[3], +tm[2] - 1, +tm[1]).getTime()) / 86400000 <= 90) {
            return `https://www.tjk.org/TR/YarisSever/Info/YarisVideoAt/At?AtKodu=${encodeURIComponent(atId)}&KosuKodu=${kk[1]}`;
          }
        }
        return '';
      };
      const kn = String(parseInt(g(iK), 10) || '');
      if (!out.yaris) {
        out.yaris = {
          t: g(iT),
          d: [pist, msf ? msf + 'm' : ''].filter(Boolean).join(' · '),
          y: [g(iH), g(iT)].filter(Boolean).join(' · '),
          st: g(iSt).replace(/[^\d]/g, ''),
          sh: g(iH), kn, v: video(g(iT)),
          tk: iTk >= 0 && iTk < td.length ? clean($(td[iTk]).text()).split(/[\s,;/]+/).filter((w) => TAKI_KOD.test(w)).join(',') : '?',
        };
      }
      if (!out.gal && iS >= 0 && /^1\b/.test(g(iS))) {
        const gny = g(iG).replace(/[^\d.,]/g, '');
        out.gal = {
          t: g(iT), d: g(iD),
          y: [g(iH), msf, pist].filter(Boolean).join(' · '),
          k: [g(iC), g(iJk), gny ? 'Gny ' + gny : ''].filter(Boolean).join(' · '),
          no: g(iSt).replace(/[^\d]/g, ''),
          sh: g(iH), kn, v: video(g(iT)),
        };
      }
      if (out.yaris && (out.gal || iS < 0)) break;
    }
    break;
  }
  return out;
}

/* ---------- Son galop (uygulamadaki _galopIso ile aynı mantık) ---------- */
const trLower = (s) => String(s).replace(/İ/g, 'i').replace(/I/g, 'ı').toLowerCase();

function parseGalop(html) {
  const $ = cheerio.load(html);
  const n = (s) => trLower(clean(s));
  const ts = (t) => { const m = t.match(/(\d{1,2})[./](\d{1,2})[./](\d{4})/); return m ? new Date(+m[3], +m[2] - 1, +m[1]).getTime() : 0; };
  let rs = null, hi = -1;
  for (const t of $('table').toArray()) {
    if ($(t).find('table').length) continue;
    const tr = $(t).find('tr').toArray();
    for (let i = 0; i < tr.length && i < 3; i++) {
      const b = n($(tr[i]).text());
      if (b.includes('at adı') && b.includes('i. tarihi') && b.includes('pist') && b.includes('i. türü')) { rs = tr; hi = i; break; }
    }
    if (rs) break;
  }
  if (!rs) return { err: 'İdman tablosu yok' };
  const h = $(rs[hi]).find('th,td').toArray().map((c) => n($(c).text()));
  const ix = (a) => h.findIndex((x) => x.includes(a));
  const iT = ix('i. tarihi'), iP = ix('pist'), iK = ix('i. türü'), iJ = ix('i. jokeyi'), iH = ix('i. hip');
  const mes = [1400, 1200, 1000, 800, 600, 400, 200].map((m) => [m, h.findIndex((x) => x.replace(/[^\dm]/g, '') === m + 'm')]);
  let best = null, bt = 0;
  for (let i = hi + 1; i < rs.length; i++) {
    const td = $(rs[i]).find('td').toArray();
    if (td.length < 5 || td.length <= iT) continue;
    if (iK >= 0 && iK < td.length && !/galop|sprint/i.test(n($(td[iK]).text()))) continue;
    const t = ts(n($(td[iT]).text()));
    if (t > bt) { bt = t; best = td; }
  }
  if (!best) return null;
  const g = (j) => (j >= 0 && j < best.length ? clean($(best[j]).text()) : '');
  const pistH = g(iP) ? g(iP).substring(0, 1).toUpperCase() : '';
  const pist = pistH === 'Ç' ? 'Çim' : pistH === 'K' ? 'Kum' : pistH === 'S' ? 'Sentetik' : '';
  const det = [];
  for (const [m, j] of mes) { const v = g(j); if (v && v !== '-') det.push(`${m}m ${v}`); }
  return { t: g(iT), d: det.slice(0, 4).join(' · '), y: [g(iH), pist, g(iJ)].filter(Boolean).join(' · ') };
}

/* ---------- Video sayfasından mp4 adresi (uygulamadaki getVideoMp4 ile aynı) ---------- */
const mp4Cache = new Map();
function resolveMp4(url) {
  if (!url) return Promise.resolve('');
  if (/\.mp4(\?|$)/i.test(url)) return Promise.resolve(url.startsWith('//') ? 'https:' + url : url);
  if (mp4Cache.has(url)) return mp4Cache.get(url);
  const p = (async () => {
    try {
      const h = await fetchHtml(url, 2);
      const m = h.match(/(?:https?:)?\/\/video-cdn\.tjk\.org\/videoftp\/[^"\s<>\\]+?\.mp4/i) || h.match(/videoftp\/\d{4}\/\d{2}\/[\w-]+\.mp4/i);
      if (!m) return '';
      let u = m[0];
      if (u.startsWith('//')) u = 'https:' + u;
      else if (!/^https?:/i.test(u)) u = 'https://video-cdn.tjk.org/' + u;
      return u;
    } catch { return ''; }
  })();
  mp4Cache.set(url, p);
  return p;
}

const galopCache = new Map();
function getGalop(atId) {
  if (galopCache.has(atId)) return galopCache.get(atId);
  const id = encodeURIComponent(atId);
  const urls = [
    `https://www.tjk.org/TR/YarisSever/Query/Page/IdmanIstatistikleri?QueryParameter_AtId=${id}`,
    `https://www.tjk.org/TR/yarissever/Query/ConnectedPage/AtIdmanBilgileri?1=1&QueryParameter_AtId=${id}`,
    `https://www.tjk.org/TR/yarissever/Query/ConnectedPage/IdmanIstatistikleri?1=1&QueryParameter_AtId=${id}`,
  ];
  const p = (async () => {
    let last;
    for (const u of urls) {
      try {
        const m = parseGalop(await fetchHtml(u));
        if (m && m.err) { last = m.err; continue; }
        return m; // null = kayıt yok
      } catch (e) { last = e.message; }
    }
    throw new Error(String(last));
  })();
  galopCache.set(atId, p);
  return p;
}

const pastCache = new Map();
async function getPast(atId) {
  if (pastCache.has(atId)) return pastCache.get(atId);
  const url = `https://www.tjk.org/TR/yarissever/Query/ConnectedPage/AtKosuBilgileri?1=1&QueryParameter_AtId=${encodeURIComponent(atId)}`;
  // Aynı sayfadan hem geçmiş koşular hem son yarış/galibiyet çıkar (tek indirme)
  const p = fetchHtml(url).then((h) => ({ rows: parsePast(h, atId), hist: parseHist(h, atId) }));
  pastCache.set(atId, p);
  return p;
}

/* ---------- Gruplama (uygulamadaki _build ile aynı) ---------- */
const dateOf = (t) => { const m = t.match(DATE_RE); return m ? new Date(+m[3], +m[2] - 1, +m[1]).getTime() : 0; };

function build(horses, pasts) {
  const by = new Map();
  horses.forEach((h, i) => {
    for (const p of pasts[i]) if (p.key) { if (!by.has(p.key)) by.set(p.key, []); by.get(p.key).push({ id: h.atId, p }); }
  });
  const groups = [];
  for (const [key, rows] of by) {
    if (new Set(rows.map((r) => r.id)).size < 2) continue;
    rows.sort((a, b) => (parseInt(a.p.s, 10) || 99) - (parseInt(b.p.s, 10) || 99));
    groups.push({ key, t: rows[0].p.t, rows: rows.map((r) => ({ id: r.id, ...r.p })) });
  }
  groups.sort((a, b) => dateOf(b.t) - dateOf(a.t));
  return groups.slice(0, 12).map(({ key, rows }) => ({ key, rows }));
}

async function pool(items, n, fn) {
  let next = 0;
  await Promise.all(Array.from({ length: n }, async () => {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      await fn(items[i], i);
      await sleep(100);
    }
  }));
}

async function doDay(iso) {
  let cities;
  try { cities = await getCities(iso); } catch (e) { console.log(iso, 'şehirler alınamadı:', e.message); return; }
  console.log(iso, 'şehirler:', cities.map((c) => c.name).join(', ') || '-');
  const jobs = [];
  for (const c of cities) {
    let races = [];
    try { races = await getProgram(c, iso); } catch (e) { console.log(c.name, 'program alınamadı:', e.message); continue; }
    for (const r of races) jobs.push({ c, r, horses: r.atlar.filter((h) => !h.kosmaz && h.atId) });
  }
  const ids = [...new Set(jobs.flatMap((j) => j.horses.map((h) => h.atId)))];
  console.log(iso, 'koşu:', jobs.length, 'at:', ids.length);
  const failed = new Set();
  await pool(ids, 6, async (id) => { try { await getPast(id); } catch { failed.add(id); } });
  // Son galop: ayrı sayfa; alınamayan atın galopu belgeye yazılmaz (uygulama kendisi çeker)
  const galopFail = new Set();
  await pool(ids, 6, async (id) => { try { await getGalop(id); } catch { galopFail.add(id); } });
  // Videolar: son yarış / son galibiyet / idman bağlantılarının mp4 adresi (oynatırken TJK'ya gitmesin)
  const vids = new Set();
  for (const j of jobs) for (const h of j.horses) {
    if (h.idm) vids.add(h.idm);
    if (failed.has(h.atId)) continue;
    try { const r = await getPast(h.atId); if (r.hist.yaris?.v) vids.add(r.hist.yaris.v); if (r.hist.gal?.v) vids.add(r.hist.gal.v); } catch {}
  }
  await pool([...vids], 6, async (u) => { await resolveMp4(u); });
  console.log(iso, 'video bağlantısı:', vids.size);
  let yazilan = 0, atlanan = 0, eksik = 0;
  for (const j of jobs) {
    if (j.horses.length < 2) continue;
    if (j.horses.some((h) => failed.has(h.atId))) { eksik++; continue; }
    const res = await Promise.all(j.horses.map((h) => getPast(h.atId)));
    const pasts = res.map((r) => r.rows);
    const groups = build(j.horses, pasts);
    const atlar = {};
    for (let i = 0; i < j.horses.length; i++) {
      const id = j.horses[i].atId;
      const yy = res[i].hist.yaris, gg = res[i].hist.gal;
      const e = {
        y: yy ? { ...yy, m: await resolveMp4(yy.v) } : null,
        g: gg ? { ...gg, m: await resolveMp4(gg.v) } : null,
      };
      if (j.horses[i].idm) e.idm = { u: j.horses[i].idm, m: await resolveMp4(j.horses[i].idm) };
      if (!galopFail.has(id)) e.gl = (await getGalop(id)) ?? null;
      atlar[id] = e;
    }
    const sig = createHash('md5').update(JSON.stringify({ groups, atlar })).digest('hex');
    const ref = db.collection('beraber').doc(`${iso}_${j.c.id}_${j.r.no}`);
    if (!DRY) {
      const old = await ref.get();
      if (old.exists && old.data().sig === sig) { atlanan++; continue; }
      await ref.set({ iso, city: j.c.name, cityId: j.c.id, no: j.r.no, sig, groups, atlar, ts: admin.firestore.FieldValue.serverTimestamp() });
    } else {
      console.log(`  ${j.c.name} ${j.r.no}. koşu: ${j.horses.length} at, ${groups.length} ortak koşu`);
    }
    yazilan++;
  }
  console.log(iso, `bitti. yazılan: ${yazilan}, değişmeyen: ${atlanan}, eksik (sonra tekrar): ${eksik}`);
}

const today = todayIso();
for (const iso of [today, addDays(today, 1)]) await doDay(iso);

// 7 günden eski belgeleri sil (veritabanı şişmesin)
if (!DRY) {
  try {
    const cut = addDays(today, -7);
    const old = await db.collection('beraber').where('iso', '<', cut).limit(400).get();
    const b = db.batch();
    old.docs.forEach((d) => b.delete(d.ref));
    if (!old.empty) await b.commit();
    console.log('silinen eski belge:', old.size);
  } catch (e) {
    console.log('temizlik atlandı:', e.message);
  }
}
process.exit(0);
