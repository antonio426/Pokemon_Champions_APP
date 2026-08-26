import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const DEX_PATH = fileURLToPath(new URL('../data/pokedex.json', import.meta.url));
const POOL_PATH = fileURLToPath(new URL('../data/pool.json', import.meta.url));

if (!existsSync(DEX_PATH)) {
  throw new Error('找不到 data/pokedex.json，請先執行：npm run fetch');
}

const dex = JSON.parse(readFileSync(DEX_PATH, 'utf8'));

/** 所有形態，含地區形態與 Mega。 */
export const ENTRIES = Object.freeze(dex.entries);
export const GENERATED_AT = dex.generatedAt;

/**
 * OCR 出來的字串不會乾淨：可能夾帶等級、性別符號、全形空白、殘缺的括號。
 * 正規化只保留 CJK 與英數，讓比對不被雜訊拖累。
 */
export function normalize(text) {
  return String(text ?? '')
    .normalize('NFKC')
    .replace(/[Ll][Vv]\.?\s*\d+/g, '')
    .replace(/[♂♀]/g, '')
    // 保留漢字、假名、拉丁字母與數字；標點、符號、空白一律丟掉。
    // 長音符號 ー 屬於 Script=Common，得單獨列進來，否則片假名名稱會被切壞。
    .replace(/[^\p{Script=Han}\p{Script=Katakana}\p{Script=Hiragana}\p{Script=Latin}\p{Nd}ー]/gu, '')
    .toLowerCase();
}

const byId = new Map();
const byExact = new Map(); // 正規化後字串 → 條目陣列

function addKey(map, key, entry) {
  if (!key) return;
  const list = map.get(key);
  if (list) list.push(entry);
  else map.set(key, [entry]);
}

for (const e of ENTRIES) {
  byId.set(e.id, e);
  addKey(byExact, normalize(e.zh), e);
  addKey(byExact, normalize(e.zhBase), e);
  addKey(byExact, normalize(e.en), e);
  addKey(byExact, normalize(e.slug), e);
  addKey(byExact, normalize(e.ja), e);
}

/** 依內部代號取單筆。 */
export function byPokemonId(id) {
  return byId.get(Number(id)) ?? null;
}

/**
 * 賽季可用清單。存在 data/pool.json 時自動載入，用來把比對範圍從
 * 一千多筆縮到幾百筆 —— 這是規劃書裡提高辨識準確率的主要手段。
 * 格式：{ "name": "...", "ids": [25, 6, ...] } 或 { "names": ["皮卡丘", ...] }
 */
let activePool = null;

export function loadPoolFile(file = POOL_PATH) {
  if (!existsSync(file)) return null;
  const cfg = JSON.parse(readFileSync(file, 'utf8'));
  setPool(cfg.ids ?? cfg.names ?? [], cfg.name);
  return activePool;
}

export function setPool(members, name = 'custom') {
  if (!members || members.length === 0) {
    activePool = null;
    return null;
  }
  const set = new Set();
  for (const m of members) {
    if (typeof m === 'number') {
      if (byId.has(m)) set.add(byId.get(m));
      continue;
    }
    for (const e of byExact.get(normalize(m)) ?? []) set.add(e);
  }
  activePool = { name, entries: [...set] };
  return activePool;
}

export function getPool() {
  return activePool;
}

export function clearPool() {
  activePool = null;
}

function candidates() {
  return activePool ? activePool.entries : ENTRIES;
}

/** 上限式編輯距離：超過 max 就提早收手，掃全圖鑑時省下大量無用計算。 */
function editDistance(a, b, max) {
  const al = a.length;
  const bl = b.length;
  if (Math.abs(al - bl) > max) return max + 1;
  let prev = new Uint16Array(bl + 1);
  let curr = new Uint16Array(bl + 1);
  for (let j = 0; j <= bl; j++) prev[j] = j;
  for (let i = 1; i <= al; i++) {
    curr[0] = i;
    let rowMin = curr[0];
    const ca = a.charCodeAt(i - 1);
    for (let j = 1; j <= bl; j++) {
      const cost = ca === b.charCodeAt(j - 1) ? 0 : 1;
      curr[j] = Math.min(curr[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost);
      if (curr[j] < rowMin) rowMin = curr[j];
    }
    if (rowMin > max) return max + 1;
    [prev, curr] = [curr, prev];
  }
  return prev[bl];
}

/**
 * 同一隻寶可夢在圖鑑裡常有多筆「戰鬥上等價」的條目（皮卡丘的各種帽子、
 * 屬性與本體相同的 Mega）。對屬性剋制而言牠們是同一個東西，收斂成一筆，
 * 並優先保留預設形態的名稱，避免結果被裝飾性形態洗版。
 */
function battleKey(entry) {
  return `${entry.speciesId}|${entry.types.join('/')}`;
}

function preferDefault(a, b) {
  if (a.isDefault !== b.isDefault) return a.isDefault ? -1 : 1;
  return a.id - b.id;
}

function collapse(results, limit) {
  const best = new Map();
  for (const r of results) {
    const key = battleKey(r.entry);
    const prev = best.get(key);
    if (!prev || r.score > prev.score || (r.score === prev.score && preferDefault(r.entry, prev.entry) < 0)) {
      best.set(key, r);
    }
  }
  return [...best.values()]
    .sort((a, b) => b.score - a.score || preferDefault(a.entry, b.entry))
    .slice(0, limit);
}

/**
 * 把一段（可能有錯字的）文字解析成寶可夢。
 * 先試精確命中，不中再做模糊比對。
 *
 * @returns {{entry, score, matched, exact}[]} 依分數由高到低
 */
export function resolve(text, { limit = 5, minScore = 0.5 } = {}) {
  const q = normalize(text);
  if (!q) return [];

  const pool = candidates();
  const inPool = activePool ? new Set(pool) : null;

  const exact = (byExact.get(q) ?? []).filter((e) => !inPool || inPool.has(e));
  if (exact.length > 0) {
    return collapse(
      exact.map((entry) => ({ entry, score: 1, matched: q, exact: true })),
      limit
    );
  }

  const scored = [];
  for (const e of pool) {
    for (const key of [e.zh, e.zhBase, e.en, e.ja]) {
      const k = normalize(key);
      if (!k) continue;
      const max = Math.max(1, Math.ceil(Math.max(k.length, q.length) * (1 - minScore)));
      const d = editDistance(q, k, max);
      if (d > max) continue;
      const score = 1 - d / Math.max(k.length, q.length);
      if (score >= minScore) scored.push({ entry: e, score, matched: k, exact: false });
    }
  }
  return collapse(scored, limit);
}

/** resolve 的單一結果版本，找不到回傳 null。 */
export function lookup(text, opts) {
  return resolve(text, { ...opts, limit: 1 })[0] ?? null;
}
