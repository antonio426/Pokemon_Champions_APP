import Foundation

/// 載入內嵌資料集（由 tools/fetch_data.mjs 從 data/ 同步至 Resources/）。
public enum CoreDataStore {
    public static func loadTypeChart() throws -> TypeChart {
        TypeChart(file: try load("type_chart", as: TypeChartFile.self))
    }

    public static func loadPokedex() throws -> Pokedex {
        Pokedex(file: try load("pokedex", as: PokedexFile.self))
    }

    private static func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try JSONDecoder().decode(T.self, from: try Data(contentsOf: url))
    }
}
