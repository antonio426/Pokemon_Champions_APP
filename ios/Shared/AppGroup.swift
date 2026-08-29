import Foundation
import PokemonChampionCore

/// App、Widget、Broadcast Extension 三個行程之間唯一的溝通管道：App Group 容器。
///
/// Broadcast Extension 活在 50MB 的記憶體配額裡，而且不能啟動 Live Activity
/// （只有前景 App 可以）。所以分工是：
///   - App：開戰前啟動 Live Activity。
///   - Extension：每隔幾秒辨識一次畫面，把 `LiveSummary` 寫進共享容器。
///   - App 回到前景（或收到推播）時，讀最新的 summary 更新 Live Activity。
///   （不經 APNs 的即時更新是規劃書 Phase 3 標記的最高風險項，需要真機驗證。）
public enum AppGroup {
    /// 真機部署時要換成自己 Team 可用的 group id —— 與三份 .entitlements 一起換。
    public static let identifier = "group.com.pokemonchampion.shared"

    private static let summaryFile = "live-summary.json"

    /// Extension 留下的分析結果，帶寫入時間 —— App 端要用它判斷「這是這一場的，
    /// 還是上一場遺留的」，否則回前景時舊資料會蓋掉剛釘上的動態島。
    public struct SharedSummary: Codable {
        public let summary: LiveSummary
        public let writtenAt: Date

        public init(summary: LiveSummary, writtenAt: Date = Date()) {
            self.summary = summary
            self.writtenAt = writtenAt
        }
    }

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Extension 端：寫入最新分析結果。沒有 entitlement（例如未簽名的模擬器建置）就靜默跳過。
    public static func writeSummary(_ summary: LiveSummary) {
        guard let url = containerURL?.appendingPathComponent(summaryFile),
              let data = try? JSONEncoder().encode(SharedSummary(summary: summary)) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// App 端：讀取 Extension 留下的最新結果（含寫入時間）。
    public static func readSummary() -> SharedSummary? {
        guard let url = containerURL?.appendingPathComponent(summaryFile),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSummary.self, from: data)
    }
}
