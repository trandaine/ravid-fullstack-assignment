"""Chromadb vector store service wrapper for isolated user collections."""

from __future__ import annotations

import contextlib
import threading

import chromadb
from django.conf import settings

_client_lock = threading.Lock()
_chroma_client: chromadb.ClientAPI | None = None


def get_client() -> chromadb.ClientAPI:
    """Return or lazily initialize the Chroma client."""
    global _chroma_client
    if _chroma_client is None:
        with _client_lock:
            if _chroma_client is None:
                chroma_host = getattr(settings, "CHROMA_HOST", None)
                if chroma_host:
                    _chroma_client = chromadb.HttpClient(
                        host=chroma_host,
                        port=int(getattr(settings, "CHROMA_PORT", 8000)),
                        settings=chromadb.Settings(anonymized_telemetry=False),
                    )
                else:
                    _chroma_client = chromadb.PersistentClient(
                        path=str(settings.CHROMA_PERSIST_DIR),
                        settings=chromadb.Settings(anonymized_telemetry=False),
                    )
    return _chroma_client


def reset_client() -> None:
    """Reset singleton client for test teardowns."""
    global _chroma_client
    with _client_lock:
        _chroma_client = None


def get_collection(owner_id: int) -> chromadb.Collection:
    """Return or create isolated collection for user_{user_id}."""
    return get_client().get_or_create_collection(f"user_{owner_id}")


def upsert_chunks(
    owner_id: int,
    document_id: int,
    texts: list[str],
    embeddings: list[list[float]],
) -> None:
    """Upsert text chunks and embeddings into user-isolated collection."""
    if not texts:
        return
    collection = get_collection(owner_id)
    ids = [f"{document_id}:{i}" for i in range(len(texts))]
    metadatas = [
        {"document_id": str(document_id), "chunk_index": i}
        for i in range(len(texts))
    ]
    collection.upsert(
        ids=ids,
        embeddings=embeddings,
        documents=texts,
        metadatas=metadatas,
    )


def delete_document_vectors(owner_id: int, document_id: int) -> None:
    """Delete all vectors for a specific document from user's collection."""
    try:
        collection = get_collection(owner_id)
    except Exception:
        return

    with contextlib.suppress(Exception):
        collection.delete(where={"document_id": str(document_id)})
