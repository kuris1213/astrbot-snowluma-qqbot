from __future__ import annotations

from dataclasses import dataclass, field
from email.utils import parseaddr
from pathlib import Path
import re
from typing import Any


EMAIL_RE = re.compile(
    r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?))*$"
)


def _parse_email(address: str, field_name: str) -> str:
    _, parsed = parseaddr(address)
    if not parsed or not EMAIL_RE.fullmatch(parsed):
        raise ValueError(f"Invalid email address in {field_name}: {address}")
    return parsed


def _normalize_email_list(value: Any, field_name: str) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        values = [value]
    elif isinstance(value, list):
        values = value
    else:
        raise ValueError(f"{field_name} must be a string or list of strings.")

    normalized: list[str] = []
    for item in values:
        if not isinstance(item, str):
            raise ValueError(f"{field_name} must contain only strings.")
        address = item.strip()
        if not address:
            continue
        normalized.append(_parse_email(address, field_name))
    return normalized


@dataclass(slots=True)
class FileReference:
    path: Path
    filename: str | None = None

    @classmethod
    def from_payload(cls, payload: dict[str, Any], field_name: str) -> "FileReference":
        if not isinstance(payload, dict):
            raise ValueError(f"Each item in {field_name} must be an object.")
        raw_path = payload.get("path")
        if not isinstance(raw_path, str) or not raw_path.strip():
            raise ValueError(
                f"Each item in {field_name} must include a non-empty path."
            )
        filename = payload.get("filename")
        if filename is not None and not isinstance(filename, str):
            raise ValueError(f"filename in {field_name} must be a string.")
        return cls(path=Path(raw_path).expanduser(), filename=filename)


@dataclass(slots=True)
class InlineImageReference(FileReference):
    cid: str = ""

    @classmethod
    def from_payload(
        cls, payload: dict[str, Any], field_name: str
    ) -> "InlineImageReference":
        file_ref = FileReference.from_payload(payload, field_name)
        cid = payload.get("cid")
        if not isinstance(cid, str) or not cid.strip():
            raise ValueError(f"Each item in {field_name} must include a non-empty cid.")
        return cls(path=file_ref.path, filename=file_ref.filename, cid=cid.strip())


@dataclass(slots=True)
class MailRequest:
    to: list[str]
    subject: str
    cc: list[str] = field(default_factory=list)
    bcc: list[str] = field(default_factory=list)
    text_body: str = ""
    html_body: str = ""
    reply_to: str = ""
    attachments: list[FileReference] = field(default_factory=list)
    inline_images: list[InlineImageReference] = field(default_factory=list)

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "MailRequest":
        if not isinstance(payload, dict):
            raise ValueError("send_email payload must be an object.")

        subject = payload.get("subject")
        if not isinstance(subject, str) or not subject.strip():
            raise ValueError("subject is required.")

        text_body = payload.get("text_body") or ""
        html_body = payload.get("html_body") or ""
        if not isinstance(text_body, str) or not isinstance(html_body, str):
            raise ValueError("text_body and html_body must be strings.")
        if not text_body.strip() and not html_body.strip():
            raise ValueError("At least one of text_body or html_body must be provided.")

        reply_to = payload.get("reply_to") or ""
        if not isinstance(reply_to, str):
            raise ValueError("reply_to must be a string.")
        if reply_to:
            reply_to = _parse_email(reply_to, "reply_to")

        attachments_payload = payload.get("attachments") or []
        inline_payload = payload.get("inline_images") or []

        if not isinstance(attachments_payload, list):
            raise ValueError("attachments must be a list.")
        if not isinstance(inline_payload, list):
            raise ValueError("inline_images must be a list.")

        to = _normalize_email_list(payload.get("to"), "to")
        if not to:
            raise ValueError("to must contain at least one valid email address.")

        return cls(
            to=to,
            cc=_normalize_email_list(payload.get("cc"), "cc"),
            bcc=_normalize_email_list(payload.get("bcc"), "bcc"),
            subject=subject.strip(),
            text_body=text_body.strip(),
            html_body=html_body.strip(),
            reply_to=reply_to,
            attachments=[
                FileReference.from_payload(item, "attachments")
                for item in attachments_payload
            ],
            inline_images=[
                InlineImageReference.from_payload(item, "inline_images")
                for item in inline_payload
            ],
        )

    @property
    def all_recipients(self) -> list[str]:
        recipients: list[str] = []
        for address in self.to + self.cc + self.bcc:
            if address not in recipients:
                recipients.append(address)
        return recipients
