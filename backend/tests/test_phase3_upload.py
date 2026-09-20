"""Tests for Phase 3: File Upload Endpoint and Validators."""

import pytest
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.documents.models import Document
from apps.documents.validators import (
    BAD_FORMAT_MESSAGE,
    validate_uploaded_document,
)
from apps.rag.models import IngestionJob
from rest_framework.exceptions import ValidationError

User = get_user_model()


class TestValidators:
    def test_invalid_extension_raises(self):
        f = SimpleUploadedFile("script.py", b"print('hi')", content_type="text/x-python")
        with pytest.raises(ValidationError) as exc:
            validate_uploaded_document(f)
        assert BAD_FORMAT_MESSAGE in str(exc.value)

    def test_invalid_mime_type_raises(self):
        f = SimpleUploadedFile("bad.txt", b"hello", content_type="application/json")
        with pytest.raises(ValidationError) as exc:
            validate_uploaded_document(f)
        assert BAD_FORMAT_MESSAGE in str(exc.value)

    def test_oversized_file_raises(self, settings):
        settings.MAX_UPLOAD_MB = 1
        big_content = b"x" * (1 * 1024 * 1024 + 10)
        f = SimpleUploadedFile("big.txt", big_content, content_type="text/plain")
        with pytest.raises(ValidationError) as exc:
            validate_uploaded_document(f)
        assert "File too large. Maximum allowed size is 1 MB." in str(exc.value)

    def test_valid_file_passes(self):
        f = SimpleUploadedFile("doc.md", b"# Markdown", content_type="text/markdown")
        assert validate_uploaded_document(f) == f


@pytest.mark.django_db
class TestDocumentUploadEndpoint:
    def test_unauthenticated_upload_returns_401(self):
        client = APIClient()
        response = client.post("/api/documents/upload/", {})
        assert response.status_code == 401
        assert "error" in response.data

    def test_authenticated_upload_success_returns_202_and_creates_records(self):
        user = User.objects.create_user(username="uploader", password="password123")
        client = APIClient()
        client.force_authenticate(user=user)

        file_content = b"Hello world text document"
        uploaded_file = SimpleUploadedFile("note.txt", file_content, content_type="text/plain")

        response = client.post(
            "/api/documents/upload/",
            {"file": uploaded_file},
            format="multipart",
        )

        assert response.status_code == 202
        assert response.data["message"] == "Document uploaded and ingestion started"
        assert "document_id" in response.data
        assert "task_id" in response.data

        doc = Document.objects.get(pk=response.data["document_id"])
        assert doc.owner == user
        assert doc.original_name == "note.txt"
        assert doc.size_bytes == len(file_content)

        job = IngestionJob.objects.get(celery_task_id=response.data["task_id"])
        assert job.source_document == doc
        assert job.owner == user
        assert job.status in [IngestionJob.Status.PENDING, IngestionJob.Status.STARTED, IngestionJob.Status.SUCCESS]

    def test_authenticated_upload_invalid_extension_returns_400(self):
        user = User.objects.create_user(username="uploader2", password="password123")
        client = APIClient()
        client.force_authenticate(user=user)

        uploaded_file = SimpleUploadedFile("image.png", b"\x89PNG\r\n\x1a\n", content_type="image/png")

        response = client.post(
            "/api/documents/upload/",
            {"file": uploaded_file},
            format="multipart",
        )

        assert response.status_code == 400
        assert response.data["error"] == BAD_FORMAT_MESSAGE
