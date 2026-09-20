# Specification: Document Management & Vector Storage API

## ADDED Requirements

### Requirement: Document Upload Endpoint (`POST /api/documents/upload/`)

The system shall provide a multipart form-data endpoint allowing authenticated users to upload private knowledge base documents (`.pdf`, `.txt`, `.md`). The endpoint must validate file constraints, persist the file to the media storage path, create relational tracking records (`Document`, `IngestionJob`), enqueue an asynchronous background ingestion task, and return HTTP `202 Accepted` immediately.

#### Scenario: Successful document upload and async dispatch
- **GIVEN** an authenticated user with valid credentials
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` with a valid `file` field containing a 2 MB `.pdf` document
- **THEN** the system persists the file to `uploads/user_{user_id}/<unique_filename>`
- **AND** creates a `Document` record in PostgreSQL with `owner_id`, `original_name`, `storage_path`, `content_type`, and `size_bytes`
- **AND** creates an `IngestionJob` record with `status=PENDING` linked to the user and document
- **AND** dispatches a background Celery task `ingest_document_task` with the `document_id` and `ingestion_job_id`
- **AND** returns HTTP `202 Accepted` with payload:
  ```json
  {
    "message": "Document uploaded and ingestion started",
    "document_id": "<document_id>",
    "task_id": "<task_id>"
  }
  ```

#### Scenario: Rejection of unsupported file extensions
- **GIVEN** an authenticated user
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` containing a file named `spreadsheet.xlsx` or `archive.zip`
- **THEN** the system rejects the file without saving to disk or creating database records
- **AND** returns HTTP `400 Bad Request` with payload:
  ```json
  {
    "error": "Invalid file format. Only PDF, TXT, and Markdown files are allowed."
  }
  ```

#### Scenario: Rejection of files exceeding maximum size limit
- **GIVEN** an authenticated user
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` containing a `.pdf` file with size 15 MB (> 10 MB limit)
- **THEN** the system rejects the file without dispatching background tasks
- **AND** returns HTTP `400 Bad Request` with payload:
  ```json
  {
    "error": "File size exceeds 10 MB limit."
  }
  ```

#### Scenario: Rejection of missing file payload
- **GIVEN** an authenticated user
- **WHEN** the user sends a `POST` request to `/api/documents/upload/` with empty form-data or missing `file` key
- **THEN** the system returns HTTP `400 Bad Request` with payload:
  ```json
  {
    "error": "No file was submitted."
  }
  ```

#### Scenario: Rejection of unauthenticated upload request
- **GIVEN** an unauthenticated client request without valid JWT or Basic Auth headers
- **WHEN** the client sends a `POST` request to `/api/documents/upload/`
- **THEN** the system returns HTTP `401 Unauthorized` with payload:
  ```json
  {
    "error": "Authentication credentials were not provided."
  }
  ```

---

### Requirement: Document Ingestion Status Endpoint (`GET /api/documents/status/`)

The system shall provide an endpoint to query the real-time status of an asynchronous document ingestion pipeline by `task_id`. The response must expose only standardized high-level states: `PROCESSING`, `SUCCESS`, and `FAILURE`.

#### Scenario: Polling status for an active or pending ingestion task
- **GIVEN** an authenticated user who owns a valid `task_id` for an ongoing ingestion job
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=<task_id>`
- **AND** the database status is `PENDING` or `STARTED`
- **THEN** the system returns HTTP `200 OK` with payload:
  ```json
  {
    "task_id": "<task_id>",
    "status": "PROCESSING"
  }
  ```

#### Scenario: Polling status for a successfully completed ingestion task
- **GIVEN** an authenticated user who owns a valid `task_id`
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=<task_id>`
- **AND** the background ingestion pipeline completed extraction, chunking, embedding, and vector indexing
- **THEN** the database `IngestionJob.status` is `SUCCESS`
- **AND** the system returns HTTP `200 OK` with payload:
  ```json
  {
    "task_id": "<task_id>",
    "status": "SUCCESS",
    "message": "Document successfully parsed, embedded, and indexed in vector storage."
  }
  ```

#### Scenario: Polling status for a failed ingestion task
- **GIVEN** an authenticated user who owns a valid `task_id`
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=<task_id>`
- **AND** the background task encountered an unrecoverable extraction or indexing failure
- **THEN** the database `IngestionJob.status` is `FAILURE` and `error_message` is populated
- **AND** the system returns HTTP `200 OK` with payload:
  ```json
  {
    "task_id": "<task_id>",
    "status": "FAILURE",
    "error": "Failed to parse document content."
  }
  ```

#### Scenario: Missing required query parameter
- **GIVEN** an authenticated user
- **WHEN** the user sends a `GET` request to `/api/documents/status/` without the `task_id` query parameter
- **THEN** the system returns HTTP `400 Bad Request` with payload:
  ```json
  {
    "error": "Query parameter 'task_id' is required."
  }
  ```

#### Scenario: Querying non-existent or foreign task ID
- **GIVEN** an authenticated user
- **WHEN** the user sends a `GET` request to `/api/documents/status/?task_id=<foreign_or_invalid_task_id>`
- **AND** the `task_id` either does not exist or belongs to another user
- **THEN** the system returns HTTP `404 Not Found` with payload:
  ```json
  {
    "error": "Ingestion task not found."
  }
  ```

---

### Requirement: Background Ingestion Pipeline

The background worker shall process uploaded documents asynchronously through a multi-stage pipeline: text extraction, semantic chunking, dense vector embedding calculation, and vector indexing in Chroma under user-isolated namespaces.

#### Scenario: Complete ingestion lifecycle for a PDF document
- **GIVEN** an `IngestionJob` in `PENDING` status for an uploaded PDF file
- **WHEN** the Celery worker executes the ingestion task
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
- **GIVEN** an `IngestionJob` for a corrupted or password-protected PDF file
- **WHEN** the Celery worker fails during text extraction
- **THEN** the worker catches the exception without crashing the worker process
- **AND** updates `IngestionJob.status=FAILURE` and sets `IngestionJob.error_message="Failed to parse document content."`
- **AND** logs the structured error details with `task_id`, `document_id`, and `user_id`
