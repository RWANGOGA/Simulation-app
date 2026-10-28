"""A 500 has to stay readable from the browser.

Starlette wraps the whole user middleware stack in `ServerErrorMiddleware`, so an
unhandled exception becomes a 500 *outside* `CORSMiddleware` and never receives
its headers. The browser then reports "blocked by CORS policy", and the failure
that actually happened stays invisible - which is how a missing database column
spent a day looking like a CORS misconfiguration. The handler attaches the header
itself; these tests pin that.
"""
import asyncio

from starlette.requests import Request

from app.main import _unhandled_exception_handler

ALLOWED = "https://rwangoga.github.io"


def _request(origin: str) -> Request:
    return Request({"type": "http", "headers": [(b"origin", origin.encode())]})


def _response_for(origin: str):
    return asyncio.run(
        _unhandled_exception_handler(_request(origin), RuntimeError("boom"))
    )


def test_allowed_origin_can_read_the_500() -> None:
    response = _response_for(ALLOWED)

    assert response.status_code == 500
    assert response.headers["access-control-allow-origin"] == ALLOWED
    assert response.headers["access-control-allow-credentials"] == "true"


def test_unknown_origin_gets_no_cors_header() -> None:
    response = _response_for("https://not-allowed.example")

    assert response.status_code == 500
    assert "access-control-allow-origin" not in response.headers


def test_the_response_does_not_leak_the_underlying_error() -> None:
    response = _response_for(ALLOWED)

    assert b"boom" not in response.body
