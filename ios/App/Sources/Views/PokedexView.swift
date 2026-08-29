import SwiftUI
import PokemonChampionCore

/// 圖鑑：搜尋（含錯字容錯）＋ 瀏覽全部 1,351 筆，點進去看攻防總表。
/// CLI `pmc who` / `pmc find` 的圖形版。
struct PokedexView: View {
    @State private var query = ""

    private var searchResults: [PokedexMatch] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return Pokedex.shared.resolve(query, limit: 25, minScore: 0.4)
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    // List 是懶載入，直接放全圖鑑（預設形態）也不會卡。
                    ForEach(defaultEntries) { entry in
                        NavigationLink(value: entry) {
                            PokemonRow(entry: entry)
                        }
                    }
                } else {
                    ForEach(Array(searchResults.enumerated()), id: \.element.entry.id) { _, match in
                        NavigationLink(value: match.entry) {
                            PokemonRow(entry: match.entry,
                                       subtitle: match.exact ? nil : "相似度 \(Int(match.score * 100))%")
                        }
                    }
                    if searchResults.isEmpty {
                        Text("找不到「\(query)」")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "名稱（繁中／英／日，支援錯字）")
            .navigationTitle("圖鑑")
            .navigationDestination(for: PokedexEntry.self) { entry in
                PokemonDetailView(entry: entry)
            }
        }
    }

    private var defaultEntries: [PokedexEntry] {
        Pokedex.shared.entries.filter(\.isDefault)
    }
}

/// 單隻寶可夢的攻防總表 —— `pmc who` 的輸出。
struct PokemonDetailView: View {
    let entry: PokedexEntry

    private var defense: DefenseProfile { DefenseProfile(types: entry.types) }
    private var offense: OffenseProfile { OffenseProfile(types: entry.types) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    SpriteView(entry: entry, size: 80)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.displayName).font(.title2.bold())
                        if let en = entry.en {
                            Text("#\(entry.speciesId) \(en)")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            ForEach(entry.types, id: \.self) { TypeBadge(type: $0) }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("防禦面（被打）") {
                defenseRow("4× 致命", defense.x4, color: .red)
                defenseRow("2× 被剋", defense.x2, color: .orange)
                defenseRow("½× 抗性", defense.x05, color: .blue)
                defenseRow("¼× 高抗", defense.x025, color: .blue)
                defenseRow("0× 無效", defense.x0, color: .purple)
            }

            Section("攻擊面（本系打出去最好的一發）") {
                offenseRow("2× 以上", offense.multipliers.filter { $0.value >= 2 }.map(\.key))
                offenseRow("被半減以下", offense.multipliers.filter { $0.value < 1 }.map(\.key))
            }

            if !siblingForms.isEmpty {
                Section("其他形態") {
                    ForEach(siblingForms) { form in
                        NavigationLink(value: form) {
                            PokemonRow(entry: form, subtitle: form.form)
                        }
                    }
                }
            }
        }
        .navigationTitle(entry.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 同物種、屬性不同的其他形態（噴火龍 → Mega X 火/龍）。
    private var siblingForms: [PokedexEntry] {
        Pokedex.shared.entries.filter {
            $0.speciesId == entry.speciesId && $0.id != entry.id && $0.types != entry.types
        }
    }

    @ViewBuilder
    private func defenseRow(_ label: String, _ types: [PokemonType], color: Color) -> some View {
        if !types.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                    .frame(width: 72, alignment: .leading)
                FlowTypeBadges(types: types)
            }
        }
    }

    @ViewBuilder
    private func offenseRow(_ label: String, _ types: [PokemonType]) -> some View {
        if !types.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                    .frame(width: 72, alignment: .leading)
                FlowTypeBadges(types: types.sorted { $0.index < $1.index })
            }
        }
    }
}

/// 一排會自動換行的屬性標籤。
struct FlowTypeBadges: View {
    let types: [PokemonType]

    var body: some View {
        // iOS 16 沒有原生 flow layout；LazyVGrid 固定欄寬的效果已經夠好。
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 4, alignment: .leading)],
                  alignment: .leading, spacing: 4) {
            ForEach(types, id: \.self) { TypeBadge(type: $0, compact: true) }
        }
    }
}
