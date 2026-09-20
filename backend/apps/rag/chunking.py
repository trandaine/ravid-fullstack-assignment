"""Text chunking utilities for RAG ingestion."""

from __future__ import annotations

from django.conf import settings
from langchain_text_splitters import RecursiveCharacterTextSplitter


def split_text_into_chunks(
    text: str,
    chunk_size: int | None = None,
    chunk_overlap: int | None = None,
) -> list[str]:
    """Split text into chunks using RecursiveCharacterTextSplitter."""
    effective_chunk_size = (
        chunk_size if chunk_size is not None else getattr(settings, "CHUNK_SIZE", 1000)
    )
    effective_chunk_overlap = (
        chunk_overlap
        if chunk_overlap is not None
        else getattr(settings, "CHUNK_OVERLAP", 150)
    )

    splitter = RecursiveCharacterTextSplitter(
        chunk_size=effective_chunk_size,
        chunk_overlap=effective_chunk_overlap,
    )
    return splitter.split_text(text)
