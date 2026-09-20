"""URL routing for chat app."""

from django.urls import path
from apps.chat.views import ChatQueryView

app_name = "chat"

urlpatterns = [
    path("query/", ChatQueryView.as_view(), name="query"),
]
