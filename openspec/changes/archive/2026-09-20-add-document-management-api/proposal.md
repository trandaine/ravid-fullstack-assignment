# Proposal: Document Management & Vector Storage API

## Problem Statement

Users require a mechanism to build a private knowledge base by uploading personal documents (`.pdf`, `.txt`, `.md`). Ingesting documents for Retrieval-Augmented Generation (RAG) involves computationally intensive operations: raw text extraction, semantic chunking, dense vector embedding calculation, and vector database indexing. Executing these operations synchronously within the HTTP request-response lifecycle degrades API responsiveness, introduces gateway timeouts for multi-page documents, and blocks web server threads.

The system must provide an asynchronous ingestion architecture where document upload immediately returns an ingestion task identifier, allowing clients to poll task status while background workers handle extraction, chunking, embedding, and isolated vector storage.

## User Value

- **Immediate Acknowledgment**: Clients receive an immediate `202 Accepted` response with a `task_id` upon file upload without waiting for parsing or embedding generation.
- **Deterministic Status Tracking**: Clients query a single status endpoint to monitor ingestion lifecycle transitions across `PROCESSING`, `SUCCESS`, and `FAILURE` states.
- **Data Isolation**: Chunks and embeddings are partitioned into dedicated, user-scoped vector namespaces, ensuring that a user's private documents are never queryable by or leaked to other users.

## Scope Boundaries

### Goals

- Implement `POST /api/documents/upload/` to accept `.pdf`, `.txt`, and `.md` files up to 10 MB, store binary payloads to disk, create relational tracking records, and dispatch asynchronous ingestion tasks.
- Implement `GET /api/documents/status/` to return real-time ingestion state (`PROCESSING`, `SUCCESS`, `FAILURE`) for a given `task_id`.
- Implement background Celery ingestion pipeline:
  - Text extraction from PDF (`pypdf`/LangChain loaders), TXT, and Markdown files.
  - Text chunking using LangChain `RecursiveCharacterTextSplitter` with `chunk_size=1000` and `chunk_overlap=150`.
  - Dense embedding generation using local HuggingFace `all-MiniLM-L6-v2` (384 dimensions).
  - Vector storage and indexing in Chroma using per-user isolated collections (`user_{user_id}`).
- Enforce strict authentication and owner-scoping across all document operations.

### Non-Goals

- RAG query execution and LLM answer synthesis (`POST /api/chat/query/`), covered in Part 1.2.
- Hypothetical Document Embeddings (HyDE) retrieval pipelines, covered in Part 1.3.
- Mobile client UI components, file pickers, or polling handlers, covered in Part 2.
- Document listing (`GET /api/documents/`) and deletion (`DELETE /api/documents/<id>/`) endpoints.
- Support for file formats beyond PDF, TXT, and Markdown (e.g., DOCX, HTML, EPUB, images/OCR).
