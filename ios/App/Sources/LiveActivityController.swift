import Foundation
import Combine
import ActivityKit
import PokemonChampionCore

/// 動態島（Live Activity）的啟動／更新／結束。
///
/// 只有前景 App 能啟動 Live Activity —— Broadcast Extension 不行。
/// 所以流程是：開戰前在 App 裡啟動，之後 App 每次回到前景就從
/// App Group 讀 Extension 留下的最新 `LiveSummary` 來更新。
@MainActor
final class LiveActivityController: ObservableObject {
    @Published private(set) var isRunning = false

    private var activity: Activity<BattleActivityAttributes>?

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(with summary: LiveSummary) {
        end()   // 同時只留一個
        do {
            activity = try Activity.request(
                attributes: BattleActivityAttributes(startedAt: Date()),
                content: ActivityContent(state: summary, staleDate: nil)
            )
            isRunning = true
        } catch {
            // 最常見的失敗：使用者在系統設定關掉了即時動態。UI 上已經用
            // isSupported 擋住按鈕，這裡不再打擾使用者。
            isRunning = false
        }
    }

    func update(with summary: LiveSummary) {
        guard let activity else { return }
        Task {
            await activity.update(ActivityContent(state: summary, staleDate: nil))
        }
    }

    /// App 回到前景時呼叫：撿起 Broadcast Extension 寫進 App Group 的最新結果。
    func refreshFromAppGroup() {
        guard isRunning, let latest = AppGroup.readSummary() else { return }
        update(with: latest)
    }

    func end() {
        guard let activity else { return }
        let final = activity.content
        Task {
            await activity.end(final, dismissalPolicy: .immediate)
        }
        self.activity = nil
        isRunning = false
    }
}
