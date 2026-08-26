import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const raw = JSON.parse(
  readFileSync(fileURLToPath(new URL('../data/types.json', import.meta.url)), 'utf8')
);

/** 18 種屬性的內部代號，順序固定，可直接當矩陣索引。 */
export const TYPES = Object.freeze(raw.order.slice());
export const TYPE_NAMES = Object.freeze(raw.names);

const INDEX = new Map(TYPES.map((t, i) => [t, i]));

/** 繁中屬性名 → 內部代號，例：'超能力' → 'psychic'。 */
const ZH_TO_TYPE = new Map(TYPES.map((t) => [raw.names[t].zh, t]));
// 常見的別名與遊戲內縮寫，OCR 讀到什麼都盡量接得住
for (const [alias, type] of Object.entries({
  普通: 'normal', 一般系: 'normal',
  火系: 'fire', 火焰: 'fire',
  水系: 'water',
  電系: 'electric', 電氣: 'electric',
  草系: 'grass',
  冰系: 'ice', 冰凍: 'ice',
  格鬥系: 'fighting', 戰鬥: 'fighting',
  毒系: 'poison',
  地面系: 'ground',
  飛行系: 'flying',
  超能: 'psychic', 超能力系: 'psychic', 念力: 'psychic',
  蟲系: 'bug', 昆蟲: 'bug',
  岩石系: 'rock', 岩: 'rock',
  幽靈系: 'ghost', 鬼: 'ghost',
  龍系: 'dragon',
  惡系: 'dark', 邪惡: 'dark',
  鋼系: 'steel',
  妖精系: 'fairy', 仙子: 'fairy',
})) ZH_TO_TYPE.set(alias, type);

/**
 * 18×18 密集倍率矩陣，MATRIX[攻][防]。
 * 開機時展開一次，之後所有查詢都是陣列索引，沒有物件走訪。
 */
const MATRIX = TYPES.map((atk) => {
  const row = new Float64Array(TYPES.length).fill(1);
  const rel = raw.chart[atk];
  for (const d of rel.super) row[INDEX.get(d)] = 2;
  for (const d of rel.notVery) row[INDEX.get(d)] = 0.5;
  for (const d of rel.immune) row[INDEX.get(d)] = 0;
  return row;
});

export function isType(t) {
  return INDEX.has(t);
}

/** 把使用者/OCR 給的字串正規化成內部代號；認不得回傳 null。 */
export function toType(input) {
  if (input == null) return null;
  const s = String(input).trim();
  if (INDEX.has(s)) return s;
  const lower = s.toLowerCase();
  if (INDEX.has(lower)) return lower;
  return ZH_TO_TYPE.get(s) ?? null;
}

export function zhName(type) {
  return TYPE_NAMES[type]?.zh ?? type;
}

function normalizeDefenders(defTypes) {
  const list = (Array.isArray(defTypes) ? defTypes : [defTypes])
    .map(toType)
    .filter(Boolean);
  if (list.length === 0) throw new TypeError('至少需要一個有效的防禦方屬性');
  if (list.length > 2) throw new TypeError('寶可夢最多只有兩種屬性');
  return [...new Set(list)];
}

/**
 * 單一招式屬性打向防禦方（單屬或雙屬）的最終倍率。
 * 回傳 0 / 0.25 / 0.5 / 1 / 2 / 4。
 */
export function effectiveness(attackType, defTypes) {
  const atk = toType(attackType);
  if (atk == null) throw new TypeError(`未知的攻擊屬性：${attackType}`);
  const row = MATRIX[INDEX.get(atk)];
  let mult = 1;
  for (const d of normalizeDefenders(defTypes)) mult *= row[INDEX.get(d)];
  return mult;
}

/**
 * 防禦面總表：這隻寶可夢被 18 種屬性打分別吃多少倍。
 * 回傳 { multipliers, x4, x2, x1, x05, x025, x0 }，各分組已依 TYPES 順序排列。
 */
export function defenseProfile(defTypes) {
  const defenders = normalizeDefenders(defTypes);
  const multipliers = {};
  const buckets = { x4: [], x2: [], x1: [], x05: [], x025: [], x0: [] };
  const bucketOf = { 4: 'x4', 2: 'x2', 1: 'x1', 0.5: 'x05', 0.25: 'x025', 0: 'x0' };
  for (const atk of TYPES) {
    const m = effectiveness(atk, defenders);
    multipliers[atk] = m;
    buckets[bucketOf[m]].push(atk);
  }
  return { types: defenders, multipliers, ...buckets };
}

/**
 * 攻擊面總表：以這隻寶可夢的本系招式（STAB）打出去，對 18 種單屬各是多少倍。
 * 取兩個屬性中較好的那個倍率，代表「牠最好的本系打點」。
 */
export function offenseProfile(atkTypes) {
  const attackers = normalizeDefenders(atkTypes);
  const best = {};
  const via = {};
  for (const def of TYPES) {
    let top = -1;
    let topType = null;
    for (const atk of attackers) {
      const m = MATRIX[INDEX.get(atk)][INDEX.get(def)];
      if (m > top) { top = m; topType = atk; }
    }
    best[def] = top;
    via[def] = topType;
  }
  return { types: attackers, multipliers: best, via };
}

export const _internal = { MATRIX, INDEX };
