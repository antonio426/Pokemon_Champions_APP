import SwiftUI
import PhotosUI
import PokemonChampionCore

/// 截圖匯入模式（規劃書 Phase 2 的核心功能）：
/// 選一張對戰截圖 → Vision OCR → 分邊 → 名稱解析 → 剋制分析。
/// 跟 CLI 的 `pmc shot` 是同一條管線，OCR 引擎從 Windows OCR 換成 Vision。
struct ScreenshotAnalysisView: View {
    @EnvironmentObject private var store: TeamStore

    @State private var pickedItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var state: AnalysisState = .idle

    enum AnalysisState {
        case idle
        case working
        case failed(String)
        case done(reading: TeamReading, matchup: TeamMatchup?, summary: LiveSummary?, ocrMs: Double)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $pickedItem, matching: .screenshots) {
                        Label("選擇對戰截圖", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        loadDemoImage()
                    } label: {
                        Label("用內建範例圖試試", systemImage: "wand.and.stars")
                    }
                } footer: {
                    Text("拍下對戰準備畫面（左我方、右對方）的截圖效果最好。範例圖是 Phase 0 的合成測試圖。")
                }

                if let previewImage {
                    Section("截圖") {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                resultSections
            }
            .navigationTitle("截圖辨識")
            .onChange(of: pickedItem) { item in
                guard let item else { return }
                Task { await loadPickedImage(item) }
            }
        }
    }

    @ViewBuilder
    private var resultSections: some View {
        switch state {
        case .idle:
            Section {
                EmptyHint(icon: "camera.viewfinder",
                          title: "還沒有截圖",
                          message: "選一張對戰截圖，幾十毫秒內就能看到雙方的剋制分析。全程離線。")
            }
        case .working:
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("辨識中…").foregroundColor(.secondary)
                }
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }
        case .done(let reading, let matchup, let summary, let ocrMs):
            recognizedSection(title: "我方（辨識結果）", team: reading.mine)
            recognizedSection(title: "對方（辨識結果）", team: reading.theirs)

            if !reading.unresolved.isEmpty {
                Section("無法解析的文字") {
                    ForEach(Array(reading.unresolved.enumerated()), id: \.offset) { _, item in
                        Text(item.text).font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            if !reading.isEmpty {
                Section {
                    Button {
                        store.replace(mine: reading.mine.map(\.entry),
                                      theirs: reading.theirs.map(\.entry))
                    } label: {
                        Label("帶入對戰分析頁", systemImage: "arrow.right.circle.fill")
                    }
                } footer: {
                    Text(String(format: "OCR 耗時 %.0f ms", ocrMs))
                }
            }

            if let summary {
                Section("動態島摘要") { LiveSummaryCard(summary: summary) }
            }
            if let matchup {
                Section("對戰矩陣") { MatchupMatrixView(matchup: matchup) }
                ThreatAnswerSections(matchup: matchup)
            }
            if reading.isEmpty {
                Section {
                    EmptyHint(icon: "questionmark.circle",
                              title: "沒認出任何寶可夢",
                              message: "確認截圖是對戰準備畫面（雙方名單左右分列）。也可以在設定裡關掉賽季清單再試。")
                }
            }
        }
    }

    @ViewBuilder
    private func recognizedSection(title: String, team: [TeamReading.Recognized]) -> some View {
        if !team.isEmpty {
            Section(title) {
                ForEach(Array(team.enumerated()), id: \.element.entry.id) { _, hit in
                    PokemonRow(entry: hit.entry,
                               subtitle: hit.exact
                                   ? "OCR：\(hit.ocrText)"
                                   : "OCR：\(hit.ocrText)（相似度 \(Int(hit.score * 100))%）")
                }
            }
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem) async {
        state = .working
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            state = .failed("讀不到這張圖片")
            return
        }
        await analyze(image)
    }

    private func loadDemoImage() {
        guard let url = Bundle.main.url(forResource: "demo-battle", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            state = .failed("內建範例圖遺失")
            return
        }
        state = .working
        Task { await analyze(image) }
    }

    private func analyze(_ image: UIImage) async {
        previewImage = image
        guard let cgImage = image.cgImage else {
            state = .failed("讀不到圖片內容")
            return
        }
        do {
            let result = try await VisionTeamReader.analyze(cgImage)
            state = .done(reading: result.reading, matchup: result.matchup,
                          summary: result.summary, ocrMs: result.ocrMs)
        } catch {
            state = .failed("辨識失敗：\(error.localizedDescription)")
        }
    }
}
