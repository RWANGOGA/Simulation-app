"""Request correlation and access logging.

Every response gets an ``X-Request-ID``. A caller may supply one (a gateway or a
mobile client retrying a request), but only if it looks like an id — an
arbitrary header value ends up in logs and in a response header, so it is
validated rather than trusted.

One access line is written per request. It logs the matched **route template**
(``/api/v1/triage/patient/{patient_code}``) rather than the raw path, because
the raw path is a patient identifier — logging it would undo the redaction work
done on the API responses themselves.
"""

from __future__ import annotations

import logging
import re
import time

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

from app.core.logging import new_request_id, request_id_var

logger = logging.getLogger("app.access")

REQUEST_ID_HEADER = "X-Request-ID"

# An id we are willing to log and echo back: short, printable, no newlines.
_VALID_ID = re.compile(r"^[A-Za-z0-9._:-]{1,64}$")

# Patient codes look like P-770043. Used only for unmatched routes, where
# Starlette has no route template to offer.
_PATIENT_CODE = re.compile(r"P-[A-Za-z0-9]+", re.IGNORECASE)
_UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)


def route_template(request: Request) -> str:
    """The request path with every path parameter replaced by its name.

    ``/api/v1/triage/patient/P-770043`` becomes
    ``/api/v1/triage/patient/{patient_code}``, so the log can answer "how often
    is this endpoint called" without recording whose record was read.

    Derived from ``path_params`` rather than ``scope["route"]`` because the
    installed FastAPI wraps included routers lazily and the matched route's
    ``path`` is only the sub-router's fragment (``/health``, not
    ``/api/v1/health``). Rewriting the actual path works the same whether or not
    a route matched and does not depend on router internals.
    """
    path = request.url.path
    params = request.path_params or {}
    if params:
        # Match whole segments: substituting by substring could rewrite a
        # literal part of the path that happens to equal a parameter value.
        names_by_value = {str(value): name for name, value in params.items() if value}
        path = "/".join(
            f"{{{names_by_value[segment]}}}" if segment in names_by_value else segment
            for segment in path.split("/")
        )
    return _UUID.sub("{uuid}", _PATIENT_CODE.sub("{code}", path))


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(
        self, request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        supplied = request.headers.get(REQUEST_ID_HEADER, "")
        request_id = supplied if _VALID_ID.match(supplied or "") else new_request_id()

        token = request_id_var.set(request_id)
        request.state.request_id = request_id
        started = time.perf_counter()

        try:
            response = await call_next(request)
        except Exception:
            # The exception handlers inside the router have already had their
            # turn; anything here is unhandled. Log it with the id so the
            # client's report of "it broke" can be matched to a traceback.
            logger.exception(
                "request_failed",
                extra={
                    "method": request.method,
                    "route": route_template(request),
                    "duration_ms": _elapsed_ms(started),
                },
            )
            raise
        else:
            logger.info(
                "request",
                extra={
                    "method": request.method,
                    "route": route_template(request),
                    "status": response.status_code,
                    "duration_ms": _elapsed_ms(started),
                },
            )
            response.headers[REQUEST_ID_HEADER] = request_id
            return response
        finally:
            request_id_var.reset(token)


def _elapsed_ms(started: float) -> float:
    return round((time.perf_counter() - started) * 1000, 2)
