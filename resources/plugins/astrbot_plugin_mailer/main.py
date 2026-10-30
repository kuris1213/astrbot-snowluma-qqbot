from __future__ import annotations

from pathlib import Path
from typing import Any

from astrbot.api import AstrBotConfig, FunctionTool, logger
from astrbot.api.event import AstrMessageEvent, filter
from astrbot.api.star import Context, Star, StarTools

from .mailer.message_builder import build_message
from .mailer.models import MailRequest
from .mailer.smtp_client import SMTPSettings, send_message


class MailerPlugin(Star):
    def __init__(self, context: Context, config: AstrBotConfig) -> None:
        super().__init__(context)
        self.context = context
        self.config = config
        self.data_dir = StarTools.get_data_dir("astrbot_plugin_mailer")
        self.attachments_dir = self.data_dir / "attachments"
        self.attachments_dir.mkdir(parents=True, exist_ok=True)

        if self._get_bool("tool", "enable_llm_tool", True):
            self.context.add_llm_tools(self._build_send_email_tool())

    def _group(self, name: str) -> dict[str, Any]:
        value = self.config.get(name, {})
        return value if isinstance(value, dict) else {}

    def _get_bool(self, group_name: str, key: str, default: bool) -> bool:
        group = self._group(group_name)
        value = group.get(key, default)
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"true", "1", "yes", "on"}:
                return True
            if normalized in {"false", "0", "no", "off", ""}:
                return False
        if isinstance(value, (int, float)) and value in {0, 1}:
            return bool(value)
        raise ValueError(f"{group_name}.{key} 必须是布尔值。")

    def _get_list_of_strings(
        self, group_name: str, key: str, default: list[str] | None = None
    ) -> list[str]:
        group = self._group(group_name)
        value = group.get(key, default or [])
        if value is None:
            return []
        if not isinstance(value, list):
            raise ValueError(f"{group_name}.{key} 必须是字符串列表。")
        normalized: list[str] = []
        for item in value:
            if not isinstance(item, str):
                raise ValueError(f"{group_name}.{key} 只能包含字符串。")
            text = item.strip()
            if text:
                normalized.append(text)
        return normalized

    def _get_sender_id_allowlist(self) -> list[str]:
        security_cfg = self._security_config()
        value = security_cfg.get("allowed_sender_ids", [])
        if value is None:
            return []
        if not isinstance(value, list):
            raise ValueError("security.allowed_sender_ids 必须是列表。")

        normalized: list[str] = []
        for item in value:
            if isinstance(item, (list, dict, set, tuple)):
                raise ValueError(
                    "security.allowed_sender_ids 只能包含可转换为字符串的标量值。"
                )
            text = str(item).strip()
            if text:
                normalized.append(text)
        return normalized

    def _smtp_config(self) -> dict[str, Any]:
        return self._group("smtp")

    def _tool_config(self) -> dict[str, Any]:
        return self._group("tool")

    def _security_config(self) -> dict[str, Any]:
        return self._group("security")

    def _build_send_email_tool(self) -> FunctionTool:
        return FunctionTool(
            name="send_email",
            description=(
                "在用户明确要求发送邮件时，通过受控 SMTP 通道发送邮件。"
                "优先使用 html_body 生成结构化富文本邮件；仅在用户明确要求纯文本或没有富文本内容时使用 text_body。"
                "如果包含图片，优先使用 html_body 配合 inline_images。必须具备清晰的收件人、主题和正文。"
            ),
            parameters={
                "type": "object",
                "properties": {
                    "to": {
                        "type": "array",
                        "description": "主收件人邮箱地址列表。",
                        "items": {"type": "string"},
                    },
                    "cc": {
                        "type": "array",
                        "description": "可选的抄送邮箱地址列表。",
                        "items": {"type": "string"},
                    },
                    "bcc": {
                        "type": "array",
                        "description": "可选的密送邮箱地址列表。",
                        "items": {"type": "string"},
                    },
                    "subject": {
                        "type": "string",
                        "description": "邮件主题。",
                    },
                    "text_body": {
                        "type": "string",
                        "description": "纯文本正文。text_body 和 html_body 至少提供一个；如果未明确要求纯文本，优先使用 html_body。",
                    },
                    "html_body": {
                        "type": "string",
                        "description": "可选的 HTML 正文。text_body 和 html_body 至少提供一个；需要富文本排版或内嵌图片时优先使用 html_body。",
                    },
                    "reply_to": {
                        "type": "string",
                        "description": "可选的回复地址。",
                    },
                    "attachments": {
                        "type": "array",
                        "description": "可选的本地附件列表。",
                        "items": {
                            "type": "object",
                            "properties": {
                                "path": {
                                    "type": "string",
                                    "description": "绝对路径，或相对于插件附件目录的路径。",
                                },
                                "filename": {
                                    "type": "string",
                                    "description": "可选的附件文件名覆盖值。",
                                },
                            },
                            "required": ["path"],
                        },
                    },
                    "inline_images": {
                        "type": "array",
                        "description": "可选的内嵌图片列表，通过 html_body 中的 cid: 引用。",
                        "items": {
                            "type": "object",
                            "properties": {
                                "path": {
                                    "type": "string",
                                    "description": "绝对路径，或相对于插件附件目录的路径。",
                                },
                                "cid": {
                                    "type": "string",
                                    "description": "在 html_body 中以 cid:xxx 形式引用的内容 ID。",
                                },
                                "filename": {
                                    "type": "string",
                                    "description": "可选的文件名覆盖值。",
                                },
                            },
                            "required": ["path", "cid"],
                        },
                    },
                },
                "required": ["to", "subject"],
            },
            handler=MailerPlugin._send_email_tool_handler,
        )

    async def _send_email_tool_handler(
        self,
        event: AstrMessageEvent,
        payload: dict[str, Any] | None = None,
        **payload_kwargs: Any,
    ) -> str:
        merged_payload: dict[str, Any] = {}
        if payload is not None:
            if not isinstance(payload, dict):
                raise ValueError("工具参数必须是对象。")
            merged_payload.update(payload)
        merged_payload.update(payload_kwargs)
        return await self.send_email_tool(event, **merged_payload)

    def _smtp_settings(self) -> SMTPSettings:
        smtp_cfg = self._smtp_config()
        host = str(smtp_cfg.get("host", "")).strip()
        username = str(smtp_cfg.get("username", "")).strip()
        password = str(smtp_cfg.get("password", "")).strip()
        from_email = str(smtp_cfg.get("from_email", "")).strip()
        use_tls = self._get_bool("smtp", "use_tls", True)
        use_starttls = self._get_bool("smtp", "use_starttls", False)
        timeout_seconds = float(smtp_cfg.get("timeout_seconds", 30))
        port = int(smtp_cfg.get("port", 465))

        missing = [
            name
            for name, value in {
                "smtp.host": host,
                "smtp.from_email": from_email,
            }.items()
            if not value
        ]
        if missing:
            raise ValueError(f"缺少必要 SMTP 配置项: {', '.join(missing)}")
        if use_tls and use_starttls:
            raise ValueError("smtp.use_tls 和 smtp.use_starttls 不能同时开启。")
        if not 1 <= port <= 65535:
            raise ValueError("smtp.port 必须在 1 到 65535 之间。")
        if timeout_seconds <= 0:
            raise ValueError("smtp.timeout_seconds 必须大于 0。")

        return SMTPSettings(
            host=host,
            port=port,
            username=username,
            password=password,
            use_tls=use_tls,
            use_starttls=use_starttls,
            timeout_seconds=timeout_seconds,
        )

    def _check_sender_allowed(self, event: AstrMessageEvent) -> None:
        allowed_sender_ids = self._get_sender_id_allowlist()
        if allowed_sender_ids and str(event.get_sender_id()) not in allowed_sender_ids:
            raise PermissionError("当前发送者没有权限使用邮件发送功能。")

    def _recipient_domain(self, address: str) -> str:
        return address.rsplit("@", 1)[-1].lower()

    def _check_recipient_policy(self, request: MailRequest) -> None:
        allowed_domains = {
            item.lower()
            for item in self._get_list_of_strings("security", "allowed_domains", [])
        }
        blocked_domains = {
            item.lower()
            for item in self._get_list_of_strings("security", "blocked_domains", [])
        }

        for recipient in request.all_recipients:
            domain = self._recipient_domain(recipient)
            if domain in blocked_domains:
                raise ValueError(f"收件人域名在黑名单中: {domain}")
            if allowed_domains and domain not in allowed_domains:
                raise ValueError(f"收件人域名不在白名单中: {domain}")

    def _allowed_roots(self) -> list[Path]:
        roots = [self.attachments_dir.resolve()]
        for entry in self._get_list_of_strings(
            "security", "allowed_attachment_roots", []
        ):
            roots.append(Path(entry).expanduser().resolve())
        deduped: list[Path] = []
        for root in roots:
            if root not in deduped:
                deduped.append(root)
        return deduped

    def _resolve_safe_path(self, raw_path: Path) -> Path:
        path = raw_path
        if not path.is_absolute():
            path = self.attachments_dir / path
        resolved = path.resolve()
        if not resolved.is_file():
            raise ValueError(f"文件不存在: {resolved}")

        if self._get_bool("security", "allow_unsafe_all_attachment_paths", False):
            return resolved

        for root in self._allowed_roots():
            try:
                resolved.relative_to(root)
                return resolved
            except ValueError:
                continue
        raise ValueError(f"文件不在允许的附件目录内: {resolved}")

    def _check_file_limits(self, request: MailRequest) -> None:
        security_cfg = self._security_config()
        max_attachment_size = (
            int(security_cfg.get("max_attachment_size_mb", 10)) * 1024 * 1024
        )
        max_total_size = (
            int(security_cfg.get("max_total_attachment_size_mb", 25)) * 1024 * 1024
        )
        if max_attachment_size <= 0:
            raise ValueError("security.max_attachment_size_mb 必须大于 0。")
        if max_total_size <= 0:
            raise ValueError("security.max_total_attachment_size_mb 必须大于 0。")
        if max_total_size < max_attachment_size:
            raise ValueError(
                "security.max_total_attachment_size_mb 不能小于 max_attachment_size_mb。"
            )

        total_size = 0
        for file_ref in [*request.attachments, *request.inline_images]:
            safe_path = self._resolve_safe_path(file_ref.path)
            file_ref.path = safe_path
            file_size = safe_path.stat().st_size
            if file_size > max_attachment_size:
                raise ValueError(
                    f"文件超过单文件大小限制: {safe_path.name} ({file_size} bytes)"
                )
            total_size += file_size

        if total_size > max_total_size:
            raise ValueError(f"附件和内嵌图片总大小超过限制 ({total_size} bytes)")

    def _check_content_limits(self, request: MailRequest) -> None:
        security_cfg = self._security_config()
        if len(request.html_body) > int(security_cfg.get("max_html_length", 200000)):
            raise ValueError("html_body 超过最大长度限制。")
        if request.inline_images and not request.html_body:
            raise ValueError("使用 inline_images 时必须提供 html_body。")

    async def _send_mail(self, request: MailRequest) -> str:
        settings = self._smtp_settings()
        smtp_cfg = self._smtp_config()
        from_email = str(smtp_cfg.get("from_email", "")).strip()
        from_name = str(smtp_cfg.get("from_name", "AstrBot Mailer")).strip()
        subject_prefix = str(smtp_cfg.get("subject_prefix", ""))
        default_reply_to = str(smtp_cfg.get("default_reply_to", "")).strip()

        message = build_message(
            request=request,
            from_email=from_email,
            from_name=from_name,
            subject_prefix=subject_prefix,
            default_reply_to=default_reply_to,
        )

        status_code, status_message = await send_message(
            settings=settings,
            message=message,
            sender=from_email,
            recipients=request.all_recipients,
        )

        status_segment = f" SMTP 状态: {status_code}"
        if status_message:
            status_segment += f" {status_message}"

        return (
            "邮件发送成功。"
            f"{status_segment}。"
            f" 收件人: {', '.join(request.to)}。"
            f" 主题: {message['Subject']}"
        )

    async def send_email_tool(self, event: AstrMessageEvent, **payload: Any) -> str:
        logger.info("mailer tool invoked by %s", event.get_sender_id())
        self._check_sender_allowed(event)
        if self._get_bool("tool", "require_tool_confirmation", False):
            raise PermissionError(
                "当前已开启工具确认，不能直接发送邮件，请改为人工确认后再发送。"
            )

        request = MailRequest.from_payload(payload)
        self._check_recipient_policy(request)
        self._check_content_limits(request)
        self._check_file_limits(request)
        return await self._send_mail(request)

    @filter.permission_type(filter.PermissionType.ADMIN)
    @filter.command("mail_test")
    async def mail_test(self, event: AstrMessageEvent, recipient: str = ""):
        """发送一封简单测试邮件，用于验证 SMTP 配置。

        用法: /mail_test recipient@example.com
        """
        try:
            self._check_sender_allowed(event)
            if not recipient.strip():
                yield event.plain_result("用法: /mail_test recipient@example.com")
                return

            request = MailRequest.from_payload(
                {
                    "to": [recipient],
                    "subject": "AstrBot 邮件插件测试",
                    "text_body": "这是一封由 astrbot_plugin_mailer 发送的测试邮件。",
                }
            )
            self._check_recipient_policy(request)
            self._check_content_limits(request)
            self._check_file_limits(request)
            result = await self._send_mail(request)
            yield event.plain_result(result)
        except Exception as exc:
            logger.exception("mail_test failed")
            yield event.plain_result(f"mail_test 失败: {exc}")

    @filter.permission_type(filter.PermissionType.ADMIN)
    @filter.command("mail_config_check")
    async def mail_config_check(self, event: AstrMessageEvent):
        """检查当前插件 SMTP 配置。"""
        try:
            self._check_sender_allowed(event)
            settings = self._smtp_settings()
            from_email = str(self._smtp_config().get("from_email", "")).strip()
            allowed_root_count = len(self._allowed_roots())
            yield event.plain_result(
                "邮件插件配置校验通过。"
                f" SMTP: {settings.host}:{settings.port}，发件人: {from_email}，允许目录数量: {allowed_root_count}，"
                f" 任意路径开关: {'开启' if self._get_bool('security', 'allow_unsafe_all_attachment_paths', False) else '关闭'}"
            )
        except Exception as exc:
            yield event.plain_result(f"邮件插件配置无效: {exc}")
