import Foundation
import Combine
import ActivityKit
import PokemonChampionCore

/// 動態島（Live Activity）的啟動／更新／結束。
///
/// 只有前景 App 能啟動 Live Activity —— Broadcast Extension 不行。
/// 所以流程是：開戰前在 App 裡啟動，之後 App 每次回到前景就從
/// App Group 讀 Extension 留下的最新 `LiveSummary` 來更新。
///
/// Live Activity 的壽命比 App 行程長（最多 8 小時）：App 被滑掉再打開時，
/// 必須把系統還記得的 activity 認領回來，否則鎖定畫面上那張卡片
/// 再也更新不了、也關不掉，重新釘選還會疊出第二張。
@MainActor
final class LiveActivityController: ObservableObject {
    @Published private(set) var isRunning = false

    private var activity: Activity<BattleActivityAttributes>?
    private var stateWatcher: Task<Void, Never>?
    private var adoptWatcher: Task<Void, Never>?

    init() {
        adoptExistingActivity()
    }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(with summary: LiveSummary) {
        // 同時只留一張卡：把系統清單裡的全部收掉，而不只是自己記得的那一個。
        let stale = Activity<BattleActivityAttributes>.activities
        adoptWatcher?.cancel()
        stateWatcher?.cancel()
        activity = nil
        isRunning = false
        for old in stale {
            Task { await old.end(old.content, dismissalPolicy: .immediate) }
        }

        do {
            let started = try Activity.request(
                attributes: BattleActivityAttributes(startedAt: Date()),
                content: ActivityContent(state: summary, staleDate: nil)
            )
            activity = started
            isRunning = true
            watchState(of: started)
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
    /// 只接受「這張卡釘上之後」寫入的資料 —— 上一場對戰遺留的檔案不能蓋掉現在的畫面。
    func refreshFromAppGroup() {
        guard isRunning, let activity,
              let shared = AppGroup.readSummary(),
              shared.writtenAt > activity.attributes.startedAt else { return }
        update(with: shared.summary)
    }

    func end() {
        stateWatcher?.cancel()
        stateWatcher = nil
        // 同樣收掉系統清單裡的全部，孤兒卡片也一起清。
        for old in Activity<BattleActivityAttributes>.activities {
            Task { await old.end(old.content, dismissalPolicy: .immediate) }
        }
        activity = nil
        isRunning = false
    }

    // MARK: - 與系統狀態同步

    /// App 重啟後認領還活著的 activity。冷啟動瞬間 `activities` 可能還是空的
    /// （ActivityKit 尚在還原），所以再掛一個 activityUpdates 補認領。
    private func adoptExistingActivity() {
        if let existing = Activity<BattleActivityAttributes>.activities.first {
            adopt(existing)
            return
        }
        adoptWatcher = Task { [weak self] in
            for await restored in Activity<BattleActivityAttributes>.activityUpdates {
                guard let self, self.activity == nil else { break }
                self.adopt(restored)
                break
            }
        }
    }

    private func adopt(_ existing: Activity<BattleActivityAttributes>) {
        activity = existing
        isRunning = true
        watchState(of: existing)
    }

    /// 使用者可以直接從鎖定畫面把卡片滑掉 —— App 內的按鈕狀態要跟著走，
    /// 不然畫面上會留著一組按了沒反應的「更新／結束」。
    private func watchState(of activity: Activity<BattleActivityAttributes>) {
        stateWatcher?.cancel()
        stateWatcher = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard state == .dismissed || state == .ended else { continue }
                guard let self, self.activity?.id == activity.id else { return }
                self.activity = nil
                self.isRunning = false
                return
            }
        }
    }
}
