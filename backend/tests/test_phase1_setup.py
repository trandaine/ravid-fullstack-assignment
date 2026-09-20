"""Tests for Phase 1 environment, settings, celery, and common error envelope."""

from django.test import RequestFactory, SimpleTestCase
from rest_framework import status
from rest_framework.exceptions import AuthenticationFailed, ValidationError

from apps.common.exceptions import error_envelope_handler
from config.celery import app as celery_app


class Phase1SanityTests(SimpleTestCase):
    def test_celery_app_configuration(self):
        self.assertEqual(celery_app.main, "ravid")
        self.assertIsNotNone(celery_app.conf)

    def test_error_envelope_handler_formats_dict(self):
        exc = ValidationError({"file": ["The 'file' field is required."]})
        factory = RequestFactory()
        request = factory.post("/api/documents/upload/")
        context = {"request": request}
        response = error_envelope_handler(exc, context)

        self.assertIsNotNone(response)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(response.data, {"error": "The 'file' field is required."})

    def test_error_envelope_handler_formats_auth_failed(self):
        exc = AuthenticationFailed("Authentication credentials were not provided.")
        factory = RequestFactory()
        request = factory.get("/api/documents/status/")
        context = {"request": request}
        response = error_envelope_handler(exc, context)

        self.assertIsNotNone(response)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertEqual(
            response.data,
            {"error": "Authentication credentials were not provided."},
        )
