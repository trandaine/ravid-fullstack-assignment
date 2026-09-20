"""Shared test fixtures for RAVID tests."""

from __future__ import annotations

import contextlib
import pytest


def _wipe_chroma() -> None:
    from apps.rag import vectorstore

    client = vectorstore.get_client()
    for col in client.list_collections():
        name = getattr(col, "name", col)
        with contextlib.suppress(Exception):
            client.delete_collection(name)


@pytest.fixture(autouse=True)
def reset_chroma_state():
    """Ensure Chroma vector state is wiped before and after each test."""
    _wipe_chroma()
    yield
    _wipe_chroma()
