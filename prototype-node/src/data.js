// 載入 data/ 目錄的共用資料集（與 Swift Package 同一份來源）。
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const DATA_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "data");

export function loadJson(name) {
  return JSON.parse(readFileSync(join(DATA_DIR, name), "utf8"));
}

export const DATA_DIR_PATH = DATA_DIR;
