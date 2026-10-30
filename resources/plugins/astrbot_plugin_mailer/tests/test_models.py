from __future__ import annotations

import pytest

from astrbot_plugin_mailer.mailer.models import MailRequest


def test_mail_request_parses_nested_payloads() -> None:
    request = MailRequest.from_payload(
        {
            "to": ["alice@example.com"],
            "cc": "bob@example.com",
            "bcc": ["carol@example.com"],
            "subject": "Quarterly update",
            "html_body": "<p>Hello</p>",
            "attachments": [{"path": "report.pdf", "filename": "Q1.pdf"}],
            "inline_images": [{"path": "chart.png", "cid": "chart-1"}],
        }
    )

    assert request.to == ["alice@example.com"]
    assert request.cc == ["bob@example.com"]
    assert request.bcc == ["carol@example.com"]
    assert request.subject == "Quarterly update"
    assert request.text_body == ""
    assert request.inline_images[0].cid == "chart-1"
    assert request.attachments[0].filename == "Q1.pdf"


def test_mail_request_requires_body() -> None:
    with pytest.raises(ValueError, match="At least one of text_body or html_body"):
        MailRequest.from_payload(
            {
                "to": ["alice@example.com"],
                "subject": "Missing body",
            }
        )


def test_mail_request_requires_non_empty_to() -> None:
    with pytest.raises(ValueError, match="at least one valid email address"):
        MailRequest.from_payload(
            {
                "to": ["   "],
                "subject": "Missing recipient",
                "text_body": "Hello",
            }
        )


def test_mail_request_rejects_invalid_email() -> None:
    with pytest.raises(ValueError, match="Invalid email address"):
        MailRequest.from_payload(
            {
                "to": ["not-an-email"],
                "subject": "Oops",
                "text_body": "Hello",
            }
        )
