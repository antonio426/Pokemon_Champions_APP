#!/usr/bin/env node
/**
 * fetch_data.mjs — 從 PokeAPI 官方 CSV 產生本專案的資料集：
 *
 *   data/type_chart.json  18×18 屬性剋制表（含繁中/英文屬性名）
 *   data/pokedex.json     全國圖鑑（繁中/英文名 + 屬性，含特殊型態）
 *
 * 並同步複製到 Swift Package 的 Resources 目錄，確保 Node 原型與
 * Swift 實作讀到同一份資料。
 *
 * 用法：node tools/fetch_data.mjs
 * 資料來源：https://github.com/PokeAPI/pokeapi (data/v2/csv)
 */

import { mkdir, writeFile, copyFile, access } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const CSV_BASE =
  "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv";

// PokeAPI languages.csv：4 = zh-Hant（繁體中文）、9 = en
const LANG_ZH_HANT = 4;
const LANG_EN = 9;

async function fetchCsv(name) {
  const url = `${CSV_BASE}/${name}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`下載失敗 ${url}: HTTP ${res.status}`);
  return parseCsv(await res.text());
}

/** 極簡 CSV 解析（支援雙引號欄位），回傳物件陣列。 */
function parseCsv(text) {
  const rows = [];
  let field = "",
    row = [],
    inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (inQuotes) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else inQuotes = false;
      } else field += c;
    } else if (c === '"') inQuotes = true;
    else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      field = "";
      if (row.length > 1 || row[0] !== "") rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== "" || row.length) {
    row.push(field);
    rows.push(row);
  }
  const header = rows.shift();
  return rows.map((r) =>
    Object.fromEntries(header.map((h, idx) => [h, r[idx] ?? ""]))
  );
}

function capitalize(s) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

async function main() {
  console.log("下載 PokeAPI CSV…");
  const [
    types,
    typeNames,
    typeEfficacy,
    pokemon,
    pokemonTypes,
    speciesNames,
    formNames,
    forms,
  ] = await Promise.all([
    fetchCsv("types.csv"),
    fetchCsv("type_names.csv"),
    fetchCsv("type_efficacy.csv"),
    fetchCsv("pokemon.csv"),
    fetchCsv("pokemon_types.csv"),
    fetchCsv("pokemon_species_names.csv"),
    fetchCsv("pokemon_form_names.csv"),
    fetchCsv("pokemon_forms.csv"),
  ]);

  // ---- 屬性表（只取本傳 18 屬性，排除 unknown/shadow 等 id>18）----
  const realTypes = types
    .filter((t) => Number(t.id) >= 1 && Number(t.id) <= 18)
    .sort((a, b) => Number(a.id) - Number(b.id));

  const nameOf = (rows, idKey, id, lang, nameKey = "name") => {
    const hit = rows.find(
      (r) => Number(r[idKey]) === id && Number(r.local_language_id) === lang
    );
    return hit ? hit[nameKey] : null;
  };

  const typeList = realTypes.map((t) => {
    const id = Number(t.id);
    return {
      id,
      identifier: t.identifier,
      name_en:
        nameOf(typeNames, "type_id", id, LANG_EN) ?? capitalize(t.identifier),
      name_zh: nameOf(typeNames, "type_id", id, LANG_ZH_HANT),
    };
  });
  const idToIdentifier = new Map(typeList.map((t) => [t.id, t.identifier]));

  // ---- 18×18 剋制表：chart[攻擊][防禦] = 0 | 0.5 | 1 | 2 ----
  const chart = {};
  for (const t of typeList) chart[t.identifier] = {};
  for (const row of typeEfficacy) {
    const atk = idToIdentifier.get(Number(row.damage_type_id));
    const def = idToIdentifier.get(Number(row.target_type_id));
    if (!atk || !def) continue;
    chart[atk][def] = Number(row.damage_factor) / 100;
  }
  // 驗證完整性
  for (const a of typeList)
    for (const d of typeList)
      if (chart[a.identifier][d.identifier] === undefined)
        throw new Error(`剋制表缺格：${a.identifier} → ${d.identifier}`);

  const typeChart = {
    source: "PokeAPI type_efficacy.csv",
    generation: 9,
    types: typeList,
    chart,
  };

  // ---- 全國圖鑑 ----
  const typesByPokemon = new Map();
  for (const row of pokemonTypes) {
    const pid = Number(row.pokemon_id);
    if (!typesByPokemon.has(pid)) typesByPokemon.set(pid, []);
    typesByPokemon.get(pid)[Number(row.slot) - 1] = idToIdentifier.get(
      Number(row.type_id)
    );
  }

  // 特殊型態的繁中全名（例：雷丘（阿羅拉的樣子））取自 pokemon_form_names.csv
  const formByPokemonId = new Map(); // pokemon_id -> form_id（取 is_default 型態）
  for (const f of forms) {
    const pid = Number(f.pokemon_id);
    if (!formByPokemonId.has(pid) || Number(f.is_default) === 1)
      formByPokemonId.set(pid, Number(f.id));
  }

  const entries = [];
  for (const p of pokemon) {
    const pid = Number(p.id);
    const speciesId = Number(p.species_id);
    const t = typesByPokemon.get(pid);
    if (!t || !t.length) continue;
    const isDefault = Number(p.is_default) === 1;

    let nameZh = nameOf(speciesNames, "pokemon_species_id", speciesId, LANG_ZH_HANT);
    let nameEn = nameOf(speciesNames, "pokemon_species_id", speciesId, LANG_EN);
    if (!isDefault) {
      const formId = formByPokemonId.get(pid);
      // 繁中的 pokemon_name 欄位多為空，改用「物種名（型態名）」組合
      const formFullZh = formId
        ? nameOf(formNames, "pokemon_form_id", formId, LANG_ZH_HANT, "pokemon_name")
        : null;
      const formPartZh = formId
        ? nameOf(formNames, "pokemon_form_id", formId, LANG_ZH_HANT, "form_name")
        : null;
      const formEn = formId
        ? nameOf(formNames, "pokemon_form_id", formId, LANG_EN, "pokemon_name")
        : null;
      nameZh =
        formFullZh ||
        (nameZh && formPartZh ? `${nameZh}（${formPartZh}）` : null) ||
        (nameZh ? `${nameZh}（${p.identifier}）` : null);
      nameEn = formEn || capitalize(p.identifier);
    }
    if (!nameZh && !nameEn) continue;

    entries.push({
      id: pid, // PokeAPI pokemon id（型態唯一鍵）
      dex: speciesId, // 全國圖鑑編號
      identifier: p.identifier,
      name_en: nameEn,
      name_zh: nameZh,
      types: t.filter(Boolean),
      is_default: isDefault,
    });
  }
  entries.sort((a, b) => a.id - b.id);

  const pokedex = {
    source: "PokeAPI pokemon/pokemon_species_names/pokemon_types csv",
    language: "zh-Hant",
    count: entries.length,
    pokemon: entries,
  };

  // ---- 輸出 ----
  const dataDir = join(ROOT, "data");
  await mkdir(dataDir, { recursive: true });
  await writeFile(
    join(dataDir, "type_chart.json"),
    JSON.stringify(typeChart, null, 1)
  );
  await writeFile(
    join(dataDir, "pokedex.json"),
    JSON.stringify(pokedex, null, 1)
  );
  console.log(
    `已產生 data/type_chart.json（18×18）與 data/pokedex.json（${entries.length} 筆）`
  );

  // ---- 同步到 Swift Package Resources ----
  const swiftRes = join(
    ROOT,
    "swift",
    "PokemonChampionsCore",
    "Sources",
    "PokemonChampionsCore",
    "Resources"
  );
  const swiftTestRes = join(
    ROOT,
    "swift",
    "PokemonChampionsCore",
    "Tests",
    "PokemonChampionsCoreTests",
    "Resources"
  );
  await mkdir(swiftRes, { recursive: true });
  await mkdir(swiftTestRes, { recursive: true });
  await copyFile(join(dataDir, "type_chart.json"), join(swiftRes, "type_chart.json"));
  await copyFile(join(dataDir, "pokedex.json"), join(swiftRes, "pokedex.json"));
  try {
    await access(join(dataDir, "test_vectors.json"));
    await copyFile(
      join(dataDir, "test_vectors.json"),
      join(swiftTestRes, "test_vectors.json")
    );
  } catch {
    console.log("（尚無 data/test_vectors.json，略過複製）");
  }
  console.log("已同步至 Swift Package Resources。");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
