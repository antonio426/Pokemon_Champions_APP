import ActivityKit
import WidgetKit
import SwiftUI
import PokemonChampionCore

/// 動態島與鎖定畫面的 Live Activity。
///
/// ContentState 就是核心層的 `LiveSummary`：一行威脅、一行解答。
/// 規劃書對這塊的要求是「空間只夠放一行威脅、一行解答」——
/// `liveSummary()` 產生的字串就是為這個空間設計的，這裡只負責排版。
struct BattleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BattleActivityAttributes.self) { context in
            // 鎖定畫面／非動態島機型的橫幅
            LockScreenBattleView(summary: context.state)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("威脅").font(.caption2)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label {
                        Text("解答").font(.caption2)
                    } icon: {
                        Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.threat)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(context.state.answer)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            } compactLeading: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(context.state.threatCount > 0 ? .red : .gray)
            } compactTrailing: {
                Text("\(context.state.answerCount)")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundColor(context.state.answerCount > 0 ? .green : .gray)
            } minimal: {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundColor(context.state.threatCount > 0 ? .red : .green)
            }
        }
    }
}

struct LockScreenBattleView: View {
    let summary: LiveSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text(summary.threat)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                Text(summary.answer)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
        }
        .foregroundColor(.white)
        .padding(14)
    }
}
