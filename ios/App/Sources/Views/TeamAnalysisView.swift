import SwiftUI
import PokemonChampionCore

/// 對戰分析主頁：編兩隊 → 矩陣、威脅、解答、動態島摘要。
/// CLI `pmc team` 的圖形版。
struct TeamAnalysisView: View {
    @EnvironmentObject private var store: TeamStore
    @StateObject private var liveActivity = LiveActivityController()
    @State private var searchTarget: SearchTarget?
    @Environment(\.scenePhase) private var scenePhase

    enum SearchTarget: Identifiable {
        case mine, theirs
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            List {
                teamSection(title: "我方隊伍", entries: store.mine, isMine: true)
                teamSection(title: "對方隊伍", entries: store.theirs, isMine: false)

                if let matchup = store.matchup, let summary = store.summary {
                    Section("動態島摘要") {
                        LiveSummaryCard(summary: summary)
                        liveActivityControls(summary: summary)
                    }
                    Section("對戰矩陣") {
                        MatchupMatrixView(matchup: matchup)
                    }
                    ThreatAnswerSections(matchup: matchup)
                } else {
                    // 沒有分析結果、但動態島還釘著（例如把隊伍清空了）——
                    // 結束鈕必須留在畫面上，不能讓卡片變成關不掉的孤兒。
                    if liveActivity.isRunning {
                        Section("動態島") {
                            Button("結束動態島", role: .destructive) { liveActivity.end() }
                        }
                    }
                    Section {
                        EmptyHint(icon: "shield.lefthalf.filled",
                                  title: "兩邊都放至少一隻",
                                  message: "加入我方與對方的寶可夢後，這裡會顯示完整的屬性剋制分析。")
                    }
                }
            }
            .navigationTitle("對戰分析")
            .sheet(item: $searchTarget) { target in
                PokemonSearchSheet { entry in
                    store.add(entry, toMine: target == .mine)
                }
            }
            .onChange(of: scenePhase) { phase in
                // 回前景時撿 Broadcast Extension 留在 App Group 的最新結果。
                if phase == .active { liveActivity.refreshFromAppGroup() }
            }
        }
    }

    @ViewBuilder
    private func teamSection(title: String, entries: [PokedexEntry], isMine: Bool) -> some View {
        Section {
            ForEach(entries) { entry in
                PokemonRow(entry: entry)
            }
            .onDelete { offsets in
                if isMine { store.mine.remove(atOffsets: offsets) }
                else { store.theirs.remove(atOffsets: offsets) }
            }
            if entries.count < TeamStore.maxTeamSize {
                Button {
                    searchTarget = isMine ? .mine : .theirs
                } label: {
                    Label("加入寶可夢", systemImage: "plus.circle")
                }
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                Text("\(entries.count)/\(TeamStore.maxTeamSize)")
                    .font(.caption.monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private func liveActivityControls(summary: LiveSummary) -> some View {
        if liveActivity.isSupported {
            if liveActivity.isRunning {
                HStack {
                    Button("更新動態島") { liveActivity.update(with: summary) }
                    Spacer()
                    Button("結束", role: .destructive) { liveActivity.end() }
                }
                .buttonStyle(.borderless)
            } else {
                Button {
                    liveActivity.start(with: summary)
                } label: {
                    Label("釘上動態島", systemImage: "platter.filled.top.iphone")
                }
            }
        } else {
            Text("此裝置未開啟「即時動態」（設定 → 瞄準這個 App → 即時動態）。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

/// 動態島摘要卡：一行威脅、一行解答 —— 跟 Live Activity 顯示的內容一模一樣。
struct LiveSummaryCard: View {
    let summary: LiveSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text(summary.threat).font(.subheadline.weight(.medium))
                Spacer()
                if summary.threatCount > 0 {
                    Text("打中 \(summary.threatCount) 隻")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundColor(.green)
                Text(summary.answer).font(.subheadline.weight(.medium))
                Spacer()
                if summary.answerCount > 0 {
                    Text("超效 \(summary.answerCount) 隻")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
