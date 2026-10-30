# QQ 机器人部署配置（由 deploy\install.ps1 生成）
#
# 这是「本机部署参数」，不是 AstrBot 的业务配置。
# 真正的业务配置在 templates\ 目录里，安装时渲染成 astrbot\data\cmd_config.json
# 与 snowluma 的 config\*.json。
#
# 本文件已被 .gitignore 忽略：它可能包含你的 API Key / 令牌，不要提交到 GitHub。

@{
    # ── 账号 ────────────────────────────────────────────────
    BotQQ        = ''                 # 机器人 QQ 号（建议用小号）
    AdminQQ      = ''                 # 主人 QQ 号，用于 /bili主动 等管理员命令
    OneBotToken  = ''                 # SnowLuma 与 AstrBot 之间的共享令牌，随机 32 位十六进制
    DeepSeekKey  = ''                 # DeepSeek API Key，形如 sk-xxxxxxxx

    # ── 路径（相对路径以仓库根目录为基准）───────────────────
    AstrBotHome  = 'astrbot'          # AstrBot 工作目录（里面会有 .astrbot 与 data\）
    SnowLumaHome = 'C:\SnowLuma'      # SnowLuma 解压目录（官方发行包）
    QQExe        = ''                 # QQ.exe 的完整路径，留空则自动探测
    LogsDir      = 'logs'
    ToolsBin     = ''                 # 可选：ffmpeg / yt-dlp 等外部命令所在目录

    # ── SnowLuma WebUI ─────────────────────────────────────
    # 仅当 SnowLuma 的 config\webui.json 不存在时作为初始密码；登录后请自行修改。
    SnowLumaWebUIPassword = ''

    # ── 本地向量模型（知识库用，可选）───────────────────────
    EmbeddingEnabled  = $true
    EmbeddingPython   = ''            # 留空 = 使用 .venv-embedding\Scripts\python.exe
    EmbeddingModelDir = 'models\bge-small-zh-v1.5'

    # ── 本地日语语音（可选，需自行安装 AnifLive-TTS）─────────
    TtsEnabled   = $false
    TtsExe       = ''                 # 例如 C:\AnifLive-TTS\.venv\Scripts\aniflive-tts.exe
    TtsModelDir  = 'models\tts\kurisu-v2proplus'
    TtsSharedDir = ''                 # AnifLive 的 shared 目录，留空 = 模型目录的上一级\shared
    TtsPort      = 9882
}
