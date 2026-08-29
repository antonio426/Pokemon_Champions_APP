import SwiftUI
import PokemonChampionCore

/// 屬性查詢：挑防禦方的一或兩個屬性，直接看整張防禦面。
/// CLI `pmc type` / `pmc calc` 的圖形版。
struct TypeChartView: View {
    @State private var primary: PokemonType = .fire
    @State private var secondary: PokemonType?

    private var defenderTypes: [PokemonType] {
        if let secondary, secondary != primary { return [primary, secondary] }
        return [primary]
    }

    private var defense: DefenseProfile { DefenseProfile(types: defenderTypes) }

    var body: some View {
        NavigationStack {
            List {
                Section("防禦方屬性") {
                    Picker("主屬性", selection: $primary) {
                        ForEach(PokemonType.allCases, id: \.self) { Text($0.zh).tag($0) }
                    }
                    Picker("副屬性", selection: $secondary) {
                        Text("無").tag(PokemonType?.none)
                        ForEach(PokemonType.allCases, id: \.self) { t in
                            Text(t.zh).tag(PokemonType?.some(t))
                        }
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        Text("被打時：")
                        ForEach(defenderTypes, id: \.self) { TypeBadge(type: $0) }
                    }
                    groupRow("4×", defense.x4, color: .red)
                    groupRow("2×", defense.x2, color: .orange)
                    groupRow("1×", defense.x1, color: .secondary)
                    groupRow("½×", defense.x05, color: .blue)
                    groupRow("¼×", defense.x025, color: .blue)
                    groupRow("0×", defense.x0, color: .purple)
                } header: {
                    Text("防禦面總表")
                } footer: {
                    Text("第六世代（含）之後的相剋表；資料與 CLI、動態島用的是同一份。")
                }
            }
            .navigationTitle("屬性相剋")
        }
    }

    @ViewBuilder
    private func groupRow(_ label: String, _ types: [PokemonType], color: Color) -> some View {
        if !types.isEmpty {
            HStack(alignment: .top) {
                Text(label)
                    .font(.callout.monospacedDigit().weight(.bold))
                    .foregroundColor(color)
                    .frame(width: 40, alignment: .leading)
                FlowTypeBadges(types: types)
            }
        }
    }
}
