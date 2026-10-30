#Requires -Version 5.1
<#
.SYNOPSIS
  一键初始化 AstrBot + SnowLuma QQ 机器人（Windows 10/11 x64）。

.DESCRIPTION
  做四件事：
    1. 安装 uv 与 AstrBot 4.29.3（PyPI，独立 Python 3.12 环境）；
    2. 建立 AstrBot 工作目录，铺开插件 / 表情包 / 知识库；
    3. 把 templates 里的脱敏配置渲染成本机配置（写入随机令牌与你的 QQ/Key）；
    4. 可选：创建本地向量模型（bge-small-zh-v1.5）运行环境。

  SnowLuma 是第三方软件，需要你从官方渠道下载后解压，本脚本只负责写它的配置。

.PARAMETER Yes
  全部使用默认值 / 自动确认，不交互（适合脚本化部署）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\install.ps1

.EXAMPLE
  .\deploy\install.ps1 -Yes -BotQQ 123456789 -AdminQQ 10001 -DeepSeekKey sk-xxx -SkipEmbedding
#>
[CmdletBinding()]
param(
    [string]$AstrBotHome,
    [string]$SnowLumaHome,
    [string]$QQExe,
    [string]$BotQQ,
    [string]$AdminQQ,
    [string]$OneBotToken,
    [string]$DeepSeekKey,
    [switch]$SkipAstrBot,
    [switch]$SkipEmbedding,
    [switch]$SkipSnowLuma,
    [switch]$Force,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Off

. (Join-Path $PSScriptRoot 'lib\common.ps1')

$repo = Get-RepoRoot
Write-Host ''
Write-Host '=============================================='
Write-Host ' AstrBot + SnowLuma QQ 机器人 · 部署初始化'
Write-Host " 仓库目录：$repo"
Write-Host '=============================================='
Write-Host ''

if (-not [Environment]::Is64BitOperatingSystem) {
    throw '本项目只支持 64 位 Windows。'
}

$configPath = Get-BotConfigPath
$old = $null
if (Test-Path -LiteralPath $configPath) {
    $old = Import-PowerShellDataFile -Path $configPath
    Write-Host "[配置] 已存在 $configPath，本次会复用其中的值（可用参数覆盖）。"
}

# ── 1. 收集参数 ────────────────────────────────────────────
function Use-OldOrPrompt {
    param([string]$Name, [string]$Current, [string]$Prompt, [string]$Default = '')
    if ($Current) { return $Current }
    if ($old -and $old.ContainsKey($Name) -and $old[$Name]) { return [string]$old[$Name] }
    if ($Yes) { return $Default }
    return (Read-HostDefault -Prompt $Prompt -Default $Default)
}

if (-not $BotQQ) { $BotQQ = Use-OldOrPrompt -Name 'BotQQ' -Current '' -Prompt '机器人 QQ 号（建议用小号）' }
if (-not $AdminQQ) { $AdminQQ = Use-OldOrPrompt -Name 'AdminQQ' -Current '' -Prompt '主人 QQ 号（接收通知、执行管理员命令）' }
if (-not $AstrBotHome) {
    $AstrBotHome = Use-OldOrPrompt -Name 'AstrBotHome' -Current '' -Prompt 'AstrBot 工作目录' -Default 'astrbot'
}
if (-not $SnowLumaHome) {
    $SnowLumaHome = Use-OldOrPrompt -Name 'SnowLumaHome' -Current '' -Prompt 'SnowLuma 解压目录' -Default 'C:\SnowLuma'
}
if (-not $QQExe) {
    $QQExe = Use-OldOrPrompt -Name 'QQExe' -Current '' -Prompt 'QQ.exe 路径' -Default (Get-DefaultQQExe)
}
if (-not $OneBotToken) {
    if ($old -and $old.ContainsKey('OneBotToken') -and $old['OneBotToken']) { $OneBotToken = [string]$old['OneBotToken'] }
    else { $OneBotToken = New-RandomToken }
}
$snowlumaWebUIPassword = ''
if ($old -and $old.ContainsKey('SnowLumaWebUIPassword') -and $old['SnowLumaWebUIPassword']) {
    $snowlumaWebUIPassword = [string]$old['SnowLumaWebUIPassword']
} else {
    $snowlumaWebUIPassword = 'SnowLuma@' + (New-RandomToken).Substring(0, 8)
}
if (-not $DeepSeekKey -and $old -and $old.ContainsKey('DeepSeekKey')) {
    $DeepSeekKey = [string]$old['DeepSeekKey']
}
if (-not $DeepSeekKey -and -not $Yes) {
    $inputKey = Read-Host 'DeepSeek API Key（可留空，之后在 WebUI 里填）'
    if ($inputKey) { $DeepSeekKey = $inputKey.Trim() }
}

if ($BotQQ -notmatch '^[1-9][0-9]{4,11}$') { throw "机器人 QQ 号格式不对：'$BotQQ'（应为 5~12 位数字）" }
if ($AdminQQ -notmatch '^[1-9][0-9]{4,11}$') { throw "主人 QQ 号格式不对：'$AdminQQ'" }
if ($OneBotToken.Length -lt 16) { throw 'OneBot 令牌至少 16 位，请重新生成' }

# ── 2. uv 与 AstrBot ──────────────────────────────────────
function Get-UvExe {
    $cmd = Get-Command 'uv' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

function Install-Uv {
    Write-Host '[uv] 未检测到 uv，准备安装……'
    $winget = Get-Command 'winget' -ErrorAction SilentlyContinue
    if ($winget -and (Confirm-Step -Prompt '用 winget 安装 uv（Astral）？' -Yes:$Yes)) {
        & winget install -e --id astral-sh.uv --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -eq 0) { return }
        Write-Warning '[uv] winget 安装失败，改试官方脚本。'
    }
    if (-not $Yes -and -not (Confirm-Step -Prompt '执行官方安装脚本 https://astral.sh/uv/install.ps1 ？')) {
        throw '已取消。请手动安装 uv 后重跑：https://docs.astral.sh/uv/'
    }
    $script = (Invoke-WebRequest -Uri 'https://astral.sh/uv/install.ps1' -UseBasicParsing).Content
    Invoke-Expression $script
}

$uv = Get-UvExe
if (-not $uv) {
    Install-Uv
    $uv = Get-UvExe
}
if (-not $uv) { throw 'uv 安装后仍找不到可执行文件，请重开一个终端再试。' }
Write-Host "[uv] $uv"

if (-not $SkipAstrBot) {
    Write-Host '[AstrBot] 安装 / 更新 astrbot==4.29.3（首次会下载 Python 与依赖，约 3~8 分钟）……'
    & $uv tool install 'astrbot==4.29.3' --python 3.12
    if ($LASTEXITCODE -ne 0) { throw "uv tool install 失败（exit $LASTEXITCODE），请检查网络或代理。" }
    $astrbotExe = Find-AstrBotExe
    if (-not $astrbotExe) { throw '安装完成但找不到 astrbot 命令，请检查 %USERPROFILE%\.local\bin 是否在 PATH。' }
    Write-Host "[AstrBot] $astrbotExe"
}

# ── 3. AstrBot 工作目录与资源 ─────────────────────────────
$astrbotRoot = Resolve-RepoPath $AstrBotHome
$dataDir = Join-Path $astrbotRoot 'data'
$dirs = @(
    $astrbotRoot,
    $dataDir,
    (Join-Path $dataDir 'config'),
    (Join-Path $dataDir 'plugins'),
    (Join-Path $dataDir 'plugin_data'),
    (Join-Path $dataDir 'knowledge_base'),
    (Join-Path $dataDir 'logs'),
    (Join-Path $dataDir 'attachments'),
    (Join-Path $dataDir 'temp'),
    (Join-Path $dataDir 'workspaces'),
    (Join-Path $dataDir 'skills'),
    (Join-Path $dataDir 't2i_templates'),
    (Join-Path $dataDir 'webchat')
)
foreach ($dir in $dirs) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
New-Item -ItemType File -Force -Path (Join-Path $astrbotRoot '.astrbot') | Out-Null

function Copy-Tree {
    param([string]$Source, [string]$Destination, [string]$Label)
    if (-not (Test-Path -LiteralPath $Source)) { Write-Warning "[$Label] 源目录不存在，跳过：$Source"; return }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Destination -Recurse -Force
    Write-Host "[$Label] 已铺开到 $Destination"
}

Copy-Tree -Source (Join-Path $repo 'resources\plugins') -Destination (Join-Path $dataDir 'plugins') -Label '插件'
Copy-Tree -Source (Join-Path $repo 'resources\meme-packs') -Destination (Join-Path $dataDir 'plugin_data\meme_manager') -Label '表情包'

$kbTarget = Join-Path $dataDir 'knowledge_base\kb.db'
if ((Test-Path -LiteralPath $kbTarget) -and -not $Force) {
    Write-Host "[知识库] 已存在 $kbTarget，保留现有数据（-Force 可覆盖）。"
} else {
    Copy-Tree -Source (Join-Path $repo 'resources\knowledge_base') -Destination (Join-Path $dataDir 'knowledge_base') -Label '知识库'
}

# ── 4. 渲染配置 ───────────────────────────────────────────
$uvTools = (& $uv tool dir) | Select-Object -First 1
$py = Join-Path $uvTools 'astrbot\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $py)) {
    $py = Get-Command 'python' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
}
if (-not $py -or -not (Test-Path -LiteralPath $py)) {
    throw '找不到可用于渲染配置的 Python（AstrBot 的 uv 环境）。请先完成 AstrBot 安装。'
}

$renderArgs = @(
    (Join-Path $PSScriptRoot 'tools\render_config.py'),
    '--repo', $repo,
    '--astrbot-home', $astrbotRoot,
    '--token', $OneBotToken,
    '--bot-qq', $BotQQ,
    '--admin-qq', $AdminQQ,
    '--snowluma-home', (Resolve-RepoPath $SnowLumaHome)
)
if ($DeepSeekKey) { $renderArgs += @('--deepseek-key', $DeepSeekKey) }
if ($Force) { $renderArgs += '--force' }
& $py @renderArgs
if ($LASTEXITCODE -ne 0) { throw '配置渲染失败，见上面的报错。' }

# ── 5. 写本机部署配置 ─────────────────────────────────────
function Escape-Psd1([string]$Value) { return ($Value -replace "'", "''") }

# 重复安装时保留上一轮的语音/外部工具设置，避免被重置
$ttsEnabled = $false
$ttsExe = ''
$ttsModelDir = 'models\tts\kurisu-v2proplus'
$ttsSharedDir = ''
$ttsPort = 9882
$toolsBin = ''
$embeddingEnabled = (-not $SkipEmbedding)
if ($old) {
    if ($old.ContainsKey('TtsEnabled')) { $ttsEnabled = [bool]$old['TtsEnabled'] }
    if ($old.ContainsKey('TtsExe')) { $ttsExe = [string]$old['TtsExe'] }
    if ($old.ContainsKey('TtsModelDir') -and $old['TtsModelDir']) { $ttsModelDir = [string]$old['TtsModelDir'] }
    if ($old.ContainsKey('TtsSharedDir')) { $ttsSharedDir = [string]$old['TtsSharedDir'] }
    if ($old.ContainsKey('TtsPort') -and $old['TtsPort']) { $ttsPort = [int]$old['TtsPort'] }
    if ($old.ContainsKey('ToolsBin')) { $toolsBin = [string]$old['ToolsBin'] }
    if ($old.ContainsKey('EmbeddingEnabled')) { $embeddingEnabled = [bool]$old['EmbeddingEnabled'] }
}
$psd1 = @"
@{
    BotQQ        = '$(Escape-Psd1 $BotQQ)'
    AdminQQ      = '$(Escape-Psd1 $AdminQQ)'
    OneBotToken  = '$(Escape-Psd1 $OneBotToken)'
    DeepSeekKey  = '$(Escape-Psd1 $DeepSeekKey)'

    AstrBotHome  = '$(Escape-Psd1 $AstrBotHome)'
    SnowLumaHome = '$(Escape-Psd1 $SnowLumaHome)'
    QQExe        = '$(Escape-Psd1 $QQExe)'
    LogsDir      = 'logs'
    ToolsBin     = '$(Escape-Psd1 $toolsBin)'

    SnowLumaWebUIPassword = '$(Escape-Psd1 $snowlumaWebUIPassword)'

    EmbeddingEnabled  = `$$embeddingEnabled
    EmbeddingPython   = ''
    EmbeddingModelDir = 'models\bge-small-zh-v1.5'

    TtsEnabled   = `$$ttsEnabled
    TtsExe       = '$(Escape-Psd1 $ttsExe)'
    TtsModelDir  = '$(Escape-Psd1 $ttsModelDir)'
    TtsSharedDir = '$(Escape-Psd1 $ttsSharedDir)'
    TtsPort      = $ttsPort
}
"@
[System.IO.File]::WriteAllText($configPath, $psd1, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "[配置] 已写入 $configPath"

# ── 6. 生成启动入口（纯 ASCII，避免 .bat / .vbs 编码坑）──
$startAll = Join-Path $PSScriptRoot 'start-all.ps1'
$vbs = @"
' Auto-generated by install.ps1. Keep this file ASCII-only and without BOM.
Dim sh
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$startAll""", 0, False
"@
$ascii = New-Object System.Text.ASCIIEncoding
[System.IO.File]::WriteAllText((Join-Path $repo 'startup-hidden.vbs'), $vbs, $ascii)

$bat = "@echo off`r`npowershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $PSScriptRoot 'open-admin.ps1')`"`r`n"
[System.IO.File]::WriteAllText((Join-Path $repo '打开管理页.bat'), $bat, $ascii)
Write-Host '[入口] 已生成 startup-hidden.vbs 与 打开管理页.bat'

# ── 7. 本地向量模型运行环境（可选）───────────────────────
if (-not $SkipEmbedding) {
    $venvDir = Join-Path $repo '.venv-embedding'
    $venvPy = Join-Path $venvDir 'Scripts\python.exe'
    $needVenv = -not (Test-Path -LiteralPath $venvPy)
    $hasTorch = $false
    if (-not $needVenv) {
        & $venvPy -c "import torch, transformers" 2>$null
        $hasTorch = ($LASTEXITCODE -eq 0)
    }
    if ($needVenv -or -not $hasTorch) {
        if (Confirm-Step -Prompt '安装本地向量模型依赖（torch CPU + transformers，约 1~2 GB 下载）？' -Yes:$Yes) {
            & $uv venv $venvDir --python 3.12
            & $uv pip install --python $venvPy --index-url https://download.pytorch.org/whl/cpu torch
            if ($LASTEXITCODE -ne 0) { Write-Warning 'torch 安装失败；知识库向量检索将不可用。' }
            & $uv pip install --python $venvPy transformers
            if ($LASTEXITCODE -ne 0) { Write-Warning 'transformers 安装失败。' }
        } else {
            Write-Host '[向量模型] 已跳过。之后可重跑 install.ps1 或手动创建 .venv-embedding。'
        }
    } else {
        Write-Host '[向量模型] 运行环境已就绪。'
    }
}

# ── 8. 收尾提示 ───────────────────────────────────────────
Write-Host ''
Write-Host '=============================================='
Write-Host ' 初始化完成'
Write-Host '=============================================='
Write-Host " AstrBot 工作目录 : $astrbotRoot"
Write-Host " SnowLuma 目录    : $(Resolve-RepoPath $SnowLumaHome)"
Write-Host " 机器人 QQ        : $BotQQ"
Write-Host " 主人 QQ          : $AdminQQ"
Write-Host " SnowLuma 初始密码: $snowlumaWebUIPassword"
Write-Host ''

# 把 API Key 归属与费用提醒同时写进控制台和 logs\API-KEY-README.txt，
# 让每一个 clone 下来部署的人都能看到（仓库本身不包含任何 Key）。
$logsRoot = Join-Path $repo 'logs'
New-Item -ItemType Directory -Force -Path $logsRoot | Out-Null
$keyNotice = @"
【部署提醒】DeepSeek API Key 由「部署者本人」提供，本仓库不包含任何可用 Key
====================================================================
1. 仓库里只有占位符 sk-REPLACE_WITH_YOUR_DEEPSEEK_KEY，没有作者的 Key。
2. Key 属于你自己的 DeepSeek 账号，模型调用产生的费用记在你的账户。
3. install 时填写的 Key 只写入本机：
     deploy\config.psd1
     astrbot\data\cmd_config.json
   这两个文件都被 .gitignore 排除，不会进入 Git。
4. 没有 Key 时：机器人能启动、能收 QQ 消息，但不会回复对话；
   热搜、梗百科等命令类插件仍可正常使用。
5. 不要把 Key 发给别人、贴在 Issue/截图里，或用 git add -f 提交。
6. 获取 Key：https://platform.deepseek.com/api_keys
7. 改用其它模型：AstrBot 面板 → 服务商；或本地 Ollama 等 OpenAI 兼容端点。

生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
[System.IO.File]::WriteAllText((Join-Path $logsRoot 'API-KEY-README.txt'), $keyNotice, (New-Object System.Text.UTF8Encoding($true)))

Write-Host ' ── 关于 DeepSeek API Key ──' -ForegroundColor Cyan
Write-Host '  Key 由「部署者本人」提供，仓库不包含任何可用 Key。' -ForegroundColor Yellow
Write-Host '  调用费用记在 Key 所属的 DeepSeek 账户。' -ForegroundColor Yellow
Write-Host '  已写入本机 deploy\config.psd1 与 astrbot\data\cmd_config.json（均被 .gitignore 排除）。'
Write-Host "  详细说明已写入 logs\API-KEY-README.txt"
if (-not $DeepSeekKey) {
    Write-Host ''
    Write-Host '  [!] 本次没有填写 DeepSeek Key：' -ForegroundColor Red
    Write-Host '      机器人能启动、能收消息，但不会回复对话。' -ForegroundColor Red
    Write-Host '      启动后到 http://127.0.0.1:6185 → 服务商 → deepseek 填自己的 Key。' -ForegroundColor Red
}
Write-Host ''
Write-Host ' 下一步：'
Write-Host '   1. 若还没装 SnowLuma，按 docs\01-部署指南.md 第 3 节下载并解压；'
Write-Host '   2. 运行 deploy\start-all.ps1（或双击 打开管理页.bat）；'
Write-Host '   3. 首次启动后，在 logs\astrbot.out.log 里搜索 "Initial password" 获取面板密码；'
Write-Host '   4. 浏览器打开 http://127.0.0.1:6185 登录并改成自己的密码。'
Write-Host ''
