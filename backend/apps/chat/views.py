"""Views for chat and RAG query endpoints."""

from __future__ import annotations

import logging
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.chat.llm import LLMServiceError
from apps.chat.rag_chain import run_query
from apps.chat.serializers import QuerySerializer

logger = logging.getLogger(__name__)


class ChatQueryView(APIView):
    """Execute retrieval-augmented generation query against user's documents."""

    permission_classes = [IsAuthenticated]

    def post(self, request: Request) -> Response:
        serializer = QuerySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        data = serializer.validated_data
        query: str = data["query"]
        message_histories: list[dict] = data.get("message_histories", [])
        use_hyde: bool = data.get("use_hyde", False)

        try:
            answer = run_query(
                user_id=request.user.id,
                query=query,
                message_histories=message_histories,
                use_hyde=use_hyde,
            )
            return Response({"answer": answer}, status=status.HTTP_200_OK)
        except LLMServiceError as exc:
            logger.error("LLMServiceError in ChatQueryView: %s", exc)
            return Response(
                {"error": "The AI service is temporarily unavailable. Please try again later."},
                status=status.HTTP_502_BAD_GATEWAY,
            )
