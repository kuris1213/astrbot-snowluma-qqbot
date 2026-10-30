#Requires -Version 5.1
<#
  打开三个管理页：AstrBot(6185) / SnowLuma(5099) / 主动消息插件(4100)。
  任一核心服务没起时，会先在后台拉起整套（embedding → SnowLuma → AstrBot → QQ）。
  用法：双击仓库根目录的「打开管理页.bat」，或
        powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\open-admin.ps1
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$astrbotUrl = 'http://127.0.0.1:6185/'
$snowlumaUrl = 'http://127.0.0.1:5099/'
$proactiveUrl = 'http://127.0.0.1:4100/'

if (-not (Test-PortListening -Port 5099) -or -not (Test-PortListening -Port 6185)) {
    Write-Host '[服务] 未全部运行，正在后台启动整套……首次启动约 60~120 秒。'
    $startAll = Join-Path $PSScriptRoot 'start-all.ps1'
    if (Test-Path -LiteralPath $startAll) {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $startAll `
            -WindowStyle Hidden
    } else {
        Write-Warning "[服务] 找不到 $startAll"
    }
    if (-not (Wait-Port -Port 5099 -TimeoutSeconds 200)) { Write-Warning '[SnowLuma] 200 秒内未就绪。' }
    if (-not (Wait-Port -Port 6185 -TimeoutSeconds 240)) { Write-Warning '[AstrBot] 240 秒内未就绪。' }
}

if (-not (Wait-Port -Port 4100 -TimeoutSeconds 20)) {
    Write-Host '[主动消息] 4100 暂未就绪，页面稍后可能可用。'
}

Start-Process $astrbotUrl
Start-Sleep -Milliseconds 400
Start-Process $snowlumaUrl
Start-Sleep -Milliseconds 400
Start-Process $proactiveUrl

Write-Host ''
Write-Host '已打开：'
Write-Host "  AstrBot    $astrbotUrl  （初始密码见 logs\astrbot.out.log）"
Write-Host "  SnowLuma   $snowlumaUrl"
Write-Host "  主动消息   $proactiveUrl"
