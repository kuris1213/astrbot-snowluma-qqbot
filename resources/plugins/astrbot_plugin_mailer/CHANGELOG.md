# Changelog

本项目遵循语义化版本管理。

## 0.1.1 - 2026-04-06

首个稳定修复版本，聚焦运行时兼容性、配置健壮性、安全边界和测试隔离问题，适合作为插件市场发布版本。

### Changed

- 优化 `send_email` 工具描述，进一步引导 LLM 优先生成 HTML 富文本邮件
- 补充 `allowed_sender_ids` 的配置说明，明确应填写平台用户 ID，而不是 UMO
- 增加 `smtp.timeout_seconds` 配置项，用于控制 SMTP 网络调用超时
- 进一步规范 WebUI 配置文案与危险选项提示
- 更新 README 与发布说明，使文档与当前实现保持一致

### Fixed

- 修复 `FunctionTool.handler` 在 AstrBot 运行时下的绑定方式，解决 LLM 调用时的参数错位问题
- 修复 `send_email` 工具参数 schema 在部分 OpenAI 兼容提供方下因顶层 `anyOf` 不受支持而导致的 400 请求错误
- 修复 LLM 工具路径与管理命令路径在内容限制校验上的不一致问题
- 修复 SMTP 发送结果格式化异常，避免返回冗余的 `{}` 等无意义状态文本
- 修复 `mail_config_check` 泄露完整本地绝对路径的问题，改为最小化信息输出
- 修复 `send_email` 工具 schema 与运行时约束不一致的问题，为正文增加 `anyOf` 契约说明
- 修复 SMTP 缺少超时控制的问题，避免网络异常时长时间挂起
- 修复 SMTP 端口缺少范围校验的问题
- 修复 `smtp.use_tls` 与 `smtp.use_starttls` 可能被错误同时开启的问题
- 修复布尔配置使用 `bool(...)` 强转导致的隐性逻辑错误，改为显式强类型解析
- 修复多个安全列表配置在误填字符串时会被逐字符解析的问题
- 修复附件大小限制配置缺少合法区间校验的问题
- 修复 `allowed_sender_ids` 在数字型用户 ID 场景下的兼容性回归
- 修复测试中 `asyncio.run(...)` 可能与现有事件循环冲突的问题
- 修复测试环境中 `sys.modules` 与 `sys.path` 的隔离不足问题
- 修复 `_resolve_safe_path()` 中的无效局部变量

### Security

- 增加强危险配置 `security.allow_unsafe_all_attachment_paths` 的醒目风险提示
- 收紧邮箱格式校验，同时保持对内网 SMTP 场景下单标签域名的兼容
- 收紧邮箱域名标签规则，拒绝明显非法的连字符域名写法
- 改进 HTML 转纯文本回退逻辑，过滤 `script/style` 内容并处理 HTML 实体

### Test

- 扩充测试覆盖到运行时 handler 绑定、SMTP 状态格式化、配置布尔解析、列表配置校验、大小限制边界、发送者白名单兼容性与 HTML 回退逻辑
- 当前版本测试状态：`23 passed`

## 0.1.0 - 2026-04-06

首个可用版本，提供 AstrBot SMTP 邮件发送插件的完整基础能力。

### Added

- 新增 AstrBot 插件入口与标准插件结构
- 新增 `send_email` LLM 工具，可由模型发起邮件发送
- 新增 SMTP 发信能力，支持隐式 TLS 与 STARTTLS
- 新增纯文本邮件发送能力
- 新增 HTML 富文本邮件发送能力
- 新增基于 `cid:` 的内嵌图片发送能力
- 新增本地文件附件发送能力
- 新增 `/mail_test` 管理命令，用于测试 SMTP 发信链路
- 新增 `/mail_config_check` 管理命令，用于检查当前配置
- 新增 WebUI 配置 schema，并按 `smtp`、`tool`、`security` 分组展示
- 新增收件人域名白名单与黑名单限制
- 新增调用者 ID 白名单限制
- 新增附件目录沙箱限制
- 新增单文件大小与总附件大小限制
- 新增 HTML 正文长度限制
- 新增可选高风险开关 `security.allow_unsafe_all_attachment_paths`
- 新增中文 README 文档
- 新增单元测试，覆盖请求解析、MIME 构造、路径安全、工具调用适配和 SMTP 返回格式化

### Changed

- 优化 `send_email` 工具描述，引导 LLM 优先生成富文本邮件而不是纯文本邮件
- 规范化 WebUI 配置项文案，将主标题放入 `description`，说明文字放入 `hint`
- 将 `/mail_test` 与 `/mail_config_check` 调整为默认仅管理员可用
- 优化邮件发送成功后的返回结果格式，避免出现冗余 SMTP 响应对象字符串

### Fixed

- 修复 `FunctionTool.handler` 在 AstrBot 运行时下的绑定兼容问题
- 修复 LLM 调用工具时因 handler 参数错位导致的发送失败问题
- 修复空收件人未被尽早拦截的问题
- 修复 `smtp.use_tls` 与 `smtp.use_starttls` 可同时开启的问题
- 修复测试命令与工具路径在内容限制校验上的行为不一致问题

### Security

- 默认禁止读取任意本地附件路径
- 默认仅允许插件附件目录和显式配置的允许目录中的文件作为附件或内嵌图片
- 文档中补充了危险配置项的风险提示与生产环境使用建议

### Test

- 当前版本测试状态：`17 passed`
