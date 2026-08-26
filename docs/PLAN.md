# Pokemon Champions 屬性即時查詢 App — 開發規劃書

> 最後更新：2026-08-26。Phase 0 與 Phase 1 的程式碼已在本 repo 完成（見下方進度標記）。

## 1. 產品目標

在《Pokemon Champions》對戰進行中，玩家不需切出遊戲：

1. iOS **螢幕錄製**（ReplayKit Broadcast Upload Extension）即時取得遊戲畫面
2. **OCR**（Vision framework，繁體中文）辨識畫面上雙方寶可夢名稱
3. **18×18 屬性剋制引擎** 查出弱點、抗性、無效與雙方 STAB 威脅
4. 結果即時顯示於**動態島**（ActivityKit Live Activity）

## 2. 架構總覽

```mermaid
flowchart LR
    subgraph 共用資料層["共用資料層 data/（PokeAPI 產生）"]
        TC[type_chart.json<br/>18×18 剋制表]
        DX[pokedex.json<br/>繁中全國圖鑑 1351 筆]
        TV[test_vectors.json<br/>共用驗收向量]
    end
    subgraph Node 原型["Node 原型（Windows/Ubuntu）"]
        NOCR[tesseract.js chi_tra] --> NPIPE[normalize → extract → matchup]
    end
    subgraph Swift 實作["Swift（iOS 上線用）"]
        VOCR[Vision OCR zh-Hant] --> SPIPE[PokemonChampionsCore<br/>同一套演算法]
        SPIPE --> ISLAND[ActivityKit 動態島]
    end
    共用資料層 --> Node 原型
    共用資料層 --> Swift 實作
```

核心設計：**同一份資料、同一套演算法規格、兩份實作互為驗收基準**。
`data/test_vectors.json` 內含演算法規格（spec 欄位）與全部向量，Node 與 Swift 測試都必須全綠。

### 端到端資料流（兩邊一致）

```
畫面/截圖 → OCR → normalizeOcrText（去除 CJK 間空白）→ extract（最長名稱比對）
         → fuzzy（Levenshtein 容錯）→ analyze（剋制報告）→ UI／動態島
```

## 3. 開發環境策略：Windows/Ubuntu 能做什麼、何時需要 macOS

| 階段 | Windows/Ubuntu | 說明 |
|---|---|---|
| Phase 0 原型 | ✅ 完全可行 | Node + tesseract.js，本機已完成並驗證 |
| Phase 1 核心邏輯 | ✅ 撰寫可行；測試需 Linux/macOS | 純 Swift Package 零 Apple 框架依賴；Ubuntu 官方 Swift 工具鏈可 `swift test` |
| Phase 2 截圖匯入版 App | ❌ | SwiftUI / Vision / PhotosPicker 需 Xcode（僅 macOS） |
| Phase 3 即時版 | ❌ | ReplayKit / ActivityKit / Instruments 壓測需 macOS + 實體 iPhone |
| Phase 4 上架 | ❌ | 簽署、上傳、TestFlight 需 Xcode |

**macOS 取得路徑（建議順序）**：

1. **進 Phase 2 前**：先租雲端 Mac（MacStadium、MacinCloud、AWS EC2 Mac…）驗證可行性，風險最低
2. **確定走到 Phase 3**：購入 Mac mini——Extension 記憶體壓測要反覆用 Instruments + 實機插線除錯，遠端延遲會嚴重拖慢效率，長期成本也低於持續租用
3. **獨立固定成本**：Apple Developer Program 年費（US$99），真機安裝、TestFlight、上架皆需要，與開發機方案無關

**本機補充選項**：Windows 上安裝 WSL2 + Ubuntu 後即可跑 Phase 1 的 `swift test`（本機目前未安裝 WSL，需系統管理員權限與重開機）。

## 4. 分階段計畫

### Phase 0 — Node 原型（✅ 已完成，2026-08-26）

位置：`prototype-node/`

- [x] 資料集產生器 `tools/fetch_data.mjs`（PokeAPI CSV → JSON，含繁中型態名）
- [x] 18×18 剋制引擎、圖鑑查詢、Levenshtein 模糊比對、名稱擷取
- [x] 對戰分析（弱點/抗性/無效/STAB/威脅）
- [x] OCR 管線（tesseract.js `chi_tra`）+ CLI（`vs`/`def`/`lookup`/`text`/`scan`）
- [x] 12 項測試全綠（含共用驗收向量）
- [x] **端到端冒煙測試通過**：合成戰鬥截圖 → OCR → 正確報告（`fixtures/battle_sample.png`）

**Phase 0 的關鍵發現**：tesseract 對繁中會在字元間插空白（「噴火龍」→「噴火 龍」），
名稱擷取前必須做 CJK 間空白正規化。此規則已寫入共用規格（`normalize_ocr`），
iOS Vision 端也要套用同一前處理。

### Phase 1 — 核心 Swift Package（✅ 程式碼完成；⏳ 待 Linux/macOS 驗證）

位置：`swift/PokemonChampionsCore/`

- [x] `TypeChart` / `Pokedex` / `Matchup` / `CoreDataStore`，演算法與 Node 一對一對應
- [x] 資料檔內嵌為 SwiftPM resources（由 `tools/fetch_data.mjs` 同步，勿手改）
- [x] XCTest 讀取同一份 `test_vectors.json`
- [ ] 在 Ubuntu（或 WSL2 / 雲端 Mac）執行 `swift test` 確認全綠 ← **下一個里程碑**

### Phase 2 — 截圖匯入版 iOS App（需 macOS）

不碰 ReplayKit，先用「手動匯入截圖」驗證真實遊戲畫面的 OCR 命中率：

- SwiftUI App + PhotosPicker 匯入對戰截圖
- Vision `VNRecognizeTextRequest`（`recognitionLanguages = ["zh-Hant"]`，iOS 16+）
- 重用 `PokemonChampionsCore`（Phase 1 成果原封不動搬入）
- 收集真實截圖建立 fixtures 回歸測試（比照 `fixtures/battle_sample.png` 模式）
- 此版本已可上 TestFlight 給朋友試用

### Phase 3 — 即時版：螢幕錄製 + 動態島（需 macOS + 實體 iPhone）

- ReplayKit **Broadcast Upload Extension** 接收畫面幀
  - ⚠️ 核心風險：Extension 記憶體上限約 **50MB**，超限直接被系統終止
  - 對策：降採樣後再 OCR、只裁切名稱出現的 ROI 區域、節流丟幀（例如每秒 1–2 幀）、
    畫面無變化時跳過（幀差偵測）
- Extension → 主 App：App Group（UserDefaults / 檔案）傳遞辨識結果
- ActivityKit Live Activity 顯示於動態島；**只在辨識到的寶可夢改變時 update**（ActivityKit 有更新頻率節流）
- Instruments（Allocations / Leaks）反覆壓測 Extension 記憶體——此階段強烈建議實體 Mac + 插線 iPhone

### Phase 4 — 上架（需 macOS）

- App Store 審查注意事項：
  - 不得內嵌任何官方美術素材（圖示、寶可夢圖片）；名稱/屬性資料來自開源 PokeAPI
  - 螢幕錄製需清楚的隱私聲明（畫面只在裝置上處理、不上傳）
  - 定位為「對戰輔助查詢工具」，避免宣稱與任天堂/寶可夢公司有關聯
- TestFlight 公測 → 正式送審

## 5. 風險與對策

| 風險 | 影響 | 對策 |
|---|---|---|
| Extension 50MB 記憶體上限 | Phase 3 直接失敗 | ROI 裁切、降採樣、丟幀；Phase 3 一開始就上 Instruments，不要最後才測 |
| OCR 誤字/斷字 | 辨識不到寶可夢 | 已驗證：正規化 + 最長比對 + Levenshtein 容錯；持續收集真實截圖擴充向量 |
| 動態島更新節流 | 顯示延遲 | 只在結果變化時 update；同場對戰用同一個 Live Activity |
| 遊戲 UI 未知/改版 | ROI 與字型失準 | ROI 設成可配置；fixtures 回歸測試在改版後快速校準 |
| 版權 | 下架風險 | 不用官方素材；資料來源標注 PokeAPI |
| Windows Swift 工具鏈不成熟 | Phase 1 驗證卡住 | 用 WSL2 Ubuntu 或雲端 Mac 跑 `swift test`；程式碼本身零平台依賴 |

## 6. 驗收基準

- 唯一真相：`data/test_vectors.json`（含演算法規格 spec）
- Node：`cd prototype-node && npm test` → 12/12 綠（✅ 目前狀態）
- Swift：`cd swift/PokemonChampionsCore && swift test` → 全綠（⏳ 待 Linux/macOS 環境）
- 兩邊任何演算法改動：先改 spec 與向量，再同步改兩份實作

## 7. Repo 結構

```
data/                         共用資料集（tools/fetch_data.mjs 產生）
  type_chart.json             18×18 剋制表（繁中/英文屬性名）
  pokedex.json                全國圖鑑 1351 筆（含特殊型態繁中名）
  test_vectors.json           共用驗收向量 + 演算法規格
tools/fetch_data.mjs          從 PokeAPI CSV 重建 data/ 並同步 Swift resources
prototype-node/               Phase 0 原型（Node 24）
  src/                        typechart / pokedex / matchup / pipeline / ocr / cli
  test/                       12 項測試（含共用向量）
  fixtures/battle_sample.png  OCR 冒煙測試用合成截圖
swift/PokemonChampionsCore/   Phase 1 核心（SwiftPM，Linux 可測）
docs/PLAN.md                  本文件
```

## 8. 下一步（依序）

1. **驗證 Phase 1**：在 Ubuntu／WSL2／雲端 Mac 執行 `swift test`（唯一還沒綠的格子）
2. 遊戲實際畫面到手後：收集真實對戰截圖 → `prototype-node` 跑 `scan` 驗證命中率 → 擴充 fixtures 與向量
3. 進 Phase 2 前：決定 macOS 方案（建議先租雲端 Mac 試水）
4. 註冊 Apple Developer Program（US$99/年）
5. Phase 2 開工：Xcode 專案 + 截圖匯入 + Vision OCR，直接引用 `PokemonChampionsCore`
