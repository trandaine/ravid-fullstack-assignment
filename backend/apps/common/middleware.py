"""Cross-cutting HTTP middleware for request ID tracking and structured logging."""

from __future__ import annotations

import logging
import time
import uuid
from collections.abc import Callable

from django.http import HttpRequest, HttpResponse

logger = logging.getLogger(__name__)

REQUEST_ID_ATTR = "_ravid_request_id"


def get_request_id(request: HttpRequest) -> str:
    """Return the request_id attached to request, or empty string."""
    return getattr(request, REQUEST_ID_ATTR, "")


class RequestIdMiddleware:
    """Attach UUID4 request_id and echo in X-Request-ID response header."""

    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        request_id = request.headers.get("X-Request-Id") or str(uuid.uuid4())
        setattr(request, REQUEST_ID_ATTR, request_id)

        response = self.get_response(request)
        response["X-Request-ID"] = request_id
        return response


class RequestLoggingMiddleware:
    """Log structured JSON summary for HTTP requests."""

    def __init__(self, get_response: Callable[[HttpRequest], HttpResponse]) -> None:
        self.get_response = get_response

    def __call__(self, request: HttpRequest) -> HttpResponse:
        start = time.monotonic()
        response = self.get_response(request)
        duration_ms = round((time.monotonic() - start) * 1000, 2)

        logger.info(
            "http_request",
            extra={
                "request_id": get_request_id(request),
                "method": request.method,
                "path": request.path,
                "status": response.status_code,
                "duration_ms": duration_ms,
            },
        )
        return response
