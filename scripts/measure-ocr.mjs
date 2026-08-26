#!/usr/bin/env node
/**
 * Phase 0 的驗收量測工具。
 *
 * 規劃書訂的門檻是「OCR 對繁中寶可夢名稱辨識正確率 ≥ 90%」。這支腳本把
 * 那句話變成一個可以重複執行、會給出數字的東西：拿一批標好答案的截圖跑完
 * 整條管線，逐張比對，最後印出總正確率並以離開碼表示達標與否。
 *
 * 標準答案放在 fixtures/labels.json：
 *   {
 *     "battle-01.png": { "mine": ["噴火龍", "沙奈朵"], "theirs": ["水箭龜"] },
 *     "battle-02.png": { "mine": [...], "theirs": [...] }
 *   }
 *
 *   node scripts/measure-ocr.mjs [--dir fixtures] [--labels fixtures/labels.json]
 *                               [--scale 0.4] [--threshold 0.9] [--json]
 */
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readTeams, DEFAULT_LAYOUT } from '../src/pipeline.mjs';
import { loadPoolFile, getPool } from '../src/pokedex.mjs';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i === -1 ? fallback : argv[i + 1];
};

const DIR = path.resolve(ROOT, flag('dir', 'fixtures'));
const LABELS = path.resolve(ROOT, flag('labels', path.join(DIR, 'labels.json')));
const THRESHOLD = Number(flag('threshold', 0.9));
const SCALE = Number(flag('scale', DEFAULT_LAYOUT.scale));
const POOL = flag('pool', null);
const AS_JSON = argv.includes('--json');

/** 比對兩份名單。順序不重要，內容才重要。 */
function compare(expected, actual) {
  const want = expected.map((s) => s.trim()).filter(Boolean);
  const got = actual.map((e) => e.zh);
  const remaining = [...got];

  const hits = [];
  const misses = [];
  for (const name of want) {
    const i = remaining.indexOf(name);
    if (i === -1) misses.push(name);
    else { hits.push(name); remaining.splice(i, 1); }
  }
  return { want: want.length, hits, misses, extra: remaining };
}

async function main() {
  if (!existsSync(LABELS)) {
    console.error(`✖ 找不到標準答案檔：${path.relative(ROOT, LABELS)}`);
    console.error('');
    console.error('  Phase 0 需要一批「真實對戰截圖 + 人工標好的答案」才量得出準確率。');
    console.error('  請把截圖放進 fixtures/，並照下面的格式建立 fixtures/labels.json：');
    console.error('');
    console.error('  {');
    console.error('    "battle-01.png": { "mine": ["噴火龍", "沙奈朵"], "theirs": ["水箭龜"] }');
    console.error('  }');
    process.exit(2);
  }

  if (POOL) loadPoolFile(path.resolve(ROOT, POOL));
  else loadPoolFile();

  const labels = JSON.parse(await readFile(LABELS, 'utf8'));
  const files = Object.keys(labels);
  if (files.length === 0) {
    console.error('✖ 標準答案檔是空的');
    process.exit(2);
  }

  const rows = [];
  let totalWant = 0;
  let totalHit = 0;
  let totalExtra = 0;
  let totalMs = 0;

  for (const file of files) {
    const imagePath = path.resolve(DIR, file);
    if (!existsSync(imagePath)) {
      rows.push({ file, error: '找不到圖片' });
      continue;
    }
    const label = labels[file];
    let result;
    try {
      result = await readTeams(imagePath, { ...DEFAULT_LAYOUT, scale: SCALE });
    } catch (err) {
      rows.push({ file, error: err.message });
      continue;
    }

    const mine = compare(label.mine ?? [], result.mine);
    const theirs = compare(label.theirs ?? [], result.theirs);
    const want = mine.want + theirs.want;
    const hit = mine.hits.length + theirs.hits.length;
    const extra = mine.extra.length + theirs.extra.length;

    totalWant += want;
    totalHit += hit;
    totalExtra += extra;
    totalMs += result.ocrMs;

    rows.push({
      file,
      accuracy: want === 0 ? 1 : hit / want,
      want, hit, extra,
      ocrMs: result.ocrMs,
      misses: [...mine.misses, ...theirs.misses],
      falsePositives: [...mine.extra, ...theirs.extra],
      unresolved: result.unresolved.map((u) => u.text),
    });
  }

  const accuracy = totalWant === 0 ? 0 : totalHit / totalWant;
  const summary = {
    images: files.length,
    expected: totalWant,
    recognized: totalHit,
    falsePositives: totalExtra,
    accuracy,
    threshold: THRESHOLD,
    passed: accuracy >= THRESHOLD,
    avgOcrMs: files.length ? Math.round(totalMs / files.length) : 0,
    scale: SCALE,
    pool: getPool()?.name ?? null,
  };

  if (AS_JSON) {
    console.log(JSON.stringify({ summary, rows }, null, 2));
    process.exit(summary.passed ? 0 : 1);
  }

  console.log('');
  console.log(`Phase 0 OCR 準確率量測  （降取樣 ${SCALE}×${summary.pool ? `，賽季清單 ${summary.pool}` : ''}）`);
  console.log('');
  for (const r of rows) {
    if (r.error) { console.log(`  ✖ ${r.file}  ${r.error}`); continue; }
    const mark = r.accuracy >= THRESHOLD ? '✔' : '✖';
    console.log(`  ${mark} ${r.file}  ${(r.accuracy * 100).toFixed(0)}%  (${r.hit}/${r.want})  OCR ${r.ocrMs}ms`);
    if (r.misses.length) console.log(`      漏掉：${r.misses.join('、')}`);
    if (r.falsePositives.length) console.log(`      誤判：${r.falsePositives.join('、')}`);
    if (r.unresolved.length) console.log(`      無法解析的文字：${r.unresolved.join('、')}`);
  }
  console.log('');
  console.log(`  總計    ${summary.recognized}/${summary.expected} 正確，誤判 ${summary.falsePositives} 筆`);
  console.log(`  正確率  ${(accuracy * 100).toFixed(1)}%  （門檻 ${(THRESHOLD * 100).toFixed(0)}%）`);
  console.log(`  OCR 平均耗時  ${summary.avgOcrMs}ms`);
  console.log('');
  console.log(summary.passed
    ? '  ✔ 達標 —— 可以進入 Phase 1'
    : '  ✖ 未達標 —— 調整版面切法、降取樣倍率或賽季清單後重測');
  console.log('');

  process.exit(summary.passed ? 0 : 1);
}

main().catch((err) => {
  console.error(`✖ ${err.message}`);
  process.exit(2);
});
