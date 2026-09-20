"""URL routing for RAG app."""

from django.urls import path

from .views import IngestionStatusView

app_name = "rag"

urlpatterns = [
    path("status/", IngestionStatusView.as_view(), name="ingestion-status"),
]
