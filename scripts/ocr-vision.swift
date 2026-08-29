// macOS 的 OCR 後端：Vision VNRecognizeTextRequest —— 跟 iOS App 同一個引擎。
//
// 這支檔案刻意寫成 Swift 5.1 語法、只用 macOS 10.15 SDK 有的 API：
// 這台開發機的 CommandLineTools 是 2019 年的，但執行期的 Vision 是系統的新版，
// 支援到 revision 3（含 zh-Hant）。唯一的陷阱是 revision 預設值跟「連結時的 SDK」
// 走，舊 SDK 連結出來預設 revision 1、只認英文 —— 所以下面顯式設 revision。
//
// 介面與 scripts/ocr.ps1 一對一：同名參數、同形狀的 JSON 輸出（座標為原圖像素）。
// 由 src/ocr.mjs 惰性編譯進 .cache/ 後呼叫。
import Foundation
import CoreGraphics
import ImageIO
import Vision

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("✖ " + message + "\n").data(using: .utf8)!)
    exit(1)
}

// --- 參數解析（--key value，鍵名與 ocr.ps1 相同）---
var opts: [String: String] = [:]
var iterator = CommandLine.arguments.dropFirst().makeIterator()
while let arg = iterator.next() {
    guard arg.hasPrefix("--"), let value = iterator.next() else { fail("參數格式：--key value") }
    opts[String(arg.dropFirst(2))] = value
}
guard let inputPath = opts["path"] else { fail("缺 --path") }
let left = Double(opts["left"] ?? "0") ?? 0
let top = Double(opts["top"] ?? "0") ?? 0
let width = Double(opts["width"] ?? "1") ?? 1
let height = Double(opts["height"] ?? "1") ?? 1
let scale = Double(opts["scale"] ?? "0.4") ?? 0.4
let language = opts["language"] ?? "zh-Hant"

let url = URL(fileURLWithPath: inputPath)
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("讀不到圖片：\(inputPath)")
}

let srcW = image.width
let srcH = image.height

// 與 ocr.ps1 相同的幾何：先把整張圖縮放，再在「縮放後」的座標系裁切。
let scaledW = max(1, Int((Double(srcW) * scale).rounded()))
let scaledH = max(1, Int((Double(srcH) * scale).rounded()))
let cropX = min(Int((left * Double(scaledW)).rounded()), scaledW - 1)
let cropY = min(Int((top * Double(scaledH)).rounded()), scaledH - 1)
let cropW = max(1, min(Int((width * Double(scaledW)).rounded()), scaledW - cropX))
let cropH = max(1, min(Int((height * Double(scaledH)).rounded()), scaledH - cropY))

guard let context = CGContext(data: nil, width: cropW, height: cropH,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("建立繪圖 context 失敗")
}
context.interpolationQuality = .high
// CGContext 原點在左下。把整張縮放圖畫進 cropW×cropH 的畫布，
// 位移讓（cropX, cropY，上緣原點）的裁切框對齊畫布。
context.draw(image, in: CGRect(x: -cropX, y: -(scaledH - cropY - cropH),
                               width: scaledW, height: scaledH))
guard let prepared = context.makeImage() else { fail("裁切縮放失敗") }

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
// 關鍵：見檔頭註解。用執行期支援的最大 revision，而不是舊 SDK 的預設值。
request.revision = VNRecognizeTextRequest.supportedRevisions.max() ?? VNRecognizeTextRequestRevision1
let visionLanguage = language.hasPrefix("zh") ? "zh-Hant" : language
request.recognitionLanguages = [visionLanguage, "en-US"]
// 與 iOS 端（Shared/VisionTeamReader.swift）一致：名稱不是自然語句，不要語言糾正。
request.usesLanguageCorrection = false

let started = Date()
let handler = VNImageRequestHandler(cgImage: prepared, options: [:])
do {
    try handler.perform([request])
} catch {
    fail("Vision 辨識失敗：\(error.localizedDescription)")
}
let elapsedMs = Int((Date().timeIntervalSince(started) * 1000).rounded())

// 座標換算回原圖像素（上緣原點），跟 ocr.ps1 的輸出同一個座標系。
// Vision 是行級輸出，沒有逐字框 —— words 放一個涵蓋整行的元素，
// pipeline.mjs 對 words 只拿寬度總和，語意不變。
var lines: [[String: Any]] = []
for case let obs as VNRecognizedTextObservation in request.results ?? [] {
    guard let candidate = obs.topCandidates(1).first else { continue }
    let box = obs.boundingBox   // 相對 prepared（裁切+縮放後），原點左下
    let x = Int(((Double(cropX) + Double(box.minX) * Double(cropW)) / scale).rounded())
    let y = Int(((Double(cropY) + (1 - Double(box.maxY)) * Double(cropH)) / scale).rounded())
    let w = Int((Double(box.width) * Double(cropW) / scale).rounded())
    let h = Int((Double(box.height) * Double(cropH) / scale).rounded())
    let word: [String: Any] = ["text": candidate.string, "x": x, "y": y, "w": w, "h": h]
    lines.append(["text": candidate.string, "words": [word], "x": x, "y": y])
}

let payload: [String: Any] = [
    "path": url.path,
    "language": visionLanguage,
    "engine": "vision",
    "imageWidth": srcW,
    "imageHeight": srcH,
    "crop": [
        "x": Int((Double(cropX) / scale).rounded()), "y": Int((Double(cropY) / scale).rounded()),
        "w": Int((Double(cropW) / scale).rounded()), "h": Int((Double(cropH) / scale).rounded()),
        "scale": scale, "scaledW": cropW, "scaledH": cropH
    ],
    "elapsedMs": elapsedMs,
    "lines": lines
]
let json = try! JSONSerialization.data(withJSONObject: payload)
FileHandle.standardOutput.write(json)
