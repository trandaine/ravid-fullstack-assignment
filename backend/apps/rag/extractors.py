"""Text extraction services for PDF, TXT, and Markdown files."""

from __future__ import annotations

import os


def extract_text(file_path: str, content_type: str = "") -> str:
    """Extract plain text from PDF, TXT, or Markdown files."""
    _, ext = os.path.splitext(file_path)
    ext = ext.lower()
    ct = (content_type or "").lower()

    if "pdf" in ct or ext == ".pdf":
        return _extract_pdf(file_path)

    return _extract_plain_text(file_path)


def _extract_pdf(file_path: str) -> str:
    """Extract text from all pages using pypdf.PdfReader."""
    import pypdf  # noqa: PLC0415

    reader = pypdf.PdfReader(file_path)
    pages: list[str] = []
    for page in reader.pages:
        text = page.extract_text() or ""
        pages.append(text)
    return "\n".join(pages)


def _extract_plain_text(file_path: str) -> str:
    """Read TXT or Markdown file content with UTF-8 encoding."""
    with open(file_path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()
