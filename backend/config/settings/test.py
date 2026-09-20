"""Test settings — offline, fast, in-memory."""

import tempfile

from .base import *  # noqa: F401, F403

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": ":memory:",
    }
}

PASSWORD_HASHERS = [
    "django.contrib.auth.hashers.MD5PasswordHasher",
]

CELERY_TASK_ALWAYS_EAGER = True
CELERY_TASK_EAGER_PROPAGATES = True

MEDIA_ROOT = tempfile.mkdtemp(prefix="ravid_test_media_")
CHROMA_PERSIST_DIR = tempfile.mkdtemp(prefix="ravid_test_chroma_")

RAVID_EMBEDDINGS_STUB = True
EMBEDDING_MODEL = "stub"

LOGGING["root"]["level"] = "WARNING"  # noqa: F405
