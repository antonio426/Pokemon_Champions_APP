import SwiftUI
import PokemonChampionCore

/// 隊伍對隊伍矩陣。每格上半 = 我方本系打對方、下半 = 對方本系打我方，
/// 跟 CLI 的「1/2」表示法同義，但用顏色代替斜線。
struct MatchupMatrixView: View {
    let matchup: TeamMatchup

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("")   // 左上角空格
                        .gridColumnAlignment(.leading)
                    ForEach(Array(matchup.theirs.enumerated()), id: \.offset) { _, opponent in
                        Text(opponent.label)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .frame(width: 64)
                    }
                }
                ForEach(Array(matchup.mine.enumerated()), id: \.offset) { i, member in
                    GridRow {
                        Text(member.label)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: 80, alignment: .leading)
                        ForEach(Array(matchup.theirs.indices), id: \.self) { j in
                            MatrixCellView(cell: matchup.matrix[i][j])
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
        Text("每格上排＝我方本系打對方，下排＝對方本系打我方")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

struct MatrixCellView: View {
    let cell: MatrixCell

    var body: some View {
        VStack(spacing: 3) {
            MultiplierBadge(multiplier: cell.outgoing, offense: true)
            MultiplierBadge(multiplier: cell.incoming, offense: false)
        }
        .frame(width: 64)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// 「最該注意」與「你的解答」兩個區塊 —— CLI team 指令輸出的圖形版。
struct ThreatAnswerSections: View {
    let matchup: TeamMatchup

    private var threats: [ThreatEntry] { matchup.threats.filter { $0.count > 0 } }
    private var answers: [AnswerEntry] { matchup.answers.filter { $0.count > 0 } }

    var body: some View {
        Section("最該注意") {
            if threats.isEmpty {
                Text("對方沒有本系超效打點").font(.subheadline).foregroundColor(.secondary)
            }
            ForEach(Array(threats.enumerated()), id: \.offset) { _, threat in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(threat.peak >= 4 ? .red : .orange)
                            .font(.caption)
                        Text(threat.combatant.label).font(.subheadline.weight(.semibold))
                        ForEach(threat.combatant.types, id: \.self) { TypeBadge(type: $0, compact: true) }
                        Spacer()
                        Text("超效打中 \(threat.count) 隻").font(.caption).foregroundColor(.secondary)
                    }
                    hitLine(threat.hits, offense: false)
                }
                .padding(.vertical, 2)
            }
        }
        Section("你的解答") {
            if answers.isEmpty {
                Text("我方沒有本系超效打點 —— 考慮換人").font(.subheadline).foregroundColor(.secondary)
            }
            ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: answer.safe ? "checkmark.shield.fill" : "shield.slash")
                            .foregroundColor(answer.safe ? .green : .orange)
                            .font(.caption)
                        Text(answer.combatant.label).font(.subheadline.weight(.semibold))
                        ForEach(answer.combatant.types, id: \.self) { TypeBadge(type: $0, compact: true) }
                        Spacer()
                        Text(answer.safe ? "不吃超效" : "會被 \(Matchup.format(answer.worstIncoming))× 反打")
                            .font(.caption)
                            .foregroundColor(answer.safe ? .secondary : .orange)
                    }
                    hitLine(answer.hits, offense: true)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private func hitLine(_ hits: [ThreatEntry.Hit], offense: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                    HStack(spacing: 4) {
                        TypeBadge(type: hit.via, compact: true)
                        Text("→ \(hit.target)").font(.caption)
                        MultiplierBadge(multiplier: hit.multiplier, offense: offense)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
            }
        }
    }
}
