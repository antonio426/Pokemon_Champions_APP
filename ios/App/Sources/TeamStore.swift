import Foundation
import Combine
import PokemonChampionCore

/// 我方／對方隊伍的狀態。用圖鑑 id 存進 UserDefaults，重開 App 隊伍還在。
@MainActor
final class TeamStore: ObservableObject {
    @Published var mine: [PokedexEntry] {
        didSet { persist(mine, key: Self.mineKey) }
    }
    @Published var theirs: [PokedexEntry] {
        didSet { persist(theirs, key: Self.theirsKey) }
    }

    static let maxTeamSize = 6
    private static let mineKey = "team.mine.ids"
    private static let theirsKey = "team.theirs.ids"

    init() {
        mine = Self.restore(key: Self.mineKey)
        theirs = Self.restore(key: Self.theirsKey)
    }

    var mineCombatants: [Combatant] { mine.map { Combatant(entry: $0) } }
    var theirsCombatants: [Combatant] { theirs.map { Combatant(entry: $0) } }

    var matchup: TeamMatchup? {
        guard !mine.isEmpty, !theirs.isEmpty else { return nil }
        return Matchup.team(mine: mineCombatants, theirs: theirsCombatants)
    }

    var summary: LiveSummary? {
        guard !mine.isEmpty, !theirs.isEmpty else { return nil }
        return Matchup.liveSummary(mine: mineCombatants, theirs: theirsCombatants)
    }

    func add(_ entry: PokedexEntry, toMine: Bool) {
        var team = toMine ? mine : theirs
        guard team.count < Self.maxTeamSize, !team.contains(where: { $0.id == entry.id }) else { return }
        team.append(entry)
        if toMine { mine = team } else { theirs = team }
    }

    /// 截圖辨識的結果直接覆蓋整隊。
    func replace(mine newMine: [PokedexEntry], theirs newTheirs: [PokedexEntry]) {
        if !newMine.isEmpty { mine = Array(newMine.prefix(Self.maxTeamSize)) }
        if !newTheirs.isEmpty { theirs = Array(newTheirs.prefix(Self.maxTeamSize)) }
    }

    private func persist(_ team: [PokedexEntry], key: String) {
        UserDefaults.standard.set(team.map(\.id), forKey: key)
    }

    private static func restore(key: String) -> [PokedexEntry] {
        guard let ids = UserDefaults.standard.array(forKey: key) as? [Int] else { return [] }
        return ids.compactMap { Pokedex.shared.entry(id: $0) }
    }
}

/// 賽季清單（規劃書「縮小比對範圍」）。存名稱字串，啟動時套進 Pokedex。
@MainActor
final class SeasonPoolStore: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            applyToPokedex()
        }
    }
    /// 一行一個名稱。
    @Published var namesText: String {
        didSet {
            UserDefaults.standard.set(namesText, forKey: Self.namesKey)
            applyToPokedex()
        }
    }

    private static let enabledKey = "pool.enabled"
    private static let namesKey = "pool.names"

    init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        namesText = UserDefaults.standard.string(forKey: Self.namesKey) ?? ""
    }

    var names: [String] {
        // 全形逗號「，」是繁中輸入法的預設 —— 漏掉它，貼上的清單會整串黏成一個名稱。
        namesText
            .split(whereSeparator: { $0.isNewline || "、，,;；".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 目前清單展開後的條目數（同物種的所有形態都會納入）。
    var expandedCount: Int { Pokedex.shared.currentPool?.entries.count ?? 0 }

    /// 清單裡一個條目都對不到的名稱 —— 幾乎都是錯字。清單比對是精確命中，
    /// 錯字不會被模糊比對救，一定要讓使用者看得到。
    var unresolvedNames: [String] {
        names.filter { Pokedex.shared.exactEntries(for: $0).isEmpty }
    }

    func applyToPokedex() {
        if enabled, !names.isEmpty {
            Pokedex.shared.setPool(names: names, label: "自訂賽季")
        } else {
            Pokedex.shared.clearPool()
        }
        objectWillChange.send()
    }

    /// 載入內建的範例清單（bundle 裡的 example-pool.json，與 data/pool.example.json 同源）。
    func loadExample() {
        struct PoolFile: Decodable { let names: [String]? }
        guard let url = Bundle.main.url(forResource: "example-pool", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(PoolFile.self, from: data),
              let names = file.names else { return }
        namesText = names.joined(separator: "\n")
        enabled = true
    }
}
