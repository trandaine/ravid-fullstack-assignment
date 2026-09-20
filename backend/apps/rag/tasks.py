"""Celery background tasks for RAG ingestion."""

from __future__ import annotations

import logging
from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task(bind=True, name="apps.rag.tasks.ingest_document_task")
def ingest_document_task(self, job_id: int) -> dict:
    """Task placeholder for phase 3, implemented fully in Phase 4."""
    from apps.rag.models import IngestionJob  # noqa: PLC0415

    logger.info("ingest_document_task called with job_id=%s task_id=%s", job_id, self.request.id)
    try:
        job = IngestionJob.objects.get(pk=job_id)
        if not job.celery_task_id:
            job.celery_task_id = self.request.id
            job.save(update_fields=["celery_task_id"])
    except IngestionJob.DoesNotExist:
        logger.warning("IngestionJob pk=%s does not exist", job_id)
    return {"status": "accepted", "job_id": job_id, "task_id": self.request.id}
