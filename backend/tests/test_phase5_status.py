"""Tests for Phase 5: Ingestion Status Polling Endpoint."""

import pytest
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APIClient

from apps.documents.models import Document
from apps.rag.models import IngestionJob
from apps.rag.views import SUCCESS_MESSAGE

User = get_user_model()


@pytest.mark.django_db
class TestIngestionStatusEndpoint:
    def test_unauthenticated_status_poll_returns_401(self):
        client = APIClient()
        response = client.get("/api/documents/status/?task_id=any-id")
        assert response.status_code == 401
        assert "error" in response.data

    def test_missing_task_id_returns_400(self):
        user = User.objects.create_user(username="user1", password="password123")
        client = APIClient()
        client.force_authenticate(user=user)

        response = client.get("/api/documents/status/")
        assert response.status_code == 400
        assert response.data["error"] == "task_id query parameter is required."

    def test_nonexistent_or_other_user_task_id_returns_404(self):
        user1 = User.objects.create_user(username="u1", password="password123")
        user2 = User.objects.create_user(username="u2", password="password123")

        doc = Document.objects.create(
            owner=user2,
            original_name="u2.txt",
            file=SimpleUploadedFile("u2.txt", b"secret"),
            content_type="text/plain",
            size_bytes=6,
        )
        IngestionJob.objects.create(
            owner=user2,
            source_document=doc,
            celery_task_id="u2-task-id",
            status=IngestionJob.Status.SUCCESS,
        )

        client = APIClient()
        client.force_authenticate(user=user1)

        # Non-existent task ID
        resp_404 = client.get("/api/documents/status/?task_id=non-existent-id")
        assert resp_404.status_code == 404
        assert resp_404.data["error"] == "Task not found."

        # Other user's task ID
        resp_cross_user = client.get("/api/documents/status/?task_id=u2-task-id")
        assert resp_cross_user.status_code == 404
        assert resp_cross_user.data["error"] == "Task not found."

    def test_status_states_mapping(self):
        user = User.objects.create_user(username="statuser", password="password123")
        doc = Document.objects.create(
            owner=user,
            original_name="test.txt",
            file=SimpleUploadedFile("test.txt", b"test"),
            content_type="text/plain",
            size_bytes=4,
        )
        job = IngestionJob.objects.create(
            owner=user,
            source_document=doc,
            celery_task_id="task-processing-id",
            status=IngestionJob.Status.STARTED,
        )

        client = APIClient()
        client.force_authenticate(user=user)

        # 1. Processing (STARTED)
        resp = client.get("/api/documents/status/?task_id=task-processing-id")
        assert resp.status_code == 200
        assert resp.data == {
            "task_id": "task-processing-id",
            "status": "PROCESSING",
        }

        # 2. Success
        job.status = IngestionJob.Status.SUCCESS
        job.save(update_fields=["status"])
        resp = client.get("/api/documents/status/?task_id=task-processing-id")
        assert resp.status_code == 200
        assert resp.data == {
            "task_id": "task-processing-id",
            "status": "SUCCESS",
            "message": SUCCESS_MESSAGE,
        }

        # 3. Failure
        job.status = IngestionJob.Status.FAILURE
        job.error_message = "Corrupt PDF file."
        job.save(update_fields=["status", "error_message"])
        resp = client.get("/api/documents/status/?task_id=task-processing-id")
        assert resp.status_code == 200
        assert resp.data == {
            "task_id": "task-processing-id",
            "status": "FAILURE",
            "error": "Corrupt PDF file.",
        }
