#Requires -Version 5.1
<#
  启动 SnowLuma（QQ 协议端）。
  - 安装目录取自 deploy\config.psd1 的 SnowLumaHome；
  - 5099 已在监听时直接跳过，避免重复实例导致重复回复。
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$config = Get-BotConfig
$root = Get-SnowLumaHome -Config $config
$logs = Get-LogsDir -Config $config
$node = Join-Path $root 'node.exe'
$entry = Join-Path $root 'index.mjs'

if (Test-PortListening -Port 5099) {
    Write-Host '[SnowLuma] 已在运行（5099 正在监听），跳过启动。'
    exit 0
}
if (-not (Test-Path -LiteralPath $node)) { throw "找不到 $node。请把 SnowLuma 官方发行包解压到 $root，或修改 config.psd1 的 SnowLumaHome。" }
if (-not (Test-Path -LiteralPath $entry)) { throw "找不到 SnowLuma 入口 $entry。" }
if (-not (Test-Path -LiteralPath (Join-Path $root 'config\onebot.json'))) {
    Write-Warning "[SnowLuma] 缺少 config\onebot.json，正在从模板生成……"
    $render = Join-Path $PSScriptRoot 'tools\render_config.py'
    $py = Find-AstrBotPython
    if ($py) {
        & $py $render --repo (Get-RepoRoot) --token $config.OneBotToken --bot-qq $config.BotQQ `
            --admin-qq $config.AdminQQ --snowluma-home $root
    } else {
        Write-Warning '无法自动生成 SnowLuma 配置，请手动复制 templates\snowluma\*.json 并替换令牌。'
    }
}

$env:SNOWLUMA_ACCEPT_EULA = '1'
$env:SNOWLUMA_ACCEPT_PRIVACY = '1'
$env:SNOWLUMA_HOOK_AUTOLOAD = '1'
$env:SNOWLUMA_LOG_LEVEL = 'info'
if ($config.ContainsKey('SnowLumaWebUIPassword') -and $config.SnowLumaWebUIPassword) {
    # 仅在 config\webui.json 不存在时生效；登录后在面板里改密码即可。
    $env:SNOWLUMA_WEBUI_BOOTSTRAP_PASSWORD = $config.SnowLumaWebUIPassword
}

$p = Start-Process -FilePath $node `
    -ArgumentList '.\index.mjs' `
    -WorkingDirectory $root `
    -RedirectStandardOutput (Join-Path $logs 'snowluma.out.log') `
    -RedirectStandardError (Join-Path $logs 'snowluma.err.log') `
    -WindowStyle Hidden -PassThru

$p.Id | Set-Content -LiteralPath (Join-Path $logs 'snowluma.pid')
Write-Host "[SnowLuma] 已启动，PID=$($p.Id)  → http://127.0.0.1:5099"
