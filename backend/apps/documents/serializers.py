"""Serializers for document uploads and listings."""

from __future__ import annotations

from rest_framework import serializers

from .models import Document
from .validators import validate_uploaded_document


class DocumentUploadSerializer(serializers.Serializer):
    """Multipart serializer for document upload endpoint."""

    file = serializers.FileField()

    def validate_file(self, value: object) -> object:
        return validate_uploaded_document(value)


class DocumentSerializer(serializers.ModelSerializer):
    """Read serializer for Document instances."""

    class Meta:
        model = Document
        fields = [
            "id",
            "original_name",
            "content_type",
            "size_bytes",
            "status",
            "uploaded_at",
        ]
        read_only_fields = fields
