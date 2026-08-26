// 端到端管線：截圖 →（OCR）→ 文字 → 名稱擷取/模糊比對 → 對戰分析。
// 這條管線就是未來 iOS App 的資料流：ReplayKit 畫面 → Vision OCR → Core 引擎 → 動態島。

import { analyze } from "./matchup.js";

// CJK 區段（含全形括號，型態名會用到）
const CJK = "\\u4e00-\\u9fff\\u3400-\\u4dbf\\uff08\\uff09";
const CJK_GAP = new RegExp(`(?<=[${CJK}])\\s+(?=[${CJK}])`, "g");

/**
 * OCR 文字正規化：移除 CJK 字元之間的空白。
 * tesseract（chi_tra）常把「噴火龍」輸出成「噴火 龍」；Vision 也可能逐字斷行。
 * 規格與 Swift 端一致（見 data/test_vectors.json spec）。
 */
export function normalizeOcrText(text) {
  return text.replace(CJK_GAP, "");
}

/**
 * 從 OCR 文字產出對戰分析。
 * @param {import("./typechart.js").TypeChart} chart
 * @param {import("./pokedex.js").Pokedex} dex
 * @param {string} text OCR 輸出（或任何含寶可夢名稱的文字）
 * @param {{mineName?: string}} [options] 指定我方寶可夢名稱（截圖擷取不到我方時）
 */
export function analyzeText(chart, dex, text, options = {}) {
  const found = dex.extract(normalizeOcrText(text));

  let mine = null;
  if (options.mineName) {
    mine =
      dex.lookup(options.mineName) ?? dex.fuzzy(options.mineName)?.entry ?? null;
    if (!mine) throw new Error(`找不到我方寶可夢: ${options.mineName}`);
  }

  // 畫面上通常「對方在前、我方在後」或只有對方；沒指定我方時：
  //   找到 2 隻 → 第一隻當對方、第二隻當我方；1 隻 → 對方
  let opponent;
  if (found.length === 0) {
    return { found: [], reports: [] };
  } else if (mine) {
    opponent = found.find((p) => p.id !== mine.id) ?? found[0];
  } else if (found.length >= 2) {
    opponent = found[0];
    mine = found[1];
  } else {
    opponent = found[0];
  }

  return {
    found,
    reports: [analyze(chart, mine, opponent)],
  };
}

/** 截圖檔案 → OCR → 分析。需要 tesseract.js 與網路（首次下載語言資料）。 */
export async function analyzeImage(chart, dex, imagePath, options = {}) {
  const { recognize } = await import("./ocr.js");
  const { text, confidence } = await recognize(imagePath);
  const result = analyzeText(chart, dex, text, options);
  return { ...result, ocr: { text, confidence } };
}
