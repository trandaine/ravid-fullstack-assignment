# Specification: Document Management & Vector Storage API

## ADDED Requirements

### Requirement: Document Upload Endpoint (`POST /api/documents/upload/`)

The system shall provide a multipart form-data endpoint allowing authenticated users to upload private knowledge base documents (`.pdf`, `.txt`, `.md`). The endpoint must strictly require JWT Bearer authentication, validate file MIME and size constraints, persist the file to disk partitioned by user identifier, create relational tracking records (`Document`, `IngestionJob`) with UUIDv4 primary identifiers, enqueue an asynchronous Celery ingestion task, and return HTTP `202 Accepted` immediately with standard rate limiting headers.

#### Scenario: Successful document upload and async dispatch
- **GIVEN** an authenticated user with a valid JWT Bearer token
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` with a multipart form-data payload containing a valid 2 MB `.pdf` document in the `file` field
- **THEN** the system validates the file's MIME type against `application/pdf`, `text/plain`, and `text/markdown`
- **AND** persists the file to `uploads/user_{user_id}/<uuid4>_<sanitized_filename>`
- **AND** creates a `Document` record in PostgreSQL with UUID `id`, `owner_id`, `original_name`, `storage_path`, `content_type`, and `size_bytes`
- **AND** creates an `IngestionJob` record with `status=PENDING` linked to the document and user
- **AND** dispatches a background Celery task `ingest_document_task` with the `document_id` (UUID) and `ingestion_job_id`
- **AND** returns HTTP `202 Accepted` with rate-limiting headers (`RateLimit-Limit`, `RateLimit-Remaining`, `RateLimit-Reset`) and payload:
  ```json
  {
    "message": "Document uploaded and ingestion started",
    "document_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "task_id": "c9bf9e57-1685-4c89-bafb-ff5af830be8a"
  }
  ```

#### Scenario: Rejection of unsupported file media types (HTTP 415)
- **GIVEN** an authenticated user with a valid JWT Bearer token
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` containing a file with an unsupported extension or MIME type (e.g. `spreadsheet.xlsx`, `archive.zip`, `image.png`)
- **THEN** the system rejects the file without saving to disk or creating database records
- **AND** returns HTTP `415 Unsupported Media Type` with an RFC 7807 Problem Details payload:
  ```json
  {
    "type": "https://api.ravid.cloud/errors/unsupported-media-type",
    "title": "Unsupported Media Type",
    "status": 415,
    "detail": "Invalid file format. Only PDF, TXT, and Markdown files are allowed.",
    "instance": "/api/documents/upload/",
    "invalid_params": [
      {
        "name": "file",
        "reason": "Unsupported file MIME type or extension. Allowed formats: application/pdf (.pdf), text/plain (.txt), text/markdown (.md)."
      }
    ]
  }
  ```

#### Scenario: Rejection of oversized files exceeding limit (HTTP 413)
- **GIVEN** an authenticated user with a valid JWT Bearer token
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` containing a `.pdf` file with size 15 MB (> 10 MB limit)
- **THEN** the system aborts reading the payload and rejects the request without dispatching background tasks
- **AND** returns HTTP `413 Payload Too Large` with an RFC 7807 Problem Details payload:
  ```json
  {
    "type": "https://api.ravid.cloud/errors/payload-too-large",
    "title": "Payload Too Large",
    "status": 413,
    "detail": "File size exceeds 10 MB limit.",
    "instance": "/api/documents/upload/",
    "invalid_params": [
      {
        "name": "file",
        "reason": "Uploaded file size (15728640 bytes) exceeds the maximum allowed threshold of 10485760 bytes (10 MB)."
      }
    ]
  }
  ```

#### Scenario: Rejection of missing file field or malformed form-data (HTTP 400)
- **GIVEN** an authenticated user with a valid JWT Bearer token
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` with an empty body or missing `file` multipart field
- **THEN** the system returns HTTP `400 Bad Request` with an RFC 7807 Problem Details payload:
  ```json
  {
    "type": "https://api.ravid.cloud/errors/bad-request",
    "title": "Bad Request",
    "status": 400,
    "detail": "No file was submitted in the multipart form-data payload.",
    "instance": "/api/documents/upload/",
    "invalid_params": [
      {
        "name": "file",
        "reason": "The 'file' field is required."
      }
    ]
  }
  ```

#### Scenario: Rejection of unauthenticated upload request (HTTP 401)
- **GIVEN** a client request lacking a valid `Authorization: Bearer <jwt_token>` header or supplying an expired token
- **WHEN** the client sends a `POST` request to `/api/documents/upload/`
- **THEN** the system rejects the request immediately before parsing the multipart payload
- **AND** returns HTTP `401 Unauthorized` with an RFC 7807 Problem Details payload:
  ```json
  {
    "type": "https://api.ravid.cloud/errors/unauthorized",
    "title": "Unauthorized",
    "status": 401,
    "detail": "Authentication credentials were not provided or token is invalid.",
    "instance": "/api/documents/upload/"
  }
  ```

#### Scenario: Rejection of requests exceeding rate limits (HTTP 429)
- **GIVEN** an authenticated user who has exceeded the allowed upload rate limit quota
- **WHEN** the user sends a `POST` request to `/api/documents/upload/`
- **THEN** the system returns HTTP `429 Too Many Requests` with `Retry-After: 60` and standard rate-limiting headers:
  ```json
  {
    "type": "https://api.ravid.cloud/errors/too-many-requests",
    "title": "Too Many Requests",
    "status": 429,
    "detail": "Rate limit exceeded. Please retry after 60 seconds.",
    "instance": "/api/documents/upload/"
  }
  ```

---

### Requirement: Document Ingestion Status Endpoint (`GET /api/documents/status/`)

The system shall provide an endpoint to query the real-time status of an asynchronous document ingestion task using the query parameter `task_id` (UUID format). The endpoint strictly requires JWT Bearer authentication, validates task ownership to prevent IDOR probing, provides polling interval guidance via `Retry-After` headers during processing, and returns strictly typed polymorphic responses discriminated by the `status` field (`PROCESSING`, `SUCCESS`, `FAILURE`).

#### Scenario: Polling status for an active or pending ingestion task (HTTP 200 PROCESSING)
- **GIVEN** an authenticated user who owns an active ingestion job with task UUID `c9bf9e57-1685-4c89-bafb-ff5af830be8a`
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=c9bf9e57-1685-4c89-bafb-ff5af830be8a`
- **AND** the database status is `PENDING` or `STARTED`
- **THEN** the system returns HTTP `200 OK` with response header `Retry-After: 3` and payload matching `IngestionStatusProcessingResponse`:
  ```json
  {
    "task_id": "c9bf9e57-1685-4c89-bafb-ff5af830be8a",
    "status": "PROCESSING"
  }
  ```

#### Scenario: Polling status for a successfully completed ingestion task (HTTP 200 SUCCESS)
- **GIVEN** an authenticated user who owns a completed ingestion job
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=c9bf9e57-1685-4c89-bafb-ff5af830be8a`
- **AND** the Celery background pipeline successfully extracted, chunked, embedded, and indexed all document vectors into Chroma
- **THEN** the database `IngestionJob.status` is `SUCCESS`
- **AND** the system returns HTTP `200 OK` with payload matching `IngestionStatusSuccessResponse`:
  ```json
  {
    "task_id": "c9bf9e57-1685-4c89-bafb-ff5af830be8a",
    "status": "SUCCESS",
    "message": "Document successfully parsed, embedded, and indexed in vector storage."
  }
  ```

#### Scenario: Polling status for a failed ingestion task (HTTP 200 FAILURE)
- **GIVEN** an authenticated user who owns a failed ingestion job
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=c9bf9e57-1685-4c89-bafb-ff5af830be8a`
- **AND** the background task encountered an unrecoverable extraction or indexing failure
- **THEN** the database `IngestionJob.status` is `FAILURE` and `error_message` is recorded
- **AND** the system returns HTTP `200 OK` with payload matching `IngestionStatusFailureResponse`:
  ```json
  {
    "task_id": "c9bf9e57-1685-4c89-bafb-ff5af830be8a",
    "status": "FAILURE",
    "error": "Failed to parse document content."
  }
  ```

#### Scenario: Missing or invalid task_id query parameter (HTTP 400)
- **GIVEN** an authenticated user
- **WHEN** the user sends a `GET` request to `/api/documents/status/` without `task_id` or with a non-UUID string (e.g. `?task_id=invalid-123`)
- **THEN** the system returns HTTP `400 Bad Request` with an RFC 7807 Problem Details payload:
  ```json
  {
    "type": "https://api.ravid.cloud/errors/bad-request",
    "title": "Bad Request",
    "status": 400,
    "detail": "Query parameter 'task_id' must be a valid UUIDv4 string.",
    "instance": "/api/documents/status/",
    "invalid_params": [
      {
        "name": "task_id",
        "reason": "Parameter is missing or does not conform to UUIDv4 format."
      }
    ]
  }
  ```

#### Scenario: Querying non-existent or foreign task ID (HTTP 404)
- **GIVEN** an authenticated user
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=d8cf9e57-1685-4c89-bafb-ff5af830be99`
- **AND** the `task_id` does not exist or belongs to another user
- **THEN** the system returns HTTP `404 Not Found` with an RFC 7807 Problem Details payload (preventing task existence probing):
  ```json
  {
    "type": "https://api.ravid.cloud/errors/not-found",
    "title": "Not Found",
    "status": 404,
    "detail": "Ingestion task not found.",
    "instance": "/api/documents/status/"
  }
  ```

#### Scenario: Unauthenticated status polling request (HTTP 401)
- **GIVEN** an unauthenticated client request lacking valid JWT Bearer credentials
- **WHEN** the client sends a `GET` request to `/api/documents/status/?task_id=c9bf9e57-1685-4c89-bafb-ff5af830be8a`
- **THEN** the system returns HTTP `401 Unauthorized` with an RFC 7807 Problem Details payload:
  ```json
  {
    "type": "https://api.ravid.cloud/errors/unauthorized",
    "title": "Unauthorized",
    "status": 401,
    "detail": "Authentication credentials were not provided or token is invalid.",
    "instance": "/api/documents/status/"
  }
  ```

---

### Requirement: Background Ingestion Pipeline

The background worker shall process uploaded documents asynchronously through a multi-stage pipeline: text extraction, semantic chunking, dense vector embedding calculation, and vector indexing in Chroma under user-isolated namespaces.

#### Scenario: Complete ingestion lifecycle for a PDF document
- **GIVEN** an `IngestionJob` in `PENDING` status for an uploaded PDF file
- **WHEN** the Celery worker executes `ingest_document_task(document_id, ingestion_job_id)`
- **THEN** the worker sets `IngestionJob.status=STARTED`
- **AND** extracts raw text content from the PDF file using `pypdf` / LangChain PDF loaders
- **AND** splits the text into semantic chunks using LangChain `RecursiveCharacterTextSplitter` with `chunk_size=1000` and `chunk_overlap=150`
- **AND** computes 384-dimensional dense embeddings for all chunks via HuggingFace `all-MiniLM-L6-v2`
- **AND** upserts the chunk vectors, page contents, and metadata (`document_id`, `owner_id`, `chunk_index`, `source_name`) into the Chroma collection named `user_{user_id}`
- **AND** updates `IngestionJob.status=SUCCESS` and records `chunk_count` in PostgreSQL

#### Scenario: Ingestion handling for TXT and Markdown files
- **GIVEN** an `IngestionJob` for an uploaded `.txt` or `.md` file
- **WHEN** the Celery worker executes the ingestion task
- **THEN** the worker reads and decodes the file as UTF-8 text
- **AND** executes chunking, embedding, and vector upsert identical to the standard pipeline

#### Scenario: Ingestion failure due to corrupt or unreadable file
- **GIVEN** an `IngestionJob` for a corrupted or unreadable document
- **WHEN** the Celery worker encounters an exception during text extraction or indexing
- **THEN** the worker catches the exception without crashing the worker process
- **AND** updates `IngestionJob.status=FAILURE` and sets `IngestionJob.error_message="Failed to parse document content."`
- **AND** logs the structured error details with `task_id`, `document_id`, and `user_id`
