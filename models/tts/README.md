# 语音模型目录（不随仓库分发）

这里应该放 **AnifLive-TTS 的模型包**，默认期望路径：

```text
models\tts\kurisu-v2proplus\
├─ manifest.json
├─ source.json
├─ checksums.json
├─ onnx\
├─ engines\        （TensorRT，必须在本机重建）
└─ voices\
```

完整模型约 **6.9 GiB**，GitHub 单文件上限 100 MB，所以仓库里只有一个占位。

`kurisu-v2proplus.metadata\` 里保存了模型包的三份元数据（**不含权重**）：

| 文件 | 作用 |
|---|---|
| `manifest.json` | 模型 id、语言、精度、引擎指纹 |
| `source.json` | 原始 GPT / SoVITS checkpoint 的 SHA256 |
| `checksums.json` | 模型包内每个文件的 SHA256，供 `-Verify` 使用 |

## 下载

夸克网盘（2.31 GiB，含 onnx + voices + shared）：

```text
链接：https://pan.quark.cn/s/32fa2c35348a?pwd=RF3D
提取码：RF3D
文件：kurisu-v2proplus-portable.7z
SHA256：ad6f963906a737bfb24b476244476a6407ac21a67298eb0bc6003556d03467e2
```

## 怎么装

```powershell
# 夸克下载后，指向本地 7z（会自动解压）
.\scripts\install-tts-model.ps1 -Source "D:\downloads\kurisu-v2proplus-portable.7z"

# 模型已经在本机别处（目录联接，不占额外空间）
.\scripts\install-tts-model.ps1 -Source "D:\models\kurisu-v2proplus"

# 有直链时
.\scripts\install-tts-model.ps1 -DownloadUrl "https://example.com/kurisu-v2proplus-portable.7z"

# 校验
.\scripts\install-tts-model.ps1 -Source "D:\models\kurisu-v2proplus" -Verify
```

然后在 `deploy\config.psd1` 里设：

```powershell
TtsEnabled = $true
TtsExe     = 'C:\AnifLive-TTS\.venv\Scripts\aniflive-tts.exe'
```

详见 [docs/05-模型与语音.md](../../docs/05-模型与语音.md)。

## 分享给别人时

不要带 `engines\`：TensorRT 引擎绑定 GPU 型号 / 显存 / CUDA / TensorRT / 平台指纹，换机器就用不了。
只分享 `onnx\` + `voices\` + 元数据 + 上一级的 `shared\`（约 3.0 GiB），对方解压后运行：

```powershell
aniflive-tts model rebuild-engines --model-package <模型目录>
```

重建需要 NVIDIA 显卡。压缩率参考：ONNX 用 zip 约 92.6%（只省 7%），便携包用 7z 实测 3.02 → 2.31 GiB（约 77%）。

本仓库提供打包脚本：

```powershell
.\scripts\build-tts-portable.ps1 -Source "D:\models\kurisu-v2proplus" -Compress
```

## 授权提醒

- AnifLive-TTS 本体是 **PolyForm Noncommercial 1.0.0**，不得商用。
- 模型音色涉及角色版权，公开分发前请自行确认授权。
- 本仓库不提供模型下载地址，也不对模型内容负责。
