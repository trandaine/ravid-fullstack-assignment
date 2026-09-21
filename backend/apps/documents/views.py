"""Views for document management."""

from __future__ import annotations

import logging
from django.db import transaction
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.request import Request
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.rag.models import IngestionJob
from apps.rag.tasks import ingest_document_task

from .models import Document
from .serializers import DocumentSerializer, DocumentUploadSerializer

logger = logging.getLogger(__name__)


def _first_error_message(errors: dict | list | str) -> str:
    """Extract the first validation error string recursively."""
    if isinstance(errors, str):
        return errors
    if isinstance(errors, list) and errors:
        return _first_error_message(errors[0])
    if isinstance(errors, dict) and errors:
        first_val = next(iter(errors.values()))
        return _first_error_message(first_val)
    return "Invalid input."


class DocumentListView(APIView):
    """GET /api/documents/ - list documents owned by authenticated user."""

    permission_classes = [IsAuthenticated]

    def get(self, request: Request) -> Response:
        documents = Document.objects.filter(owner=request.user).order_by("-uploaded_at")
        serializer = DocumentSerializer(documents, many=True)
        return Response(serializer.data, status=status.HTTP_200_OK)


class DocumentDeleteView(APIView):
    """DELETE /api/documents/<int:pk>/ - delete document owned by authenticated user."""

    permission_classes = [IsAuthenticated]

    def delete(self, request: Request, pk: int) -> Response:
        try:
            document = Document.objects.get(pk=pk, owner=request.user)
        except Document.DoesNotExist:
            return Response(
                {"error": "Document not found."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if document.file:
            document.file.delete(save=False)
        document.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class DocumentUploadView(APIView):
    """POST /api/documents/upload/ - upload document and start ingestion."""

    permission_classes = [IsAuthenticated]

    def post(self, request: Request) -> Response:
        serializer = DocumentUploadSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(
                {"error": _first_error_message(serializer.errors)},
                status=status.HTTP_400_BAD_REQUEST,
            )

        uploaded_file = serializer.validated_data["file"]

        with transaction.atomic():
            doc = Document(
                owner=request.user,
                original_name=uploaded_file.name,
                content_type=getattr(uploaded_file, "content_type", "") or "text/plain",
                size_bytes=uploaded_file.size,
                status=Document.Status.UPLOADED,
            )
            doc.file.save(uploaded_file.name, uploaded_file, save=False)
            doc.save()

            job = IngestionJob.objects.create(
                owner=request.user,
                source_document=doc,
                status=IngestionJob.Status.PENDING,
            )

        task_result = ingest_document_task.delay(job.pk)
        job.celery_task_id = task_result.id
        job.save(update_fields=["celery_task_id"])

        return Response(
            {
                "message": "Document uploaded and ingestion started",
                "document_id": doc.id,
                "task_id": task_result.id,
            },
            status=status.HTTP_202_ACCEPTED,
        )
