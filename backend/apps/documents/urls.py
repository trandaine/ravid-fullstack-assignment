"""URL routing for documents app."""

from django.urls import path

from .views import DocumentDeleteView, DocumentListView, DocumentUploadView

app_name = "documents"

urlpatterns = [
    path("", DocumentListView.as_view(), name="document-list"),
    path("<int:pk>/", DocumentDeleteView.as_view(), name="document-delete"),
    path("upload/", DocumentUploadView.as_view(), name="document-upload"),
]
