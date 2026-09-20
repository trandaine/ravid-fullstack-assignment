"""URL routing for documents app."""

from django.urls import path

from .views import DocumentUploadView

app_name = "documents"

urlpatterns = [
    path("upload/", DocumentUploadView.as_view(), name="document-upload"),
]
