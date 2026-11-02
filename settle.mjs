// Bitmiş koşuların sonuçlarını TJK'dan çekip kuponlara (posts/*/coupon/legs[].res) yazar.
// WRITE=1 değilse sadece deneme yapar: ne yazacağını ekrana basar, veritabanına dokunmaz.
import admin from 'firebase-admin';
import * as cheerio from 'cheerio';

const WRITE = process.env.WRITE === '1';
const UA = 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Mobile Safari/537.36';

admin.initializeApp({ credential: admin.credential.cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)) });
const db = admin.firestore();

const todayIso = () => new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Istanbul' }).format(new Date());
const tjkDate = (iso) => { const [y, m, d] = iso.split('-'); return `${d}/${m}/${y}`; };
const era = (iso) => (iso < todayIso() ? 'yesterday' : 'today');
const clean = (s) => String(s || '').replace(/\s+/g, ' ').trim();
const key = (s) => String(s || '').toUpperCase().replace(/İ/g, 'I').replace(/Ş/g, 'S').replace(/Ğ/g, 'G').replace(/Ü/g, 'U').replace(/Ö/g, 'O').replace(/Ç/g, 'C').replace(/[^A-Z0-9]/g, '');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchHtml(url) {
  let last;
  for (let i = 0; i < 4; i++) {
    try {
      const r = await fetch(url, { headers: { 'User-Agent': UA, 'Accept-Language': 'tr-TR,tr;q=0.9' }, signal: AbortSignal.timeout(30000) });
      if (r.ok) return await r.text();
      last = 'HTTP ' + r.status;
    } catch (e) {
      last = e.message;
    }
    await sleep(1500 * (i + 1));
  }
  throw new Error('TJK bağlantı hatası: ' + last);
}

async function getCities(iso) {
  const url = `https://www.tjk.org/TR/yarissever/Info/Page/GunlukYarisProgrami?QueryParameter_Tarih=${encodeURIComponent(tjkDate(iso))}&Era=${era(iso)}`;
  const $ = cheerio.load(await fetchHtml(url));
  const seen = new Set();
  const out = [];
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
    if (adi) out.push({ id: m[1], name: adi });
  });
  return out;
}

// koşu no -> geliş sırası (at numaraları). Emin olunamayan koşu atlanır.
async function getResults(city, iso) {
  const url = `https://www.tjk.org/TR/yarissever/Info/Sehir/GunlukYarisSonuclari?SehirId=${city.id}&QueryParameter_Tarih=${encodeURIComponent(tjkDate(iso))}&SehirAdi=${encodeURIComponent(city.name)}&Era=${era(iso)}`;
  const $ = cheerio.load(await fetchHtml(url));
  const out = {};
  const headRe = /^\s*(\d+)\s*\.\s*Ko[şsŞS]u/i;
  let head = null;
  let sonNo = 0;
  let logged = false;
  $('body *').each((_, el) => {
    const $el = $(el);
    if (el.tagName !== 'table') {
      if ($el.closest('table').length) return;
      if ($el.children().length <= 2) {
        const t = clean($el.text());
        if (t.length < 400) {
          const m = t.match(headRe);
          if (m) head = Number(m[1]);
        }
      }
      return;
    }
    const trs = $el.find('tr').toArray();
    const bi = trs.findIndex((tr) => /At\s*[İIi]smi/i.test($(tr).text()));
    if (bi < 0) return;
    const bas = $(trs[bi]).find('th,td').toArray().map((e) => clean($(e).text()));
    if (!logged) { console.log('  tablo başlığı:', bas.join(' | ')); logged = true; }
    let iS = bas.findIndex((h) => /^(S|Sıra|Sira)$/i.test(h));
    if (iS < 0) iS = 0;
    const iIsim = bas.findIndex((h) => /At\s*[İIi]smi/i.test(h));
    const iNo = bas.findIndex((h) => /^(St|No|Start|Numara)$/i.test(h));
    if (iIsim < 0) return;

    let no = head;
    if (no == null || out[no] !== undefined || no <= sonNo) no = sonNo + 1;
    const sira = [];
    let tamam = true;
    for (const tr of trs.slice(bi + 1)) {
      const td = $(tr).find('td').toArray();
      if (td.length <= Math.max(iS, iIsim)) continue;
      const sr = parseInt(clean($(td[iS]).text()), 10);
      if (!sr) continue;
      const nm = clean($(td[iIsim]).text()).match(/\(\s*(\d{1,2})\s*\)/);
      let atNo = nm ? Number(nm[1]) : NaN;
      if (Number.isNaN(atNo) && iNo >= 0 && td[iNo]) atNo = parseInt(clean($(td[iNo]).text()), 10);
      if (!atNo) { tamam = false; break; }
      sira.push({ sr, no: atNo });
    }
    sonNo = no;
    if (!tamam || sira.length < 2) { console.log(`  ${no}. koşu: at numarası okunamadı, atlandı`); return; }
    sira.sort((a, b) => a.sr - b.sr);
    const nums = sira.map((x) => x.no);
    if (sira[0].sr !== 1 || new Set(nums).size !== nums.length || nums.some((n) => n < 1 || n > 30)) {
      console.log(`  ${no}. koşu: sonuç tutarsız, atlandı`);
      return;
    }
    out[no] = nums;
  });
  return out;
}

const today = todayIso();
const snap = await db.collection('posts').orderBy('ts', 'desc').limit(300).get();
const groups = new Map();
for (const doc of snap.docs) {
  const c = doc.data().coupon;
  if (!c || typeof c !== 'object' || !Array.isArray(c.legs)) continue;
  const bekler = c.legs.some((l) => l && !Array.isArray(l.res) && typeof l.win !== 'number');
  const iso = String(c.iso || '');
  const city = String(c.city || '');
  if (!bekler || !iso || !city || iso > today) continue;
  const k = `${iso}|${city}`;
  if (!groups.has(k)) groups.set(k, []);
  groups.get(k).push(doc);
}
console.log(`Mod: ${WRITE ? 'YAZMA AÇIK' : 'DENEME (veritabanına yazılmaz)'} · bekleyen grup: ${groups.size}`);

const citiesCache = {};
let yazilan = 0;
for (const [k, docs] of groups) {
  const [iso, cityName] = k.split('|');
  try {
    citiesCache[iso] ??= await getCities(iso);
    const cs = citiesCache[iso];
    const city = cs.find((x) => x.name === cityName) || cs.find((x) => key(x.name) === key(cityName)) || cs.find((x) => key(x.name).startsWith(key(cityName)));
    if (!city) { console.log(`${k}: şehir bulunamadı`); continue; }
    console.log(`${k}:`);
    const res = await getResults(city, iso);
    for (const [r, order] of Object.entries(res)) console.log(`  ${r}. koşu geliş sırası: ${order.join('-')}`);
    for (const doc of docs) {
      const c = doc.data().coupon;
      const legs = c.legs.map((l) => ({ ...l }));
      const yazilacak = [];
      for (const l of legs) {
        const r = Number(l.r);
        if (!l || Array.isArray(l.res) || typeof l.win === 'number' || !Number.isFinite(r) || !res[r]) continue;
        l.res = res[r];
        yazilacak.push(r);
      }
      if (!yazilacak.length) continue;
      console.log(`  kupon ${doc.id}: ${yazilacak.join(',')}. koşu(lar) ${WRITE ? 'yazılıyor' : 'yazılırdı'}`);
      if (WRITE) { await doc.ref.update({ 'coupon.legs': legs }); yazilan++; }
    }
  } catch (e) {
    console.log(`${k}: hata: ${e.message}`);
  }
}
console.log(`Bitti. Yazılan kupon: ${yazilan}`);
process.exit(0);
