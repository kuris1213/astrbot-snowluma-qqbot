from __future__ import annotations

from pathlib import Path

from astrbot_plugin_mailer.mailer.message_builder import build_message, html_to_text
from astrbot_plugin_mailer.mailer.models import MailRequest


def test_html_to_text_strips_tags() -> None:
    assert html_to_text("<p>Hello <strong>world</strong></p>") == "Hello world"


def test_html_to_text_ignores_script_and_unescapes_entities() -> None:
    assert (
        html_to_text(
            "<style>.x{}</style><script>alert(1)</script><p>Hello&nbsp;world</p>"
        )
        == "Hello world"
    )


def test_build_message_adds_html_and_attachments(tmp_path: Path) -> None:
    attachment = tmp_path / "report.txt"
    attachment.write_text("report-body", encoding="utf-8")
    inline_image = tmp_path / "chart.png"
    inline_image.write_bytes(b"fake-png")

    request = MailRequest.from_payload(
        {
            "to": ["alice@example.com"],
            "subject": "Weekly report",
            "html_body": '<p>See chart <img src="cid:chart-1"></p>',
            "attachments": [{"path": str(attachment)}],
            "inline_images": [{"path": str(inline_image), "cid": "chart-1"}],
        }
    )

    message = build_message(
        request=request,
        from_email="sender@example.com",
        from_name="AstrBot",
        subject_prefix="[Bot] ",
        default_reply_to="reply@example.com",
    )

    assert message["Subject"] == "[Bot] Weekly report"
    assert message["Reply-To"] == "reply@example.com"
    assert (
        message.get_body(preferencelist=("plain",)).get_content().strip() == "See chart"
    )
    assert message.get_body(preferencelist=("html",)) is not None

    attachments = list(message.iter_attachments())
    filenames = {part.get_filename() for part in attachments}
    assert "report.txt" in filenames
    assert "Content-ID: <chart-1>" in message.as_string()
