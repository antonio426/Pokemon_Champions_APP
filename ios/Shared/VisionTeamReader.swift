import Foundation
import Vision
import CoreGraphics
import PokemonChampionCore

/// 截圖 → OCR 行。`src/ocr.mjs` + `scripts/ocr.ps1` 的 iOS 對應物。
///
/// 對應關係（規劃書「移植到 iOS 時的對應關係」那張表）：
///   Windows.Media.Ocr (zh-Hant-TW)  →  Vision VNRecognizeTextRequest (zh-Hant)
///   降取樣 + 上下裁切                →  這裡的 CGContext 縮放繪製
///   帶座標的行                       →  RecognizedLine（比例座標，交給核心層分邊）
///
/// 注意：Phase 0 量到「0.4× 降取樣最準」是 Windows OCR 的曲線。Vision 的
/// 偵測器偏好不同的字高，`layout.scale` 要在真機上重量一次 —— 參數留在
/// `BattleLayout` 就是為了這件事。
enum VisionTeamReader {

    struct Result {
        let lines: [RecognizedLine]
        let ocrMs: Double
    }

    enum ReaderError: Error {
        case imageProcessingFailed
    }

    /// 裁切（去掉頂部標題與底部按鈕）＋ 降取樣，然後跑 zh-Hant 文字辨識。
    /// 回傳的座標已換算回「相對整張原圖」的 0…1 比例，可直接餵 `Recognition.readTeams`。
    static func recognizeLines(in image: CGImage,
                               layout: BattleLayout = .battlePrepSplit) async throws -> Result {
        let prepared = try preprocess(image, layout: layout)
        let started = Date()

        // 不用 completion handler：Vision 在 perform 失敗時「丟出錯誤」和「呼叫 completion」
        // 可能同時發生，兩條路各 resume 一次就是 continuation 誤用（直接 crash）。
        // perform 是同步的，回來後 request.results 已就緒 —— 單一路徑，恰好 resume 一次。
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        // 名稱不是自然語句，語言模型的「糾正」反而會把罕見名改成常見詞；
        // 錯字交給圖鑑的模糊比對處理，那邊有量過的容錯行為。
        request.usesLanguageCorrection = false

        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: prepared, options: [:])
                do {
                    try handler.perform([request])
                    continuation.resume(returning: request.results ?? [])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let ocrMs = Date().timeIntervalSince(started) * 1000

        let lines: [RecognizedLine] = observations.compactMap { obs in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            let box = obs.boundingBox   // 相對於「裁切後」的圖，原點在左下
            // x 不受上下裁切影響；y 先翻成上到下，再映射回整張原圖的比例。
            let croppedCenterY = 1 - box.midY
            return RecognizedLine(
                text: candidate.string,
                centerX: box.midX,
                centerY: layout.top + croppedCenterY * layout.height
            )
        }

        return Result(lines: lines, ocrMs: ocrMs)
    }

    /// 一步完成：截圖 → 行 → 分邊 → 解析 → 剋制分析。
    static func analyze(_ image: CGImage,
                        layout: BattleLayout = .battlePrepSplit)
    async throws -> (reading: TeamReading, matchup: TeamMatchup?, summary: LiveSummary?, ocrMs: Double) {
        let ocr = try await recognizeLines(in: image, layout: layout)
        let (reading, matchup, summary) = Recognition.analyze(lines: ocr.lines, layout: layout)
        return (reading, matchup, summary, ocr.ocrMs)
    }

    /// 裁切上下 ＋ 降取樣，一次 CGContext 繪製完成。
    private static func preprocess(_ image: CGImage, layout: BattleLayout) throws -> CGImage {
        let width = image.width
        let height = image.height

        let cropY = Int(Double(height) * layout.top)
        let cropHeight = Int(Double(height) * layout.height)
        // CGImage 的 cropping 原點在左上，跟版面規則同向。
        guard cropHeight > 0,
              let cropped = image.cropping(to: CGRect(x: 0, y: cropY, width: width, height: cropHeight))
        else { throw ReaderError.imageProcessingFailed }

        let scale = layout.scale
        guard scale > 0, scale < 1 else { return cropped }

        let targetW = max(1, Int(Double(width) * scale))
        let targetH = max(1, Int(Double(cropHeight) * scale))
        guard let context = CGContext(
            data: nil, width: targetW, height: targetH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw ReaderError.imageProcessingFailed }

        context.interpolationQuality = .high
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let result = context.makeImage() else { throw ReaderError.imageProcessingFailed }
        return result
    }
}
