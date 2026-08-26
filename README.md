# 寶可夢對戰屬性即時查詢 — Phase 0 / Phase 1

依據《寶可夢屬性即時查詢App_專案規劃書》建置。這個 repo 涵蓋規劃書的前兩個階段：

- **Phase 0｜可行性驗證** — 離線原型：截圖 → OCR 讀名稱 → 查屬性剋制 → 輸出結果，並附一支會給出數字的準確率量測工具。
- **Phase 1｜核心資料層** — 屬性剋制計算、全國圖鑑（繁中）、賽季清單過濾，Node 與 **Swift 兩份實作**，測試互為驗收基準。

Swift 版在 [ios/PokemonChampionCore](ios/PokemonChampionCore)，透過 GitHub Actions 的
macOS runner 編譯與測試 —— **不需要 Mac**。框架選擇與打包路線的完整說明見 [ios/README.md](ios/README.md)。

---

## 快速開始

```bash
npm run fetch
```

從 PokéAPI 建立離線圖鑑（約 2,300 個請求，數分鐘；回應會快取在 `.cache/`，重跑只補缺的）。
產出 `data/pokedex.json`：1,351 筆、1,025 個物種、含地區形態與 Mega，繁中名稱零缺漏，392 KB。

```bash
npm test
```

53 項測試，涵蓋全部 3,078 種屬性組合與效能門檻。

```bash
node bin/pmc.mjs team 噴火龍,沙奈朵,耿鬼 水箭龜,班基拉斯,化石翼龍
```

---

## CLI

| 指令 | 用途 |
|---|---|
| `pmc who <名稱>` | 查一隻寶可夢的屬性、弱點、抗性 |
| `pmc vs <我方> <對方>` | 單挑：雙向倍率與勝負判定 |
| `pmc team <我方,...> <對方,...>` | 隊伍對隊伍矩陣 ＋ 威脅與解答 |
| `pmc type <屬性>[,<屬性>]` | 直接查屬性組合的防禦面 |
| `pmc calc <攻擊屬性> <防禦屬性...>` | 單一倍率 |
| `pmc find <文字>` | 模糊搜尋，用來 debug OCR 誤讀 |
| `pmc shot <圖片>` | 截圖 → 辨識雙方 → 剋制分析（Phase 0 完整管線） |
| `pmc info` | 資料庫狀態 |

共用選項：`--json`（輸出 JSON）、`--pool <檔案>`（載入賽季清單）、`--no-color`。

```
$ node bin/pmc.mjs who 班基拉斯

班基拉斯 #248 Tyranitar
  屬性      岩石 / 惡
  4× 致命   格鬥
  2× 被剋   水、草、地面、蟲、鋼、妖精
  ½ 抗性    一般、火、毒、飛行、幽靈、惡
  0× 無效   超能力
```

```
$ node bin/pmc.mjs team 噴火龍,沙奈朵,耿鬼,暴鯉龍 水箭龜,班基拉斯,化石翼龍

            水箭龜   班基拉斯 化石翼龍
  噴火龍    1/2      ½/4      ½/4
  沙奈朵    1/1      2/1      1/1
  耿鬼      1/1      ½/2      1/1
  暴鯉龍    1/½      2/2      2/2
  （每格＝我方本系打對方 / 對方本系打我方）

  最該注意
    ▲ 班基拉斯 可超效打中 3 隻，最重 4× → 噴火龍
    ▲ 化石翼龍 可超效打中 2 隻，最重 4× → 噴火龍
  你的解答
    ● 暴鯉龍 超效打中 2 隻 （會被 2× 反打）
    ● 沙奈朵 超效打中 1 隻 （不吃超效）

  動態島摘要  威脅 班基拉斯 → 噴火龍 4×   解答 暴鯉龍 → 班基拉斯 2×
```

---

## Phase 0：辨識管線

```
截圖 → 降取樣＋裁切 → Windows OCR (zh-Hant-TW) → 版面分邊 → 名稱正規化
     → 精確／模糊比對圖鑑 → 屬性剋制計算 → 摘要
```

### 為什麼用 Windows OCR 而不是 Tesseract

規劃書的 Phase 0 原文寫 Python 原型，但這台機器沒有 Python，而且更重要的是：
**Windows.Media.Ocr 跟 iOS 的 Vision `VNRecognizeTextRequest` 是同一類東西** ——
作業系統內建、針對繁中訓練、回傳帶座標的行與詞。用它量到的準確率與延遲，
對 iOS 才有參考價值；Tesseract 量出來的數字換到 Vision 上等於重來。

本機已安裝的辨識語言：`zh-Hant-TW`。

### 已驗證的發現

**降取樣會讓 OCR 變準，不是變糊。** 在合成測試圖（1170×2532，40pt 字）上實測：

| 縮放 | 辨識出的行數（應為 13） | 耗時 |
|---|---|---|
| 3× | 3 | 74ms |
| 2× | 5 | 66ms |
| 1× | 11 | 67ms |
| 0.6× | 11 | 51ms |
| **0.4×** | **12** | **37ms** |

Windows OCR 的文字偵測器有它偏好的字高範圍，手機截圖的文字對它來說偏大。
放大只會讓情況更糟。這個結論對 Phase 3 直接有用：**Broadcast Upload Extension
的記憶體配額很緊，而降解析度同時解決記憶體與準確率兩個問題** —— 規劃書把降解析度
列為記憶體不足時的「犧牲品」，實測顯示它其實是免費的收益。iOS 的 Vision 需要
用真機重測一次同樣的曲線，`--scale` 參數就是為了這件事留的。

`DEFAULT_LAYOUT.scale` 已據此設為 `0.4`。

**版面分邊有效。** 以畫面寬度比例切左右（`mineUntil: 0.45` / `theirsFrom: 0.5`），
中間地帶（標題、計時器）直接丟棄。合成測試圖上「對戰準備」被正確歸類為未解析，
沒有污染任何一邊的隊伍。

### 量測準確率

```bash
npm run measure
```

讀 `fixtures/labels.json` 的標準答案，逐張跑完整管線，印出正確率並以離開碼表示是否
達到規劃書的 90% 門檻（0 = 達標，1 = 未達標，2 = 設定有問題）。

```
Phase 0 OCR 準確率量測  （降取樣 0.4×）

  ✔ mock-battle.png  92%  (11/12)  OCR 47ms
      漏掉：超夢
      無法解析的文字：對戰準備

  總計    11/12 正確，誤判 0 筆
  正確率  91.7%  （門檻 90%）
  OCR 平均耗時  47ms

  ✔ 達標 —— 可以進入 Phase 1
```

> **這個 91.7% 不能拿來當 Phase 0 的驗收數字。** 它跑在
> `scripts/make-fixture.ps1` 產生的合成圖上 —— 純色背景、無襯線粗體、沒有動態模糊、
> 沒有半透明 UI 疊層、沒有特效遮擋。合成圖的唯一用途是證明管線接得起來。
>
> 要拿到真正的 Phase 0 數字，需要**真實對戰截圖**：把圖放進 `fixtures/`，
> 在 `fixtures/labels.json` 標好每張圖雙方的正確名單，再跑 `npm run measure`。
> 十張以上、涵蓋單打與雙打版面，數字才有意義。

### 產生合成測試圖

```bash
npm run fixture
```

---

## Phase 1：資料層

### 屬性剋制

`data/types.json` 手工建檔，第六世代之後的關係，以「攻擊方 → 超效／半減／免疫」
的稀疏形式記錄（比 324 格的密集表好審核）。載入時展開成 18×18 的 `Float64Array`
矩陣，之後所有查詢都是陣列索引。

```js
import { effectiveness, defenseProfile } from './src/typechart.mjs';

effectiveness('electric', ['water', 'flying']);  // 4
effectiveness('冰', ['龍', '飛行']);              // 4 — 繁中輸入也可以
defenseProfile(['steel', 'fairy']);              // { x4: [], x2: ['fire','ground'], x0: ['poison','dragon'], ... }
```

### 圖鑑與 OCR 容錯

`src/pokedex.mjs` 負責把「OCR 吐出來的髒字串」變成「圖鑑條目」：

1. **正規化** — 去掉等級（`Lv.50`）、性別符號（`♂♀`）、全形空白、標點；保留漢字、假名、拉丁字母、數字。
2. **精確命中** — 繁中、日文、英文、slug 都建了索引。
3. **模糊比對** — 上限式編輯距離，超過門檻提早收手。簡繁混用（`大葱鴨` → `大蔥鴨`）、形近字（`噴火竜` → `噴火龍`）都救得回來。
4. **形態收斂** — 同一物種中「戰鬥上等價」的形態（皮卡丘的各種帽子、屬性與本體相同的 Mega）收成一筆；屬性真的不同的形態（噴火龍 Mega X 是火/龍）保留。

### 賽季清單

規劃書把「縮小比對範圍」列為圖示辨識準確率不足時的主要因應手段。這裡已經實作，
而且對 OCR 同樣有效：

```bash
node bin/pmc.mjs --pool data/pool.example.json find 妙蛙化
```

把 `data/pool.json` 放好就會自動載入。實測效果：

- 模糊比對延遲從 **中位數 1.84ms 降到 0.13ms**（全圖鑑 1,351 筆 vs 限定 100 筆）
- 錯字被配到不相干寶可夢的機會大幅下降

（清單用物種名指定時，該物種的所有形態都會納入候選 —— 25 個名字會展開成 69 個條目。）

### 效能：Phase 1 驗收標準

規劃書要求「資料庫查詢單隻寶可夢剋制結果 < 10ms」。實測（`npm test` 會印出來）：

| 操作 | 中位數 | p95 |
|---|---|---|
| 單一倍率查詢 | 0.0004ms | 0.0008ms |
| **名稱查詢 ＋ 完整防禦總表** | **0.0057ms** | **0.0117ms** |
| 6v6 完整隊伍分析 | 0.065ms | 0.106ms |
| 動態島摘要 | 0.033ms | 0.045ms |
| 模糊比對（掃全圖鑑） | 1.84ms | 2.25ms |
| 模糊比對（限定 100 隻） | 0.13ms | 0.22ms |

量的是中位數與 p95，不是平均值 —— 平均值會被 JIT 暖機與 GC 掩蓋掉尾端延遲，
而在記憶體吃緊的 Broadcast Extension 裡，會出事的正是尾端。

**唯一超過 1ms 的路徑是模糊比對**，因為它會掃全圖鑑。這是 Phase 3 移植到 Extension
時第一個要盯的地方，賽季清單就是現成的解法。

---

## 測試

```bash
npm test
```

53 項，全數通過。重點涵蓋：

- **全部 3,078 種屬性組合**（18 種攻擊 × 171 種防禦組合＝18 單屬＋153 雙屬），期望值直接從 JSON 算，不經過受測模組，避免自己驗自己。
- 免疫優先、妖精三條關鍵關係、第六世代鋼屬性變更等最容易記錯的規則。
- OCR 雜訊容錯：等級前綴、性別符號、簡繁混用、形近字。
- 「完全不像名字的字串不會硬湊出結果」—— 寧可漏也不要餵錯資料給動態島。
- 效能門檻，會在退化時直接讓測試失敗。

---

## 檔案結構

```
data/
  types.json          18×18 屬性相剋（手工建檔，稀疏形式）
  pokedex.json        全國圖鑑（npm run fetch 產生）
  pool.example.json   賽季清單範本
src/
  typechart.mjs       屬性倍率計算
  pokedex.mjs         名稱解析、模糊比對、賽季清單
  matchup.mjs         單挑／隊伍分析、動態島摘要
  ocr.mjs             Windows OCR 的 Node 包裝
  pipeline.mjs        截圖 → 雙方隊伍 → 剋制分析
  format.mjs          終端機輸出
scripts/
  fetch-pokedex.mjs   建立離線圖鑑
  ocr.ps1             Windows.Media.Ocr 後端
  make-fixture.ps1    產生合成測試圖
  measure-ocr.mjs     Phase 0 準確率量測
  sync-swift-data.mjs 把 data/ 同步進 Swift package
test/                 53 項測試
bin/pmc.mjs           CLI
ios/PokemonChampionCore/  Swift 移植（見 ios/README.md）
.github/workflows/ci.yml  Ubuntu 跑 Node、macOS runner 跑 Swift
```

---

## Swift 移植（Phase 1）

```bash
npm run sync:swift    # 把 data/*.json 同步進 Swift package
```

`ios/PokemonChampionCore` 是一個純邏輯的 Swift Package，不 import UIKit / ReplayKit /
ActivityKit，因此主 App、Broadcast Extension、Widget Extension 三個 target 可以共用，
而且 `swift test` 在 CI 上不需要模擬器也不需要簽名。

測試與 Node 版一一對應（同樣涵蓋全部 3,078 種屬性組合），**移植的驗收標準就是兩邊算出來的數字一樣**。

`.github/workflows/ci.yml` 會在 Ubuntu 上跑 Node 測試、在 macOS runner 上編譯與測試
Swift，並檢查兩邊的資料檔有沒有漏同步。

> **這些 Swift 程式碼還沒有被任何編譯器看過** —— 這台機器沒有 Swift 工具鏈。
> 第一次推上 GitHub 時要預期 CI 會抓出編譯錯誤。

---

## 移植到 iOS 時的對應關係

| 這裡 | iOS |
|---|---|
| `scripts/ocr.ps1` | `Vision` / `VNRecognizeTextRequest`（`recognitionLanguages = ["zh-Hant"]`） |
| `src/ocr.mjs` 的介面 | 同形狀的 Swift wrapper，回傳帶 bounding box 的行 |
| `src/typechart.mjs` | ✔ 已完成 → `TypeChart.swift` |
| `src/pokedex.mjs` | ✔ 已完成 → `Pokedex.swift` |
| `src/matchup.mjs` | ✔ 已完成 → `Matchup.swift` |
| `data/*.json` | 直接進 app bundle，不需連網 |
| `src/pipeline.mjs` 的 `DEFAULT_LAYOUT` | Extension 內的版面規則，比例制所以跨機型通用 |
| `liveSummary()` 的輸出 | `LiveSummary`（已寫成 `Codable`，可直接當 `ContentState`） |
| `test/` | 移植後的驗收基準，數字直接沿用 |

---

## 尚未處理

- **圖示比對**（規劃書 Phase 0 的第二個驗收項目：20 隻常見寶可夢 Top-1 ≥ 80%）。
  需要對手圖示的參考圖庫與真實截圖才有辦法建立與量測；`data/pokedex.json` 已經
  存好每一筆的 `sprite` URL，可以直接拿來建參考庫。
- **真實截圖的準確率數字** —— 見上面 Phase 0 那段。
- **Swift 版的編譯驗證** —— 需要推上 GitHub 讓 macOS runner 跑一次。
- **Phase 2 之後** —— Xcode 專案（主 App + Broadcast Extension + Widget Extension）
  需要一次 Mac 或雲端 Mac 的互動 session 建立；Phase 3 與 Phase 6 的記憶體與真機測試
  需要 Instruments。其餘階段都能在 Windows 上完成，說明見 [ios/README.md](ios/README.md)。
