import { zhName, defenseProfile } from './typechart.mjs';

const ESC = '[';
const useColor = process.stdout.isTTY && !process.env.NO_COLOR;
const c = (code) => (s) => (useColor ? `${ESC}${code}m${s}${ESC}0m` : String(s));

export const red = c('31');
export const green = c('32');
export const yellow = c('33');
export const cyan = c('36');
export const dim = c('2');
export const bold = c('1');

/** 中文字在終端機佔兩格，用字元數對齊會歪掉，得按顯示寬度算。 */
export function displayWidth(s) {
  let w = 0;
  for (const ch of String(s)) {
    const cp = ch.codePointAt(0);
    const wide =
      (cp >= 0x1100 && cp <= 0x115f) ||
      (cp >= 0x2e80 && cp <= 0xa4cf) ||
      (cp >= 0xac00 && cp <= 0xd7a3) ||
      (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0xfe30 && cp <= 0xfe6f) ||
      (cp >= 0xff00 && cp <= 0xff60) ||
      (cp >= 0xffe0 && cp <= 0xffe6) ||
      (cp >= 0x20000 && cp <= 0x3fffd);
    w += wide ? 2 : 1;
  }
  return w;
}

export function pad(s, width, align = 'left') {
  const gap = Math.max(0, width - displayWidth(s));
  return align === 'right' ? ' '.repeat(gap) + s : s + ' '.repeat(gap);
}

/** 倍率標籤：0 / ¼ / ½ / 1 / 2 / 4。 */
export function multLabel(m) {
  return m === 0 ? '0' : m === 0.25 ? '¼' : m === 0.5 ? '½' : String(m);
}

/**
 * 倍率上色。invert 用在「對方打我方」的欄位——同樣是 2×，
 * 打出去是好事、被打到是壞事，顏色必須反過來才不會誤讀。
 */
export function multColor(m, invert = false) {
  const label = multLabel(m);
  if (m === 1) return dim(label);
  const bad = invert ? m > 1 : m < 1;
  return bad ? red(label) : green(label);
}

/** 一隻寶可夢的防禦面：只列出非 1 倍的部分，1 倍是雜訊。 */
export function renderDefense(types) {
  const p = defenseProfile(types);
  const row = (label, list, paint) =>
    list.length ? `  ${pad(label, 10)}${paint(list.map(zhName).join('、'))}\n` : '';
  return (
    row('4× 致命', p.x4, red) +
    row('2× 被剋', p.x2, red) +
    row('½ 抗性', p.x05, green) +
    row('¼ 強抗', p.x025, green) +
    row('0× 無效', p.x0, cyan)
  );
}

/** 隊伍對隊伍矩陣。每格是「我打牠 / 牠打我」。 */
export function renderMatrix({ mine, theirs, matrix }) {
  if (mine.length === 0 || theirs.length === 0) return dim('  （資料不足，無法比對）\n');
  const nameW = Math.max(...mine.map((m) => displayWidth(m.label)), 8);
  const colW = Math.max(...theirs.map((t) => displayWidth(t.label)), 7);

  let out = `  ${pad('', nameW)}  ` + theirs.map((t) => pad(t.label, colW)).join(' ') + '\n';
  for (let i = 0; i < mine.length; i++) {
    const cells = theirs.map((_, j) => {
      const cell = matrix[i][j];
      const plain = `${multLabel(cell.outgoing)}/${multLabel(cell.incoming)}`;
      const colored = `${multColor(cell.outgoing)}/${multColor(cell.incoming, true)}`;
      return colored + ' '.repeat(Math.max(0, colW - displayWidth(plain)));
    });
    out += `  ${pad(mine[i].label, nameW)}  ${cells.join(' ')}\n`;
  }
  out += dim('  （每格＝我方本系打對方 / 對方本系打我方）\n');
  return out;
}

export function renderSummary({ threats, answers }) {
  let out = '';
  const top = threats.filter((t) => t.count > 0).slice(0, 3);
  if (top.length) {
    out += bold('  最該注意\n');
    for (const t of top) {
      const h = t.hits[0];
      out += `    ${red('▲')} ${t.combatant.label} 可超效打中 ${t.count} 隻，最重 ${red(h.multiplier + '×')} → ${h.target}\n`;
    }
  }
  const best = answers.filter((a) => a.count > 0).slice(0, 3);
  if (best.length) {
    out += bold('  你的解答\n');
    for (const a of best) {
      const tag = a.safe ? green('（不吃超效）') : dim(`（會被 ${a.worstIncoming}× 反打）`);
      out += `    ${green('●')} ${a.combatant.label} 超效打中 ${a.count} 隻 ${tag}\n`;
    }
  }
  return out || dim('  （雙方本系互無超效打點）\n');
}
