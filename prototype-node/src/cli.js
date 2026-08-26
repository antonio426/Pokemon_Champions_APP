#!/usr/bin/env node
// CLI：在桌面上模擬未來 App 的查詢體驗。
//
//   node src/cli.js vs <我方> <對方>      雙方對戰分析（例：vs 皮卡丘 噴火龍）
//   node src/cli.js def <名稱>            單隻防禦弱點表
//   node src/cli.js lookup <名稱>         圖鑑查詢（含模糊比對）
//   node src/cli.js text "<一段文字>" [--mine 名稱]   從文字擷取並分析
//   node src/cli.js scan <截圖檔> [--mine 名稱]       OCR 截圖並分析

import { loadJson } from "./data.js";
import { TypeChart } from "./typechart.js";
import { Pokedex } from "./pokedex.js";
import { analyze, fmtMult } from "./matchup.js";
import { analyzeText, analyzeImage } from "./pipeline.js";

const chart = new TypeChart(loadJson("type_chart.json"));
const dex = new Pokedex(loadJson("pokedex.json"));

function resolveOrExit(name) {
  const hit = dex.lookup(name) ?? dex.fuzzy(name)?.entry;
  if (!hit) {
    console.error(`找不到寶可夢：「${name}」`);
    process.exit(1);
  }
  return hit;
}

function printReport(r) {
  const opp = r.opponent;
  console.log(`\n◤ 對方：${opp.name_zh}（${opp.name_en}） #${opp.dex} [${opp.types_zh.join("/")}]`);
  if (r.mine)
    console.log(`◣ 我方：${r.mine.name_zh}（${r.mine.name_en}） #${r.mine.dex} [${r.mine.types_zh.join("/")}]`);

  const line = (items) =>
    items.map((o) => `${o.type_zh}${fmtMult(o.multiplier)}`).join("　") || "（無）";
  console.log(`\n打「${opp.name_zh}」特效（>1×）：${line(r.weaknesses)}`);
  console.log(`抗性（<1×）：${line(r.resistances)}`);
  console.log(`無效（0×）：${line(r.immunities)}`);

  if (r.my_stab) {
    console.log(`\n我方本屬性輸出：${line(r.my_stab)}`);
    console.log(`對方本屬性威脅：${line(r.threats)}`);
  }
  console.log();
}

function parseMine(args) {
  const i = args.indexOf("--mine");
  if (i === -1) return { rest: args, mineName: undefined };
  const mineName = args[i + 1];
  return { rest: [...args.slice(0, i), ...args.slice(i + 2)], mineName };
}

const [cmd, ...args] = process.argv.slice(2);

switch (cmd) {
  case "vs": {
    const [mineName, oppName] = args;
    if (!mineName || !oppName) {
      console.error("用法：node src/cli.js vs <我方> <對方>");
      process.exit(1);
    }
    printReport(analyze(chart, resolveOrExit(mineName), resolveOrExit(oppName)));
    break;
  }
  case "def": {
    const target = resolveOrExit(args[0] ?? "");
    printReport(analyze(chart, null, target));
    break;
  }
  case "lookup": {
    const q = args[0] ?? "";
    const exact = dex.lookup(q);
    const hit = exact ?? dex.fuzzy(q)?.entry;
    if (!hit) {
      console.error(`找不到：「${q}」`);
      process.exit(1);
    }
    if (!exact) console.log(`（模糊比對：「${q}」→「${hit.name_zh}」）`);
    console.log(JSON.stringify(hit, null, 2));
    break;
  }
  case "text": {
    const { rest, mineName } = parseMine(args);
    const result = analyzeText(chart, dex, rest.join(" "), { mineName });
    if (!result.reports.length) {
      console.log("文字中沒有找到寶可夢名稱。");
      break;
    }
    console.log(`擷取到：${result.found.map((p) => p.name_zh).join("、")}`);
    result.reports.forEach(printReport);
    break;
  }
  case "scan": {
    const { rest, mineName } = parseMine(args);
    const imagePath = rest[0];
    if (!imagePath) {
      console.error("用法：node src/cli.js scan <截圖檔> [--mine 名稱]");
      process.exit(1);
    }
    console.log("OCR 辨識中…（首次執行會下載 chi_tra 語言資料）");
    const result = await analyzeImage(chart, dex, imagePath, { mineName });
    console.log(`OCR 信心值：${result.ocr.confidence?.toFixed(1) ?? "?"}`);
    console.log(`OCR 文字：${result.ocr.text.replace(/\s+/g, " ").trim().slice(0, 200)}`);
    if (!result.reports.length) {
      console.log("截圖中沒有辨識到寶可夢名稱。");
      break;
    }
    console.log(`擷取到：${result.found.map((p) => p.name_zh).join("、")}`);
    result.reports.forEach(printReport);
    break;
  }
  default:
    console.log(
      [
        "Pokemon Champions 屬性查詢原型",
        "",
        "  vs <我方> <對方>              雙方對戰分析",
        "  def <名稱>                    單隻防禦弱點表",
        "  lookup <名稱>                 圖鑑查詢（含模糊比對）",
        '  text "<文字>" [--mine 名稱]   從文字擷取並分析',
        "  scan <截圖檔> [--mine 名稱]   OCR 截圖並分析",
      ].join("\n")
    );
}
