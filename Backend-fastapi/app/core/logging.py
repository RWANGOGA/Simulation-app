"""Structured logging with a per-request correlation id.

Nothing configured logging before this. Every module called
``logging.getLogger(__name__)`` and then ``logger.info(...)``, but with no
handler and no level set, the root logger's last-resort handler only ever
printed WARNING and above to stderr, formatted as a bare message. So the audit
and lifecycle lines the code deliberately writes at INFO were being thrown away,
and the only startup output was three ``print()`` calls in ``main.py``.

Two things change here:

* one JSON object (or one aligned line) per event, with a timestamp, level,
  logger name and request id, so logs can be searched and aggregated; and
* every line written while handling a request carries that request's id, taken
  from a contextvar, so a single id stitches together the access line, the
  application logs and any traceback.
"""

from __future__ import annotations

import json
import logging
import secrets
import sys
from contextvars import ContextVar
from datetime import datetime, timezone
from typing import Any, TextIO

# Set per request by RequestContextMiddleware. A contextvar rather than a
# thread-local because handlers are async and a thread is shared between
# requests; rather than an argument because that would mean touching every
# logger call site.
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")

# Attributes every LogRecord already has, so anything else in __dict__ is a
# field the caller passed via extra=.
_RESERVED = set(vars(logging.LogRecord("", 0, "", 0, "", (), None))) | {
    "message",
    "asctime",
    "taskName",
    "request_id",
}

_handler: logging.Handler | None = None


def current_request_id() -> str:
    """The id of the request being handled, or "-" outside one."""
    return request_id_var.get()


def new_request_id() -> str:
    """Short, opaque and safe to put in a header or a log line."""
    return secrets.token_hex(8)


def _extras(record: logging.LogRecord) -> dict[str, Any]:
    return {
        key: value
        for key, value in vars(record).items()
        if key not in _RESERVED and not key.startswith("_")
    }


def _timestamp(created: float) -> str:
    return datetime.fromtimestamp(created, tz=timezone.utc).isoformat(
        timespec="milliseconds"
    )


class JsonFormatter(logging.Formatter):
    """One JSON object per line — what a log aggregator actually wants."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "time": _timestamp(record.created),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
        }
        payload.update(_extras(record))
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        # default=str so a stray UUID or Decimal in extra= cannot break logging
        # and take the request down with it.
        return json.dumps(payload, default=str, ensure_ascii=False)


class PlainFormatter(logging.Formatter):
    """Readable single lines for a developer's terminal, same fields."""

    def format(self, record: logging.LogRecord) -> str:
        head = (
            f"{_timestamp(record.created)} {record.levelname:<8} "
            f"[{getattr(record, 'request_id', '-')}] {record.name}: "
            f"{record.getMessage()}"
        )
        extras = _extras(record)
        if not extras:
            return head + ("\n" + self.formatException(record.exc_info) if record.exc_info else "")
        rendered = " ".join(f"{key}={value}" for key, value in extras.items())
        tail = f"\n{self.formatException(record.exc_info)}" if record.exc_info else ""
        return f"{head} {rendered}{tail}"


class _RequestIdFilter(logging.Filter):
    """Copies the ambient request id onto every record.

    Lives on the handler rather than on each logger so records from uvicorn,
    SQLAlchemy and anything else that logs through the root logger get the same
    treatment.
    """

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        return True


def configure_logging(
    level: str = "INFO",
    format: str = "plain",  # noqa: A002 - matches the setting name
    stream: TextIO | None = None,
) -> None:
    """Install the handler once; later calls only adjust level and format.

    Idempotent on purpose: TestClient calls this per app import, and pytest's
    caplog installs its own root handler which must not be ripped out.
    """
    global _handler

    if _handler is None:
        _handler = logging.StreamHandler(stream or sys.stdout)
        _handler.addFilter(_RequestIdFilter())
        logging.getLogger().addHandler(_handler)
    elif stream is not None:
        # Tests point the same handler at a StringIO; rebuild would drop the
        # filter and leave a stray handler behind on the root logger.
        _handler.setStream(stream)

    _handler.setFormatter(
        JsonFormatter() if format.lower() == "json" else PlainFormatter()
    )

    root = logging.getLogger()
    root.setLevel(level.upper())
    if root.level > logging.INFO:
        root.setLevel(logging.INFO)

    # Uvicorn logs every request line itself, with the raw URL — which for this
    # API includes the patient code. Our access line uses the route template
    # instead, so the per-request duplicate is off.
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
