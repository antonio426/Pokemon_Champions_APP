// 引擎自身的健全性測試（Node 專屬，不在共用向量內）。
import test from "node:test";
import assert from "node:assert/strict";
import { loadJson } from "../src/data.js";
import { TypeChart } from "../src/typechart.js";
import { Pokedex, levenshtein } from "../src/pokedex.js";
import { analyze } from "../src/matchup.js";
import { analyzeText } from "../src/pipeline.js";

const chart = new TypeChart(loadJson("type_chart.json"));
const dex = new Pokedex(loadJson("pokedex.json"));

test("剋制表完整：18×18 全有值且只有合法乘數", () => {
  assert.equal(chart.types.length, 18);
  const legal = new Set([0, 0.5, 1, 2]);
  for (const a of chart.types)
    for (const d of chart.types) {
      const v = chart.chart[a.identifier][d.identifier];
      assert.ok(legal.has(v), `${a.identifier}→${d.identifier} = ${v}`);
    }
});

test("圖鑑：全部條目都有屬性，繁中名涵蓋所有預設型態", () => {
  assert.ok(dex.entries.length >= 1000);
  for (const p of dex.entries) {
    assert.ok(p.types.length >= 1 && p.types.length <= 2, p.identifier);
    if (p.is_default) assert.ok(p.name_zh, `#${p.dex} ${p.identifier} 缺繁中名`);
  }
});

test("levenshtein 基本性質", () => {
  assert.equal(levenshtein("", "abc"), 3);
  assert.equal(levenshtein("皮卡丘", "皮卡丘"), 0);
  assert.equal(levenshtein("皮卡丘", "皮丘"), 1);
  assert.equal(levenshtein("噴火龍", "暴鯉龍"), 2);
});

test("analyze：皮卡丘 vs 噴火龍", () => {
  const r = analyze(chart, dex.lookup("皮卡丘"), dex.lookup("噴火龍"));
  assert.equal(r.my_stab[0].multiplier, 2); // 電打火/飛 = 2
  assert.deepEqual(
    r.weaknesses.map((w) => w.type).sort(),
    ["electric", "rock", "water"].sort()
  );
  assert.equal(r.weaknesses[0].type, "rock"); // 岩 4× 排最前
  assert.equal(r.immunities[0].type, "ground");
});

test("pipeline：從戰鬥文字產出報告", () => {
  const r = analyzeText(chart, dex, "對手派出了噴火龍！", { mineName: "皮卡丘" });
  assert.equal(r.reports.length, 1);
  assert.equal(r.reports[0].opponent.name_zh, "噴火龍");
  assert.equal(r.reports[0].mine.name_zh, "皮卡丘");
});

test("pipeline：兩隻名稱時第一隻為對方", () => {
  const r = analyzeText(chart, dex, "噴火龍 vs 皮卡丘");
  assert.equal(r.reports[0].opponent.name_zh, "噴火龍");
  assert.equal(r.reports[0].mine.name_zh, "皮卡丘");
});
