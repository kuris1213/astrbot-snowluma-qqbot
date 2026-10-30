# 第三方组件清单

本仓库 `resources/plugins/` 下是 10 个 AstrBot 插件，**未做代码修改**（除下表注明外），
保留各自目录内的 `LICENSE`、`README.md`、`metadata.yaml`。升级插件时直接用官方版本覆盖即可。

| 目录 | 显示名 | 版本 | 作者 | 上游 | 许可证 |
|---|---|---|---|---|---|
| `astrbot_plugin_meme_manager` | 表情包管理器 | 5.2.5 | anka | <https://github.com/anka-afk/astrbot_plugin_meme_manager> | MIT |
| `astrbot_plugin_proactive_chat` | 主动消息 | 1.2.6 | DBJD-CR | <https://github.com/Pancakes-Labs/astrbot_plugin_proactive_chat> | AGPL-3.0 |
| `astrbot_plugin_bilibili_ai_bot` | B站 AI Bot | 1.7.2 | chenluQwQ | <https://github.com/chenluQwQ/astrbot_plugin_bilibili_ai_bot> | MIT |
| `astrbot_plugin_ja_voice` | 中文文字 + 日语语音 | 1.0.0 | 本项目 | —（本仓库原创） | MIT |
| `astrbot_plugin_qzone_ultra` | QQ 空间 Ultra | 0.9.0 | 雪风 bir | <https://github.com/diaomin66/astrbot_plugin_qzone_ultra> | MIT |
| `astrbot_plugin_memewiki` | 梗百科 | 1.6.0 | local / cnmeme.wiki | <https://cnmeme.wiki> | MIT |
| `astrbot_plugin_suanle_bushuo` | 算了不说 | 0.1.4 | 木又知 | <https://github.com/muyouzhi6/astrbot_plugin_suanle_bushuo> | 未声明 |
| `astrbot_plugin_hotsearch` | 全网热搜 | 1.0.7 | 柠柚 | <https://github.com/ningyou8023/astrbot_plugin_hotsearch> | AGPL-3.0 |
| `astrbot_plugin_mailer` | 学会发邮件 | 0.1.1 | Fold | <https://github.com/FFFold/astrbot_plugin_mailer> | 未声明 |
| `astrbot_plugin_zhen_deepseek_web` | 真·DeepSeek 联网搜索 | 1.2.0 | dusi-lai | <https://github.com/dusi-lai/astrbot_plugin_zhen_deepseek_web> | MIT |

## 需要注意的改动

| 插件 | 改动 |
|---|---|
| `astrbot_plugin_proactive_chat` | 上游版本无改动；旧部署里曾把 `core/task_scheduler.py` 的 `misfire_grace_time` 调大（防睡眠错过任务），本仓库**没有**带这个补丁。需要的话见 `docs/06-排障手册.md`。 |
| `astrbot_plugin_bilibili_ai_bot` | 旧部署里曾把字幕接口改为优先 `x/player/wbi/v2`；本仓库为上游原版，升级/重装不会丢补丁问题。 |
| `astrbot_plugin_ja_voice` | 本项目自带的小插件，只做「文字照发 + 调本地 TTS」。源码在插件目录内，MIT。 |

## 运行时下载的组件（不随仓库分发）

| 组件 | 版本 | 授权 | 获取方式 |
|---|---|---|---|
| AstrBot | 4.29.3 | AGPL-3.0 | `uv tool install astrbot==4.29.3 --python 3.12` |
| SnowLuma | 2.2.x（win32-x64） | 源码可见·非商业 + EULA，含专有组件 | 官方发行渠道，见 `docs/01-部署指南.md` |
| AnifLive-TTS | 1.5.x | PolyForm Noncommercial 1.0.0 | 自行构建/安装，见 `docs/05-模型与语音.md` |
| QQ NT | 9.9.x | 腾讯官方 | 官网下载 |
| uv | 0.5+ | MIT/Apache-2.0 | <https://docs.astral.sh/uv/> |
