import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { mkdir, stat } from 'node:fs/promises';
import path from 'node:path';

const execFileAsync = promisify(execFile);
const PS_SCRIPT = fileURLToPath(new URL('../scripts/ocr.ps1', import.meta.url));
const SWIFT_SOURCE = fileURLToPath(new URL('../scripts/ocr-vision.swift', import.meta.url));
const CACHE_DIR = fileURLToPath(new URL('../.cache/', import.meta.url));
const SWIFT_BIN = path.join(CACHE_DIR, 'ocr-vision');

/**
 * Phase 0 的 OCR 後端依平台派發：
 *
 *   - Windows：Windows.Media.Ocr（scripts/ocr.ps1）
 *   - macOS：Vision VNRecognizeTextRequest（scripts/ocr-vision.swift）——
 *     跟 iOS App 同一個引擎，在 Mac 上量到的準確率對 iOS 才有參考價值。
 *
 * 兩個後端吃同名參數、回同形狀的 JSON（座標為原圖像素），
 * 這一層只負責把參數丟過去、把 JSON 收回來。
 */
export async function recognize(imagePath, {
  left = 0,
  top = 0,
  width = 1,
  height = 1,
  scale = 0.4,
  language = 'zh-Hant-TW',
  timeoutMs = 30000,
} = {}) {
  let stdout;
  if (process.platform === 'darwin') {
    const bin = await ensureVisionBinary();
    const args = [
      '--path', path.resolve(imagePath),
      '--left', String(left), '--top', String(top),
      '--width', String(width), '--height', String(height),
      '--scale', String(scale), '--language', language,
    ];
    try {
      ({ stdout } = await execFileAsync(bin, args, {
        timeout: timeoutMs,
        maxBuffer: 32 * 1024 * 1024,
        encoding: 'utf8',
      }));
    } catch (err) {
      throw new Error(`OCR 執行失敗：${(err.stderr || err.message).trim()}`);
    }
  } else {
    const args = [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', PS_SCRIPT,
      '-Path', path.resolve(imagePath),
      '-Left', String(left), '-Top', String(top),
      '-Width', String(width), '-Height', String(height),
      '-Scale', String(scale), '-Language', language,
    ];
    try {
      ({ stdout } = await execFileAsync('powershell.exe', args, {
        timeout: timeoutMs,
        maxBuffer: 32 * 1024 * 1024,
        encoding: 'utf8',
        windowsHide: true,
      }));
    } catch (err) {
      throw new Error(`OCR 執行失敗：${(err.stderr || err.message).trim()}`);
    }
  }
  try {
    return JSON.parse(stdout);
  } catch {
    throw new Error(`OCR 回傳的不是 JSON：${stdout.slice(0, 300)}`);
  }
}

/** Vision CLI 惰性編譯進 .cache/，來源檔更新時自動重編。 */
async function ensureVisionBinary() {
  await mkdir(CACHE_DIR, { recursive: true });
  const [src, bin] = await Promise.all([
    stat(SWIFT_SOURCE),
    stat(SWIFT_BIN).catch(() => null),
  ]);
  if (bin && bin.mtimeMs > src.mtimeMs) return SWIFT_BIN;
  try {
    await execFileAsync('swiftc', ['-O', SWIFT_SOURCE, '-o', SWIFT_BIN], { timeout: 180000 });
  } catch (err) {
    throw new Error(`編譯 Vision OCR 後端失敗（需要 Xcode Command Line Tools）：${(err.stderr || err.message).trim()}`);
  }
  return SWIFT_BIN;
}

export const OCR_AVAILABLE = process.platform === 'win32' || process.platform === 'darwin';
