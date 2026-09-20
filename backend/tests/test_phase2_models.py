"""Tests for Phase 2: Data Models & Persistence."""

import pytest
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.documents.models import Document
from apps.rag.models import IngestionJob

User = get_user_model()


@pytest.mark.django_db
class TestPhase2Models:
    def test_create_document_and_ingestion_job(self):
        user = User.objects.create_user(username="testuser", password="password123")
        uploaded = SimpleUploadedFile("sample.txt", b"sample content", content_type="text/plain")

        doc = Document.objects.create(
            owner=user,
            original_name="sample.txt",
            file=uploaded,
            content_type="text/plain",
            size_bytes=len(b"sample content"),
            status=Document.Status.UPLOADED,
        )

        assert doc.pk is not None
        assert doc.owner == user
        assert doc.status == "UPLOADED"
        assert f"uploads/user_{user.id}/" in doc.file.name

        job = IngestionJob.objects.create(
            owner=user,
            source_document=doc,
            celery_task_id="celery-task-12345",
            status=IngestionJob.Status.PENDING,
            chunk_count=0,
        )

        assert job.pk is not None
        assert job.source_document == doc
        assert job.owner == user
        assert job.celery_task_id == "celery-task-12345"
        assert job.status == "PENDING"
        assert str(doc).startswith(f"Document({doc.pk}")
        assert str(job).startswith(f"IngestionJob({job.pk}")
