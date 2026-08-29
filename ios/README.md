# iOS：在 Windows 上開發這個 App

## 結論先講

「Windows 開發 iOS」的通用建議是 **React Native + Expo + Expo Go 即時預覽 + EAS Build 雲端打包**。
這套建議的**後半段（雲端打包）完全適用**，已經照做了；**前半段（框架選擇）套在這個 App 上會踩空**。

原因是這個 App 的核心功能全都落在 Expo Go 碰不到的地方：

| 規劃書的核心元件 | Expo Go | React Native（development build） | 誰來寫 |
|---|---|---|---|
| Broadcast Upload Extension（ReplayKit） | ✗ 完全不支援 | 需要 config plugin 建立額外 target | **Swift** |
| Extension 內的 Vision OCR | ✗ | ✗ JS 不在那個行程裡執行 | **Swift** |
| App Group 共享容器 | ✗ | config plugin 可設定 entitlement | Swift / 橋接 |
| Live Activity / 動態島 | ✗ | 需要 WidgetKit extension target | **Swift（SwiftUI）** |
| 主 App UI（截圖匯入、設定） | ✓ | ✓ | JS / TS |

**Expo Go 直接出局** —— 它只能跑純 JS，任何 app extension 都不行。掃 QR Code 秒級熱更新那條路，
在這個專案從第一天就不存在。

至於完整的 React Native（development build）：Broadcast Upload Extension 與 Live Activity
確實可以透過 config plugin 建立 target（[LiveKit](https://github.com/livekit/client-sdk-react-native-expo-plugin)、
[Stream](https://getstream.io/video/docs/react-native/guides/screensharing/expo/)、
[VideoSDK](https://docs.videosdk.live/react-native/guide/video-and-audio-calling-api-sdk/extras/expo-ios-screen-share)
都有現成的做法），[Expo 官方也支援 Live Activity](https://expo.dev/blog/home-screen-widgets-and-live-activities-in-expo)。
但這些 plugin 做的是「幫你把 target 接進 Xcode 專案」，**target 裡面的程式碼仍然是 Swift**。

而這個專案的風險幾乎全部集中在那些 Swift 裡：

- **Broadcast Upload Extension 有 50MB 的硬性記憶體上限**，超過就被 jetsam 直接砍掉
  （[Apple Developer Forums](https://developer.apple.com/forums/thread/131210)）。
  更麻煩的是 ReplayKit 自己就吃掉一大塊 —— 有回報指出使用者程式碼只用了 25MB 仍被砍
  （[iPad 大畫面的案例](https://developer.apple.com/forums/thread/651367)）。
  在這種預算下再塞一個 JS runtime 是不可能的。
- Vision OCR、影格處理、降取樣，全部得在那 50MB 內完成。
- 規劃書把 Phase 3 標為「整個專案風險最高的一步」，判斷是對的。

**所以結論是：原生 Swift + 雲端 macOS CI。** 加一層 React Native 只會讓風險最低的
主 App UI 變方便，卻在風險最高的地方多一層要維護的膠水。

---

## 那「Windows 開發」還成立嗎？成立。

| 工作 | 在 Windows 做得到？ |
|---|---|
| 寫 Swift、寫測試 | ✓ 任何編輯器 |
| 屬性剋制、圖鑑、比對邏輯 | ✓ 已完成，見下 |
| 編譯與跑單元測試 | ✓ 推上 GitHub，macOS runner 代跑 |
| 產生 .ipa、上 TestFlight | ✓ CI 加簽名設定即可 |
| **對著 iPhone 除錯 Extension 的記憶體** | ✗ 需要 Xcode Instruments |
| **在模擬器/真機上看 UI** | ✗ |

**唯一真正需要 Mac 的是 Phase 3 和 Phase 6** —— Extension 的記憶體壓力測試與真機整合測試。
那也正好是規劃書標為最高風險的兩個階段。前面所有階段都可以在這台 Windows 上完成。

三種打包路線對這個專案的適用性：

| 方案 | 適用 | 說明 |
|---|---|---|
| **GitHub Actions（macOS runner）** | ✓ 首選 | 已建好 `.github/workflows/ci.yml`。公開 repo 免費；私有 repo 的 macOS 用量以 10 倍計費，所以 workflow 特意把 Swift job 與 Node job 分開 |
| Codemagic / Bitrise | ✓ | 有免費額度，UI 比 YAML 友善 |
| Expo EAS Build | ✗ | 綁 Expo 生態，這個專案不走 RN |
| 租 MacinCloud / 舊 Mac mini | ✓ 後期必要 | Phase 3 與 Phase 6 需要 Instruments 與真機除錯時 |

**Apple Developer Program（US$99/年）是硬需求**，不是可選項：App Group entitlement 與
Live Activity 都無法用免費的 7 天個人簽名。這筆錢要在 Phase 3 開始前就付。

---

## 已完成：`PokemonChampionCore`

規劃書 Phase 1「把 Phase 0 驗證過的邏輯搬進 Swift，做成獨立可測試的模組」。

```
ios/PokemonChampionCore/
  Package.swift
  Sources/PokemonChampionCore/
    TypeChart.swift      屬性倍率計算（18×18 密集矩陣）
    Pokedex.swift        名稱解析、OCR 容錯、賽季清單
    Matchup.swift        單挑／隊伍分析、LiveSummary
    Resources/           types.json + pokedex.json（由 data/ 同步）
  Tests/PokemonChampionCoreTests/
    TypeChartTests.swift  含全部 3,078 種屬性組合
    PokedexTests.swift
    MatchupTests.swift
```

刻意只放**純邏輯 + 資料**，不 import UIKit / ReplayKit / ActivityKit。這樣：

- 主 App、Broadcast Extension、Widget Extension 三個 target 都能共用同一份邏輯。
- `swift test` 在 macOS runner 上直接跑完，**不需要模擬器、不需要簽名**，CI 又快又便宜。
- Extension 那 50MB 的預算裡，只裝真正需要的東西。

測試與 Node 版一一對應 —— 移植的驗收標準就是「兩邊算出來的數字一樣」。
`LiveSummary` 已經寫成 `Codable`，之後直接當 Live Activity 的 `ContentState`，
測試也已經驗過它序列化後小於 512 bytes。

### 資料同步

Node 版與 Swift 版必須吃同一份 JSON，否則兩邊測試各自通過卻算出不同結果。

```bash
npm run sync:swift
```

CI 會跑 `--check` 版本，漏同步就讓建置失敗。

---

## Phase 2 已完成：三個 target 的 Xcode 專案

規劃書 Phase 2 的「建 Xcode 專案（主 App + Broadcast Extension + Widget Extension）」
已經做完，而且**不需要互動式 Xcode session** —— 專案由 [project.yml](project.yml)
（XcodeGen）定義，`.xcodeproj` 是生成物：

```bash
brew install xcodegen
cd ios && xcodegen generate
```

```
ios/
  project.yml           三個 target 的完整定義（bundle id、entitlements、Info.plist 都在這）
  App/                  主 App：對戰分析、截圖辨識（Vision）、圖鑑、屬性、設定
  Shared/               跨 target 共用：VisionTeamReader、BattleActivityAttributes、AppGroup
  BattleWidget/         Live Activity／動態島
  BroadcastExtension/   ReplayKit SampleHandler（Phase 3 鷹架，記憶體策略見原始碼註解）
```

管線邏輯（分邊、解析、去重）在核心 package 的 `Recognition.swift`，有測試；
App 與 Extension 只把 Vision 的輸出餵進去。CI 的 `app` job 會建置全部三個
target 並上傳模擬器版 .app artifact。

### 已知的 Phase 3 開放問題（規劃書標記的最高風險，需真機驗證）

- Broadcast Extension 的 50MB 上限：SampleHandler 已用「節流 + CVPixelBuffer 直送
  + regionOfInterest + autoreleasepool」的組合把配置壓到最低，但數字要 Instruments 量。
- **Extension 不能啟動 Live Activity**，目前走「App 先啟動 → Extension 寫 App Group →
  App 回前景時更新」。真正的即時更新要嘛走 ActivityKit push（需要伺服器），
  要嘛接受回前景才刷新 —— 這個取捨要在 Phase 3 用真機做了才能拍板。

## 下一步

1. **推上 GitHub 讓 CI 跑一次** —— Node 測試在這台 Mac 已驗證（53/53），
   Swift 部分（核心測試 + 三個 target 建置）要 macOS runner 給答案。
2. 付 Apple Developer Program，取得 Team ID；把 `project.yml` 三處 entitlements 與
   `Shared/AppGroup.swift` 的 group id 換成自己 Team 可用的值。
3. Phase 3：Extension 的記憶體壓力測試。這是需要真機 + Instruments 的第一個關卡。

> 如果想在 Windows 上先確認 Swift 編得過，可以裝
> [Swift for Windows](https://www.swift.org/install/windows/)。它跑得動這個 package 的
> 純邏輯部分（Foundation + XCTest 都有），但 `Bundle.module` 的資源載入行為與 Apple 平台
> 有差異，可能要調整。這是可選的加速手段，不是必要條件 —— CI 一樣會把關。
