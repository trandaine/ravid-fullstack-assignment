# Implementation Tasks: Document Management & Vector Storage API

## Phase 1: Environment & Project Setup

- [ ] 1.1 Initialize Django backend project structure under `backend/` with modular settings (`config/settings/base.py`, `local.py`, `test.py`).
- [ ] 1.2 Configure Celery application instance in `backend/config/celery.py` with Redis broker settings.
- [ ] 1.3 Add dependencies to `requirements.txt` / `pyproject.toml` (`django`, `djangorestframework`, `djangorestframework-simplejwt`, `celery`, `redis`, `psycopg2-binary`, `langchain`, `langchain-community`, `langchain-huggingface`, `sentence-transformers`, `chromadb`, `pypdf`).
- [ ] 1.4 Create shared error envelope handler and response helpers in `backend/apps/common/`.

## Phase 2: Data Models & Persistence

- [ ] 2.1 Create `backend/apps/documents/` Django app and define the `Document` model with user foreign key, file metadata, and storage path fields.
- [ ] 2.2 Create `backend/apps/rag/` Django app and define the `IngestionJob` model with `celery_task_id`, `status` choices, `chunk_count`, and `error_message`.
- [ ] 2.3 Generate and apply initial database migrations for `apps/documents` and `apps/rag`.

## Phase 3: File Upload Endpoint (`POST /api/documents/upload/`)

- [ ] 3.1 Implement file validators in `backend/apps/documents/validators.py` to enforce allowed extensions (`.pdf`, `.txt`, `.md`) and size limit (<= 10 MB).
- [ ] 3.2 Implement `DocumentUploadSerializer` in `backend/apps/documents/serializers.py` to validate incoming multipart form-data.
- [ ] 3.3 Implement `DocumentUploadView` in `backend/apps/documents/views.py`:
  - Enforce authentication.
  - Save file to `MEDIA_ROOT/uploads/user_{user_id}/`.
  - Create `Document` and `IngestionJob` records in a database transaction.
  - Enqueue `ingest_document_task` to Celery with `task_id`.
  - Return HTTP `202 Accepted` with `document_id` and `task_id`.
- [ ] 3.4 Wire route `POST /api/documents/upload/` into `backend/apps/documents/urls.py` and central `config/urls.py`.

## Phase 4: Celery Ingestion Pipeline & Vector Store

- [ ] 4.1 Implement Chroma vector store service wrapper in `backend/apps/rag/vectorstore.py` to manage isolated collections per user (`user_{user_id}`).
- [ ] 4.2 Configure local HuggingFace embeddings (`all-MiniLM-L6-v2`) in `backend/apps/rag/embeddings.py`.
- [ ] 4.3 Implement text extraction service in `backend/apps/rag/extractors.py` supporting PDF (`pypdf`), TXT, and Markdown files.
- [ ] 4.4 Implement text chunking service in `backend/apps/rag/chunking.py` using `RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=150)`.
- [ ] 4.5 Implement Celery task `ingest_document_task` in `backend/apps/rag/tasks.py` orchestrating extraction, chunking, embedding, vector upsert, and updating `IngestionJob` state.

## Phase 5: Status Polling Endpoint (`GET /api/documents/status/`)

- [ ] 5.1 Implement `IngestionStatusView` in `backend/apps/rag/views.py`:
  - Validate presence of `task_id` query parameter.
  - Query `IngestionJob` scoped to `owner=request.user` and `celery_task_id=task_id`.
  - Map internal states (`PENDING`, `STARTED` -> `PROCESSING`; `SUCCESS` -> `SUCCESS`; `FAILURE` -> `FAILURE`).
  - Return standardized JSON response payloads matching the API specification.
- [ ] 5.2 Wire route `GET /api/documents/status/` into `backend/apps/rag/urls.py` and central `config/urls.py`.

## Phase 6: Automated Testing & Verification

- [ ] 6.1 Write unit tests for file validation rules (invalid format, oversized file, missing payload).
- [ ] 6.2 Write integration tests for `POST /api/documents/upload/` verifying 202 response, file storage, database records, and Celery task dispatch.
- [ ] 6.3 Write integration tests for `GET /api/documents/status/` verifying `PROCESSING`, `SUCCESS`, and `FAILURE` response formats, as well as 404 on foreign/invalid `task_id`.
- [ ] 6.4 Write unit tests for the ingestion pipeline verifying PDF/TXT text extraction, chunking counts, and Chroma collection namespace isolation.
