# Software Requirements Specification

## Purpose

This document defines the formal Software Requirements Specification (SRS) for the R.A.V.I.D. Fullstack RAG Chatbot system, comprising the Django backend API and the Flutter mobile client. Functional requirements use RFC 2119 "shall" statements. Each requirement maps directly to the technical objectives in the assessment brief.

## System Overview

The system provides a personal knowledge base chatbot platform:
- **Backend**: Django REST Framework API with asynchronous Celery workers, Redis queue, PostgreSQL database, Chroma vector database, and OpenRouter LLM gateway.
- **Mobile**: Flutter client featuring secure authentication, document management, interactive chat thread interface, local SQLite/Hive caching for offline access, and thread management.

---

## Functional Requirements — Backend API

### FR-1 User Registration

- The system shall expose `POST /api/register/`.
- The endpoint shall accept a JSON body containing `email` and `password` (multipart form-data is also supported).
- The endpoint shall validate that the email is unique and that the password meets security requirements.
- On success the endpoint shall return `201 Created` with `{ "message": "User registered successfully", "user_id": "<user_id>" }`.
- On validation failure the endpoint shall return `400 Bad Request` with the error envelope `{ "error": "<message>" }`.

### FR-2 User Login

- The system shall expose `POST /api/login/`.
- The endpoint shall accept a JSON body with `email` and `password`.
- The endpoint shall support both HTTP Basic Auth header decoding and JSON payload authentication.
- On success the endpoint shall return `200 OK` with `{ "message": "Login successful", "token": "<jwt_access_token>" }`.
- On authentication failure the endpoint shall return `401 Unauthorized` with `{ "error": "Invalid email or password" }`.

### FR-2b Current User Identity

- The system shall expose `GET /api/auth/me/`.
- The endpoint shall require authentication (`Authorization: Bearer <token>` or HTTP Basic Auth).
- On success the endpoint shall return `200 OK` with `{ "user_id": <int>, "email": "<email>" }`.
- Missing or invalid credentials shall return `401 Unauthorized`.

### FR-3 Route Protection & Per-User Isolation

- The system shall require valid authentication for all document management and chat endpoints.
- Registration (`/api/register/`) and login (`/api/login/`) shall remain public.
- The system shall enforce owner-scoping on all resource access: querying, listing, or deleting resources owned by another user shall return `404 Not Found` (never `403 Forbidden`) to avoid leaking existence.
- Every error response across all endpoints shall adhere strictly to the JSON envelope format `{ "error": "<message>" }`.

### FR-4 Document Upload

- The system shall expose `POST /api/documents/upload/`.
- The endpoint shall accept `multipart/form-data` with a `file` field.
- The endpoint shall validate the uploaded file format against allowed extensions: `.pdf`, `.txt`, and `.md`.
- The endpoint shall reject disallowed file formats with `400 Bad Request` and `{ "error": "Invalid file format. Only PDF, TXT, and Markdown files are allowed." }`.
- The endpoint shall reject files exceeding 10 MB with `400 Bad Request` and `{ "error": "File size exceeds 10 MB limit." }`.
- The endpoint shall persist the uploaded file on the storage volume under `uploads/user_{user_id}/`.
- The endpoint shall create a `Document` record and an `IngestionJob` record tied to the authenticated user.
- The endpoint shall enqueue an asynchronous Celery task and return `202 Accepted` with:
  ```json
  {
    "message": "Document uploaded and ingestion started",
    "document_id": "<document_id>",
    "task_id": "<task_id>"
  }
  ```

### FR-4b Document Listing

- The system shall expose `GET /api/documents/`.
- The endpoint shall require authentication and return `200 OK` with an array of documents owned strictly by the authenticated user.

### FR-4c Document Deletion

- The system shall expose `DELETE /api/documents/<id>/`.
- The endpoint shall require authentication and delete the document record, stored file bytes, and corresponding chunk vectors in Chroma.
- On success the endpoint shall return `204 No Content`.
- Accessing a document ID belonging to another user shall return `404 Not Found`.

### FR-5 Ingestion Task Status

- The system shall expose `GET /api/documents/status/`.
- The endpoint shall accept the query parameter `task_id`.
- While the background task executes, the endpoint shall return `200 OK` with:
  ```json
  {
    "task_id": "<task_id>",
    "status": "PROCESSING"
  }
  ```
- On successful pipeline completion, the endpoint shall return `200 OK` with:
  ```json
  {
    "task_id": "<task_id>",
    "status": "SUCCESS",
    "message": "Document successfully parsed, embedded, and indexed in vector storage."
  }
  ```
- On pipeline failure, the endpoint shall return `200 OK` with:
  ```json
  {
    "task_id": "<task_id>",
    "status": "FAILURE",
    "error": "<description_of_failure>"
  }
  ```
- The public status values shall strictly be `PROCESSING`, `SUCCESS`, and `FAILURE`.
- Internal Celery states `PENDING`, `STARTED`, and `RETRY` shall map to `PROCESSING`.
- The endpoint shall return `404 Not Found` if `task_id` does not exist or does not belong to the requesting user.

### FR-6 Text Extraction Pipeline

- The background worker shall extract raw text based on MIME/file type:
  - PDF: parsed via `pypdf` or LangChain `PyPDFLoader`
  - TXT / Markdown: decoded as UTF-8 text via LangChain `TextLoader`
- Any extraction failure shall update the `IngestionJob` status to `FAILURE` with descriptive `error_message` and emit a structured log.

### FR-7 Chunking

- The background pipeline shall split extracted text using LangChain's `RecursiveCharacterTextSplitter`.
- The chunker shall use standard parameters: `chunk_size = 1000` and `chunk_overlap = 150`.
- Each generated chunk shall retain metadata: `document_id`, `owner_id`, `chunk_index`, and `source_name`.

### FR-8 Embedding Generation

- The pipeline shall compute dense vector embeddings using the open-source HuggingFace `all-MiniLM-L6-v2` model (384 dimensions) via `langchain-huggingface`.
- The embedding model shall run locally in-process without requiring external paid API keys.

### FR-9 Isolated Vector Storage

- The pipeline shall store chunk vectors in Chroma vector database.
- The system shall maintain dedicated, isolated collections per user using the namespace convention `user_{user_id}`.
- Vectors belonging to User A shall never be inserted into or queryable from User B's collection.

### FR-10 Owner-Scoped Retrieval

- The retrieval engine shall query Chroma vector store using cosine similarity restricted to collection `user_{user_id}`.
- The default retrieval parameter shall return the top `k = 4` most relevant chunks.

### FR-11 Standard RAG Chat Query

- The system shall expose `POST /api/chat/query/`.
- The endpoint shall accept a JSON body containing `query` (string) and optional `message_histories` (array of prior messages).
- The pipeline shall:
  1. Embed the query vector using the local embedding model.
  2. Retrieve the top `k` chunks from the authenticated user's Chroma collection.
  3. Construct a grounded context prompt injecting retrieved chunks and recent conversation history.
  4. Call OpenRouter LLM (`https://openrouter.ai/api/v1/chat/completions`) using a free-tier model.
- On success the endpoint shall return `200 OK` with:
  ```json
  {
    "answer": "<generated_assistant_response>"
  }
  ```

### FR-12 Advanced Retrieval via HyDE (Bonus)

- The `POST /api/chat/query/` endpoint shall support an optional boolean flag `"use_hyde": true` in the request payload.
- When `use_hyde` is `true`, the retrieval pipeline shall execute the Hypothetical Document Embeddings workflow:
  1. **Hypothetical Generation:** Prompt the OpenRouter LLM with a zero-shot prompt to draft a hypothetical, ideal passage answering the user query.
  2. **Hypothetical Embedding:** Compute the vector embedding of the generated hypothetical passage instead of the raw short query.
  3. **Enhanced Vector Search:** Use the hypothetical vector to retrieve top chunks from the user's isolated collection `user_{user_id}`.
  4. **Grounded Synthesis:** Pass the retrieved source chunks and the original user query to the final LLM to generate the verified answer.
- **Fallback Rule:** If hypothetical passage generation fails or times out, the pipeline shall automatically fall back to standard raw query retrieval without returning an error to the client.

### FR-13 No-Relevant-Context Guard

- When vector retrieval returns no chunks or similarity scores fall below the relevance threshold, the system shall return a grounded refusal stating that the user's uploaded documents do not contain sufficient information to answer the question.
- The system shall not hallucinate or answer from parametric memory when knowledge base context is absent.

### FR-14 LLM Gateway Integration

- The backend shall route all completion requests to OpenRouter (`https://openrouter.ai/api/v1`).
- The system shall use free-tier models (such as `google/gemma-2-9b-it:free`, `mistralai/mistral-7b-instruct:free`, or `openchat/openchat-7b:free`).
- The OpenRouter API key shall be loaded securely from environment variable `OPENROUTER_API_KEY` and never exposed in logs or client payloads.

---

## Functional Requirements — Flutter Mobile Client

### FR-15 Authentication & Session Management

- The mobile app shall provide a clean Login Screen with Username/Email and Password input fields with real-time validation (non-empty, minimum length).
- The app shall authenticate against the backend API via HTTP Basic Auth or JWT tokens.
- The app shall securely store auth tokens/credentials using platform secure storage (`flutter_secure_storage` backed by iOS Keychain and Android Keystore/EncryptedSharedPreferences).
- The app shall perform auto-login on app launch when valid stored credentials exist.
- The app shall provide a logout action that clears secure storage and navigates to the Login Screen.

### FR-16 Document Management UI

- The mobile app shall provide a dedicated Document Management Screen allowing users to:
  - Pick files from device storage (`.pdf`, `.txt`, `.md`).
  - Trigger upload to `POST /api/documents/upload/`.
  - Display live ingestion status indicators (`PROCESSING` spinner, `SUCCESS` badge, `FAILURE` banner with error details).
  - List existing uploaded documents with file metadata (name, size, upload date).

### FR-17 Interactive Chat Interface

- The mobile app shall provide a responsive Chat Screen:
  - Distinct UI bubbles for user messages (aligned right, primary color) and assistant responses (aligned left, secondary container).
  - Floating/fixed bottom input bar with multiline text editing, send button, and clear state.
  - Real-time message status indicators: `Sending` (clock/spinner), `Delivered` (check icon), `Failed` (alert icon with retry tap target).
  - Automatic scrolling to the newest message upon receiving a response or sending.
  - HyDE toggle switch in the app bar or input settings enabling advanced retrieval mode.

### FR-18 Local Chat History & Multi-Thread Management (Bonus)

- The mobile app shall support multi-thread conversations persisted locally (via SQLite `sqflite` or Hive):
  - **Thread Schema:** `id` (UUID), `title` (auto-generated from first message or default), `created_at`, `updated_at`.
  - **Message Schema:** `id` (UUID), `thread_id` (foreign key), `sender` (`user` | `assistant`), `content`, `timestamp`, `status` (`sending` | `delivered` | `failed`).
- **Conversation Drawer / Sidebar:** A navigable drawer listing all historical chat sessions ordered by `updated_at DESC`.
- **New Chat Action:** A persistent action to initiate a fresh thread at any time.
- **Thread Deletion:** Capability to delete a thread (with cascade deletion of its messages) via swipe-to-dismiss or long-press modal.
- **Offline Reading:** Past chat threads and messages shall load instantly from local storage without network latency.
- **Context Injection:** When sending a message, the app shall inject the last `N` messages (default `N = 6`) from the active local thread into the `message_histories` request payload.

---

## Non-Functional Requirements

### NFR-1 Reliability & Async Decoupling

- Document ingestion shall never block the HTTP request-response cycle; all heavy parsing and embedding shall run inside Celery workers.
- The backend shall recover gracefully from temporary OpenRouter API rate limits or network drops.

### NFR-2 Per-User Isolation & Security

- Storage directories (`uploads/user_{user_id}/`) and Chroma collections (`user_{user_id}`) shall strictly isolate user data.
- API endpoints shall reject unauthenticated requests with `401 Unauthorized` and cross-tenant requests with `404 Not Found`.
- Mobile client credentials shall never be stored in plaintext `SharedPreferences` or unencrypted files.

### NFR-3 Performance & Latency

- Document upload API response time shall be under 500 ms (acknowledging upload and returning `task_id`).
- Local embedding generation and Chroma vector retrieval shall complete in under 300 ms.
- Mobile chat list scrolling shall maintain 60 FPS without UI jank.

### NFR-4 Portability & Packaging

- The complete backend stack shall be runnable via standard `docker compose up --build`.
- The Flutter mobile project shall build cleanly for Android (APK) and iOS without proprietary dependencies.

### NFR-5 Observability

- Backend services (Django and Celery) shall output structured JSON logs with contextual fields (`service`, `task_id`, `user_id`, `endpoint`, `duration_ms`).
- Sensitive data (passwords, JWT tokens, OpenRouter API keys, raw document content) shall never appear in logs.

---

## Technical Baseline

| Component | Technology | Version / Choice |
|---|---|---|
| Backend Framework | Python / Django REST Framework | Python 3.12, Django 5.x |
| Database | PostgreSQL | 16-alpine |
| Task Queue & Broker | Celery + Redis | Celery 5.x, Redis 7-alpine |
| Vector Store | Chroma | Latest standalone / in-memory |
| RAG Framework | LangChain | `langchain`, `langchain-community`, `langchain-huggingface` |
| Embedding Model | HuggingFace | `sentence-transformers/all-MiniLM-L6-v2` (384 dims, local) |
| LLM Gateway | OpenRouter | `https://openrouter.ai/api/v1` (Free-tier models) |
| Mobile Framework | Flutter | Flutter 3.x / Dart 3.x |
| Mobile Secure Store | `flutter_secure_storage` | Keychain (iOS) & Keystore (Android) |
| Mobile Local Database | `sqflite` / `hive` | Local relational / key-value storage |
| Containerization | Docker & Docker Compose | Compose v2 |

---

## Known Ambiguities And Current Defaults

1. **Authentication Mode:** The brief mentions HTTP Basic Auth for mobile and JWT for bonus. The backend implements DRF SimpleJWT with HTTP Basic Auth compatibility so both login styles function seamlessly.
2. **Context Injection Count:** The mobile client injects the last 6 messages (`3 user + 3 assistant turns`) into `message_histories` to balance prompt budget and conversational coherence.
3. **HyDE Fallback:** If hypothetical passage generation fails (e.g. rate limit), the pipeline automatically falls back to raw query embedding without raising an unhandled exception.
