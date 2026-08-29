import ReplayKit
import CoreMedia
import ImageIO
import Vision
import PokemonChampionCore

/// Broadcast Upload Extension：對戰中每隔幾秒辨識一次畫面，
/// 把 `LiveSummary` 寫進 App Group，供主 App 更新動態島。
///
/// ⚠️ 這是規劃書 Phase 3 的鷹架 —— 整個專案風險最高的一步，理由：
///
///   1. **50MB 硬性記憶體上限**，超過就被 jetsam 直接砍掉，而 ReplayKit
///      自己就吃掉一大塊。這裡的每個決定都以記憶體優先：
///        - Vision 直接吃 CVPixelBuffer，不複製成 CGImage。
///        - 用 `regionOfInterest` 裁掉上下雜訊，而不是另外配置裁切後的緩衝。
///        - 節流：每 `processInterval` 秒最多處理一幀，其餘直接丟。
///        - `autoreleasepool` 包住整段處理，避免暫存物件堆積到下一幀。
///   2. Phase 0 量到的「0.4× 降取樣最準」是 Windows OCR 的曲線；Vision 的
///      最佳降取樣率要用真機 + Instruments 重量。真機驗證前，這裡先不降取樣，
///      靠節流控制負載。
///   3. Extension 不能啟動 Live Activity，只能把結果放進 App Group；
///      不經 APNs 的即時更新是已知的開放問題（見 ios/README.md）。
///
/// 在模擬器或未簽名建置上，App Group 容器拿不到，寫入會靜默跳過 —— 這讓
/// CI 能編譯這個 target，而不需要任何簽名設定。
final class SampleHandler: RPBroadcastSampleHandler {

    /// 幾秒處理一幀。對戰畫面的隊伍名單不會每秒都變，2 秒已經夠即時。
    private let processInterval: TimeInterval = 2.0
    private var lastProcessed = Date.distantPast
    private var busy = false

    private let layout = BattleLayout.battlePrepSplit

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer,
                                      with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = Date()
        guard !busy, now.timeIntervalSince(lastProcessed) >= processInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastProcessed = now
        busy = true
        defer { busy = false }

        // 被錄的是「前景的那個遊戲」，不是本 App —— 橫向遊戲的影格會帶方向附件，
        // 忽略它的話文字是轉了 90° 的，zh-Hant 什麼都認不出來。
        let orientation = Self.orientation(of: sampleBuffer)

        autoreleasepool {
            recognize(pixelBuffer, orientation: orientation)
        }
    }

    /// ReplayKit 把畫面方向放在 sample buffer 的附件裡（RPVideoSampleOrientationKey）。
    /// 附件缺席時當作直向。真機驗證項目之一（Phase 3）。
    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let raw = CMGetAttachment(sampleBuffer,
                                        key: RPVideoSampleOrientationKey as CFString,
                                        attachmentModeOut: nil) as? NSNumber,
              let parsed = CGImagePropertyOrientation(rawValue: raw.uint32Value)
        else { return .up }
        return parsed
    }

    private func recognize(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        request.usesLanguageCorrection = false
        // 原點在左下：裁掉最上面 (1 - top - height) 與最下面 top 之外的區域。
        request.regionOfInterest = CGRect(x: 0, y: 1 - layout.top - layout.height,
                                          width: 1, height: layout.height)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observations = request.results else { return }

        // 設了 regionOfInterest 之後，boundingBox 是「相對 ROI」的座標。
        // ROI 是滿版寬，所以 x 直接就是整個畫面的比例；y 要映射回整圖，
        // 才符合 RecognizedLine 的座標契約（0 = 整張圖最上緣）。
        // （若實測發現某版 Vision 回傳的是整圖座標，此映射仍保持單調，
        //   分邊與排序結果不變 —— 但 Phase 3 真機驗證時要確認一次。）
        let lines: [RecognizedLine] = observations.compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            let roiTopDownY = 1 - obs.boundingBox.midY
            return RecognizedLine(text: text,
                                  centerX: obs.boundingBox.midX,
                                  centerY: layout.top + roiTopDownY * layout.height)
        }

        let (reading, _, summary) = Recognition.analyze(lines: lines, layout: layout)
        guard !reading.isEmpty, let summary else { return }
        AppGroup.writeSummary(summary)
    }

    override func broadcastFinished() {
        // 對戰結束。留著最後一份 summary，App 回前景時還能看到終局狀態。
    }
}
