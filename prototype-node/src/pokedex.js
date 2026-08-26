// 全國圖鑑：精確查詢、模糊比對（OCR 誤字容錯）、與文字中的名稱擷取。
// 演算法規格見 data/test_vectors.json 的 spec 欄位——Swift 實作必須一致。

export class Pokedex {
  /** @param {{pokemon: Array}} json data/pokedex.json 的內容 */
  constructor(json) {
    this.entries = json.pokemon;
    this.byId = new Map(this.entries.map((p) => [p.id, p]));
    this.byZh = new Map();
    this.byEnLower = new Map();
    this.byIdentifier = new Map();
    for (const p of this.entries) {
      // 同名時保留 id 較小者（基礎型態優先）
      if (p.name_zh && !this.byZh.has(p.name_zh)) this.byZh.set(p.name_zh, p);
      if (p.name_en && !this.byEnLower.has(p.name_en.toLowerCase()))
        this.byEnLower.set(p.name_en.toLowerCase(), p);
      if (!this.byIdentifier.has(p.identifier))
        this.byIdentifier.set(p.identifier, p);
    }
    // 供 extract 使用：名稱長度由長到短
    this.zhNamesByLength = [...this.byZh.keys()].sort(
      (a, b) => b.length - a.length
    );
    this.maxZhNameLength = this.zhNamesByLength.length
      ? this.zhNamesByLength[0].length
      : 0;
  }

  /** 精確查詢：繁中 → 英文（不分大小寫）→ identifier。找不到回傳 null。 */
  lookup(query) {
    return (
      this.byZh.get(query) ??
      this.byEnLower.get(query.toLowerCase()) ??
      this.byIdentifier.get(query.toLowerCase()) ??
      null
    );
  }

  /**
   * 模糊比對（只對 name_zh）：Levenshtein 距離 ≤ maxDistance 且 < 查詢長度；
   * 取最小距離，同距離取 id 最小者。精確命中優先。
   */
  fuzzy(query, maxDistance = 2) {
    const exact = this.lookup(query);
    if (exact) return { entry: exact, distance: 0 };
    let best = null;
    let bestDist = Infinity;
    const qLen = [...query].length;
    for (const p of this.entries) {
      if (!p.name_zh) continue;
      // 長度差已超過上限者直接略過（距離下界）
      const nLen = [...p.name_zh].length;
      if (Math.abs(nLen - qLen) > maxDistance) continue;
      const d = levenshtein(query, p.name_zh);
      if (d > maxDistance || d >= qLen) continue;
      if (d < bestDist || (d === bestDist && p.id < best.id)) {
        best = p;
        bestDist = d;
      }
    }
    return best ? { entry: best, distance: bestDist } : null;
  }

  /**
   * 從一段文字（OCR 輸出）擷取圖鑑名稱：
   * 由左至右，每個位置取以該位置開頭的最長名稱，命中後跳過其長度。
   * 回傳依出現順序、去重的條目陣列。
   */
  extract(text) {
    const chars = [...text];
    const found = [];
    const seen = new Set();
    let i = 0;
    while (i < chars.length) {
      let matched = null;
      const maxLen = Math.min(this.maxZhNameLength, chars.length - i);
      for (let len = maxLen; len >= 1; len--) {
        const candidate = chars.slice(i, i + len).join("");
        const entry = this.byZh.get(candidate);
        if (entry) {
          matched = { entry, len };
          break;
        }
      }
      if (matched) {
        if (!seen.has(matched.entry.id)) {
          seen.add(matched.entry.id);
          found.push(matched.entry);
        }
        i += matched.len;
      } else {
        i += 1;
      }
    }
    return found;
  }
}

/** 標準 Levenshtein 編輯距離（以 Unicode scalar 為單位）。 */
export function levenshtein(a, b) {
  const s = [...a];
  const t = [...b];
  const m = s.length;
  const n = t.length;
  if (m === 0) return n;
  if (n === 0) return m;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const curr = [i];
    for (let j = 1; j <= n; j++) {
      const cost = s[i - 1] === t[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    prev = curr;
  }
  return prev[n];
}
