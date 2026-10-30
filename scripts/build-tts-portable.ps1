#Requires -Version 5.1
<#
.SYNOPSIS
  把完整的 AnifLive-TTS 模型包精简成「可分享的便携包」。

.DESCRIPTION
  完整包里的 engines\ 是 TensorRT 引擎，绑定 GPU/CUDA/TensorRT/平台指纹，
  换一台机器就用不了，而且占 4.8 GiB。便携包只保留可跨机器复用的部分：

    kurisu-v2proplus\onnx\          约 2.0 GiB
    kurisu-v2proplus\voices\        < 10 MB
    kurisu-v2proplus\manifest.json  去掉 active_engine_fingerprint
    kurisu-v2proplus\source.json
    kurisu-v2proplus\checksums.json 按精简后的文件重新生成
    shared\                         约 1.0 GiB（AnifLive 公共权重）

  对方解压后先在本机重建引擎：
    aniflive-tts model rebuild-engines --model-package <模型目录>

.PARAMETER Source
  本机完整的模型目录，默认 D:\models\kurisu-v2proplus。

.PARAMETER SharedDir
  AnifLive 的 shared 目录，默认 <Source 的上一级>\shared。

.PARAMETER Output
  输出目录，默认 D:\models\portable。

.PARAMETER AnifLivePython
  AnifLive-TTS 所在虚拟环境的 python.exe；用它来重算 checksums.json。

.PARAMETER Compress
  同时生成 kurisu-v2proplus-portable.7z（自动下载 7zr.exe）。

.PARAMETER NoShared
  不复制 shared（只做模型本体，约 2.0 GiB）。发布到 Hugging Face 时推荐，
  对方用 AnifLive 的 setup_shared_assets.py 自行下载。

.PARAMETER SplitSize
  配合 -Compress 使用，例如 "1900m" 生成 .001/.002 分卷。

.EXAMPLE
  .\scripts\build-tts-portable.ps1

.EXAMPLE
  .\scripts\build-tts-portable.ps1 -Compress -SplitSize 1900m
#>
[CmdletBinding()]
param(
    [string]$Source = 'D:\models\kurisu-v2proplus',
    [string]$SharedDir = '',
    [string]$Output = 'D:\models\portable',
    [string]$AnifLivePython = 'D:\gpt.sovit\AnifLive-TTS\.venv\Scripts\python.exe',
    [switch]$Compress,
    [string]$SplitSize = '',
    [switch]$NoShared,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\deploy\lib\common.ps1')

$Source = [System.IO.Path]::GetFullPath($Source)
$Output = [System.IO.Path]::GetFullPath($Output)
if (-not $SharedDir) { $SharedDir = Join-Path (Split-Path $Source -Parent) 'shared' }
$SharedDir = [System.IO.Path]::GetFullPath($SharedDir)

Write-Host ''
Write-Host '构建 AnifLive-TTS 便携包'
Write-Host "  源模型：$Source"
Write-Host "  shared：$SharedDir"
Write-Host "  输出：  $Output"
Write-Host ''

if (-not (Test-Path -LiteralPath (Join-Path $Source 'manifest.json'))) { throw "$Source 不是模型包（缺 manifest.json）" }
if (-not (Test-Path -LiteralPath (Join-Path $Source 'onnx'))) { throw "$Source 缺 onnx\ 目录" }
if (-not $NoShared -and -not (Test-Path -LiteralPath $SharedDir)) { throw "找不到 shared 目录：$SharedDir（用 -SharedDir 指定）" }
if (-not (Test-Path -LiteralPath $AnifLivePython)) { throw "找不到 AnifLive 的 python：$AnifLivePython（用 -AnifLivePython 指定）" }

$pkg = Join-Path $Output 'kurisu-v2proplus'
if (Test-Path -LiteralPath $pkg) {
    if (-not $Force) { throw "$pkg 已存在；加 -Force 覆盖。" }
    Remove-Item -LiteralPath $pkg -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $pkg | Out-Null
if (-not $NoShared) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Output 'shared') | Out-Null
}

Write-Host '[复制] onnx / voices / validation-inputs ……'
foreach ($sub in @('onnx', 'voices', 'validation-inputs')) {
    $from = Join-Path $Source $sub
    if (-not (Test-Path -LiteralPath $from)) { Write-Host "  skip $sub（源里没有）"; continue }
    & robocopy $from (Join-Path $pkg $sub) /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
}
Copy-Item -LiteralPath (Join-Path $Source 'manifest.json'), (Join-Path $Source 'source.json') -Destination $pkg -Force

if (-not $NoShared) {
    Write-Host '[复制] shared（约 1 GB）……'
    & robocopy $SharedDir (Join-Path $Output 'shared') /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
}

Write-Host '[处理] 去掉 engines 指纹并按精简后的文件重算 checksums ……'
$metaPy = Join-Path $env:TEMP 'aniflive_portable_meta.py'
$metaCode = @'
import json
import sys
from pathlib import Path
from aniflive_tts.model_package import validate_checksums, write_checksums

pkg = Path(sys.argv[1])
manifest = json.loads((pkg / "manifest.json").read_text("utf-8-sig"))
manifest.pop("active_engine_fingerprint", None)
manifest.pop("engines_rebuilt_at", None)
(pkg / "manifest.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
write_checksums(pkg)
validate_checksums(pkg)
print("checksums ok")
'@
[System.IO.File]::WriteAllText($metaPy, $metaCode, (New-Object System.Text.UTF8Encoding($false)))
& $AnifLivePython $metaPy $pkg
if ($LASTEXITCODE -ne 0) { throw '重算 checksums 失败，请检查 AnifLivePython 是否可导入 aniflive_tts' }

$size = (Get-ChildItem -LiteralPath $Output -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("[完成] 便携包目录：{0}（{1:N2} GiB）" -f $Output, ($size / 1GB))

if ($Compress) {
    $sevenZip = Join-Path $env:TEMP '7zr.exe'
    if (-not (Test-Path -LiteralPath $sevenZip)) {
        Write-Host '[下载] 7zr.exe（约 600 KB）……'
        Invoke-WebRequest -Uri 'https://www.7-zip.org/a/7zr.exe' -OutFile $sevenZip -UseBasicParsing
    }
    $archive = Join-Path $Output 'kurisu-v2proplus-portable.7z'
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    Get-ChildItem -Path $Output -Filter 'kurisu-v2proplus-portable.7z.*' -ErrorAction SilentlyContinue |
        Remove-Item -Force

    $sevenArgs = @('a', '-t7z', '-mx=5', '-ms=off')
    if ($SplitSize) { $sevenArgs += "-v$SplitSize" }
    $sevenArgs += @('kurisu-v2proplus-portable.7z', 'kurisu-v2proplus')
    if (-not $NoShared) { $sevenArgs += 'shared' }

    Write-Host '[压缩] 7z（非 solid，需要几分钟）……'
    Push-Location $Output
    try {
        & $sevenZip @sevenArgs
        if ($LASTEXITCODE -ne 0) { throw "7z 压缩失败（exit $LASTEXITCODE）" }
    } finally {
        Pop-Location
    }
    Get-ChildItem -Path $Output -Filter 'kurisu-v2proplus-portable.7z*' |
        Select-Object Name, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 1) } } |
        Format-Table -AutoSize
}

Write-Host ''
Write-Host '下一步：'
Write-Host '  · 上传到 Hugging Face / 网盘（不要放进 Git 仓库，见 docs\05-模型与语音.md 第 3 节）'
Write-Host '  · 对方下载后：.\scripts\install-tts-model.ps1 -Source <压缩包或目录>'
Write-Host '  · 然后在本机重建引擎：aniflive-tts model rebuild-engines --model-package <模型目录>'
Write-Host ''
