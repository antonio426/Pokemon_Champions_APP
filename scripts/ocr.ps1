<#
.SYNOPSIS
  用 Windows.Media.Ocr（zh-Hant-TW）辨識圖片文字，輸出 JSON。

.DESCRIPTION
  這是 Phase 0 的 OCR 後端。挑 Windows OCR 而不是 Tesseract，是因為它
  跟 iOS 上的 Vision VNRecognizeTextRequest 性質最接近：同樣是作業系統
  內建、同樣針對繁中訓練、同樣回傳帶座標的行與詞。原型在這裡量到的準確率
  才有資格當成 iOS 的參考基準。

  裁切與縮放參數都用 0~1 的比例表示，這樣同一組設定可以套用在不同解析度
  的截圖上，不用為每種機型重調。

.EXAMPLE
  powershell -File scripts/ocr.ps1 -Path shot.png -Left 0 -Top 0.1 -Width 0.35 -Height 0.8 -Scale 2
#>
param(
  [Parameter(Mandatory = $true)][string]$Path,
  [double]$Left = 0,
  [double]$Top = 0,
  [double]$Width = 1,
  [double]$Height = 1,
  [double]$Scale = 1,
  [string]$Language = 'zh-Hant-TW'
)

$ErrorActionPreference = 'Stop'
# 這支腳本的輸出會被 Node 以 UTF-8 讀走；PowerShell 5.1 預設吐 ANSI，會把中文變亂碼。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Fail($msg) {
  [Console]::Error.WriteLine($msg)
  exit 1
}

$full = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path -LiteralPath $full)) { Fail "找不到圖片：$full" }

Add-Type -AssemblyName System.Runtime.WindowsRuntime | Out-Null
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
$null = [Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
$null = [Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]

# WinRT 的 IAsyncOperation 在 PowerShell 裡沒有 await，得自己轉成 Task 再等。
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
  })[0]

function Await($op, $type) {
  $task = $asTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
  $task.Wait(-1) | Out-Null
  $task.Result
}

$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($full)) ([Windows.Storage.StorageFile])
$stream = Await ($file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])

$srcW = [int]$decoder.PixelWidth
$srcH = [int]$decoder.PixelHeight

# BitmapTransform 的 Bounds 是套在「縮放後」的座標系上，不是原圖上 ——
# ScaledWidth/ScaledHeight 指的是整張圖縮放後的尺寸，裁切才在那之後發生。
# 這裡先算出縮放後的畫布，再把比例換算成縮放後的裁切框。
$scaledW = [Math]::Max(1, [int][Math]::Round($srcW * $Scale))
$scaledH = [Math]::Max(1, [int][Math]::Round($srcH * $Scale))

$cropX = [Math]::Min([int][Math]::Round($Left * $scaledW), $scaledW - 1)
$cropY = [Math]::Min([int][Math]::Round($Top * $scaledH), $scaledH - 1)
$cropW = [Math]::Max(1, [Math]::Min([int][Math]::Round($Width * $scaledW), $scaledW - $cropX))
$cropH = [Math]::Max(1, [Math]::Min([int][Math]::Round($Height * $scaledH), $scaledH - $cropY))

$transform = New-Object Windows.Graphics.Imaging.BitmapTransform
$transform.ScaledWidth = $scaledW
$transform.ScaledHeight = $scaledH
$transform.InterpolationMode = [Windows.Graphics.Imaging.BitmapInterpolationMode]::Fant
$bounds = New-Object Windows.Graphics.Imaging.BitmapBounds
$bounds.X = $cropX; $bounds.Y = $cropY; $bounds.Width = $cropW; $bounds.Height = $cropH
$transform.Bounds = $bounds

$bitmap = Await ($decoder.GetSoftwareBitmapAsync(
    [Windows.Graphics.Imaging.BitmapPixelFormat]::Bgra8,
    [Windows.Graphics.Imaging.BitmapAlphaMode]::Premultiplied,
    $transform,
    [Windows.Graphics.Imaging.ExifOrientationMode]::RespectExifOrientation,
    [Windows.Graphics.Imaging.ColorManagementMode]::ColorManageToSRgb)) ([Windows.Graphics.Imaging.SoftwareBitmap])

$lang = New-Object Windows.Globalization.Language($Language)
$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
if ($null -eq $engine) { Fail "系統沒有 $Language 的 OCR 語言包，可用：$([Windows.Media.Ocr.OcrEngine]::AvailableRecognizerLanguages.LanguageTag -join ', ')" }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
$sw.Stop()

# 座標換算回原圖像素，之後要跟畫面版面規則（左側我方 / 右側對方）對照。
$lines = @()
foreach ($line in $result.Lines) {
  $words = @()
  foreach ($w in $line.Words) {
    $words += [ordered]@{
      text = $w.Text
      x    = [int][Math]::Round(($cropX + $w.BoundingRect.X) / $Scale)
      y    = [int][Math]::Round(($cropY + $w.BoundingRect.Y) / $Scale)
      w    = [int][Math]::Round($w.BoundingRect.Width / $Scale)
      h    = [int][Math]::Round($w.BoundingRect.Height / $Scale)
    }
  }
  $first = $words | Select-Object -First 1
  $lines += [ordered]@{
    # Windows OCR 對中文會在字之間插空白，這裡直接接回去
    text  = ($line.Words | ForEach-Object { $_.Text }) -join ''
    words = $words
    x     = if ($first) { $first.x } else { 0 }
    y     = if ($first) { $first.y } else { 0 }
  }
}

$payload = [ordered]@{
  path       = $full
  language   = $Language
  imageWidth = $srcW
  imageHeight = $srcH
  crop       = [ordered]@{
    x = [int][Math]::Round($cropX / $Scale); y = [int][Math]::Round($cropY / $Scale)
    w = [int][Math]::Round($cropW / $Scale); h = [int][Math]::Round($cropH / $Scale)
    scale = $Scale; scaledW = $cropW; scaledH = $cropH
  }
  elapsedMs  = [int]$sw.ElapsedMilliseconds
  lines      = $lines
}

$payload | ConvertTo-Json -Depth 8 -Compress
