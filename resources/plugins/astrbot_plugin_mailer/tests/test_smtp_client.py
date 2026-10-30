from __future__ import annotations

from types import SimpleNamespace

from astrbot_plugin_mailer.mailer.smtp_client import _normalize_status_message


def test_normalize_status_message_reads_message_attribute() -> None:
    status = SimpleNamespace(message=b"OK: queued as 12345")

    assert _normalize_status_message(status) == "OK: queued as 12345"


def test_normalize_status_message_ignores_empty_object_repr() -> None:
    class EmptyRepr:
        def __str__(self) -> str:
            return "{}"

    assert _normalize_status_message(EmptyRepr()) == ""
