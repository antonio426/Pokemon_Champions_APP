import SwiftUI
import ReplayKit
import PokemonChampionCore

struct SettingsView: View {
    @EnvironmentObject private var pool: SeasonPoolStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("啟用賽季清單", isOn: $pool.enabled)
                    if pool.enabled {
                        TextEditor(text: $pool.namesText)
                            .font(.body)
                            .frame(minHeight: 120)
                        HStack {
                            Text("\(pool.names.count) 個名稱 → \(pool.expandedCount) 個條目")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Button("載入範例清單") { pool.loadExample() }
                                .font(.caption)
                        }
                        if !pool.unresolvedNames.isEmpty {
                            Label("無法辨識（可能是錯字）：\(pool.unresolvedNames.joined(separator: "、"))",
                                  systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                } header: {
                    Text("賽季清單")
                } footer: {
                    Text("一行一個名稱。設定後，搜尋與截圖辨識的模糊比對只會在清單內找 —— " +
                         "比對速度快一個數量級，錯字也更不容易配到不相干的寶可夢。")
                }

                Section {
                    HStack {
                        BroadcastPickerButton()
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("開始對戰畫面辨識")
                            Text("錄影期間每隔數秒自動辨識雙方隊伍")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("即時辨識（實驗中）")
                } footer: {
                    Text("需要真機、簽名與 App Group 設定（規劃書 Phase 3）。" +
                         "模擬器與未簽名建置上此功能不可用。")
                }

                Section("關於") {
                    LabeledContent("圖鑑條目", value: "\(Pokedex.shared.entries.count)")
                    LabeledContent("資料建立時間", value: String(Pokedex.shared.generatedAt.prefix(10)))
                    LabeledContent("相剋表", value: "第六世代之後")
                    LabeledContent("資料來源", value: "PokéAPI（離線打包）")
                }
            }
            .navigationTitle("設定")
        }
    }
}

/// ReplayKit 的系統直播選擇器。SwiftUI 沒有原生包裝，橋一層 UIKit。
struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        picker.preferredExtension = "com.pokemonchampion.app.broadcast"
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
