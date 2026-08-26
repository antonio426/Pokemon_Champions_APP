# Pokemon_Champions_APP

寶可夢對戰屬性即時查詢 — 螢幕錄製擷取畫面，OCR 辨識雙方寶可夢，將屬性剋制資訊即時顯示於 iOS 動態島。含 18×18 屬性剋制引擎與繁中全國圖鑑，Node 原型與 Swift 兩份實作互為驗收基準。

**開發規劃書：[docs/PLAN.md](docs/PLAN.md)**（分階段計畫、Windows/macOS 環境策略、風險對策）

## 目前進度

- ✅ **Phase 0**：Node 原型完成 —— 資料集、剋制引擎、模糊比對、OCR 管線、CLI，12 項測試全綠，端到端 OCR 冒煙測試通過
- ✅ **Phase 1**：核心 Swift Package 程式碼完成（`swift/PokemonChampionsCore/`），待 Linux/macOS 跑 `swift test`
- ⏳ **Phase 2+**：iOS App（需 macOS / Xcode），見規劃書

## 快速開始（Windows/Ubuntu，Node 24+）

```bash
cd prototype-node
npm install
npm test                          # 12 項測試（含共用驗收向量）
node src/cli.js vs 皮卡丘 噴火龍   # 對戰分析
node src/cli.js def 烈咬陸鯊       # 防禦弱點表
node src/cli.js scan fixtures/battle_sample.png   # OCR 截圖 → 報告
```

## 資料集

`data/` 由 `node tools/fetch_data.mjs` 從 [PokeAPI](https://github.com/PokeAPI/pokeapi) 官方 CSV 產生：

- `type_chart.json` — 18×18 屬性剋制表（繁中/英文屬性名）
- `pokedex.json` — 全國圖鑑 1351 筆（含特殊型態繁中名，如「雷丘（阿羅拉的樣子）」）
- `test_vectors.json` — 共用驗收向量與演算法規格；Node 與 Swift 測試都必須全綠

執行產生器會同步把資料複製進 Swift Package 的 Resources，兩份實作永遠讀同一份資料。
