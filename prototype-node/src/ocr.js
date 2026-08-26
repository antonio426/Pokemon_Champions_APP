// OCR 轉接層：
//   - recognize(imagePath)：tesseract.js（chi_tra），對應 iOS 端的 Vision framework
//   - 測試時用 pipeline.analyzeText() 直接餵文字（mock 路徑），不依賴 OCR
// 首次執行會自動下載 chi_tra 語言資料（需網路）。

export async function recognize(imagePath) {
  const { createWorker } = await import("tesseract.js");
  const worker = await createWorker("chi_tra");
  try {
    const { data } = await worker.recognize(imagePath);
    return { text: data.text, confidence: data.confidence };
  } finally {
    await worker.terminate();
  }
}
