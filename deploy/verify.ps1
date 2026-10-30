#Requires -Version 5.1
<#
  部署自检：逐项检查依赖、配置一致性、端口与数据文件。
  用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\deploy\verify.ps1
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$repo = Get-RepoRoot
$fail = 0
$warn = 0

function Check-Ok([string]$Name, [string]$Detail = '') {
    Write-Host ("  [ OK ] {0,-28} {1}" -f $Name, $Detail) -ForegroundColor Green
}
function Check-Warn([string]$Name, [string]$Detail = '') {
    Write-Host ("  [WARN] {0,-28} {1}" -f $Name, $Detail) -ForegroundColor Yellow
    $script:warn++
}
function Check-Fail([string]$Name, [string]$Detail = '') {
    Write-Host ("  [FAIL] {0,-28} {1}" -f $Name, $Detail) -ForegroundColor Red
    $script:fail++
}

Write-Host ''
Write-Host 'AstrBot + SnowLuma 部署自检'
Write-Host '----------------------------------------------'

if (-not (Test-Path -LiteralPath (Get-BotConfigPath))) {
    Check-Fail 'deploy\config.psd1' '不存在，请先运行 install.ps1'
    exit 1
}
$config = Get-BotConfig
Check-Ok 'deploy\config.psd1' '已加载'

$astrbotRoot = Resolve-RepoPath $config.AstrBotHome
if (Test-Path -LiteralPath (Join-Path $astrbotRoot '.astrbot')) { Check-Ok 'AstrBot 工作目录' $astrbotRoot } else { Check-Fail 'AstrBot 工作目录' "缺少 $astrbotRoot\.astrbot" }

$exe = Find-AstrBotExe
if ($exe) { Check-Ok 'astrbot 命令' $exe } else { Check-Fail 'astrbot 命令' '未安装，运行 install.ps1' }

$cmdConfig = Join-Path $astrbotRoot 'data\cmd_config.json'
if (Test-Path -LiteralPath $cmdConfig) {
    Check-Ok 'cmd_config.json' $cmdConfig
    $raw = Get-Content -LiteralPath $cmdConfig -Raw -Encoding UTF8
    if ($raw -match 'sk-REPLACE_WITH_YOUR_DEEPSEEK_KEY' -or $raw -match 'YOUR_QQ_NUMBER') {
        Check-Warn '配置占位符' '仍含占位符，请重跑 install.ps1 或手动填写'
    }
    if ($config.OneBotToken -and $raw -notmatch [regex]::Escape($config.OneBotToken)) {
        Check-Fail 'OneBot 令牌' 'cmd_config.json 与 config.psd1 不一致'
    } else {
        Check-Ok 'OneBot 令牌' '两端一致'
    }

    # DeepSeek Key 必须由部署者本人提供，仓库不包含任何可用 Key
    $keyOk = $false
    try {
        $cfgObj = $raw | ConvertFrom-Json
        $ds = @($cfgObj.provider_sources) | Where-Object { $_.provider -eq 'deepseek' } | Select-Object -First 1
        if ($ds) {
            foreach ($k in @($ds.key)) {
                if ($k -and $k -notlike 'sk-REPLACE*') { $keyOk = $true }
            }
        }
    } catch {
        $keyOk = $false
    }
    if ($keyOk) {
        Check-Ok 'DeepSeek API Key' '已配置（仅本机，不会进 Git）'
    } else {
        Check-Warn 'DeepSeek API Key' '未配置：机器人不会回话；Key 需部署者本人提供（见 logs\API-KEY-README.txt）'
    }
} else {
    Check-Fail 'cmd_config.json' '不存在，安装未完成'
}

$snowlumaRoot = Get-SnowLumaHome -Config $config
if (Test-Path -LiteralPath (Join-Path $snowlumaRoot 'node.exe')) { Check-Ok 'SnowLuma' $snowlumaRoot } else { Check-Fail 'SnowLuma' "找不到 $snowlumaRoot\node.exe" }

$snowlumaOnebot = Join-Path $snowlumaRoot 'config\onebot.json'
if (Test-Path -LiteralPath $snowlumaOnebot) {
    $onebot = Get-Content -LiteralPath $snowlumaOnebot -Raw -Encoding UTF8
    if ($config.OneBotToken -and $onebot -notmatch [regex]::Escape($config.OneBotToken)) {
        Check-Fail 'SnowLuma 令牌' 'config\onebot.json 与 config.psd1 不一致'
    } else {
        Check-Ok 'SnowLuma 令牌' '两端一致'
    }
    $account = Join-Path $snowlumaRoot ("config\onebot_{0}.json" -f $config.BotQQ)
    if (Test-Path -LiteralPath $account) { Check-Ok '账号级 OneBot 配置' $account } else { Check-Warn '账号级 OneBot 配置' '未找到，首次登录后可在 WebUI 生成' }
} else {
    Check-Warn 'SnowLuma 配置' '尚未生成 config\onebot.json'
}

$plugins = Join-Path $astrbotRoot 'data\plugins'
$pluginCount = 0
if (Test-Path -LiteralPath $plugins) { $pluginCount = (Get-ChildItem $plugins -Directory).Count }
if ($pluginCount -ge 10) { Check-Ok '插件' "$pluginCount 个" } elseif ($pluginCount -gt 0) { Check-Warn '插件' "只有 $pluginCount 个" } else { Check-Fail '插件' 'data\plugins 为空' }

$memes = Join-Path $astrbotRoot 'data\plugin_data\meme_manager\packs'
if (Test-Path -LiteralPath $memes) { Check-Ok '表情包' ((Get-ChildItem $memes -Directory).Count.ToString() + ' 个资源包') } else { Check-Warn '表情包' '未铺开' }

$modelDir = Resolve-RepoPath $config.EmbeddingModelDir
if (Test-Path -LiteralPath (Join-Path $modelDir 'model.safetensors')) { Check-Ok '本地向量模型' $modelDir } else { Check-Warn '本地向量模型' '缺失，知识库语义检索不可用' }

if ($config.ContainsKey('TtsEnabled') -and $config.TtsEnabled) {
    $ttsModel = Resolve-RepoPath $config.TtsModelDir
    if (Test-Path -LiteralPath (Join-Path $ttsModel 'manifest.json')) { Check-Ok '本地语音模型' $ttsModel } else { Check-Fail '本地语音模型' '缺失（见 docs\05-模型与语音.md）' }
} else {
    Check-Warn '本地语音' '未启用（可选）'
}

Write-Host '----------------------------------------------'
Write-Host "端口状态：6185=$(Test-PortListening -Port 6185)  5099=$(Test-PortListening -Port 5099)  6199=$(Test-PortListening -Port 6199)  8010=$(Test-PortListening -Port 8010)"
Write-Host ''
if ($fail -gt 0) {
    Write-Host "自检结果：$fail 项失败，$warn 项警告。" -ForegroundColor Red
    exit 1
}
Write-Host "自检结果：通过（$warn 项警告）。" -ForegroundColor Green
exit 0
