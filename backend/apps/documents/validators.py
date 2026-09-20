"""File validation utilities for document uploads."""

from __future__ import annotations

import os
from typing import Final

from django.conf import settings
from rest_framework import serializers

ALLOWED_EXTENSIONS: Final[frozenset[str]] = frozenset({".pdf", ".txt", ".md"})
ALLOWED_CONTENT_TYPES: Final[frozenset[str]] = frozenset(
    {
        "application/pdf",
        "text/plain",
        "text/markdown",
        "text/x-markdown",
        "application/octet-stream",
    }
)
BAD_FORMAT_MESSAGE: Final[str] = (
    "Invalid file format. Only PDF, TXT, and Markdown files are allowed."
)


def validate_uploaded_document(uploaded_file: object) -> object:
    """Validate extension, content type, and file size for uploaded documents."""
    filename = getattr(uploaded_file, "name", "") or ""
    _, ext = os.path.splitext(filename)
    if ext.lower() not in ALLOWED_EXTENSIONS:
        raise serializers.ValidationError(BAD_FORMAT_MESSAGE)

    raw_content_type = getattr(uploaded_file, "content_type", "") or ""
    content_type = raw_content_type.split(";")[0].strip().lower()
    if content_type and content_type not in ALLOWED_CONTENT_TYPES:
        raise serializers.ValidationError(BAD_FORMAT_MESSAGE)

    max_mb = getattr(settings, "MAX_UPLOAD_MB", 10)
    max_bytes = max_mb * 1024 * 1024
    size = getattr(uploaded_file, "size", 0)
    if size > max_bytes:
        raise serializers.ValidationError(
            f"File too large. Maximum allowed size is {max_mb} MB."
        )

    return uploaded_file
