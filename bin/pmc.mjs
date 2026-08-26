#!/usr/bin/env node
/**
 * pmc —— 寶可夢屬性剋制查詢 CLI。
 *
 * 這支工具是 Phase 0/1 的操作介面：資料層的每個能力都能在終端機驗一次，
 * 之後移植到 Swift 時，這裡的行為就是驗收基準。
 */
import { TYPES, zhName, effectiveness, defenseProfile, toType } from '../src/typechart.mjs';
import { resolve as resolveName, ENTRIES, GENERATED_AT, setPool, loadPoolFile, getPool } from '../src/pokedex.mjs';
import { pairMatchup, teamMatchup, liveSummary, asCombatant, weaknessReport } from '../src/matchup.mjs';
import { renderDefense, renderMatrix, renderSummary, bold, dim, red, green, cyan, multLabel, pad } from '../src/format.mjs';

const HELP = `${bold('pmc')} — 寶可夢屬性剋制查詢

用法
  pmc who <名稱>                   查一隻寶可夢：屬性、弱點、抗性
  pmc vs <我方> <對方>              單挑：誰打誰幾倍、誰佔上風
  pmc team <我方,...> <對方,...>    隊伍對隊伍：完整矩陣 + 威脅與解答
  pmc type <屬性>[,<屬性>]          直接查屬性組合的防禦面
  pmc calc <攻擊屬性> <防禦屬性...>  單一倍率
  pmc find <文字>                   模糊搜尋（用來debug OCR 誤讀）
  pmc shot <圖片路徑>               截圖 → 辨識雙方 → 剋制分析（Phase 0 管線）
  pmc info                          資料庫狀態

選項
  --pool <檔案>   載入賽季可用清單，縮小辨識比對範圍
  --json          輸出 JSON，方便接其他工具
  --no-color      關閉顏色

範例
  pmc who 班基拉斯
  pmc vs 噴火龍 水箭龜
  pmc team 噴火龍,沙奈朵,耿鬼 水箭龜,班基拉斯,化石翼龍
  pmc shot fixtures/mock-battle.png
`;

const argv = process.argv.slice(2);
const opts = { json: false, pool: null };
const rest = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i] === '--json') opts.json = true;
  else if (argv[i] === '--no-color') process.env.NO_COLOR = '1';
  else if (argv[i] === '--pool') opts.pool = argv[++i];
  else rest.push(argv[i]);
}

const [cmd, ...args] = rest;
const out = (v) => process.stdout.write(typeof v === 'string' ? v : JSON.stringify(v, null, 2) + '\n');
const die = (msg) => { process.stderr.write(red(`✖ ${msg}\n`)); process.exit(1); };

/** 逗號或空白分隔都接受——複製貼上隊伍名單時兩種都常見。 */
const splitList = (s) => String(s).split(/[,，\s]+/).map((x) => x.trim()).filter(Boolean);

if (opts.pool) {
  const pool = loadPoolFile(opts.pool);
  if (!pool) die(`找不到清單檔：${opts.pool}`);
} else {
  loadPoolFile();
}

function combatantOrDie(name) {
  const c = asCombatant(name);
  if (!c) die(`查無此寶可夢：${name}（試試 pmc find ${name}）`);
  return c;
}

function cmdWho(name) {
  const hits = resolveName(name, { limit: 5 });
  if (hits.length === 0) die(`查無此寶可夢：${name}`);
  const top = hits[0];
  const e = top.entry;
  if (opts.json) return out({ entry: e, defense: defenseProfile(e.types), alternatives: hits.slice(1).map((h) => h.entry.zh) });

  const conf = top.exact ? '' : dim(`（模糊比對 ${(top.score * 100).toFixed(0)}%）`);
  out(`\n${bold(e.zh)} ${dim(`#${e.speciesId} ${e.en}`)} ${conf}\n`);
  out(`  屬性      ${cyan(e.types.map(zhName).join(' / '))}\n`);
  out(renderDefense(e.types));
  if (hits.length > 1) out(dim(`  其他相近：${hits.slice(1).map((h) => h.entry.zh).join('、')}\n`));
  out('\n');
}

function cmdVs(a, b) {
  const m = pairMatchup(combatantOrDie(a), combatantOrDie(b));
  if (opts.json) return out(m);
  out(`\n${bold(m.mine.label)} ${dim(m.mine.types.map(zhName).join('/'))}  vs  ${bold(m.theirs.label)} ${dim(m.theirs.types.map(zhName).join('/'))}\n\n`);
  const arrow = m.edge === 'favorable' ? green('▲ 你佔上風') : m.edge === 'unfavorable' ? red('▼ 你吃虧') : dim('＝ 勢均力敵');
  out(`  你打牠    ${green(multLabel(m.outgoing.multiplier) + '×')} ${dim(`（本系 ${m.outgoing.viaZh}）`)} ${m.outgoing.verdict}\n`);
  out(`  牠打你    ${red(multLabel(m.incoming.multiplier) + '×')} ${dim(`（本系 ${m.incoming.viaZh}）`)} ${m.incoming.verdict}\n`);
  out(`\n  ${arrow}\n\n`);
}

function cmdTeam(mineArg, theirsArg) {
  const mine = splitList(mineArg).map(combatantOrDie);
  const theirs = splitList(theirsArg).map(combatantOrDie);
  const result = teamMatchup(mine, theirs);
  if (opts.json) return out({ ...result, summary: liveSummary(mine, theirs) });
  out('\n');
  out(renderMatrix(result));
  out('\n');
  out(renderSummary(result));
  const s = liveSummary(mine, theirs);
  out(`\n  ${dim('動態島摘要')}  ${red('威脅')} ${s.threat}   ${green('解答')} ${s.answer}\n\n`);
}

function cmdType(spec) {
  const types = splitList(spec).map(toType);
  if (types.some((t) => !t)) die(`未知屬性：${spec}`);
  if (opts.json) return out(defenseProfile(types));
  out(`\n${bold(types.map(zhName).join(' / '))} 的防禦面\n`);
  out(renderDefense(types));
  out('\n');
}

function cmdCalc(atk, ...defs) {
  const defList = defs.flatMap(splitList);
  const m = effectiveness(atk, defList);
  if (opts.json) return out({ attack: toType(atk), defend: defList.map(toType), multiplier: m });
  out(`${zhName(toType(atk))} → ${defList.map((d) => zhName(toType(d))).join('/')} = ${bold(m + '×')}\n`);
}

function cmdFind(text) {
  const hits = resolveName(text, { limit: 10, minScore: 0.3 });
  if (opts.json) return out(hits.map((h) => ({ zh: h.entry.zh, id: h.entry.id, types: h.entry.types, score: h.score })));
  if (hits.length === 0) return out(dim(`  找不到與「${text}」相近的寶可夢\n`));
  out(`\n  「${text}」的候選\n`);
  for (const h of hits) {
    out(`  ${pad((h.score * 100).toFixed(0) + '%', 6, 'right')}  ${pad(h.entry.zh, 22)} ${dim(h.entry.types.map(zhName).join('/'))}\n`);
  }
  out('\n');
}

async function cmdShot(file) {
  const { analyzeScreenshot } = await import('../src/pipeline.mjs');
  const r = await analyzeScreenshot(file);
  if (opts.json) return out(r);
  out(`\n${bold('辨識結果')} ${dim(`OCR ${r.ocrMs}ms / 總計 ${r.totalMs}ms`)}\n`);
  out(`  我方  ${r.mine.map((e) => `${e.zh}${e.exact ? '' : dim(`(${(e.score * 100).toFixed(0)}%)`)}`).join('、') || dim('（無）')}\n`);
  out(`  對方  ${r.theirs.map((e) => `${e.zh}${e.exact ? '' : dim(`(${(e.score * 100).toFixed(0)}%)`)}`).join('、') || dim('（無）')}\n`);
  if (r.unresolved.length) out(dim(`  未解析  ${r.unresolved.map((u) => u.text).join('、')}\n`));
  if (!r.matchup) return out(dim('\n  沒有辨識到任何寶可夢，無法分析\n\n'));
  out('\n');
  out(renderMatrix(r.matchup));
  out('\n');
  out(renderSummary(r.matchup));
  out(`\n  ${dim('動態島摘要')}  ${red('威脅')} ${r.summary.threat}   ${green('解答')} ${r.summary.answer}\n\n`);
}

function cmdInfo() {
  const pool = getPool();
  const info = {
    entries: ENTRIES.length,
    species: new Set(ENTRIES.map((e) => e.speciesId)).size,
    types: TYPES.length,
    generatedAt: GENERATED_AT,
    pool: pool ? { name: pool.name, size: pool.entries.length } : null,
  };
  if (opts.json) return out(info);
  out(`\n  圖鑑條目    ${info.entries}（${info.species} 個物種，含地區形態與 Mega）\n`);
  out(`  屬性        ${info.types}\n`);
  out(`  資料產生於  ${info.generatedAt}\n`);
  out(`  賽季清單    ${pool ? `${pool.name}（${pool.entries.length} 隻）` : dim('未載入（比對全圖鑑）')}\n\n`);
}

const need = (n, usage) => { if (args.length < n) die(`參數不足。用法：${usage}`); };

try {
  switch (cmd) {
    case 'who': need(1, 'pmc who <名稱>'); cmdWho(args[0]); break;
    case 'vs': need(2, 'pmc vs <我方> <對方>'); cmdVs(args[0], args[1]); break;
    case 'team': need(2, 'pmc team <我方,...> <對方,...>'); cmdTeam(args[0], args[1]); break;
    case 'type': need(1, 'pmc type <屬性>[,<屬性>]'); cmdType(args[0]); break;
    case 'calc': need(2, 'pmc calc <攻擊屬性> <防禦屬性...>'); cmdCalc(args[0], ...args.slice(1)); break;
    case 'find': need(1, 'pmc find <文字>'); cmdFind(args[0]); break;
    case 'shot': need(1, 'pmc shot <圖片路徑>'); await cmdShot(args[0]); break;
    case 'info': cmdInfo(); break;
    case undefined:
    case 'help':
    case '--help':
    case '-h': out(HELP); break;
    default: die(`未知指令：${cmd}\n\n${HELP}`);
  }
} catch (err) {
  die(err.message);
}
