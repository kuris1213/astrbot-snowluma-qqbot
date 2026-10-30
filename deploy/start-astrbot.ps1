#Requires -Version 5.1
<#
  启动 AstrBot（机器人框架）。
  - 工作目录取自 deploy\config.psd1 的 AstrBotHome；
  - 6185 已在监听时直接跳过；
  - 日志写到 <LogsDir>\astrbot.out.log / .err.log。
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$config = Get-BotConfig
$root = Get-AstrBotHome -Config $config
$logs = Get-LogsDir -Config $config
$exe = Find-AstrBotExe

if (-not $exe) { throw '找不到 astrbot 命令，请先运行 deploy\install.ps1（或确认 %USERPROFILE%\.local\bin 在 PATH 中）。' }
if (-not (Test-Path -LiteralPath (Join-Path $root '.astrbot'))) { throw "找不到 $root\.astrbot 标记，请先运行 install.ps1。" }

if (Test-PortListening -Port 6185) {
    Write-Host '[AstrBot] 已在运行（6185 正在监听），跳过启动。'
    exit 0
}

Enable-Utf8Environment

# ── DeepSeek Key 提醒（Key 由部署者本人提供，仓库不包含）──────
$keyOk = $false
$cmdPath = Join-Path $root 'data\cmd_config.json'
if (Test-Path -LiteralPath $cmdPath) {
    try {
        $cfgObj = Get-Content -LiteralPath $cmdPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $ds = @($cfgObj.provider_sources) | Where-Object { $_.provider -eq 'deepseek' } | Select-Object -First 1
        if ($ds) {
            foreach ($k in @($ds.key)) {
                if ($k -and $k -notlike 'sk-REPLACE*') { $keyOk = $true }
            }
        }
    } catch {
        # 配置还没写完整时忽略，让 AstrBot 自己报错
    }
}
$keyNotice = Join-Path $logs 'API-KEY-README.txt'
if (-not (Test-Path -LiteralPath $keyNotice)) {
    $short = @"
【部署提醒】DeepSeek API Key 由「部署者本人」提供，本仓库不包含任何可用 Key。
Key 只写在本机 deploy\config.psd1 与 astrbot\data\cmd_config.json（均被 .gitignore 排除）。
没有 Key 时机器人能收消息但不会回复；获取：https://platform.deepseek.com/api_keys
"@
    [System.IO.File]::WriteAllText($keyNotice, $short, (New-Object System.Text.UTF8Encoding($true)))
}
if (-not $keyOk) {
    Write-Warning '[AstrBot] 没有可用的 DeepSeek API Key：机器人能收消息，但不会回复对话。'
    Write-Warning '          Key 必须由部署者本人提供（自己的 DeepSeek 账号），详见 logs\API-KEY-README.txt。'
}

# 插件依赖的外部命令（ffmpeg / ffprobe / yt-dlp）：优先用仓库内 tools\bin，其次用配置里的 ToolsBin
$pathParts = @()
$localTools = Join-Path (Get-RepoRoot) 'tools\bin'
if (Test-Path -LiteralPath $localTools) { $pathParts += $localTools }
if ($config.ContainsKey('ToolsBin') -and $config.ToolsBin) {
    $toolsBin = Resolve-RepoPath $config.ToolsBin
    if (Test-Path -LiteralPath $toolsBin) { $pathParts += $toolsBin }
}
if ($pathParts.Count -gt 0) {
    $env:PATH = (($pathParts + $env:PATH) -join ';')
}

$p = Start-Process -FilePath $exe `
    -ArgumentList 'run' `
    -WorkingDirectory $root `
    -RedirectStandardOutput (Join-Path $logs 'astrbot.out.log') `
    -RedirectStandardError (Join-Path $logs 'astrbot.err.log') `
    -WindowStyle Hidden -PassThru

$p.Id | Set-Content -LiteralPath (Join-Path $logs 'astrbot.pid')
Write-Host "[AstrBot] 已启动，PID=$($p.Id)  → http://127.0.0.1:6185"
