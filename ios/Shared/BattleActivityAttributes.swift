import Foundation
import ActivityKit
import PokemonChampionCore

/// Live Activity 的型別定義。App 與 Widget Extension 兩邊都要編譯到同一份，
/// ActivityKit 才能把它們接上 —— 所以放在 Shared/。
///
/// `ContentState` 直接用核心層的 `LiveSummary`：它從一開始就是為此設計的
/// （Codable、Hashable，測試驗過序列化後 < 512 bytes）。
struct BattleActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveSummary

    /// 開戰時就固定的資訊（不會隨更新變動）。
    var startedAt: Date
}
