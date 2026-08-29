import SwiftUI
import PokemonChampionCore

@main
struct PokemonChampionApp: App {
    @StateObject private var teamStore = TeamStore()
    @StateObject private var poolStore = SeasonPoolStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(teamStore)
                .environmentObject(poolStore)
                .onAppear {
                    // 賽季清單在啟動時套用一次 —— 之後的模糊比對都只掃清單內。
                    poolStore.applyToPokedex()
                }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            TeamAnalysisView()
                .tabItem { Label("對戰分析", systemImage: "shield.lefthalf.filled") }
            ScreenshotAnalysisView()
                .tabItem { Label("截圖辨識", systemImage: "camera.viewfinder") }
            PokedexView()
                .tabItem { Label("圖鑑", systemImage: "book.closed") }
            TypeChartView()
                .tabItem { Label("屬性", systemImage: "circle.hexagongrid") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
