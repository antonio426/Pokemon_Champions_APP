import SwiftUI
import PokemonChampionCore

/// 搜尋並挑一隻寶可夢。模糊比對走的是跟 OCR 同一條路 ——
/// 打「大蔥鴨」或「大葱鴨」都找得到，跟 CLI 的 `pmc find` 行為一致。
struct PokemonSearchSheet: View {
    let onPick: (PokedexEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    // 訂閱清單狀態，清單變更時結果跟著刷新。
    @EnvironmentObject private var pool: SeasonPoolStore

    private var results: [PokedexMatch] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Pokedex.shared.resolve(query, limit: 12, minScore: 0.4)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Text("輸入繁中、英文或日文名稱；打錯字也沒關係，模糊比對會救回來。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if pool.enabled {
                        Text("賽季清單生效中（\(pool.expandedCount) 個條目）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                ForEach(Array(results.enumerated()), id: \.element.entry.id) { _, match in
                    Button {
                        onPick(match.entry)
                        dismiss()
                    } label: {
                        PokemonRow(entry: match.entry,
                                   subtitle: match.exact ? nil : "相似度 \(Int(match.score * 100))%")
                    }
                    .buttonStyle(.plain)
                }
                if !query.isEmpty && results.isEmpty {
                    Text("找不到「\(query)」—— 若有設定賽季清單，可能不在清單內。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "名稱（支援錯字）")
            .navigationTitle("加入寶可夢")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
