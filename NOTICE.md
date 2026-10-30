# NOTICE

本仓库是一套「QQ 机器人部署模板」，不是从零写的机器人框架。仓库里同时存在：

1. **作者原创**：`deploy/`、`scripts/`、`docs/`、`README.md`、`templates/`（脱敏后的配置结构）——MIT，见 `LICENSE`。
2. **第三方开源插件**：`resources/plugins/` 下 10 个插件，来自 AstrBot 插件生态，各自保留 `LICENSE` / `metadata.yaml`。它们不是本仓库作者的作品，授权以各自目录内的许可证为准。
3. **模型与素材**：
   - `models/bge-small-zh-v1.5`：BAAI 出品，MIT；原仓库 <https://huggingface.co/BAAI/bge-small-zh-v1.5>。
   - `resources/meme-packs/`：动漫/网络表情包图片，版权归原权利人；仅用于个人自托管，**不要商用、不要二次售卖**。
   - `personas/`、`assets/astrbot-persona-prompts/`：角色人格提示词与素材。角色及作品版权归原作者/权利方（例如《命运石之门》相关权利方），本项目与它们没有关联。
4. **未随仓库分发、需要你自行安装的第三方软件**：
   - **SnowLuma**：源码可见、非商业授权（SnowLuma Source-Available Non-Commercial License + EULA）。官方发行包内含专有组件，**不得再分发**。本仓库只提供配置模板和下载指引，不含其二进制。
   - **AnifLive-TTS**：PolyForm Noncommercial 1.0.0。本仓库不包含其代码与 7 GB 语音模型；语音模型涉及角色音色，请自行确认授权与使用范围。
   - **AstrBot**：AGPL-3.0，由 `uv tool install astrbot==4.29.3` 从 PyPI 安装，本仓库不含其源码。

## 合规提醒

- 用非官方协议端（SnowLuma）接入 QQ 可能违反腾讯的服务条款，存在封号风险；请只用自己的账号、自担风险。
- B 站自动评论/私信等功能受平台规则约束；仓库里的示例配置默认把高频动作关到较低水平，请遵守平台规则。
- 如果你要公开 fork，请先删掉 `resources/meme-packs/`、`personas/`、`models/` 中你不确定授权的部分。

## 隐私

仓库内所有配置均为占位符，不含任何真实 QQ 号、API Key、Cookie、密码或聊天记录。
如果你把自己的 `deploy/config.psd1`、`astrbot/data/` 提交上去，请先确认 `.gitignore` 生效。
