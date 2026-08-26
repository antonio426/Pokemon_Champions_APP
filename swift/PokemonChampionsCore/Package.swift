// swift-tools-version:5.9
// PokemonChampionsCore — 純邏輯核心（剋制引擎 / 圖鑑 / 對戰分析）。
// 不依賴任何 Apple 專屬框架，可在 Linux 上 `swift test`。
// 資料檔由 tools/fetch_data.mjs 從 data/ 同步至 Resources/，請勿手改。
import PackageDescription

let package = Package(
    name: "PokemonChampionsCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "PokemonChampionsCore", targets: ["PokemonChampionsCore"])
    ],
    targets: [
        .target(
            name: "PokemonChampionsCore",
            resources: [
                .copy("Resources/type_chart.json"),
                .copy("Resources/pokedex.json"),
            ]
        ),
        .testTarget(
            name: "PokemonChampionsCoreTests",
            dependencies: ["PokemonChampionsCore"],
            resources: [
                .copy("Resources/test_vectors.json")
            ]
        ),
    ]
)
