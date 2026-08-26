// 共用驗收向量測試 —— Swift Package 跑同一份 data/test_vectors.json。
import test from "node:test";
import assert from "node:assert/strict";
import { loadJson } from "../src/data.js";
import { TypeChart } from "../src/typechart.js";
import { Pokedex } from "../src/pokedex.js";
import { normalizeOcrText } from "../src/pipeline.js";

const vectors = loadJson("test_vectors.json");
const chart = new TypeChart(loadJson("type_chart.json"));
const dex = new Pokedex(loadJson("pokedex.json"));

test("剋制乘數 effectiveness", () => {
  for (const v of vectors.effectiveness) {
    assert.equal(
      chart.effectiveness(v.attack, v.defense),
      v.expect,
      `${v.attack} vs [${v.defense}] 應為 ${v.expect}`
    );
  }
});

test("防禦弱點表 defensive_profile", () => {
  for (const v of vectors.defensive_profile) {
    const profile = chart.defensiveProfile(v.defense);
    for (const [atk, expected] of Object.entries(v.expect_partial)) {
      assert.equal(
        profile[atk],
        expected,
        `${atk} vs [${v.defense}] 應為 ${expected}`
      );
    }
  }
});

test("精確查詢 lookup", () => {
  for (const v of vectors.lookup) {
    const hit = dex.lookup(v.query);
    assert.ok(hit, `「${v.query}」應可查到`);
    assert.equal(hit.id, v.expect_id, `「${v.query}」應為 id ${v.expect_id}`);
  }
});

test("模糊比對 fuzzy", () => {
  for (const v of vectors.fuzzy) {
    const hit = dex.fuzzy(v.query);
    assert.ok(hit, `「${v.query}」應可模糊比對到`);
    assert.equal(
      hit.entry.id,
      v.expect_id,
      `「${v.query}」應比對到 id ${v.expect_id}（實際:「${hit.entry.name_zh}」）`
    );
  }
});

test("名稱擷取 extract", () => {
  for (const v of vectors.extract) {
    const ids = dex.extract(v.text).map((p) => p.id);
    assert.deepEqual(ids, v.expect_ids, `「${v.text}」`);
  }
});

test("OCR 正規化後擷取 extract_normalized", () => {
  for (const v of vectors.extract_normalized) {
    const ids = dex.extract(normalizeOcrText(v.text)).map((p) => p.id);
    assert.deepEqual(ids, v.expect_ids, `「${v.text}」`);
  }
});
