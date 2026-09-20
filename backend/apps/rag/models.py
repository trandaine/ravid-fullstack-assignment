"""Models for RAG ingestion pipeline."""

from __future__ import annotations

from django.conf import settings
from django.db import models


class IngestionJob(models.Model):
    """Tracks asynchronous document ingestion jobs."""

    class Status(models.TextChoices):
        PENDING = "PENDING", "Pending"
        STARTED = "STARTED", "Started"
        SUCCESS = "SUCCESS", "Success"
        FAILURE = "FAILURE", "Failure"

    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="ingestion_jobs",
        db_index=True,
    )
    source_document = models.ForeignKey(
        "documents.Document",
        on_delete=models.CASCADE,
        related_name="jobs",
    )
    status = models.CharField(
        max_length=10,
        choices=Status.choices,
        default=Status.PENDING,
    )
    celery_task_id = models.CharField(
        max_length=255,
        unique=True,
        null=True,
        blank=True,
        db_index=True,
    )
    chunk_count = models.PositiveIntegerField(default=0)
    error_message = models.TextField(blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self) -> str:
        return (
            f"IngestionJob({self.pk}, owner={self.owner_id}, "
            f"doc={self.source_document_id}, status={self.status})"
        )
