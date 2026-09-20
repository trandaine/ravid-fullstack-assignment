"""Serializers for chat and RAG query endpoints."""

from __future__ import annotations

from rest_framework import serializers


class MessageHistorySerializer(serializers.Serializer):
    role = serializers.ChoiceField(
        choices=["user", "assistant"],
        error_messages={"invalid_choice": "Role must be either 'user' or 'assistant'."},
    )
    content = serializers.CharField(
        required=True,
        allow_blank=False,
        error_messages={"blank": "Message content cannot be blank."},
    )


class QuerySerializer(serializers.Serializer):
    query = serializers.CharField(
        required=True,
        allow_blank=False,
        max_length=2000,
        error_messages={
            "required": "The 'query' field is required and must be a non-empty string.",
            "blank": "The 'query' field is required and must be a non-empty string.",
        },
    )
    message_histories = MessageHistorySerializer(
        many=True,
        required=False,
        default=list,
    )
    use_hyde = serializers.BooleanField(
        required=False,
        default=False,
    )
