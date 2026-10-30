#Requires -Version 5.1
<#
  启动本地向量服务（AstrBot 知识库用，OpenAI 兼容 /v1/embeddings）。
  - 模型：BAAI/bge-small-zh-v1.5（512 维），默认在 models\bge-small-zh-v1.5
  - 运行环境：.venv-embedding（install.ps1 创建）或 config.psd1 里指定的 Python
  - 8010 已在监听时直接跳过。
#>
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\common.ps1')

$config = Get-BotConfig
$logs = Get-LogsDir -Config $config
$repo = Get-RepoRoot

if (Test-PortListening -Port 8010) {
    Write-Host '[Embedding] 已在运行（8010 正在监听），跳过启动。'
    exit 0
}

$python = ''
if ($config.ContainsKey('EmbeddingPython') -and $config.EmbeddingPython) {
    $python = Resolve-RepoPath $config.EmbeddingPython
} else {
    $python = Join-Path $repo '.venv-embedding\Scripts\python.exe'
}
$server = Join-Path $PSScriptRoot 'tools\embedding_server.py'
$modelDir = Resolve-RepoPath $config.EmbeddingModelDir

if (-not (Test-Path -LiteralPath $python)) {
    throw "找不到向量服务 Python：$python`n请重跑 install.ps1（不要加 -SkipEmbedding），或修改 config.psd1 的 EmbeddingPython。"
}
if (-not (Test-Path -LiteralPath $modelDir)) {
    throw "找不到向量模型目录：$modelDir`n请确认 models\bge-small-zh-v1.5 存在。"
}

Enable-Utf8Environment
$env:EMBEDDING_MODEL_DIR = $modelDir
$env:EMBEDDING_MODEL_NAME = 'bge-small-zh-v1.5'

$p = Start-Process -FilePath $python `
    -ArgumentList @($server, '--host', '127.0.0.1', '--port', '8010', '--preload') `
    -WorkingDirectory (Split-Path $server) `
    -RedirectStandardOutput (Join-Path $logs 'embedding.out.log') `
    -RedirectStandardError (Join-Path $logs 'embedding.err.log') `
    -WindowStyle Hidden -PassThru

$p.Id | Set-Content -LiteralPath (Join-Path $logs 'embedding.pid')

for ($i = 0; $i -lt 120; $i++) {
    Start-Sleep -Seconds 1
    if (Test-PortListening -Port 8010) {
        Write-Host "[Embedding] 已启动，PID=$($p.Id)  → http://127.0.0.1:8010/v1"
        exit 0
    }
    if ($p.HasExited) { break }
}

Write-Warning "[Embedding] 启动超时或进程退出，请查看 $(Join-Path $logs 'embedding.err.log')"
exit 1
