#Requires -Version 5.1
<#
  一键启动：向量服务 → SnowLuma → AstrBot →（可选）TTS → QQ 客户端。
  用法：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\start-all.ps1
    powershell ... -File .\deploy\start-all.ps1 -NoQQ     # 不自动拉起 QQ
#>
param(
    [switch]$NoQQ
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$config = Get-BotConfig

# 互斥：并发启动会打乱「先 SnowLuma 后 QQ」的顺序，导致 hook 注入失败（能发不能收）
$mutex = New-Object System.Threading.Mutex($false, 'Local\AstrBotStackStart')
if (-not $mutex.WaitOne(0)) {
    Write-Host '[启动] 另一个启动流程正在进行，跳过本次启动。'
    exit 0
}

function Start-Step {
    param([string]$Name, [string]$Script)
    Write-Host "── $Name ──"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $Script)
}

$embeddingEnabled = $true
if ($config.ContainsKey('EmbeddingEnabled')) { $embeddingEnabled = [bool]$config.EmbeddingEnabled }
$ttsEnabled = $false
if ($config.ContainsKey('TtsEnabled')) { $ttsEnabled = [bool]$config.TtsEnabled }

if ($embeddingEnabled) {
    Start-Step '本地向量服务（知识库）' 'start-embedding.ps1'
} else {
    Write-Host '── 本地向量服务：已在配置中关闭，跳过 ──'
}

Start-Step 'SnowLuma（QQ 协议端）' 'start-snowluma.ps1'
Start-Step 'AstrBot（机器人框架）' 'start-astrbot.ps1'

if ($ttsEnabled) {
    Start-Step '本地日语语音（AnifLive-TTS）' 'start-tts.ps1'
}

# 关键顺序：SnowLuma 必须先在 QQ 登录前把 hook 注入，否则「能发消息、收不到消息」
if (-not (Wait-Port -Port 5099 -TimeoutSeconds 90)) {
    Write-Warning '[SnowLuma] 90 秒内未就绪，本次不启动 QQ（避免 hook 注入顺序错误）。'
    $NoQQ = $true
}
if (-not (Wait-Port -Port 6185 -TimeoutSeconds 90)) {
    Write-Warning '[AstrBot] 90 秒内未就绪（QQ 仍会启动，稍后会自动重连）。'
}

if (-not $NoQQ) {
    Write-Host '── QQ 客户端 ──'
    $qqExe = ''
    if ($config.ContainsKey('QQExe') -and $config.QQExe) { $qqExe = Resolve-RepoPath $config.QQExe }
    if (-not $qqExe) { $qqExe = Get-DefaultQQExe }

    $qq = Get-Process -Name 'QQ' -ErrorAction SilentlyContinue
    if ($qq) {
        Write-Host '[QQ] 已在运行。若机器人「能发不能收」，请重启 QQ。'
    } elseif ($qqExe -and (Test-Path -LiteralPath $qqExe)) {
        Start-Process -FilePath $qqExe -WorkingDirectory (Split-Path $qqExe) | Out-Null
        Write-Host '[QQ] 已启动，请在 QQ 窗口扫码登录机器人账号。'
    } else {
        Write-Warning '[QQ] 找不到 QQ.exe，请手动启动并登录机器人账号。'
    }
}

Write-Host ''
Write-Host '启动流程结束：'
Write-Host '  AstrBot  http://127.0.0.1:6185'
Write-Host '  SnowLuma http://127.0.0.1:5099'
Write-Host '  主动消息 http://127.0.0.1:4100'
