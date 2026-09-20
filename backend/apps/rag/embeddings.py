"""Embeddings configuration and factory."""

from __future__ import annotations

import hashlib
from django.conf import settings

_STUB_DIM = 32


class StubEmbeddings:
    """Deterministic offline embeddings generator for testing."""

    def _hash_to_vector(self, text: str) -> list[float]:
        digest = hashlib.sha256(text.encode("utf-8", errors="replace")).digest()
        floats: list[float] = [float(b) for b in digest]
        while len(floats) < _STUB_DIM:
            floats.extend(floats[: _STUB_DIM - len(floats)])
        floats = floats[:_STUB_DIM]
        norm = sum(x * x for x in floats) ** 0.5 or 1.0
        return [x / norm for x in floats]

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        return [self._hash_to_vector(t) for t in texts]

    def embed_query(self, text: str) -> list[float]:
        return self._hash_to_vector(text)


def get_embeddings() -> object:
    """Return configured HuggingFaceEmbeddings or StubEmbeddings."""
    if getattr(settings, "RAVID_EMBEDDINGS_STUB", False):
        return StubEmbeddings()

    from langchain_huggingface import HuggingFaceEmbeddings  # noqa: PLC0415

    model_name = getattr(settings, "EMBEDDING_MODEL", "all-MiniLM-L6-v2")
    return HuggingFaceEmbeddings(model_name=model_name)
