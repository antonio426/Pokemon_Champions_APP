import SwiftUI
import PokemonChampionCore

/// 屬性小標籤。整個 App 到處都在用。
struct TypeBadge: View {
    let type: PokemonType
    var compact = false

    var body: some View {
        Text(type.zh)
            .font(compact ? .caption2 : .caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 3)
            .background(type.color, in: Capsule())
    }
}

/// 倍率標籤：「4×」紅底、「½×」藍底之類。
struct MultiplierBadge: View {
    let multiplier: Double
    /// true = 我方打出去（越高越好），false = 挨打（越高越糟）。
    var offense: Bool

    var body: some View {
        Text("\(Matchup.format(multiplier))×")
            .font(.caption.monospacedDigit())
            .fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(MultiplierStyle.color(multiplier, offense: offense), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// 一列寶可夢：官方圖 ＋ 名稱 ＋ 屬性。圖抓不到（離線）就退回屬性色圓圈。
struct PokemonRow: View {
    let entry: PokedexEntry
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            SpriteView(entry: entry, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.displayName).font(.body.weight(.medium))
                    if let form = entry.form {
                        Text(form).font(.caption2).foregroundColor(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(entry.types, id: \.self) { TypeBadge(type: $0, compact: true) }
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            Text("#\(entry.speciesId)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
}

/// 官方圖。這個 App 的核心功能完全離線，圖只是點綴 —— 沒網路時顯示屬性色替代圖即可。
struct SpriteView: View {
    let entry: PokedexEntry
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let sprite = entry.sprite, let url = URL(string: sprite) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFit()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill((entry.types.first?.color ?? .gray).opacity(0.25))
            Text(String(entry.displayName.prefix(1)))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(entry.types.first?.color ?? .gray)
        }
    }
}

/// 空狀態提示。
struct EmptyHint: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
