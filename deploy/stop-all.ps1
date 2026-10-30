#Requires -Version 5.1
<#
  停止机器人相关进程（按端口，不依赖进程名）。
  用法：
    .\deploy\stop-all.ps1              # 只停 SnowLuma / AstrBot / 向量 / TTS
    .\deploy\stop-all.ps1 -IncludeQQ   # 连 QQ 一起关
#>
param(
    [switch]$IncludeQQ
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$config = Get-BotConfig

function Stop-ByPort {
    param([int]$Port, [string]$Label)
    $conn = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue
    if (-not $conn) { Write-Host "[$Label] 未在运行。"; return }
    foreach ($procId in ($conn.OwningProcess | Select-Object -Unique)) {
        try {
            Stop-Process -Id $procId -Force -ErrorAction Stop
            Write-Host "[$Label] 已停止 PID=$procId"
        } catch {
            Write-Warning "[$Label] 停止 PID=$procId 失败：$($_.Exception.Message)"
        }
    }
}

Stop-ByPort 4100 '主动消息管理端'
Stop-ByPort 18999 'QQ 空间守护进程'
Stop-ByPort 6185 'AstrBot'
Stop-ByPort 5099 'SnowLuma'
Stop-ByPort 9882 'TTS'
Stop-ByPort 8010 'Embedding'

# 兜底：SnowLuma 可能拉起子进程，按路径匹配清理
$snowlumaHome = Get-SnowLumaHome -Config $config
if ($snowlumaHome -and (Test-Path -LiteralPath $snowlumaHome)) {
    Get-Process -Name 'node' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($snowlumaHome, [System.StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object {
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
            Write-Host "[SnowLuma] 已停止残留 node PID=$($_.Id)"
        }
}

if ($IncludeQQ) {
    Get-Process -Name 'QQ' -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-Process -Id $_.Id -Force; Write-Host "[QQ] 已停止 PID=$($_.Id)" }
}
