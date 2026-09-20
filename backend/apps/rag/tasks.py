"""Celery background tasks for RAG ingestion."""

from __future__ import annotations

import logging
from celery import shared_task

from apps.rag.chunking import split_text_into_chunks
from apps.rag.embeddings import get_embeddings
from apps.rag.extractors import extract_text
from apps.rag.vectorstore import upsert_chunks

logger = logging.getLogger(__name__)


@shared_task(bind=True, name="apps.rag.tasks.ingest_document_task")
def ingest_document_task(self, job_id: int) -> dict:
    """Execute ingestion pipeline: extract -> chunk -> embed -> upsert."""
    from apps.documents.models import Document  # noqa: PLC0415
    from apps.rag.models import IngestionJob  # noqa: PLC0415

    try:
        job = IngestionJob.objects.select_related("source_document").get(pk=job_id)
    except IngestionJob.DoesNotExist:
        logger.warning("IngestionJob pk=%s does not exist", job_id)
        return {"job_id": job_id, "status": "NOT_FOUND"}

    task_id = self.request.id or job.celery_task_id or ""
    IngestionJob.objects.filter(pk=job_id).update(
        status=IngestionJob.Status.STARTED,
        celery_task_id=task_id,
    )
    Document.objects.filter(pk=job.source_document_id).update(
        status=Document.Status.PROCESSING
    )

    try:
        doc = job.source_document
        raw_text = extract_text(doc.file.path, doc.content_type)
        if not raw_text or not raw_text.strip():
            raise ValueError("No extractable text found in document.")

        chunks = split_text_into_chunks(raw_text)
        if not chunks:
            raise ValueError("No extractable chunks produced from document.")

        embeddings_service = get_embeddings()
        vectors = embeddings_service.embed_documents(chunks)

        upsert_chunks(
            owner_id=job.owner_id,
            document_id=doc.id,
            texts=chunks,
            embeddings=vectors,
        )

        chunk_count = len(chunks)
        IngestionJob.objects.filter(pk=job_id).update(
            status=IngestionJob.Status.SUCCESS,
            chunk_count=chunk_count,
            error_message="",
        )
        Document.objects.filter(pk=doc.id).update(status=Document.Status.SUCCESS)

        logger.info(
            "Ingestion succeeded for job_id=%s doc_id=%s chunks=%s",
            job_id,
            doc.id,
            chunk_count,
        )
        return {"job_id": job_id, "status": "SUCCESS", "chunk_count": chunk_count}

    except Exception as exc:
        error_msg = str(exc)[:500]
        IngestionJob.objects.filter(pk=job_id).update(
            status=IngestionJob.Status.FAILURE,
            error_message=error_msg,
        )
        Document.objects.filter(pk=job.source_document_id).update(
            status=Document.Status.FAILURE
        )
        logger.error(
            "Ingestion failed for job_id=%s doc_id=%s error=%s",
            job_id,
            job.source_document_id,
            error_msg,
        )
        return {"job_id": job_id, "status": "FAILURE", "error": error_msg}
