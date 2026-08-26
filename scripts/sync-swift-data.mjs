#!/usr/bin/env node
/**
 * 把 data/*.json 同步進 Swift package 的資源目錄。
 *
 * Node 版與 Swift 版必須吃「同一份」資料，否則兩邊的測試各自通過卻算出不同結果，
 * 移植的驗收就失去意義。這支腳本是唯一的同步管道，CI 也會跑它並檢查有沒有漏同步。
 *
 *   node scripts/sync-swift-data.mjs         同步
 *   node scripts/sync-swift-data.mjs --check 只檢查是否已同步（CI 用，不一致就非零離開）
 */
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const SOURCE = path.join(ROOT, 'data');
const TARGET = path.join(ROOT, 'ios', 'PokemonChampionCore', 'Sources', 'PokemonChampionCore', 'Resources');
const FILES = ['types.json', 'pokedex.json'];

const CHECK = process.argv.includes('--check');
const digest = (buf) => createHash('sha256').update(buf).digest('hex').slice(0, 12);

let drift = false;
await mkdir(TARGET, { recursive: true });

for (const name of FILES) {
  const from = path.join(SOURCE, name);
  const to = path.join(TARGET, name);

  if (!existsSync(from)) {
    console.error(`✖ 來源不存在：data/${name}` + (name === 'pokedex.json' ? '（先跑 npm run fetch）' : ''));
    process.exit(2);
  }

  const src = await readFile(from);
  const dstExists = existsSync(to);
  const dst = dstExists ? await readFile(to) : null;
  const same = dstExists && src.equals(dst);

  if (CHECK) {
    if (same) {
      console.log(`  ✔ ${name}  ${digest(src)}`);
    } else {
      drift = true;
      console.log(`  ✖ ${name}  data/=${digest(src)}  swift/=${dstExists ? digest(dst) : '(缺檔)'}`);
    }
    continue;
  }

  if (same) {
    console.log(`  ─ ${name} 已是最新`);
  } else {
    await writeFile(to, src);
    console.log(`  → ${name} 已同步（${(src.length / 1024).toFixed(0)} KB, ${digest(src)}）`);
  }
}

if (CHECK && drift) {
  console.error('\n✖ Swift 資源與 data/ 不一致，請執行：node scripts/sync-swift-data.mjs');
  process.exit(1);
}
