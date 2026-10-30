#Requires -Version 5.1
<#
  启动本地日语语音服务（可选）。
  依赖第三方项目 AnifLive-TTS（PolyForm Noncommercial）与语音模型包。
  未在 config.psd1 里配置 TtsEnabled/TtsExe 时，本脚本只打印说明并退出。
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$config = Get-BotConfig
$logs = Get-LogsDir -Config $config

if (-not ($config.ContainsKey('TtsEnabled') -and $config.TtsEnabled)) {
    Write-Host '[TTS] 未启用（config.psd1 里 TtsEnabled = $false）。'
    Write-Host '      需要日语语音时，先按 docs\05-模型与语音.md 安装 AnifLive-TTS 和模型，再开启。'
    exit 0
}

$port = 9882
if ($config.ContainsKey('TtsPort') -and $config.TtsPort) { $port = [int]$config.TtsPort }

if (Test-PortListening -Port $port) {
    Write-Host "[TTS] 已在运行（$port 正在监听），跳过启动。"
    exit 0
}

$exe = Resolve-RepoPath $config.TtsExe
$modelDir = Resolve-RepoPath $config.TtsModelDir
$sharedDir = $config.TtsSharedDir
if (-not $sharedDir) {
    $sharedDir = Join-Path (Split-Path $modelDir -Parent) 'shared'
} else {
    $sharedDir = Resolve-RepoPath $sharedDir
}

if (-not (Test-Path -LiteralPath $exe)) { throw "找不到 aniflive-tts：$exe（见 docs\05-模型与语音.md）" }
if (-not (Test-Path -LiteralPath $modelDir)) { throw "找不到语音模型目录：$modelDir" }

# TensorRT 引擎与 GPU/CUDA/TRT 指纹绑定：便携包（无 engines）必须先在本机重建
$engineRoot = Join-Path $modelDir 'engines'
$hasEngine = $false
if (Test-Path -LiteralPath $engineRoot) {
    $hasEngine = [bool](Get-ChildItem -LiteralPath $engineRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'engine-manifest.json') })
}
if (-not $hasEngine) {
    throw @"
模型里没有可用的 TensorRT 引擎。AnifLive-TTS 只有 TensorRT 后端，且引擎与显卡/CUDA/TRT 绑定。
请先在本机重建（需要 NVIDIA 显卡，10~30 分钟）：
  & "$exe" model rebuild-engines --model-package "$modelDir"
重建完成后再运行 start-tts.ps1。详见 docs\05-模型与语音.md 第 3 节。
"@
}

$ttsArgs = @('serve', '--host', '127.0.0.1', '--port', $port, '--model-package', $modelDir, '--shared-dir', $sharedDir)

$p = Start-Process -FilePath $exe -ArgumentList $ttsArgs -WorkingDirectory (Split-Path $modelDir -Parent) `
    -RedirectStandardOutput (Join-Path $logs 'tts.out.log') `
    -RedirectStandardError (Join-Path $logs 'tts.err.log') `
    -WindowStyle Hidden -PassThru

$p.Id | Set-Content -LiteralPath (Join-Path $logs 'tts.pid')

for ($i = 0; $i -lt 180; $i++) {
    Start-Sleep -Seconds 1
    if (Test-PortListening -Port $port) {
        Write-Host "[TTS] 已启动，PID=$($p.Id)  → http://127.0.0.1:$port/v1"
        exit 0
    }
    if ($p.HasExited) { break }
}

Write-Warning "[TTS] 启动超时或进程退出，请看 $(Join-Path $logs 'tts.err.log')"
exit 1
