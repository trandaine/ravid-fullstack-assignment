"""Tests for Phase 1 environment, settings, celery, and common error envelope."""

from django.contrib.auth import get_user_model
from django.test import RequestFactory, SimpleTestCase, TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.exceptions import AuthenticationFailed, ValidationError
from rest_framework.test import APIClient

from apps.common.exceptions import error_envelope_handler
from config.celery import app as celery_app

User = get_user_model()


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


class JWTTokensEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.username = "jwt_test_user"
        self.password = "securepass123"
        self.user = User.objects.create_user(
            username=self.username,
            password=self.password,
        )

    def test_token_obtain_pair_success(self):
        url = reverse("token_obtain_pair")
        response = self.client.post(
            url,
            {"username": self.username, "password": self.password},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("access", response.data)
        self.assertIn("refresh", response.data)

    def test_token_obtain_pair_invalid_credentials(self):
        url = reverse("token_obtain_pair")
        response = self.client.post(
            url,
            {"username": self.username, "password": "wrongpassword"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_token_refresh_success(self):
        obtain_url = reverse("token_obtain_pair")
        obtain_res = self.client.post(
            obtain_url,
            {"username": self.username, "password": self.password},
            format="json",
        )
        refresh_token = obtain_res.data["refresh"]

        refresh_url = reverse("token_refresh")
        refresh_res = self.client.post(
            refresh_url,
            {"refresh": refresh_token},
            format="json",
        )
        self.assertEqual(refresh_res.status_code, status.HTTP_200_OK)
        self.assertIn("access", refresh_res.data)

