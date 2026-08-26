#!/usr/bin/env node
/**
 * 從 PokéAPI 抓取全國圖鑑，產出 data/pokedex.json。
 *
 * 產出的資料是「離線封裝」用的：App 執行期不連網，所有辨識與查詢都吃這份 JSON。
 * 回應會快取在 .cache/，重跑時只補缺的，中斷可續。
 *
 *   node scripts/fetch-pokedex.mjs [--concurrency 12] [--limit N] [--refresh]
 */
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const CACHE = path.join(ROOT, '.cache');
const API = 'https://pokeapi.co/api/v2';

const argv = process.argv.slice(2);
const flag = (name, fallback) => {
  const i = argv.indexOf(`--${name}`);
  return i === -1 ? fallback : argv[i + 1];
};
const CONCURRENCY = Number(flag('concurrency', 12));
const LIMIT = Number(flag('limit', 0)) || Infinity;
const REFRESH = argv.includes('--refresh');

/** 地區形態 / 特殊形態的中文標籤，用來組出「皮卡丘（阿羅拉的樣子）」這種可讀名稱。 */
const FORM_LABELS = [
  [/-alola$/, '阿羅拉的樣子'],
  [/-galar$/, '伽勒爾的樣子'],
  [/-hisui$/, '洗翠的樣子'],
  [/-paldea$/, '帕底亞的樣子'],
  [/-mega-x$/, 'Mega X'],
  [/-mega-y$/, 'Mega Y'],
  [/-mega$/, 'Mega'],
  [/-gmax$/, '超極巨化'],
  [/-therian$/, '靈獸形態'],
  [/-incarnate$/, '化身形態'],
  [/-origin$/, '起源形態'],
  [/-altered$/, '別種形態'],
  [/-sky$/, '天空形態'],
  [/-land$/, '陸上形態'],
  [/-black$/, '黑色形態'],
  [/-white$/, '白色形態'],
  [/-dusk$/, '黃昏之鬃'],
  [/-dawn$/, '拂曉之翼'],
  [/-ice$/, '疾風形態'],
  [/-shadow$/, '猛火形態'],
  [/-crowned$/, '王者形態'],
  [/-eternamax$/, '無極巨化'],
  [/-primal$/, '原始回歸'],
];

async function getJSON(url) {
  const key = createHash('sha1').update(url).digest('hex') + '.json';
  const file = path.join(CACHE, key);
  if (!REFRESH && existsSync(file)) {
    try {
      return JSON.parse(await readFile(file, 'utf8'));
    } catch {
      /* 快取毀了就當沒有，重抓 */
    }
  }
  for (let attempt = 1; ; attempt++) {
    try {
      const res = await fetch(url, { headers: { 'user-agent': 'pokemon-champion/0.1 (offline dex build)' } });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      await writeFile(file, JSON.stringify(json), 'utf8');
      return json;
    } catch (err) {
      if (attempt >= 4) throw new Error(`抓取失敗 ${url}：${err.message}`);
      await new Promise((r) => setTimeout(r, 400 * 2 ** attempt));
    }
  }
}

/** 固定併發數跑完整批工作，並回報進度。 */
async function mapPool(items, worker, { concurrency, label }) {
  const results = new Array(items.length);
  let next = 0;
  let done = 0;
  const tick = () => {
    done++;
    if (done % 25 === 0 || done === items.length) {
      process.stdout.write(`\r  ${label}：${done}/${items.length}`);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(concurrency, items.length) }, async () => {
      while (true) {
        const i = next++;
        if (i >= items.length) return;
        results[i] = await worker(items[i], i);
        tick();
      }
    })
  );
  process.stdout.write('\n');
  return results;
}

function pickName(names, lang) {
  return names.find((n) => n.language.name === lang)?.name ?? null;
}

function formLabel(slug, speciesSlug) {
  if (slug === speciesSlug) return null;
  for (const [re, label] of FORM_LABELS) if (re.test(slug)) return label;
  const suffix = slug.startsWith(`${speciesSlug}-`) ? slug.slice(speciesSlug.length + 1) : slug;
  return suffix.replace(/-/g, ' ');
}

async function main() {
  await mkdir(CACHE, { recursive: true });
  console.log('→ 取得物種清單…');
  const index = await getJSON(`${API}/pokemon-species?limit=20000`);
  const speciesRefs = index.results.slice(0, LIMIT === Infinity ? undefined : LIMIT);
  console.log(`  共 ${speciesRefs.length} 個物種`);

  console.log('→ 取得物種詳細資料（多語名稱、形態清單）…');
  const species = await mapPool(speciesRefs, (ref) => getJSON(ref.url), {
    concurrency: CONCURRENCY,
    label: '物種',
  });

  const formRefs = [];
  for (const s of species) {
    for (const v of s.varieties) {
      formRefs.push({ species: s, url: v.pokemon.url, slug: v.pokemon.name, isDefault: v.is_default });
    }
  }
  console.log(`→ 取得 ${formRefs.length} 個形態的屬性資料…`);
  const forms = await mapPool(formRefs, (ref) => getJSON(ref.url), {
    concurrency: CONCURRENCY,
    label: '形態',
  });

  const entries = [];
  for (let i = 0; i < formRefs.length; i++) {
    const ref = formRefs[i];
    const form = forms[i];
    const s = ref.species;
    const zh = pickName(s.names, 'zh-hant');
    const label = ref.isDefault ? null : formLabel(ref.slug, s.name);
    entries.push({
      id: form.id,
      speciesId: s.id,
      slug: ref.slug,
      isDefault: ref.isDefault,
      zh: label && zh ? `${zh}（${label}）` : zh,
      zhBase: zh,
      form: label,
      ja: pickName(s.names, 'ja') ?? pickName(s.names, 'ja-hrkt'),
      en: pickName(s.names, 'en') ?? s.name,
      types: form.types.sort((a, b) => a.slot - b.slot).map((t) => t.type.name),
      sprite:
        form.sprites?.other?.['official-artwork']?.front_default ??
        form.sprites?.front_default ??
        null,
    });
  }

  entries.sort((a, b) => a.speciesId - b.speciesId || (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0) || a.id - b.id);

  const missingZh = entries.filter((e) => !e.zh).length;
  const out = {
    source: 'https://pokeapi.co/',
    generatedAt: new Date().toISOString(),
    count: entries.length,
    entries,
  };
  const target = path.join(ROOT, 'data', 'pokedex.json');
  await writeFile(target, JSON.stringify(out, null, 0), 'utf8');
  console.log(`✔ 已寫入 data/pokedex.json：${entries.length} 筆（缺繁中名 ${missingZh} 筆）`);
}

main().catch((err) => {
  console.error(`\n✖ ${err.message}`);
  process.exit(1);
});
