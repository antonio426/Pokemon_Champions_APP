<#
.SYNOPSIS
  產生一張模擬對戰選人畫面的測試圖，讓 Phase 0 管線在拿到真實截圖前就能跑通。

.DESCRIPTION
  版面刻意模仿手機版對戰的選人畫面：左側直排是我方寶可夢名稱（要用 OCR 讀），
  右側是對方的圖示區。這張圖只驗證「管線接得起來」，準確率仍必須用真實截圖量。
#>
param(
  [string]$Out = 'fixtures/mock-battle.png',
  [int]$Width = 1170,
  [int]$Height = 2532,
  [string[]]$Mine = @('噴火龍', '沙奈朵', '耿鬼', '暴鯉龍', '快龍', '班基拉斯'),
  [string[]]$Theirs = @('水箭龜', '妙蛙花', '大針蜂', '鐵甲蛹', '皮卡丘', '超夢')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$full = [System.IO.Path]::GetFullPath($Out)
$dir = [System.IO.Path]::GetDirectoryName($full)
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

$bmp = New-Object System.Drawing.Bitmap($Width, $Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'ClearTypeGridFit'

$g.Clear([System.Drawing.Color]::FromArgb(24, 28, 38))

$titleFont = New-Object System.Drawing.Font('Microsoft JhengHei', 34, [System.Drawing.FontStyle]::Bold)
$nameFont = New-Object System.Drawing.Font('Microsoft JhengHei', 40, [System.Drawing.FontStyle]::Bold)
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$dim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, 180, 200))
$cardMine = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(38, 62, 96))
$cardTheirs = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(96, 44, 48))

$g.DrawString('對戰準備', $titleFont, $dim, 60, 120)

# 左側：我方，名稱以文字呈現 → OCR 的目標
$y = 300
foreach ($n in $Mine) {
  $g.FillRectangle($cardMine, 60, $y, 460, 150)
  $g.DrawString($n, $nameFont, $white, 90, ($y + 45))
  $y += 190
}

# 右側：對方，只給圖示色塊 + 小字，模擬「看得到圖但沒有清楚文字」的情況
$y = 300
foreach ($n in $Theirs) {
  $g.FillRectangle($cardTheirs, 650, $y, 460, 150)
  $g.DrawString($n, $nameFont, $white, 680, ($y + 45))
  $y += 190
}

$bmp.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output $full
