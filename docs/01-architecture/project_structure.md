# Project Structure

## Objective

Define a clean, maintainable, and reviewable monorepo layout encompassing the Django RAG backend and the Flutter mobile client application.

---

## Monorepo Layout

```text
trandai-ravid-assignment/
├── compose.yaml                      # Docker Compose orchestrating all backend services
├── Makefile                          # Convenience commands (run, test, lint, mobile-build)
├── README.md                         # Project entry point and reviewer walkthrough
├── docs/                             # Architecture and specification suite
│   ├── 00-anchor/                    # Requirements baseline (brd.md, srs.md, glossary.md)
│   ├── 01-architecture/              # Architecture guides (system_context, database, docker, etc.)
│   └── 02-mobile/                    # Mobile client architecture & UI state specifications
├── backend/                          # Django REST Framework Backend
│   ├── Dockerfile
│   ├── manage.py
│   ├── pyproject.toml / requirements.txt
│   ├── config/                       # Django project configuration
│   │   ├── settings/                 # Modular settings (base, local, test, production)
│   │   ├── urls.py                   # Central route definitions
│   │   ├── celery.py                 # Celery app and task routing
│   │   └── wsgi.py / asgi.py
│   ├── apps/
│   │   ├── accounts/                 # Registration, login, auth tokens
│   │   ├── documents/                # Document metadata, upload endpoint, file validators
│   │   ├── rag/                      # Ingestion pipeline, Chroma vectorstore, RAG & HyDE engine
│   │   └── common/                   # Shared error envelopes, JSON loggers, utilities
│   └── tests/                        # Unit, integration, and RAG pipeline tests
└── mobile/                           # Flutter Mobile Application
    ├── pubspec.yaml                  # Flutter dependencies and assets
    ├── lib/
    │   ├── main.dart                 # App bootstrap and dependency injection
    │   ├── core/                     # Shared core utilities
    │   │   ├── api/                  # Dio HTTP client, interceptors, auth token handling
    │   │   ├── storage/              # flutter_secure_storage & SQLite/Hive database helpers
    │   │   ├── theme/                # App typography, theme colors, and layout constants
    │   │   └── widgets/              # Reusable UI components (buttons, textfields, loaders)
    │   └── features/
    │       ├── auth/                 # Login UI, auth state management, auto-login logic
    │       ├── documents/            # Document picker, upload screen, ingestion status polling
    │       └── chat/                 # Chat screen, message bubbles, thread drawer, HyDE toggle
    └── test/                         # Unit and widget tests for mobile components
```

---

## Backend App Responsibilities

### `apps/accounts`
- User registration (`POST /api/register/`) and authentication (`POST /api/login/`).
- Identity introspection (`GET /api/auth/me/`).
- Token issuance and validation via `djangorestframework-simplejwt`.

### `apps/documents`
- `Document` model definition and persistence.
- Document upload view (`POST /api/documents/upload/`) with file format (`.pdf`, `.txt`, `.md`) and size (<= 10 MB) validation.
- Document listing (`GET /api/documents/`) and deletion (`DELETE /api/documents/<id>/`).
- Celery task dispatch and `IngestionJob` record creation.

### `apps/rag`
- `IngestionJob` tracking model and Celery background task implementation.
- Document parsing (`pypdf`, text loaders) and chunking (`RecursiveCharacterTextSplitter`).
- Local embedding generation via HuggingFace `all-MiniLM-L6-v2`.
- Isolated Chroma vector store manager (`user_{user_id}`).
- Ingestion status endpoint (`GET /api/documents/status/?task_id=<task_id>`).
- RAG chat query view (`POST /api/chat/query/`).
- HyDE (Hypothetical Document Embeddings) zero-shot passage generator and fallback handler.
- OpenRouter LLM gateway integration.

### `apps/common`
- Standard error response helpers (`{ "error": "<message>" }`).
- Structured JSON logging formatters.
- Shared exceptions and utility functions.

---

## Mobile Module Responsibilities

### `features/auth`
- **Presentation:** `LoginScreen` with email and password inputs, form validation, and error snackbars.
- **State Management:** `AuthBloc` / `AuthNotifier` handling unauthenticated, authenticating, and authenticated states.
- **Repository:** `AuthRepository` interacting with `POST /api/login/` and saving tokens to `flutter_secure_storage`.

### `features/documents`
- **Presentation:** `DocumentScreen` displaying active uploads, polling status badges (`PROCESSING`, `SUCCESS`, `FAILURE`), and uploaded document list.
- **State Management:** `DocumentBloc` managing document list, file picking, and polling timer intervals.
- **Repository:** `DocumentRepository` executing multipart uploads and querying status.

### `features/chat`
- **Presentation:** `ChatScreen` with message bubbles (user vs. assistant), status markers (sending, delivered, failed), thread navigation drawer, and HyDE toggle switch.
- **State Management:** `ChatBloc` managing active thread messages, optimistic UI updates, retry requests, and HyDE state.
- **Storage & Repository:** `ChatRepository` combining local SQLite/Hive persistence with remote API calls (`POST /api/chat/query/`).

---

## Layering Conventions

1. **Clean Separation of Concerns:**
   - Django views remain thin: validate input, delegate to services, format response.
   - Celery tasks delegate to pure service functions (`pipeline.py`, `retrieval.py`, `hyde.py`).
   - Flutter UI widgets contain zero business logic; all state transitions flow through state managers (Bloc/Riverpod/Notifier).

2. **Error Handling & Envelope Uniformity:**
   - All backend errors return HTTP status codes with body `{ "error": "<message>" }`.
   - Mobile repositories parse backend error envelopes and map them to user-friendly UI banners.
