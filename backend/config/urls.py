"""Root URL configuration for RAVID."""

from django.urls import include, path

urlpatterns = [
    path("api/health/", include("apps.common.urls")),
    path("api/", include("apps.documents.urls")),
    path("api/", include("apps.rag.urls")),
]
