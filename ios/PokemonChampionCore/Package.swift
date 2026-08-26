// swift-tools-version:5.9
import PackageDescription

// 這個 package 刻意只放「純邏輯 + 資料」，不碰 UIKit / ReplayKit / ActivityKit。
// 主 App、Broadcast Upload Extension、Widget Extension 三個 target 之後都會 import 它，
// 而且它能在任何 macOS runner 上用 `swift test` 跑完，不需要模擬器、不需要簽名。
// 這是「Windows 開發 + 雲端 Mac 驗證」這條路上最便宜的一段。
let package = Package(
    name: "PokemonChampionCore",
    platforms: [
        .iOS(.v16),   // Live Activity 需要 16.1，動態島也是
        .macOS(.v13)  // 讓 CI 能直接跑測試，不必開模擬器
    ],
    products: [
        .library(name: "PokemonChampionCore", targets: ["PokemonChampionCore"])
    ],
    targets: [
        .target(
            name: "PokemonChampionCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PokemonChampionCoreTests",
            dependencies: ["PokemonChampionCore"]
        )
    ]
)
