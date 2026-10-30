#Requires -Version 5.1
<#
  公共函数：路径解析、配置读取、端口探测、模板渲染。
  所有脚本都通过 dot-source 引用本文件，不直接硬编码任何绝对路径。
#>

$script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Get-RepoRoot {
    return $script:RepoRoot
}

function Get-BotConfigPath {
    return (Join-Path $script:RepoRoot 'deploy\config.psd1')
}

function Get-BotConfig {
    $path = Get-BotConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "找不到配置 $path。请先运行 deploy\install.ps1 完成初始化。"
    }
    return Import-PowerShellDataFile -Path $path
}

function Resolve-RepoPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $script:RepoRoot $Path))
}

function Get-AstrBotHome {
    param([hashtable]$Config)
    if (-not $Config) { $Config = Get-BotConfig }
    $home_ = Resolve-RepoPath $Config.AstrBotHome
    if (-not (Test-Path -LiteralPath $home_)) { throw "AstrBot 工作目录不存在：$home_，请先运行 install.ps1" }
    return $home_
}

function Get-SnowLumaHome {
    param([hashtable]$Config)
    if (-not $Config) { $Config = Get-BotConfig }
    return (Resolve-RepoPath $Config.SnowLumaHome)
}

function Get-LogsDir {
    param([hashtable]$Config)
    if (-not $Config) { $Config = Get-BotConfig }
    $dir = Resolve-RepoPath $Config.LogsDir
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    return $dir
}

function Test-PortListening {
    param([int]$Port)
    return [bool](Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
}

function Wait-Port {
    param([int]$Port, [int]$TimeoutSeconds = 90)
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        if (Test-PortListening -Port $Port) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Find-AstrBotExe {
    $cmd = Get-Command 'astrbot' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = Join-Path $env:USERPROFILE '.local\bin\astrbot.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

function Find-UvExe {
    $cmd = Get-Command 'uv' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidate = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return $null
}

function Find-AstrBotPython {
    $uv = Find-UvExe
    if (-not $uv) { return $null }
    $toolsDir = (& $uv tool dir 2>$null | Select-Object -First 1)
    if (-not $toolsDir) { return $null }
    $py = Join-Path $toolsDir 'astrbot\Scripts\python.exe'
    if (Test-Path -LiteralPath $py) { return $py }
    return $null
}

function Enable-Utf8Environment {
    $env:PYTHONIOENCODING = 'utf-8'
    $env:PYTHONUTF8 = '1'
}

function Test-AdminPrivilege {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DefaultQQExe {
    $candidates = @(
        'C:\Program Files\Tencent\QQNT\QQ.exe',
        'C:\Program Files (x86)\Tencent\QQNT\QQ.exe',
        (Join-Path $env:LOCALAPPDATA 'Programs\Tencent\QQNT\QQ.exe'),
        (Join-Path ${env:ProgramFiles} 'Tencent\QQNT\QQ.exe')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return ''
}

function New-RandomToken {
    $bytes = New-Object byte[] 16
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $rng.Dispose()
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Read-HostDefault {
    param([string]$Prompt, [string]$Default = '')
    if ($Default) {
        $value = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        return $value.Trim()
    }
    return (Read-Host $Prompt).Trim()
}

function Confirm-Step {
    param([string]$Prompt, [switch]$Yes)
    if ($Yes) { return $true }
    $answer = Read-Host "$Prompt [Y/n]"
    return ($answer -eq '' -or $answer -match '^(y|yes|是)$')
}
