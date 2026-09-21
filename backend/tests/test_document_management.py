"""Integration tests for Document list and delete endpoints."""

from __future__ import annotations

import io
import pytest
from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.test import APIClient

from apps.documents.models import Document

User = get_user_model()


@pytest.fixture
def user_a(db) -> User:
    return User.objects.create_user(username="usera", password="password123")


@pytest.fixture
def user_b(db) -> User:
    return User.objects.create_user(username="userb", password="password123")


@pytest.fixture
def client_a(user_a) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user_a)
    return client


@pytest.fixture
def client_b(user_b) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user_b)
    return client


@pytest.fixture
def doc_user_a(user_a) -> Document:
    file = SimpleUploadedFile("test_a.txt", b"Content A", content_type="text/plain")
    doc = Document.objects.create(
        owner=user_a,
        original_name="test_a.txt",
        content_type="text/plain",
        size_bytes=9,
        file=file,
        status=Document.Status.UPLOADED,
    )
    return doc


@pytest.mark.django_db
def test_list_documents_empty(client_a):
    response = client_a.get("/api/documents/")
    assert response.status_code == status.HTTP_200_OK
    assert response.data == []


@pytest.mark.django_db
def test_list_documents_owner_scoped(client_a, client_b, doc_user_a):
    # user A sees doc
    res_a = client_a.get("/api/documents/")
    assert res_a.status_code == status.HTTP_200_OK
    assert len(res_a.data) == 1
    assert res_a.data[0]["id"] == doc_user_a.id
    assert res_a.data[0]["original_name"] == "test_a.txt"

    # user B sees empty list
    res_b = client_b.get("/api/documents/")
    assert res_b.status_code == status.HTTP_200_OK
    assert len(res_b.data) == 0


@pytest.mark.django_db
def test_delete_document_success(client_a, doc_user_a):
    response = client_a.delete(f"/api/documents/{doc_user_a.id}/")
    assert response.status_code == status.HTTP_204_NO_CONTENT
    assert not Document.objects.filter(id=doc_user_a.id).exists()


@pytest.mark.django_db
def test_delete_document_foreign_user_returns_404(client_b, doc_user_a):
    response = client_b.delete(f"/api/documents/{doc_user_a.id}/")
    assert response.status_code == status.HTTP_404_NOT_FOUND
    assert Document.objects.filter(id=doc_user_a.id).exists()


@pytest.mark.django_db
def test_delete_document_not_found(client_a):
    response = client_a.delete("/api/documents/99999/")
    assert response.status_code == status.HTTP_404_NOT_FOUND
