#Requires -Version 5.1
<#
.SYNOPSIS
  安装 / 校验本地日语语音模型包（AnifLive-TTS 的 kurisu-v2proplus）。

.DESCRIPTION
  仓库不包含这个 7 GB 的模型包（GitHub 单文件上限 100 MB）。
  本脚本负责把它从你已有的位置接到仓库里，或在你下载后做完整性校验。

  模型目录结构（AnifLive-TTS model package）应至少包含：
    manifest.json
    onnx\*.onnx
    voices\default\...
    engines\<fingerprint>\*.engine   （TensorRT，可选）

.PARAMETER Source
  已有的模型目录，或压缩包（.zip / .7z / 7z 分卷 .001）。
  给目录时优先做「目录联接」，失败则复制；给压缩包时先解压到 models\tts\_extract。

.PARAMETER DownloadUrl
  模型包直链（可选）。按扩展名自动选择解压方式（.zip / .7z）；填写后会下载到 models\tts\_download。

.PARAMETER HfRepo
  Hugging Face 仓库，例如 kuris1213/kurisu-v2proplus。会用 hf CLI 下载到 models\tts\_hf。

.PARAMETER HfEndpoint
  Hugging Face 镜像地址（可选），例如 https://hf-mirror.com。

.PARAMETER Verify
  按 checksums.json 校验所有文件（7 GB，约 1~3 分钟）。

.EXAMPLE
  .\scripts\install-tts-model.ps1 -Source "D:\models\kurisu-v2proplus"

.EXAMPLE
  .\scripts\install-tts-model.ps1 -Source "D:\downloads\kurisu-v2proplus.7z"

.EXAMPLE
  .\scripts\install-tts-model.ps1 -DownloadUrl "https://example.com/kurisu-v2proplus.zip"
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$DownloadUrl,
    [string]$HfRepo,
    [string]$HfEndpoint = '',
    [string]$Target = '',
    [switch]$Copy,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\deploy\lib\common.ps1')

$repo = Get-RepoRoot
if (-not $Target) { $Target = Join-Path $repo 'models\tts\kurisu-v2proplus' }
$Target = [System.IO.Path]::GetFullPath($Target)

function Find-7z {
    foreach ($name in @('7z', '7za')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    foreach ($path in @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\7-Zip\7z.exe')
    )) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Expand-ModelArchive {
    param([string]$Archive, [string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $ext = [System.IO.Path]::GetExtension($Archive).ToLowerInvariant()
    if ($ext -eq '.zip') {
        Write-Host "[解压] zip → $Destination（7 GB 级压缩包可能需要几分钟）"
        Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
        return
    }
    if ($ext -eq '.7z' -or $ext -eq '.001') {
        $sevenZip = Find-7z
        if (-not $sevenZip) {
            throw "需要 7-Zip 才能解压 $Archive。请安装 https://www.7-zip.org/ 后重试，或先手动解压再用 -Source 指向目录。"
        }
        Write-Host "[解压] 7z → $Destination（分卷请确保 .001/.002... 都在同一目录）"
        & $sevenZip x '-y' "-o$Destination" $Archive
        if ($LASTEXITCODE -ne 0) { throw "7z 解压失败（exit $LASTEXITCODE）" }
        return
    }
    throw "不支持的压缩格式 '$ext'，请用 .zip / .7z / 7z 分卷 .001。"
}

function Get-ArchiveNameFromUrl {
    param([string]$Url)
    try {
        $name = [System.IO.Path]::GetFileName(([Uri]$Url).AbsolutePath)
        if ($name) { return $name }
    } catch { }
    return 'kurisu-v2proplus.zip'
}

Write-Host ''
Write-Host '本地语音模型安装'
Write-Host "  目标目录：$Target"
Write-Host ''

if ($DownloadUrl) {
    $downloadDir = Join-Path $repo 'models\tts\_download'
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $archive = Join-Path $downloadDir (Get-ArchiveNameFromUrl $DownloadUrl)
    Write-Host "[下载] $DownloadUrl"
    Write-Host "       → $archive"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $archive -UseBasicParsing
    $extractDir = Join-Path $downloadDir 'extracted'
    Expand-ModelArchive -Archive $archive -Destination $extractDir
    $Source = $extractDir
}

if ($HfRepo) {
    $hfCmd = Get-Command 'hf' -ErrorAction SilentlyContinue
    if (-not $hfCmd) { $hfCmd = Get-Command 'huggingface-cli' -ErrorAction SilentlyContinue }
    if (-not $hfCmd) {
        throw "需要 Hugging Face CLI：uv tool install huggingface_hub（或 pip install -U huggingface_hub）"
    }
    if ($HfEndpoint) { $env:HF_ENDPOINT = $HfEndpoint }
    $hfDir = Join-Path $repo 'models\tts\_hf'
    New-Item -ItemType Directory -Force -Path $hfDir | Out-Null
    Write-Host "[HF] hf download $HfRepo → $hfDir"
    & $hfCmd.Source download $HfRepo --local-dir $hfDir
    if ($LASTEXITCODE -ne 0) { throw "hf download 失败（exit $LASTEXITCODE）" }
    $Source = $hfDir
}

if (-not $Source) {
    Write-Host '未提供 -Source / -DownloadUrl / -HfRepo。'
    Write-Host ''
    Write-Host '请把模型包放到本机任意位置，然后重跑：'
    Write-Host '  .\scripts\install-tts-model.ps1 -Source "D:\path\to\kurisu-v2proplus"'
    Write-Host '  .\scripts\install-tts-model.ps1 -HfRepo kuris1213/kurisu-v2proplus'
    Write-Host ''
    Write-Host '模型包不在仓库里，原因见 docs\05-模型与语音.md。'
    exit 0
}

if (-not (Test-Path -LiteralPath $Source)) { throw "找不到 Source：$Source" }

if (Test-Path -LiteralPath $Source -PathType Leaf) {
    $extractDir = Join-Path $repo 'models\tts\_extract'
    Expand-ModelArchive -Archive $Source -Destination $extractDir
    $Source = $extractDir
}

# 统一找到真正的模型根（兼容压缩包多套 1~2 层目录）
$modelRoot = $Source
for ($depth = 0; $depth -lt 3; $depth++) {
    if (Test-Path -LiteralPath (Join-Path $modelRoot 'manifest.json')) { break }
    $candidate = Get-ChildItem -LiteralPath $modelRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json') } |
        Select-Object -First 1
    if (-not $candidate) { break }
    $modelRoot = $candidate.FullName
}
if (-not (Test-Path -LiteralPath (Join-Path $modelRoot 'manifest.json'))) {
    throw "$modelRoot 里没有 manifest.json，看起来不是 AnifLive-TTS 模型包。"
}

# 便携包通常把 shared 放在模型目录的同级（AnifLive 的公共权重）
New-Item -ItemType Directory -Force -Path (Split-Path $Target -Parent) | Out-Null
$sharedSource = Join-Path (Split-Path $modelRoot -Parent) 'shared'
$sharedTarget = Join-Path (Split-Path $Target -Parent) 'shared'
if ((Test-Path -LiteralPath $sharedSource) -and -not (Test-Path -LiteralPath $sharedTarget)) {
    try {
        New-Item -ItemType Junction -Path $sharedTarget -Target $sharedSource -ErrorAction Stop | Out-Null
        Write-Host "[联接] $sharedTarget → $sharedSource"
    } catch {
        Write-Host '[复制] shared 无法创建联接，改为复制（约 1 GB）……'
        Copy-Item -LiteralPath $sharedSource -Destination $sharedTarget -Recurse -Force
    }
}

$size = (Get-ChildItem -LiteralPath $modelRoot -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host ("[模型] {0}  约 {1:N1} GB" -f $modelRoot, ($size / 1GB))

if (Test-Path -LiteralPath $Target) {
    Write-Host "[跳过] $Target 已存在。如需替换请先手动删除。"
} elseif ($Copy) {
    Write-Host '[复制] 正在复制模型（3~7 GB，需要几分钟）……'
    Copy-Item -LiteralPath $modelRoot -Destination $Target -Recurse -Force
} else {
    try {
        # 同盘优先用目录联接，省空间；跨盘会失败后回退到复制
        New-Item -ItemType Junction -Path $Target -Target $modelRoot -ErrorAction Stop | Out-Null
        Write-Host "[联接] $Target → $modelRoot"
    } catch {
        Write-Host '[复制] 无法创建联接，改为复制模型（3~7 GB，需要几分钟）……'
        Copy-Item -LiteralPath $modelRoot -Destination $Target -Recurse -Force
    }
}

if ($Verify) {
    $checksums = Join-Path $modelRoot 'checksums.json'
    if (-not (Test-Path -LiteralPath $checksums)) {
        # 回退到仓库里保存的原始清单（不依赖模型包自身的 checksums.json）
        $checksums = Join-Path $repo 'models\tts\kurisu-v2proplus.metadata\checksums.json'
    }
    if (-not (Test-Path -LiteralPath $checksums)) {
        Write-Warning '找不到 checksums.json，跳过校验。'
    } else {
        $map = Get-Content -LiteralPath $checksums -Raw -Encoding UTF8 | ConvertFrom-Json
        $bad = 0
        $missing = 0
        $checked = 0
        foreach ($prop in $map.PSObject.Properties) {
            $file = Join-Path $modelRoot ($prop.Name -replace '/', '\')
            if (-not (Test-Path -LiteralPath $file)) {
                # 精简包（例如只保留 onnx、删掉 TensorRT engines）会缺少一部分文件，
                # 这不算损坏，只统计数量。
                $missing++
                continue
            }
            $checked++
            $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -ne $prop.Value) {
                Write-Warning "校验失败：$($prop.Name)"
                $bad++
            }
        }
        if ($bad -eq 0) {
            Write-Host "[校验] 已校验 $checked 个文件，全部通过。" -ForegroundColor Green
        } else {
            Write-Warning "[校验] $bad 个文件哈希不匹配（文件可能损坏）。"
        }
        if ($missing -gt 0) {
            Write-Host "[校验] 另有 $missing 个文件不在当前包中（精简包正常现象，例如删掉的 engines）。"
        }
    }
}

Write-Host ''
Write-Host '下一步：'
Write-Host '  1. 安装 AnifLive-TTS（见 docs\05-模型与语音.md），拿到 aniflive-tts.exe；'
Write-Host '  2. 在 deploy\config.psd1 里设置 TtsEnabled = $true、TtsExe = <exe 路径>；'
Write-Host '  3. 运行 deploy\start-tts.ps1。'
Write-Host ''
