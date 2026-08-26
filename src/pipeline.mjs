import { recognize } from './ocr.mjs';
import { resolve as resolveName } from './pokedex.mjs';
import { teamMatchup, liveSummary } from './matchup.mjs';

/**
 * 畫面版面規則。手機版對戰的選人畫面是左右分邊：左邊我方、右邊對方。
 * 用畫面寬度的比例切，而不是絕對像素，才能跨機型沿用。
 */
export const DEFAULT_LAYOUT = {
  name: 'battle-prep-split',
  /** x 中點小於這個比例算我方，大於 theirsFrom 算對方，中間地帶丟掉（通常是 UI 標題）。 */
  mineUntil: 0.45,
  theirsFrom: 0.5,
  /** 畫面上方通常是標題與計時器，下方是按鈕，先切掉減少雜訊。 */
  top: 0.05,
  height: 0.85,
  /** 送進 OCR 前先降取樣。實測降到 0.4 反而比原尺寸準，而且快一倍。 */
  scale: 0.4,
  /** 低於這個相似度就不當成辨識結果，寧可漏也不要餵錯資料給動態島。 */
  minScore: 0.6,
};

/**
 * 一張截圖 → 雙方隊伍。
 * 這是 Phase 0 要驗證的那條路徑，也是之後 Extension 內每 N 幀要跑的邏輯。
 */
export async function readTeams(imagePath, layout = DEFAULT_LAYOUT) {
  const cfg = { ...DEFAULT_LAYOUT, ...layout };
  const started = Date.now();
  const ocr = await recognize(imagePath, {
    top: cfg.top,
    height: cfg.height,
    scale: cfg.scale,
  });

  const mine = [];
  const theirs = [];
  const unresolved = [];

  for (const line of ocr.lines) {
    const text = line.text.trim();
    if (text.length < 2) continue;

    const width = line.words.reduce((sum, w) => sum + w.w, 0);
    const centerX = (line.x + width / 2) / ocr.imageWidth;
    const side = centerX < cfg.mineUntil ? mine : centerX > cfg.theirsFrom ? theirs : null;
    if (!side) continue;

    const [best] = resolveName(text, { limit: 1, minScore: cfg.minScore });
    if (!best) {
      unresolved.push({ text, centerX: Number(centerX.toFixed(3)), y: line.y });
      continue;
    }
    side.push({
      ...best.entry,
      ocrText: text,
      score: best.score,
      exact: best.exact,
      y: line.y,
    });
  }

  const dedupe = (list) => {
    const seen = new Set();
    return list
      .sort((a, b) => a.y - b.y)
      .filter((e) => (seen.has(e.id) ? false : seen.add(e.id)));
  };

  return {
    image: ocr.path,
    layout: cfg.name,
    ocrMs: ocr.elapsedMs,
    totalMs: Date.now() - started,
    mine: dedupe(mine),
    theirs: dedupe(theirs),
    unresolved,
  };
}

/** 截圖 → 完整剋制分析。主 App「截圖匯入模式」（Phase 2）的核心呼叫。 */
export async function analyzeScreenshot(imagePath, layout = DEFAULT_LAYOUT) {
  const teams = await readTeams(imagePath, layout);
  if (teams.mine.length === 0 && teams.theirs.length === 0) {
    return { ...teams, matchup: null, summary: null };
  }
  return {
    ...teams,
    matchup: teamMatchup(teams.mine, teams.theirs),
    summary: liveSummary(teams.mine, teams.theirs),
  };
}
