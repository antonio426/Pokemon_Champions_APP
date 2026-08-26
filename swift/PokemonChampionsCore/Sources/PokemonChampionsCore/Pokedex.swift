import Foundation

/// 圖鑑條目（含特殊型態；id 為 PokeAPI pokemon id、dex 為全國圖鑑編號）。
public struct PokedexEntry: Codable, Equatable, Sendable {
    public let id: Int
    public let dex: Int
    public let identifier: String
    public let nameEn: String?
    public let nameZh: String?
    public let types: [String]
    public let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, dex, identifier, types
        case nameEn = "name_en"
        case nameZh = "name_zh"
        case isDefault = "is_default"
    }
}

/// data/pokedex.json 的檔案結構。
public struct PokedexFile: Codable, Sendable {
    public let count: Int
    public let pokemon: [PokedexEntry]
}

/// 模糊比對結果。
public struct FuzzyMatch: Equatable, Sendable {
    public let entry: PokedexEntry
    public let distance: Int
}

/// 全國圖鑑：精確查詢、模糊比對（OCR 誤字容錯）、與文字中的名稱擷取。
/// 演算法規格見 data/test_vectors.json 的 spec 欄位——與 Node 原型一致。
public struct Pokedex: Sendable {
    public let entries: [PokedexEntry]
    private let byZh: [String: PokedexEntry]
    private let byEnLower: [String: PokedexEntry]
    private let byIdentifier: [String: PokedexEntry]
    private let maxZhNameLength: Int

    public init(file: PokedexFile) {
        let sorted = file.pokemon.sorted { $0.id < $1.id }
        self.entries = sorted

        // 同名時保留 id 較小者（基礎型態優先）
        var zh: [String: PokedexEntry] = [:]
        var en: [String: PokedexEntry] = [:]
        var ident: [String: PokedexEntry] = [:]
        for p in sorted {
            if let name = p.nameZh, zh[name] == nil { zh[name] = p }
            if let name = p.nameEn?.lowercased(), en[name] == nil { en[name] = p }
            if ident[p.identifier] == nil { ident[p.identifier] = p }
        }
        self.byZh = zh
        self.byEnLower = en
        self.byIdentifier = ident
        self.maxZhNameLength = zh.keys.map { $0.count }.max() ?? 0
    }

    public func byId(_ id: Int) -> PokedexEntry? {
        entries.first { $0.id == id }
    }

    /// 精確查詢：繁中 → 英文（不分大小寫）→ identifier。
    public func lookup(_ query: String) -> PokedexEntry? {
        byZh[query] ?? byEnLower[query.lowercased()] ?? byIdentifier[query.lowercased()]
    }

    /// 模糊比對（只對 name_zh）：Levenshtein 距離 ≤ maxDistance 且 < 查詢長度；
    /// 取最小距離，同距離取 id 最小者。精確命中優先。
    public func fuzzy(_ query: String, maxDistance: Int = 2) -> FuzzyMatch? {
        if let exact = lookup(query) { return FuzzyMatch(entry: exact, distance: 0) }
        let qChars = Array(query)
        var best: PokedexEntry?
        var bestDist = Int.max
        for p in entries {
            guard let name = p.nameZh else { continue }
            let nChars = Array(name)
            if abs(nChars.count - qChars.count) > maxDistance { continue }
            let d = levenshtein(qChars, nChars)
            if d > maxDistance || d >= qChars.count { continue }
            if d < bestDist {
                best = p
                bestDist = d
            }
            // entries 已依 id 升冪，同距離時先到者 id 較小，毋須額外處理
        }
        guard let hit = best else { return nil }
        return FuzzyMatch(entry: hit, distance: bestDist)
    }

    /// 從一段文字（OCR 輸出）擷取圖鑑名稱：
    /// 由左至右，每個位置取以該位置開頭的最長名稱，命中後跳過其長度。
    /// 回傳依出現順序、去重的條目陣列。
    public func extract(from text: String) -> [PokedexEntry] {
        let chars = Array(text)
        var found: [PokedexEntry] = []
        var seen = Set<Int>()
        var i = 0
        while i < chars.count {
            var matched: (entry: PokedexEntry, len: Int)?
            let maxLen = min(maxZhNameLength, chars.count - i)
            if maxLen >= 1 {
                for len in stride(from: maxLen, through: 1, by: -1) {
                    let candidate = String(chars[i..<(i + len)])
                    if let entry = byZh[candidate] {
                        matched = (entry, len)
                        break
                    }
                }
            }
            if let m = matched {
                if !seen.contains(m.entry.id) {
                    seen.insert(m.entry.id)
                    found.append(m.entry)
                }
                i += m.len
            } else {
                i += 1
            }
        }
        return found
    }
}

/// 標準 Levenshtein 編輯距離（以 Character 為單位）。
public func levenshtein(_ s: [Character], _ t: [Character]) -> Int {
    let m = s.count
    let n = t.count
    if m == 0 { return n }
    if n == 0 { return m }
    var prev = Array(0...n)
    var curr = [Int](repeating: 0, count: n + 1)
    for i in 1...m {
        curr[0] = i
        for j in 1...n {
            let cost = s[i - 1] == t[j - 1] ? 0 : 1
            curr[j] = Swift.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[n]
}

public func levenshtein(_ a: String, _ b: String) -> Int {
    levenshtein(Array(a), Array(b))
}

/// OCR 文字正規化：移除「兩個 CJK 字元（含全形括號）之間」的所有空白。
/// tesseract（chi_tra）常把「噴火龍」輸出成「噴火 龍」；Vision 也可能逐字斷開。
public func normalizeOcrText(_ text: String) -> String {
    func isCJK(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xFF08, 0xFF09:
            return true
        default:
            return false
        }
    }
    let chars = Array(text)
    var result: [Character] = []
    var i = 0
    while i < chars.count {
        if chars[i].isWhitespace {
            // 找到這段空白的結尾
            var j = i
            while j < chars.count && chars[j].isWhitespace { j += 1 }
            let prevIsCJK = result.last.map(isCJK) ?? false
            let nextIsCJK = j < chars.count && isCJK(chars[j])
            if !(prevIsCJK && nextIsCJK) {
                result.append(contentsOf: chars[i..<j])
            }
            i = j
        } else {
            result.append(chars[i])
            i += 1
        }
    }
    return String(result)
}
