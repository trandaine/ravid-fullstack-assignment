"""Tests for Phase 4: Ingestion Pipeline & Vector Store."""

import pytest
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.documents.models import Document
from apps.rag.chunking import split_text_into_chunks
from apps.rag.embeddings import get_embeddings
from apps.rag.models import IngestionJob
from apps.rag.tasks import ingest_document_task
from apps.rag.vectorstore import get_collection, upsert_chunks

User = get_user_model()


@pytest.mark.django_db
class TestPhase4IngestionPipeline:
    def test_chunking_splits_properly(self):
        text = "Hello world! " * 200
        chunks = split_text_into_chunks(text, chunk_size=100, chunk_overlap=20)
        assert len(chunks) > 1
        assert all(len(c) <= 120 for c in chunks)

    def test_embeddings_generation_stub(self):
        emb = get_embeddings()
        vectors = emb.embed_documents(["First sentence", "Second sentence"])
        assert len(vectors) == 2
        assert len(vectors[0]) == 32

    def test_vectorstore_isolated_namespaces(self):
        texts = ["User 1 doc content"]
        embeddings = [[0.1] * 32]

        upsert_chunks(owner_id=1, document_id=10, texts=texts, embeddings=embeddings)
        upsert_chunks(owner_id=2, document_id=20, texts=["User 2 doc"], embeddings=[[0.2] * 32])

        col1 = get_collection(1)
        col2 = get_collection(2)

        assert col1.name == "user_1"
        assert col2.name == "user_2"
        assert col1.count() == 1
        assert col2.count() == 1

    def test_full_ingest_document_task_success(self):
        user = User.objects.create_user(username="raguser", password="password123")
        file_content = b"Introduction to RAG\n\nThis is a test document explaining RAG architecture.\n" * 10
        uploaded_file = SimpleUploadedFile("rag_doc.txt", file_content, content_type="text/plain")

        doc = Document.objects.create(
            owner=user,
            original_name="rag_doc.txt",
            file=uploaded_file,
            content_type="text/plain",
            size_bytes=len(file_content),
            status=Document.Status.UPLOADED,
        )

        job = IngestionJob.objects.create(
            owner=user,
            source_document=doc,
            status=IngestionJob.Status.PENDING,
        )

        result = ingest_document_task(job.pk)
        assert result["status"] == "SUCCESS"
        assert result["chunk_count"] > 0

        job.refresh_from_db()
        doc.refresh_from_db()

        assert job.status == IngestionJob.Status.SUCCESS
        assert job.chunk_count == result["chunk_count"]
        assert doc.status == Document.Status.SUCCESS

        col = get_collection(user.pk)
        assert col.count() == result["chunk_count"]
