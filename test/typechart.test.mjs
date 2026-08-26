import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { TYPES, effectiveness, defenseProfile, offenseProfile, toType, zhName } from '../src/typechart.mjs';

const raw = JSON.parse(readFileSync(fileURLToPath(new URL('../data/types.json', import.meta.url)), 'utf8'));

/**
 * 直接從 JSON 讀出單屬倍率，不經過受測模組。
 * 測試若拿 effectiveness() 自己驗自己就沒有意義了。
 */
function expectedSingle(atk, def) {
  const rel = raw.chart[atk];
  if (rel.immune.includes(def)) return 0;
  if (rel.super.includes(def)) return 2;
  if (rel.notVery.includes(def)) return 0.5;
  return 1;
}

test('資料表結構完整：18 種屬性，每種都有相剋定義', () => {
  assert.equal(TYPES.length, 18);
  assert.equal(new Set(TYPES).size, 18);
  for (const t of TYPES) {
    assert.ok(raw.chart[t], `${t} 缺少相剋定義`);
    assert.ok(raw.names[t]?.zh, `${t} 缺少繁中名稱`);
  }
});

test('相剋定義沒有自相矛盾：同一個屬性不會同時落在兩個分組', () => {
  for (const atk of TYPES) {
    const { super: sup, notVery, immune } = raw.chart[atk];
    const all = [...sup, ...notVery, ...immune];
    assert.equal(new Set(all).size, all.length, `${atk} 的相剋分組有重複`);
    for (const d of all) assert.ok(TYPES.includes(d), `${atk} 指向未知屬性 ${d}`);
  }
});

test('18×18 全表：324 個格子都是合法倍率', () => {
  let cells = 0;
  for (const atk of TYPES) {
    for (const def of TYPES) {
      const m = effectiveness(atk, def);
      assert.ok([0, 0.5, 1, 2].includes(m), `${atk}→${def} 得到非法倍率 ${m}`);
      assert.equal(m, expectedSingle(atk, def), `${atk}→${def} 與資料表不一致`);
      cells++;
    }
  }
  assert.equal(cells, 324);
});

// 規劃書的 Phase 1 驗收標準：涵蓋「所有屬性組合」。
// 單屬 18 種 + 雙屬 C(18,2)=153 種，共 171 種防禦組合 × 18 種攻擊屬性 = 3078 組。
test('所有屬性組合：雙屬倍率等於兩個單屬倍率相乘', () => {
  const defenders = [];
  for (let i = 0; i < TYPES.length; i++) {
    defenders.push([TYPES[i]]);
    for (let j = i + 1; j < TYPES.length; j++) defenders.push([TYPES[i], TYPES[j]]);
  }
  assert.equal(defenders.length, 171);

  let checked = 0;
  for (const atk of TYPES) {
    for (const def of defenders) {
      const expected = def.reduce((acc, d) => acc * expectedSingle(atk, d), 1);
      const actual = effectiveness(atk, def);
      assert.equal(actual, expected, `${atk} → ${def.join('/')}`);
      assert.ok([0, 0.25, 0.5, 1, 2, 4].includes(actual), `${atk} → ${def.join('/')} = ${actual}`);
      checked++;
    }
  }
  assert.equal(checked, 18 * 171);
});

test('免疫優先於其他倍率：只要有一邊免疫，結果就是 0', () => {
  assert.equal(effectiveness('ground', ['flying', 'steel']), 0); // 地面對鋼是 2×，但飛行免疫
  assert.equal(effectiveness('normal', ['ghost', 'normal']), 0);
  assert.equal(effectiveness('dragon', ['fairy', 'dragon']), 0);
  assert.equal(effectiveness('psychic', ['dark', 'fighting']), 0);
  assert.equal(effectiveness('poison', ['steel', 'grass']), 0);
  assert.equal(effectiveness('electric', ['ground', 'water']), 0);
  assert.equal(effectiveness('fighting', ['ghost', 'normal']), 0);
});

test('經典對戰情境的倍率正確', () => {
  const cases = [
    ['electric', ['water', 'flying'], 4],   // 暴鯉龍 最著名的 4 倍弱點
    ['ice', ['dragon', 'flying'], 4],       // 快龍
    ['fighting', ['rock', 'dark'], 4],      // 班基拉斯
    ['rock', ['fire', 'flying'], 4],        // 噴火龍
    ['ground', ['fire', 'rock'], 4],
    ['bug', ['psychic', 'dark'], 4],
    ['water', ['fire', 'ground'], 4],
    ['fire', ['grass', 'steel'], 4],
    ['grass', ['water', 'ground'], 4],
    ['steel', ['ice', 'rock'], 4],
    ['fairy', ['dragon', 'dark'], 4],
    ['dark', ['psychic', 'ghost'], 4],
    ['flying', ['grass', 'fighting'], 4],
    ['psychic', ['fighting', 'poison'], 4],
    ['ghost', ['psychic', 'ghost'], 4],
    ['poison', ['grass', 'fairy'], 4],
    ['normal', ['rock', 'steel'], 0.25],
    ['fire', ['fire', 'water'], 0.25],
    ['bug', ['fire', 'steel'], 0.25],
    ['fighting', ['flying', 'psychic'], 0.25],
  ];
  for (const [atk, def, expected] of cases) {
    assert.equal(effectiveness(atk, def), expected, `${atk} → ${def.join('/')}`);
  }
});

test('妖精屬性的三條關鍵關係（第六世代新增，最容易記錯）', () => {
  assert.equal(effectiveness('dragon', 'fairy'), 0);
  assert.equal(effectiveness('fairy', 'dragon'), 2);
  assert.equal(effectiveness('poison', 'fairy'), 2);
  assert.equal(effectiveness('steel', 'fairy'), 2);
  assert.equal(effectiveness('fairy', 'steel'), 0.5);
  assert.equal(effectiveness('fairy', 'fire'), 0.5);
  assert.equal(effectiveness('bug', 'fairy'), 0.5);
  assert.equal(effectiveness('dark', 'fairy'), 0.5);
  assert.equal(effectiveness('fairy', 'fighting'), 2);
  assert.equal(effectiveness('fairy', 'dark'), 2);
});

test('鋼屬性在第六世代之後不再抵抗惡與幽靈', () => {
  assert.equal(effectiveness('dark', 'steel'), 1);
  assert.equal(effectiveness('ghost', 'steel'), 1);
});

test('defenseProfile 分組完整且互斥', () => {
  for (const types of [['steel', 'fairy'], ['water', 'flying'], ['normal'], ['ghost', 'dark']]) {
    const p = defenseProfile(types);
    const all = [...p.x4, ...p.x2, ...p.x1, ...p.x05, ...p.x025, ...p.x0];
    assert.equal(all.length, 18, `${types} 分組數量不對`);
    assert.equal(new Set(all).size, 18, `${types} 分組有重複`);
    for (const t of TYPES) assert.equal(p.multipliers[t], effectiveness(t, types));
  }
});

test('defenseProfile：大嘴娃（鋼/妖精）是教科書級的抗性怪', () => {
  const p = defenseProfile(['steel', 'fairy']);
  assert.deepEqual(p.x0, ['poison', 'dragon']);
  assert.deepEqual(p.x025, ['bug']);
  assert.deepEqual(p.x2, ['fire', 'ground']);
  assert.deepEqual(p.x4, []);
});

test('offenseProfile 取兩個本系中較好的打點', () => {
  const p = offenseProfile(['fire', 'flying']); // 噴火龍
  assert.equal(p.multipliers.grass, 2);          // 火 2× 勝過 飛行 2×
  assert.equal(p.multipliers.fighting, 2);       // 飛行 2×，火只有 1×
  assert.equal(p.multipliers.rock, 0.5);         // 火 0.5×、飛行 0.5×，兩邊都被抗，取較好者仍是 0.5
  assert.equal(p.via.fighting, 'flying');
});

test('offenseProfile 只在單一本系上取最佳，不會把兩系相乘', () => {
  const p = offenseProfile(['fire', 'flying']);
  assert.equal(p.multipliers.water, 1);     // 火被抗 0.5×，但飛行是 1×，取 1
  assert.equal(p.via.water, 'flying');
  assert.equal(p.via.grass, 'fire');
  assert.equal(p.multipliers.electric, 1);  // 兩系都沒有加成也沒被抗
});

test('toType 接受內部代號、繁中名與常見別名', () => {
  assert.equal(toType('psychic'), 'psychic');
  assert.equal(toType('超能力'), 'psychic');
  assert.equal(toType('超能'), 'psychic');
  assert.equal(toType('Fire'), 'fire');
  assert.equal(toType(' 妖精 '), 'fairy');
  assert.equal(toType('岩'), 'rock');
  assert.equal(toType('不存在的屬性'), null);
  assert.equal(toType(null), null);
});

test('zhName 回傳繁中名稱', () => {
  assert.equal(zhName('fighting'), '格鬥');
  assert.equal(zhName('fairy'), '妖精');
});

test('非法輸入會明確報錯，而不是回傳錯誤倍率', () => {
  assert.throws(() => effectiveness('banana', 'fire'), /未知的攻擊屬性/);
  assert.throws(() => effectiveness('fire', []), /至少需要一個有效的防禦方屬性/);
  assert.throws(() => effectiveness('fire', ['fire', 'water', 'grass']), /最多只有兩種屬性/);
});

test('重複屬性視為單屬，不會被平方', () => {
  assert.equal(effectiveness('water', ['fire', 'fire']), 2);
});
