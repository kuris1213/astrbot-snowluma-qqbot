# 本地 Embedding 服务（AstrBot 知识库用）

AstrBot 4.x 的知识库必须绑定一个 embedding provider。这里用一个小模型在本机起一个
**OpenAI 兼容** 的 embedding 接口，把「本地服务」当成普通 OpenAI Embedding 源来用。

## 组成

| 项目 | 值 |
|---|---|
| 模型 | `BAAI/bge-small-zh-v1.5`（中文小模型，512 维，CPU 推理） |
| 模型目录 | 仓库下 `models\bge-small-zh-v1.5`（可用 `config.psd1` 的 `EmbeddingModelDir` 改） |
| 服务脚本 | `deploy\tools\embedding_server.py` |
| 接口 | `http://127.0.0.1:8010/v1`（`POST /v1/embeddings`、`GET /health`、`GET /v1/models`） |
| 运行环境 | 仓库下 `.venv-embedding`（`install.ps1` 创建，torch CPU + transformers） |
| 日志 | `logs\embedding.out.log` / `embedding.err.log` |

## 启动 / 停止

```powershell
# 单独启动
.\deploy\start-embedding.ps1

# 一键启动（会依次拉起 embedding → SnowLuma → AstrBot → QQ）
.\deploy\start-all.ps1

# 停止
.\deploy\stop-all.ps1
```

启动脚本会等模型加载完、8010 端口开始监听后才返回；首次启动约 3~10 秒（CPU）。

## AstrBot 里的对应配置

`astrbot\data\cmd_config.json` 中注册为：

- source：`local_bge`，类型 `openai_embedding`
  - `embedding_api_base` = `http://127.0.0.1:8010/v1`
  - `embedding_api_key` = `sk-local`（本地服务不校验，占位用）
  - `embedding_model` = `bge-small-zh-v1.5`
  - `embedding_dimensions` = `512`
- provider id：`local_bge/bge-small-zh-v1.5`

## 注意

- **AstrBot 必须先能连上 8010**：服务没启动时，知识库上传与检索都会报错，聊天时知识库注入会静默失败（不影响正常聊天）。
- 端口固定 8010；要换端口需同时改 `start-embedding.ps1` 和 AstrBot 的 provider 配置。
- CPU 推理，单条文本约 5~20 ms；建库时几百个分块约 1 分钟。
- 换模型要同时改 `EMBEDDING_MODEL_DIR`、`embedding_model` 和维度。
- 只监听 `127.0.0.1`，不对外暴露。

## 接口自测

```powershell
Invoke-RestMethod http://127.0.0.1:8010/health
Invoke-RestMethod http://127.0.0.1:8010/v1/embeddings -Method Post `
  -ContentType 'application/json' `
  -Body '{"input":["命运石之门的世界线"],"model":"bge-small-zh-v1.5"}'
```

`/health` 返回 `{"status":"ok","model":"bge-small-zh-v1.5","ready":true}` 即正常；
embedding 数组长度应为 512。
