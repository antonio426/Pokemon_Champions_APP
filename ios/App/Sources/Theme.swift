import SwiftUI
import PokemonChampionCore

/// 屬性 → 顏色。用社群慣用的屬性色，玩家一眼就能對上。
extension PokemonType {
    var color: Color {
        switch self {
        case .normal:   return Color(red: 0.66, green: 0.65, blue: 0.48)
        case .fire:     return Color(red: 0.93, green: 0.51, blue: 0.19)
        case .water:    return Color(red: 0.39, green: 0.56, blue: 0.94)
        case .electric: return Color(red: 0.97, green: 0.82, blue: 0.17)
        case .grass:    return Color(red: 0.48, green: 0.78, blue: 0.30)
        case .ice:      return Color(red: 0.59, green: 0.85, blue: 0.84)
        case .fighting: return Color(red: 0.76, green: 0.18, blue: 0.16)
        case .poison:   return Color(red: 0.64, green: 0.24, blue: 0.63)
        case .ground:   return Color(red: 0.89, green: 0.75, blue: 0.40)
        case .flying:   return Color(red: 0.66, green: 0.56, blue: 0.95)
        case .psychic:  return Color(red: 0.98, green: 0.33, blue: 0.53)
        case .bug:      return Color(red: 0.65, green: 0.73, blue: 0.10)
        case .rock:     return Color(red: 0.71, green: 0.63, blue: 0.21)
        case .ghost:    return Color(red: 0.45, green: 0.34, blue: 0.59)
        case .dragon:   return Color(red: 0.44, green: 0.21, blue: 0.97)
        case .dark:     return Color(red: 0.44, green: 0.34, blue: 0.27)
        case .steel:    return Color(red: 0.72, green: 0.72, blue: 0.81)
        case .fairy:    return Color(red: 0.84, green: 0.52, blue: 0.68)
        }
    }
}

/// 倍率 → 顏色。紅 = 危險（挨打 / 被剋），綠 = 有利，灰 = 普通。
enum MultiplierStyle {
    static func color(_ m: Double, offense: Bool) -> Color {
        switch m {
        case 4...:      return offense ? .green : .red
        case 2..<4:     return offense ? Color.green.opacity(0.75) : Color.red.opacity(0.75)
        case 1..<2:     return .secondary
        case 0.25..<1:  return offense ? Color.orange.opacity(0.9) : Color.blue.opacity(0.7)
        default:        return offense ? .orange : .blue
        }
    }
}
