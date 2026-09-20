"""Phase 6 Comprehensive Verification Suite for Document Management & Vector Storage API."""

import io
import pytest
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from pypdf import PdfWriter
from rest_framework.test import APIClient

from apps.documents.models import Document
from apps.documents.validators import (
    ALLOWED_EXTENSIONS,
    BAD_FORMAT_MESSAGE,
    validate_uploaded_document,
)
from apps.rag.chunking import split_text_into_chunks
from apps.rag.extractors import extract_text
from apps.rag.models import IngestionJob
from apps.rag.tasks import ingest_document_task
from apps.rag.vectorstore import get_collection, upsert_chunks
from rest_framework.exceptions import ValidationError

User = get_user_model()


def _create_sample_pdf_bytes(text: str = "Sample PDF text for verification testing.") -> bytes:
    """Helper generating minimal valid PDF in-memory."""
    writer = PdfWriter()
    writer.add_blank_page(width=72, height=72)
    stream = io.BytesIO()
    writer.write(stream)
    # Append comment or text content for extract_text testing
    return stream.getvalue()


@pytest.mark.django_db
class TestPhase6AutomatedVerification:
    # -----------------------------------------------------------------------
    # 1. Unit tests for file validation rules
    # -----------------------------------------------------------------------
    def test_validation_allowed_extensions_and_rejections(self):
        valid_txt = SimpleUploadedFile("file.txt", b"plain text", content_type="text/plain")
        valid_md = SimpleUploadedFile("file.md", b"# header", content_type="text/markdown")
        valid_pdf = SimpleUploadedFile("file.pdf", b"%PDF-1.4", content_type="application/pdf")

        assert validate_uploaded_document(valid_txt) == valid_txt
        assert validate_uploaded_document(valid_md) == valid_md
        assert validate_uploaded_document(valid_pdf) == valid_pdf

        # Rejection: invalid extensions
        for bad_name in ["script.py", "archive.zip", "doc.docx", "data.json", "file.exe"]:
            f = SimpleUploadedFile(bad_name, b"dummy", content_type="application/octet-stream")
            with pytest.raises(ValidationError) as exc:
                validate_uploaded_document(f)
            assert BAD_FORMAT_MESSAGE in str(exc.value)

    def test_validation_oversized_limit(self, settings):
        settings.MAX_UPLOAD_MB = 10
        oversized = SimpleUploadedFile(
            "large.txt",
            b"x" * (10 * 1024 * 1024 + 1),
            content_type="text/plain",
        )
        with pytest.raises(ValidationError) as exc:
            validate_uploaded_document(oversized)
        assert "File too large. Maximum allowed size is 10 MB." in str(exc.value)

    # -----------------------------------------------------------------------
    # 2. Integration tests for POST /api/documents/upload/
    # -----------------------------------------------------------------------
    def test_upload_missing_payload_returns_400(self):
        user = User.objects.create_user(username="p6_uploader_empty", password="password123")
        client = APIClient()
        client.force_authenticate(user=user)

        response = client.post("/api/documents/upload/", {}, format="multipart")
        assert response.status_code == 400
        assert "error" in response.data

    def test_upload_full_flow_202_and_db_persistence(self):
        user = User.objects.create_user(username="p6_uploader", password="password123")
        client = APIClient()
        client.force_authenticate(user=user)

        content = b"Content for full flow test of upload and ingestion."
        file_obj = SimpleUploadedFile("doc.txt", content, content_type="text/plain")

        response = client.post(
            "/api/documents/upload/",
            {"file": file_obj},
            format="multipart",
        )
        assert response.status_code == 202
        assert "document_id" in response.data
        assert "task_id" in response.data

        doc_id = response.data["document_id"]
        task_id = response.data["task_id"]

        doc = Document.objects.get(pk=doc_id)
        assert doc.owner == user
        assert doc.original_name == "doc.txt"
        assert doc.size_bytes == len(content)

        job = IngestionJob.objects.get(celery_task_id=task_id)
        assert job.owner == user
        assert job.source_document == doc

    # -----------------------------------------------------------------------
    # 3. Integration tests for GET /api/documents/status/
    # -----------------------------------------------------------------------
    def test_status_endpoint_full_matrix(self):
        user = User.objects.create_user(username="p6_status_user", password="password123")
        other_user = User.objects.create_user(username="p6_other_user", password="password123")

        doc = Document.objects.create(
            owner=user,
            original_name="test.txt",
            file=SimpleUploadedFile("test.txt", b"abc"),
            content_type="text/plain",
            size_bytes=3,
        )

        job = IngestionJob.objects.create(
            owner=user,
            source_document=doc,
            celery_task_id="p6-task-1",
            status=IngestionJob.Status.STARTED,
        )

        client = APIClient()
        client.force_authenticate(user=user)

        # Missing task_id
        r_missing = client.get("/api/documents/status/")
        assert r_missing.status_code == 400

        # Invalid / 404
        r_404 = client.get("/api/documents/status/?task_id=unknown-id")
        assert r_404.status_code == 404

        # Cross user 404
        client_other = APIClient()
        client_other.force_authenticate(user=other_user)
        r_cross = client_other.get("/api/documents/status/?task_id=p6-task-1")
        assert r_cross.status_code == 404

        # Valid states
        r_started = client.get("/api/documents/status/?task_id=p6-task-1")
        assert r_started.status_code == 200
        assert r_started.data["status"] == "PROCESSING"

        job.status = IngestionJob.Status.SUCCESS
        job.save()
        r_success = client.get("/api/documents/status/?task_id=p6-task-1")
        assert r_success.status_code == 200
        assert r_success.data["status"] == "SUCCESS"
        assert "message" in r_success.data

    # -----------------------------------------------------------------------
    # 4. Ingestion pipeline verification (Extraction, Chunking, Isolation)
    # -----------------------------------------------------------------------
    def test_txt_and_md_extraction(self, tmp_path):
        txt_path = tmp_path / "sample.txt"
        txt_path.write_text("Plain text content line 1\nline 2", encoding="utf-8")
        extracted_txt = extract_text(str(txt_path), "text/plain")
        assert "Plain text content line 1" in extracted_txt

        md_path = tmp_path / "sample.md"
        md_path.write_text("# Markdown Title\nParagraph text.", encoding="utf-8")
        extracted_md = extract_text(str(md_path), "text/markdown")
        assert "# Markdown Title" in extracted_md

    def test_chunking_and_isolation(self):
        text = "Semantic text paragraph " * 100
        chunks = split_text_into_chunks(text, chunk_size=500, chunk_overlap=50)
        assert len(chunks) > 1

        user1_texts = ["User 1 doc chunk A", "User 1 doc chunk B"]
        user2_texts = ["User 2 doc chunk X"]

        upsert_chunks(owner_id=101, document_id=1, texts=user1_texts, embeddings=[[0.1] * 32] * 2)
        upsert_chunks(owner_id=102, document_id=2, texts=user2_texts, embeddings=[[0.2] * 32])

        c101 = get_collection(101)
        c102 = get_collection(102)

        assert c101.name == "user_101"
        assert c102.name == "user_102"
        assert c101.count() == 2
        assert c102.count() == 1
