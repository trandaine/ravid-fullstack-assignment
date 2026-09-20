"""Document models for uploaded files."""

from __future__ import annotations

from uuid import uuid4

from django.conf import settings
from django.db import models


def user_document_path(instance: Document, filename: str) -> str:
    """Return a unique upload path scoped to the owning user.

    Pattern: uploads/user_<owner_id>/<uuid4_hex>_<original_filename>
    """
    return f"uploads/user_{instance.owner_id}/{uuid4().hex}_{filename}"


class Document(models.Model):
    """User-uploaded document with file metadata and lifecycle status."""

    class Status(models.TextChoices):
        UPLOADED = "UPLOADED", "Uploaded"
        PROCESSING = "PROCESSING", "Processing"
        SUCCESS = "SUCCESS", "Success"
        FAILURE = "FAILURE", "Failure"

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="documents",
        db_index=True,
    )
    original_name = models.CharField(max_length=255)
    file = models.FileField(upload_to=user_document_path)
    content_type = models.CharField(max_length=100)
    size_bytes = models.PositiveIntegerField()
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.UPLOADED,
    )
    uploaded_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-uploaded_at"]

    def __str__(self) -> str:
        return f"Document({self.pk}, owner={self.owner_id}, name={self.original_name!r})"
