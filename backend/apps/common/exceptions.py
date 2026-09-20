"""Custom DRF exception handler normalizing API errors to {"error": "<message>"}."""

from __future__ import annotations

from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_default_handler

_HANDLED_STATUSES = {
    status.HTTP_400_BAD_REQUEST,
    status.HTTP_401_UNAUTHORIZED,
    status.HTTP_403_FORBIDDEN,
    status.HTTP_404_NOT_FOUND,
    status.HTTP_405_METHOD_NOT_ALLOWED,
    status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
    status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
}


def _extract_message(data: object) -> str:
    """Extract a single human-readable string from DRF error data."""
    if isinstance(data, str):
        return data

    if isinstance(data, list):
        for item in data:
            if isinstance(item, str):
                return item
            if isinstance(item, list) and item:
                return str(item[0])
        return str(data[0]) if data else "An error occurred."

    if isinstance(data, dict):
        for value in data.values():
            if isinstance(value, str):
                return value
            if isinstance(value, list) and value:
                first = value[0]
                return str(first)

    return "An error occurred."


def error_envelope_handler(exc: Exception, context: dict) -> Response | None:
    """DRF exception handler wrapping error payloads in {"error": "<msg>"}."""
    response = drf_default_handler(exc, context)

    if response is None:
        return None

    if response.status_code not in _HANDLED_STATUSES:
        return response

    message = _extract_message(response.data)
    response.data = {"error": message}
    return response
