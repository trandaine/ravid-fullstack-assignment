"""Tests for RAG Query endpoint and components."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.test import APIClient

from apps.chat.llm import LLMServiceError, StubChatModel, get_llm
from apps.chat.rag_chain import (
    build_messages,
    format_context,
    retrieve_context_hyde,
    retrieve_context_standard,
    run_query,
)
from apps.chat.serializers import MessageHistorySerializer, QuerySerializer
from apps.rag.vectorstore import upsert_chunks

User = get_user_model()


@pytest.fixture
def auth_user(db):
    return User.objects.create_user(username="testuser", password="password123")


@pytest.fixture
def api_client(auth_user):
    client = APIClient()
    client.force_authenticate(user=auth_user)
    return client


# ---------------------------------------------------------------------------
# 1. Serializer Unit Tests
# ---------------------------------------------------------------------------
class TestQuerySerializer:
    def test_valid_minimal_payload(self):
        serializer = QuerySerializer(data={"query": "What is the policy?"})
        assert serializer.is_valid(), serializer.errors
        assert serializer.validated_data["query"] == "What is the policy?"
        assert serializer.validated_data["message_histories"] == []
        assert serializer.validated_data["use_hyde"] is False

    def test_valid_full_payload(self):
        payload = {
            "query": "Can you elaborate?",
            "message_histories": [
                {"role": "user", "content": "What is the policy?"},
                {"role": "assistant", "content": "The policy requires 14 days notice."},
            ],
            "use_hyde": True,
        }
        serializer = QuerySerializer(data=payload)
        assert serializer.is_valid(), serializer.errors
        assert serializer.validated_data["use_hyde"] is True
        assert len(serializer.validated_data["message_histories"]) == 2

    def test_missing_query_field(self):
        serializer = QuerySerializer(data={})
        assert not serializer.is_valid()
        assert "query" in serializer.errors

    def test_empty_query_string(self):
        serializer = QuerySerializer(data={"query": ""})
        assert not serializer.is_valid()
        assert "query" in serializer.errors

    def test_invalid_role_in_history(self):
        payload = {
            "query": "Hello",
            "message_histories": [{"role": "invalid_role", "content": "hi"}],
        }
        serializer = QuerySerializer(data=payload)
        assert not serializer.is_valid()
        assert "message_histories" in serializer.errors

    def test_blank_content_in_history(self):
        payload = {
            "query": "Hello",
            "message_histories": [{"role": "user", "content": ""}],
        }
        serializer = QuerySerializer(data=payload)
        assert not serializer.is_valid()
        assert "message_histories" in serializer.errors


# ---------------------------------------------------------------------------
# 2. RAG Pipeline Unit Tests
# ---------------------------------------------------------------------------
class TestRAGChain:
    def test_retrieve_empty_collection(self, auth_user):
        chunks = retrieve_context_standard(user_id=auth_user.id, query="test query")
        assert chunks == []

    def test_retrieve_with_stored_chunks(self, auth_user):
        texts = ["The cancellation policy requires 14 days written notice.", "Employees get 20 vacation days."]
        # Stub embeddings produce 32-dim vectors
        from apps.rag.embeddings import get_embeddings
        emb = get_embeddings()
        vectors = emb.embed_documents(texts)
        upsert_chunks(owner_id=auth_user.id, document_id=1, texts=texts, embeddings=vectors)

        chunks = retrieve_context_standard(user_id=auth_user.id, query="cancellation policy", k=1)
        assert len(chunks) == 1
        assert "cancellation" in chunks[0] or "vacation" in chunks[0]

    def test_format_context_empty(self):
        assert format_context([]) == "No relevant document context found."

    def test_format_context_non_empty(self):
        chunks = ["chunk one", "chunk two"]
        formatted = format_context(chunks)
        assert "chunk one" in formatted
        assert "---" in formatted
        assert "chunk two" in formatted

    def test_build_messages_structure(self):
        history = [
            {"role": "user", "content": "first question"},
            {"role": "assistant", "content": "first answer"},
        ]
        messages = build_messages("context text", "second question", history)
        assert len(messages) == 4
        assert "SystemMessage" in str(type(messages[0]))
        assert "HumanMessage" in str(type(messages[1]))
        assert "AIMessage" in str(type(messages[2]))
        assert "HumanMessage" in str(type(messages[3]))

    def test_run_query_standard(self, auth_user):
        answer = run_query(user_id=auth_user.id, query="What is the policy?")
        assert isinstance(answer, str)
        assert len(answer) > 0

    def test_run_query_with_hyde(self, auth_user):
        answer = run_query(user_id=auth_user.id, query="What is the policy?", use_hyde=True)
        assert isinstance(answer, str)
        assert len(answer) > 0

    def test_run_query_hyde_fallback_on_error(self, auth_user):
        # When HyDE generation fails, fallback to standard retrieval seamlessly
        with patch.object(StubChatModel, "invoke", side_effect=[Exception("LLM error"), MagicMock(content="Fallback answer")]):
            answer = run_query(user_id=auth_user.id, query="What is the policy?", use_hyde=True)
            assert answer == "Fallback answer"

    def test_run_query_raises_llm_service_error(self, auth_user):
        with patch.object(StubChatModel, "invoke", side_effect=Exception("API unreachable")):
            with pytest.raises(LLMServiceError):
                run_query(user_id=auth_user.id, query="test query")


# ---------------------------------------------------------------------------
# 3. View / Integration Tests (`POST /api/chat/query/`)
# ---------------------------------------------------------------------------
class TestChatQueryEndpoint:
    URL = "/api/chat/query/"

    def test_unauthenticated_request_returns_401(self, db):
        unauth_client = APIClient()
        response = unauth_client.post(self.URL, {"query": "Hello"}, format="json")
        assert response.status_code == status.HTTP_401_UNAUTHORIZED
        assert "error" in response.data

    def test_successful_query_returns_200(self, api_client):
        payload = {"query": "What is the cancellation policy mentioned in the employee handbook?"}
        response = api_client.post(self.URL, payload, format="json")
        assert response.status_code == status.HTTP_200_OK
        assert "answer" in response.data
        assert isinstance(response.data["answer"], str)

    def test_successful_query_with_history_returns_200(self, api_client):
        payload = {
            "query": "Can you elaborate on the notice period?",
            "message_histories": [
                {"role": "user", "content": "What is the cancellation policy?"},
                {"role": "assistant", "content": "Written notice 14 days prior is required."},
            ],
        }
        response = api_client.post(self.URL, payload, format="json")
        assert response.status_code == status.HTTP_200_OK
        assert "answer" in response.data

    def test_successful_query_with_hyde_toggle_returns_200(self, api_client):
        payload = {
            "query": "What are the rules regarding overtime pay?",
            "use_hyde": True,
        }
        response = api_client.post(self.URL, payload, format="json")
        assert response.status_code == status.HTTP_200_OK
        assert "answer" in response.data

    def test_missing_query_returns_400(self, api_client):
        response = api_client.post(self.URL, {}, format="json")
        assert response.status_code == status.HTTP_400_BAD_REQUEST
        assert "error" in response.data

    def test_empty_query_returns_400(self, api_client):
        response = api_client.post(self.URL, {"query": "   "}, format="json")
        assert response.status_code == status.HTTP_400_BAD_REQUEST
        assert "error" in response.data

    def test_invalid_history_format_returns_400(self, api_client):
        payload = {
            "query": "Hello",
            "message_histories": [{"role": "admin", "content": "invalid"}],
        }
        response = api_client.post(self.URL, payload, format="json")
        assert response.status_code == status.HTTP_400_BAD_REQUEST
        assert "error" in response.data

    def test_llm_service_failure_returns_502(self, api_client):
        with patch("apps.chat.views.run_query", side_effect=LLMServiceError("Service down")):
            response = api_client.post(self.URL, {"query": "test query"}, format="json")
            assert response.status_code == status.HTTP_502_BAD_GATEWAY
            assert "error" in response.data
            assert "unavailable" in response.data["error"]
