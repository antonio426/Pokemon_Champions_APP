import test from 'node:test';
import assert from 'node:assert/strict';
import { TYPES, effectiveness, defenseProfile } from '../src/typechart.mjs';
import { ENTRIES, lookup, resolve, clearPool, setPool } from '../src/pokedex.mjs';
import { teamMatchup, liveSummary } from '../src/matchup.mjs';

/**
 * 規劃書 Phase 1 的驗收標準：
 *   「資料庫查詢單隻寶可夢剋制結果 < 10ms」
 *
 * 這裡量的是中位數與 p95。單看平均值會被 JIT 暖機與 GC 掩蓋掉尾端延遲，
 * 而在 Broadcast Extension 裡真正會出事的正是尾端。
 */
function measure(fn, iterations) {
  const samples = new Float64Array(iterations);
  for (let i = 0; i < 200; i++) fn(i); // 暖機
  for (let i = 0; i < iterations; i++) {
    const t0 = performance.now();
    fn(i);
    samples[i] = performance.now() - t0;
  }
  const sorted = Array.from(samples).sort((a, b) => a - b);
  return {
    median: sorted[Math.floor(sorted.length * 0.5)],
    p95: sorted[Math.floor(sorted.length * 0.95)],
    max: sorted[sorted.length - 1],
  };
}

const report = (name, s) =>
  console.log(`    ${name}: 中位數 ${s.median.toFixed(4)}ms / p95 ${s.p95.toFixed(4)}ms / 最大 ${s.max.toFixed(4)}ms`);

test('單一倍率查詢遠低於 10ms', () => {
  const stats = measure((i) => effectiveness(TYPES[i % 18], [TYPES[(i * 7) % 18], TYPES[(i * 13) % 18]]), 20000);
  report('effectiveness', stats);
  assert.ok(stats.p95 < 10, `p95 ${stats.p95}ms 超過 10ms`);
});

test('單隻寶可夢的完整剋制結果 < 10ms（Phase 1 驗收標準）', () => {
  clearPool();
  const names = ['皮卡丘', '噴火龍', '班基拉斯', '沙奈朵', '暴鯉龍', '快龍', '耿鬼', '超夢'];
  const stats = measure((i) => {
    const hit = lookup(names[i % names.length]);
    return defenseProfile(hit.entry.types);
  }, 5000);
  report('名稱查詢 + 防禦總表', stats);
  assert.ok(stats.median < 10, `中位數 ${stats.median}ms 超過 10ms`);
  assert.ok(stats.p95 < 10, `p95 ${stats.p95}ms 超過 10ms`);
});

test('圖鑑條目全掃一次的防禦總表也在預算內', () => {
  const stats = measure((i) => defenseProfile(ENTRIES[i % ENTRIES.length].types), 20000);
  report('defenseProfile', stats);
  assert.ok(stats.p95 < 10, `p95 ${stats.p95}ms 超過 10ms`);
});

/**
 * 模糊比對是唯一會掃全圖鑑的路徑，也是唯一有機會超出預算的地方。
 * 這條測試存在的目的，是在它退化時立刻叫出來——而不是等到跑進 Extension 才發現。
 */
test('模糊比對（掃全圖鑑）的延遲有被量測並記錄', () => {
  clearPool();
  const noisy = ['噴火竜', '班基拉期', '大葱鴨', '沙奈染', '暴鯉竜'];
  const stats = measure((i) => resolve(noisy[i % noisy.length], { limit: 3 }), 500);
  report('模糊比對（全圖鑑 ' + ENTRIES.length + ' 筆）', stats);
  assert.ok(stats.p95 < 50, `p95 ${stats.p95}ms —— 模糊比對退化了`);
});

test('限定賽季清單後，模糊比對快一個數量級', () => {
  const season = ENTRIES.filter((e) => e.isDefault).slice(0, 100).map((e) => e.id);

  clearPool();
  const full = measure(() => resolve('班基拉期', { limit: 3 }), 300);

  setPool(season, 'perf-season');
  const limited = measure(() => resolve('班基拉期', { limit: 3 }), 300);
  clearPool();

  report('全圖鑑', full);
  report('限定 100 隻', limited);
  assert.ok(limited.median < full.median, '縮小範圍後反而變慢了');
  assert.ok(limited.p95 < 10, `限定清單後 p95 仍有 ${limited.p95}ms`);
});

test('六對六的完整隊伍分析 < 10ms', () => {
  const mine = ['噴火龍', '沙奈朵', '耿鬼', '暴鯉龍', '快龍', '班基拉斯'];
  const theirs = ['水箭龜', '妙蛙花', '大針蜂', '鐵甲蛹', '皮卡丘', '超夢'];
  const stats = measure(() => teamMatchup(mine, theirs), 2000);
  report('teamMatchup 6v6', stats);
  assert.ok(stats.p95 < 10, `p95 ${stats.p95}ms 超過 10ms`);
});

test('動態島摘要的計算成本可忽略', () => {
  const mine = ['噴火龍', '沙奈朵', '耿鬼'];
  const theirs = ['水箭龜', '班基拉斯', '皮卡丘'];
  const stats = measure(() => liveSummary(mine, theirs), 3000);
  report('liveSummary 3v3', stats);
  assert.ok(stats.p95 < 5, `p95 ${stats.p95}ms 超過 5ms`);
});
