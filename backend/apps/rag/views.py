"""Views for RAG status polling and chat."""

from __future__ import annotations

import logging
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import IngestionJob

logger = logging.getLogger(__name__)

SUCCESS_MESSAGE = "Document successfully parsed, embedded, and indexed in vector storage."

INTERNAL_TO_PUBLIC = {
    IngestionJob.Status.PENDING: "PROCESSING",
    IngestionJob.Status.STARTED: "PROCESSING",
    IngestionJob.Status.SUCCESS: "SUCCESS",
    IngestionJob.Status.FAILURE: "FAILURE",
}


class IngestionStatusView(APIView):
    """GET /api/documents/status/?task_id=<task_id> - poll ingestion status."""

    permission_classes = [IsAuthenticated]

    def get(self, request: Request) -> Response:
        task_id = request.query_params.get("task_id", "").strip()
        if not task_id:
            return Response(
                {"error": "task_id query parameter is required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            job = IngestionJob.objects.get(
                celery_task_id=task_id,
                owner=request.user,
            )
        except IngestionJob.DoesNotExist:
            return Response(
                {"error": "Task not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        public_status = INTERNAL_TO_PUBLIC.get(job.status, "PROCESSING")

        if public_status == "SUCCESS":
            return Response(
                {
                    "task_id": task_id,
                    "status": "SUCCESS",
                    "message": SUCCESS_MESSAGE,
                },
                status=status.HTTP_200_OK,
            )

        if public_status == "FAILURE":
            return Response(
                {
                    "task_id": task_id,
                    "status": "FAILURE",
                    "error": job.error_message or "Ingestion failed.",
                },
                status=status.HTTP_200_OK,
            )

        return Response(
            {
                "task_id": task_id,
                "status": "PROCESSING",
            },
            status=status.HTTP_200_OK,
        )
