# RAVID — Fullstack RAG Document Chatbot (Backend + Mobile)

![Python](https://img.shields.io/badge/python-3.12-blue)
![Django](https://img.shields.io/badge/Django-5.x-092E20)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B)
![Celery](https://img.shields.io/badge/Celery-5.x-green)
![Chroma](https://img.shields.io/badge/Chroma-latest-red)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow)](LICENSE)

RAVID is a fullstack Retrieval-Augmented Generation (RAG) document chatbot platform composed of a Django REST Framework backend and a cross-platform Flutter mobile client. Authenticated users upload private documents (`.pdf`, `.txt`, `.md`), which are asynchronously parsed, chunked, embedded, and indexed into isolated per-user vector namespaces. Users can query their personal knowledge base through a mobile chat interface powered by standard RAG or advanced **HyDE** (Hypothetical Document Embeddings) retrieval.

---

## Tech Stack

| Layer | Choice |
|---|---|
| Backend Web Framework | Django 5.x + Django REST Framework |
| Authentication | `djangorestframework-simplejwt` + HTTP Basic Auth |
| Async Task Processing | Celery 5.x with Redis broker & result backend |
| Relational Storage | PostgreSQL 16 (users, documents, ingestion jobs) |
| Vector Database | Chroma vector store, isolated collections (`user_{user_id}`) |
| RAG Framework | LangChain (`RecursiveCharacterTextSplitter`, document loaders) |
| Embeddings | Local HuggingFace `all-MiniLM-L6-v2` (384 dims, offline, free) |
| LLM Gateway | OpenRouter (`https://openrouter.ai/api/v1`) with free-tier models |
| API Documentation | OpenAPI 3.0.3 + Swagger UI at `/api/docs/` |
| Mobile Framework | Flutter 3.x / Dart 3.x (iOS & Android) |
| Mobile Architecture | Clean Architecture with BLoC State Management |
| Mobile Secure Storage | `flutter_secure_storage` (iOS Keychain, Android Keystore) |
| Mobile Local Database | SQLite (`sqflite`) / Hive for local multi-thread persistence |
| Containerization | Docker & Docker Compose |

---

## Per-User Isolation Guarantee

Per-user isolation is enforced at every tier of the system:

- **Vector Collections:** Every user gets a dedicated Chroma collection `user_{user_id}`. Ingestion and retrieval queries strictly operate on the caller's collection.
- **Relational Ownership:** Documents and ingestion tasks are scoped by foreign keys to the authenticated user.
- **Access Control:** Accessing or querying resources belonging to another user returns **HTTP 404** (never 403) to prevent resource existence disclosure.
- **Error Consistency:** All API error responses follow the standardized envelope `{ "error": "<message>" }`.

---

## System Architecture

```
   ┌─────────────────────────────────────────────────────────┐
   │                  Flutter Mobile Client                  │
   │  - Auth & Secure Storage   - Doc Management Screen      │
   │  - Chat Bubbles + Status   - Local Multi-Thread Cache   │
   │  - HyDE Mode Toggle        - Offline Reading            │
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

---

## Quickstart (Reviewer Path)

### 1. Boot Backend with Docker Compose

**Prerequisites:** Docker + Docker Compose, an [OpenRouter](https://openrouter.ai/) free API key.

```bash
# 1. Copy environment template and fill in your OpenRouter API key
cp .env.example .env
# Edit .env: set OPENROUTER_API_KEY=sk-or-v1-...

# 2. Build and launch all backend services
docker compose up --build

# 3. Verify health
curl http://localhost:8000/api/docs/
```

| Service | URL |
|---|---|
| Django API | `http://localhost:8000` |
| Swagger UI | `http://localhost:8000/api/docs/` |
| OpenAPI Schema | `http://localhost:8000/api/schema/` |
| Chroma Vector Store | `http://localhost:8001` |

---

### 2. Run Flutter Mobile Client

```bash
cd mobile

# Install dependencies
flutter pub get

# Run on connected device or simulator
flutter run
```

---

## API Walkthrough

```bash
BASE=http://localhost:8000

# 1. Register a new account
curl -s -X POST $BASE/api/register/ \
  -H "Content-Type: application/json" \
  -d '{"email":"reviewer@example.com","password":"Sup3rSecretPassword!"}'
# → {"message":"User registered successfully","user_id":1}

# 2. Login to obtain JWT Token
TOKEN=$(curl -s -X POST $BASE/api/login/ \
  -H "Content-Type: application/json" \
  -d '{"email":"reviewer@example.com","password":"Sup3rSecretPassword!"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

# 3. Upload a document (.pdf, .txt, or .md)
curl -s -X POST $BASE/api/documents/upload/ \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/path/to/document.pdf"
# → {"message":"Document uploaded and ingestion started","document_id":1,"task_id":"<task_uuid>"}

# 4. Poll Ingestion Status
curl -s "$BASE/api/documents/status/?task_id=<task_uuid>" \
  -H "Authorization: Bearer $TOKEN"
# → {"task_id":"<task_uuid>","status":"SUCCESS","message":"Document successfully parsed, embedded, and indexed in vector storage."}

# 5. Standard RAG Chat Query
curl -s -X POST $BASE/api/chat/query/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"query":"What are the primary conclusions in the report?"}'
# → {"answer":"Based on your uploaded documents..."}

# 6. Advanced HyDE Chat Query (Hypothetical Document Embeddings)
curl -s -X POST $BASE/api/chat/query/ \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "query":"Explain the architectural trade-offs.",
    "use_hyde": true,
    "message_histories": [
      {"role": "user", "content": "Hello!"},
      {"role": "assistant", "content": "Hello! How can I assist you with your documents?"}
    ]
  }'
# → {"answer":"..."}
```

---

## Mobile Application Features

1. **Authentication & Session Persistence:** Secure login with validation, auto-login using Keychain/Keystore via `flutter_secure_storage`, and clean logout.
2. **Document Management:** Native file picker, background upload triggers, and real-time status badges (`PROCESSING`, `SUCCESS`, `FAILURE`).
3. **Interactive Chat:** Tailored message bubbles (user vs. assistant), status indicators (`Sending`, `Delivered`, `Failed` with tap-to-retry), auto-scroll, and a HyDE toggle switch.
4. **Local Multi-Thread Persistence (Bonus):** Persistent SQLite/Hive chat threads, sidebar conversation drawer, offline history review, and swipe-to-delete with cascade cleanup.

---

## Documentation Suite

Full technical specifications are maintained under `docs/`:

- **Requirements Baseline:**
  - [`docs/00-anchor/brd.md`](docs/00-anchor/brd.md) — Business Requirements Document
  - [`docs/00-anchor/srs.md`](docs/00-anchor/srs.md) — Software Requirements Specification
  - [`docs/00-anchor/glossary.md`](docs/00-anchor/glossary.md) — Architectural Glossary & Terminology
- **Architecture & System Design:**
  - [`docs/01-architecture/system_context.md`](docs/01-architecture/system_context.md) — System Topology & Component Interactions
  - [`docs/01-architecture/database.md`](docs/01-architecture/database.md) — Relational & Local Persistence Models
  - [`docs/01-architecture/docker.md`](docs/01-architecture/docker.md) — Container Topology & Compose Design
  - [`docs/01-architecture/project_structure.md`](docs/01-architecture/project_structure.md) — Monorepo Directory Organization
  - [`docs/01-architecture/api_contract.yaml`](docs/01-architecture/api_contract.yaml) — OpenAPI 3.0.3 Contract
- **Mobile Architecture:**
  - [`docs/02-mobile/architecture.md`](docs/02-mobile/architecture.md) — Flutter Client Architecture, BLoC State, & Offline Strategy
