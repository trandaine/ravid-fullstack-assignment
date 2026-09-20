# System Context

## Objective

Describe the runtime topology, component responsibilities, and interaction protocols across the fullstack R.A.V.I.D. RAG Chatbot system (Django backend, Celery async pipeline, Chroma vector database, OpenRouter gateway, and Flutter mobile application).

## Primary Actors

- **Mobile User:** registers, authenticates, uploads private documents (`.pdf`, `.txt`, `.md`), tracks ingestion status, and chats against their personal knowledge base with standard RAG or HyDE retrieval.
- **Reviewer:** boots the Docker Compose stack locally, verifies backend endpoints via Swagger UI / curl, inspects the Flutter mobile app on simulator or physical device, and reviews code and architecture.

## Core Runtime Components

```
   ┌─────────────────────────────────────────────────────────┐
   │                  Flutter Mobile Client                  │
   │  - Auth (Secure Storage)   - Doc Management UI          │
   │  - Chat Screen + Bubbles   - Local Multi-Thread Cache   │
   └────────────────────────────┬────────────────────────────┘
                                │ HTTP / JSON (JWT or Basic Auth)
                                ▼
   ┌─────────────────────────────────────────────────────────┐
   │                Django + DRF (Port 8000)                 │
   │  /api/register/            /api/login/                  │
   │  /api/auth/me/             /api/documents/upload/       │
   │  /api/documents/           /api/documents/<id>/         │
   │  /api/documents/status/    /api/chat/query/ (RAG/HyDE)  │
   │  /api/schema/              /api/docs/ (Swagger UI)      │
   └──────────────┬──────────────────┬──────────────────────┘
                  │                  │
      enqueue     │    read/write    │   OpenAI-compatible
      Celery task │    PostgreSQL    │   chat/completions
                  ▼                  ▼
         ┌──────────────┐    ┌──────────────────┐
         │ Redis broker │    │   OpenRouter LLM │
         └──────┬───────┘    │   (Free tier)    │
                ▼            └──────────────────┘
         ┌──────────────────────────────────────┐
         │  Celery Worker                       │
         │  extract → chunk → embed → upsert    │
         └──────────────┬───────────────────────┘
                        │ user_{user_id} collection
                        ▼
                 ┌──────────────┐
                 │ Chroma DB    │ ← HuggingFace all-MiniLM-L6-v2
                 └──────────────┘
```

### Flutter Mobile Application

Responsibilities:
- Provide intuitive UI for registration, login, document upload, and conversational chat.
- Store authentication tokens and user credentials securely via `flutter_secure_storage` (iOS Keychain, Android Keystore).
- Maintain local thread and message state in SQLite/Hive for instant startup and offline review.
- Inject recent conversation turns (`message_histories`) into chat queries to preserve dialogue context.
- Provide toggle for advanced HyDE retrieval mode.

### Django API Service

Responsibilities:
- Expose all REST endpoints (`/api/register/`, `/api/login/`, `/api/auth/me/`, `/api/documents/upload/`, `/api/documents/`, `/api/documents/<id>/`, `/api/documents/status/`, `/api/chat/query/`, `/api/schema/`, `/api/docs/`).
- Validate request payloads and enforce file upload constraints (.pdf/.txt/.md, max 10 MB).
- Authenticate requests via JWT (`djangorestframework-simplejwt`) or HTTP Basic Auth.
- Persist user accounts and document metadata in PostgreSQL.
- Save uploaded files to the shared media volume (`uploads/user_{user_id}/`).
- Enqueue asynchronous ingestion tasks to Celery via Redis.
- Orchestrate RAG and HyDE query pipelines: embed query/hypothetical passage, query user collection in Chroma, assemble context prompt, and invoke OpenRouter LLM.

### PostgreSQL

Responsibilities:
- Serve as the relational system of record.
- Store user authentication credentials and profiles.
- Store document metadata (ID, owner FK, original filename, storage path, content type, size, upload timestamp).
- Store `IngestionJob` tracking records (ID, owner FK, source document FK, celery task ID, status, chunk count, error message, timestamps).

### Redis

Responsibilities:
- Act as the distributed message broker for Celery ingestion tasks.
- Store Celery result backend states.

### Celery Worker

Responsibilities:
- Execute document ingestion asynchronously off the HTTP thread.
- Extract text from PDF, TXT, and Markdown files using LangChain loaders and `pypdf`.
- Split text using `RecursiveCharacterTextSplitter` (`chunk_size=1000`, `chunk_overlap=150`).
- Generate 384-dimensional dense embeddings using local HuggingFace `all-MiniLM-L6-v2`.
- Upsert chunks and metadata into the user's isolated Chroma collection (`user_{user_id}`).
- Update `IngestionJob` status to `SUCCESS` or `FAILURE` in PostgreSQL and emit structured logs.

### Chroma Vector Store

Responsibilities:
- Persist vector embeddings and chunk metadata on a named Docker volume.
- Maintain strict per-user isolation through dedicated collections (`user_{user_id}`).
- Execute fast cosine similarity vector search scoped to the authenticated caller's collection (`top_k=4`).

### Local Embedding Model

Responsibilities:
- Run in-process in both Django API (for query embeddings) and Celery worker (for chunk embeddings).
- Utilize HuggingFace `all-MiniLM-L6-v2` (384 dimensions) completely offline without external API keys.

### OpenRouter LLM Gateway

Responsibilities:
- Serve as the OpenAI-compatible gateway (`https://openrouter.ai/api/v1/chat/completions`) for LLM inference.
- Support zero-shot hypothetical answer generation for HyDE retrieval.
- Synthesize final grounded answers from retrieved document chunks and user prompts.

---

## Main Interaction Flows

### 1. Authentication Flow

1. Mobile client posts credentials to `POST /api/login/` (or sends Basic Auth).
2. Django validates credentials against PostgreSQL and returns a JWT access token.
3. Mobile client persists the token securely in Keychain/Keystore via `flutter_secure_storage`.
4. Subsequent mobile requests include `Authorization: Bearer <token>` in the header.

### 2. Document Upload and Ingestion Flow

1. User selects a `.pdf`, `.txt`, or `.md` file on the mobile app.
2. Mobile client posts multipart form-data to `POST /api/documents/upload/`.
3. Django validates file type and size (<= 10 MB), writes file to `uploads/user_{user_id}/`, creates `Document` and `IngestionJob` rows, and enqueues a Celery task.
4. Django returns `202 Accepted` with `document_id` and `task_id`.
5. Mobile app initiates polling on `GET /api/documents/status/?task_id=<task_id>`.
6. Celery worker extracts text, chunks into 1000-character segments (150 overlap), computes MiniLM embeddings, and upserts vectors into collection `user_{user_id}`.
7. Celery worker updates `IngestionJob` status to `SUCCESS`. Polling returns `SUCCESS` and mobile UI updates to show an indexed badge.

### 3. Standard RAG Chat Query Flow

1. User enters a question in the mobile chat screen.
2. Mobile client creates a local `Message(status: sending)` and posts `{ "query": "...", "message_histories": [...] }` to `POST /api/chat/query/`.
3. Django embeds the query using local MiniLM.
4. Django retrieves top `k=4` chunks from Chroma collection `user_{user_id}` using cosine similarity.
5. Django constructs a system prompt containing retrieved context, message history, and user query.
6. Django calls OpenRouter LLM (`/chat/completions`).
7. Django returns `200 OK` with `{ "answer": "..." }`.
8. Mobile client updates local message status to `delivered` and persists the assistant response.

### 4. Advanced HyDE Chat Query Flow (`use_hyde: true`)

1. User sends a query with HyDE enabled in the mobile interface.
2. Mobile client sends `{ "query": "...", "use_hyde": true, "message_histories": [...] }` to `POST /api/chat/query/`.
3. **HyDE Generation:** Django calls OpenRouter LLM with a zero-shot prompt: *"Please write a concise hypothetical passage that directly answers the following question: <query>"*.
4. **HyDE Embedding:** Django embeds the generated hypothetical passage with MiniLM instead of the raw query.
5. **HyDE Retrieval:** Django queries Chroma collection `user_{user_id}` with the hypothetical embedding to fetch top `k=4` chunks.
6. **Grounded Synthesis:** Django sends the retrieved source chunks and original user query to OpenRouter LLM to produce the verified answer.
7. **HyDE Fallback:** If the hypothetical generation fails (e.g. timeout), the pipeline gracefully falls back to raw query embedding without client-visible error.

---

## Failure Scenarios & Mitigations

| Failure Scenario | Mitigation |
|---|---|
| Corrupted or unparseable uploaded file | Celery worker catches parsing exception, sets `IngestionJob.status=FAILURE`, populates `error_message`, and logs error context. Status endpoint returns `FAILURE`. |
| OpenRouter LLM API rate limit or outage | RAG service implements retry logic with exponential backoff; returns `{ "error": "LLM service temporarily unavailable" }` on exhaustion. |
| Cross-tenant resource access attempt | Django queries filter strictly by `owner=request.user`; non-existent or foreign resources return `404 Not Found`. |
| Mobile device goes offline | Local chat messages and threads remain fully browsable in SQLite/Hive; failed outbound messages show retry icon. |
| HyDE generation failure | Catch LLM error during hypothetical generation and fall back to standard raw query embedding. |
