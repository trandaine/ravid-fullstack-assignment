"""Common views including health check."""

from django.http import JsonResponse
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.request import Request


@api_view(["GET"])
@permission_classes([AllowAny])
def health(request: Request) -> JsonResponse:
    """Liveness probe returning 200 OK."""
    return JsonResponse({"status": "ok"})
