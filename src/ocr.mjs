import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const execFileAsync = promisify(execFile);
const SCRIPT = fileURLToPath(new URL('../scripts/ocr.ps1', import.meta.url));

/**
 * Phase 0 的 OCR 後端是 Windows.Media.Ocr（見 scripts/ocr.ps1）。
 * 這一層只負責把參數丟過去、把 JSON 收回來，介面刻意設計成
 * 之後在 iOS 上換成 Vision VNRecognizeTextRequest 時可以原樣對應。
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
  const args = [
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', SCRIPT,
    '-Path', path.resolve(imagePath),
    '-Left', String(left), '-Top', String(top),
    '-Width', String(width), '-Height', String(height),
    '-Scale', String(scale), '-Language', language,
  ];
  let stdout;
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
  try {
    return JSON.parse(stdout);
  } catch {
    throw new Error(`OCR 回傳的不是 JSON：${stdout.slice(0, 300)}`);
  }
}

export const OCR_AVAILABLE = process.platform === 'win32';
