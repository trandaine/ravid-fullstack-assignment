# RAVID — Fullstack RAG Document Chatbot (Backend + Mobile)

RAVID is a fullstack Retrieval-Augmented Generation (RAG) document chatbot platform featuring a Dockerized Django REST Framework backend and a cross-platform Flutter client (supporting Mobile and Web). Users upload private documents (`.pdf`, `.txt`, `.md`), which are asynchronously parsed, chunked, embedded, and indexed into isolated per-user vector collections in ChromaDB. Users query their personal knowledge base through a conversational interface powered by standard RAG or HyDE (Hypothetical Document Embeddings) retrieval.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Backend Web Framework | Django 5.x + Django REST Framework |
| Authentication | `djangorestframework-simplejwt` (JWT Token Auth) |
| Asynchronous Processing | Celery 5.x with Redis 7 Broker & Result Backend |
| Relational Storage | PostgreSQL 16 (`users`, `documents`, `ingestion_jobs`) |
| Vector Database | ChromaDB with isolated per-user collections (`user_{id}`) |
| RAG Pipeline | LangChain (`RecursiveCharacterTextSplitter`, document loaders) |
| Embedding Model | HuggingFace `sentence-transformers/all-MiniLM-L6-v2` (384 dimensions) |
| LLM Gateway | OpenRouter / OpenAI-compatible API (`openai/gpt-oss-120b`) |
| API Documentation | OpenAPI 3.0.3 via DRF Spectacular at `/api/docs/` |
| Client Application | Flutter 3.x / Dart 3.x (Chrome Web, iOS, Android) |
| Client Architecture | Clean Architecture with BLoC State Management |
| Client Storage & Networking | `dio`, `flutter_secure_storage`, `get_it` |
| Containerization | Docker & Docker Compose |

---

## Prerequisites

Ensure the following tools are installed on your system:

- **Docker Engine & Docker Compose** (v2.0+) — [Install Docker](https://docs.docker.com/get-docker/)
- **Flutter SDK** (v3.10.0+ with Dart SDK 3.x) — [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Google Chrome** — Required for running the Flutter client on web (`flutter run -d chrome`)
- **OpenRouter / OpenAI API Key** — Access key for LLM inference (e.g. `openai/gpt-oss-120b`)

---

## Environment Variables

Copy the example environment file into `.env` at the root of the project:

```bash
cp .env.example .env
```

Configure your LLM gateway and application settings in `.env`:

```ini
# Django Settings
DJANGO_SECRET_KEY=dev-secret-key-change-in-production-1234567890
DJANGO_DEBUG=True
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,0.0.0.0,web

# PostgreSQL Configuration
POSTGRES_DB=ravid
POSTGRES_USER=ravid
POSTGRES_PASSWORD=ravid
POSTGRES_HOST=db
POSTGRES_PORT=5432

# Redis & Celery
REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/0
CELERY_RESULT_BACKEND=redis://redis:6379/0

# ChromaDB
CHROMA_HOST=chroma
CHROMA_PORT=8000

# LLM Gateway Configuration
# Supports OpenRouter or standard OpenAI-compatible endpoints
OPENROUTER_API_KEY=your_api_key_here
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_MODEL=openai/gpt-oss-120b

# Alternative OpenAI environment variables (automatically mapped if set)
# OPENAI_API_KEY=your_api_key_here
# OPENAI_API_BASE=https://openrouter.ai/api/v1
# LLM_MODEL_NAME=openai/gpt-oss-120b
```

---

## Backend Setup

### 1. Build and Start Services with Docker Compose

Launch the PostgreSQL, Redis, ChromaDB, Django API, and Celery worker services:

```bash
docker compose up --build -d
```

Check running container status:

```bash
docker compose ps
```

View live logs:

```bash
docker compose logs -f web celery
```

### 2. Run Database Migrations

Database migrations execute automatically on container startup. To run or verify migrations manually:

```bash
docker compose exec web python manage.py migrate
```

### 3. Create a Test Superuser

Create an administrative account to authenticate with the API and access the system:

```bash
docker compose exec -it web python manage.py createsuperuser
```

### 4. Verify API Availability

Once running, verify the backend endpoints:

| Service | Endpoint |
|---|---|
| Django API Base | `http://localhost:8000` |
| Swagger UI Docs | `http://localhost:8000/api/docs/` |
| OpenAPI Schema | `http://localhost:8000/api/schema/` |
| Health Check | `http://localhost:8000/api/health/` |
| ChromaDB REST | `http://localhost:8001` |

---

## Mobile & Web Setup

The Flutter application supports running directly in the browser via Chrome Web as well as connected iOS/Android simulators.

### 1. Install Dependencies

Navigate to the `mobile/` directory and install the required Dart packages:

```bash
cd mobile
flutter pub get
```

### 2. Run the App on Chrome Web

Start the application on Google Chrome targeting the local backend (`http://127.0.0.1:8000` by default):

```bash
flutter run -d chrome
```

To specify a custom backend host or port at runtime, pass `--dart-define`:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

### 3. Run on Mobile Devices / Simulators

List available devices:

```bash
flutter devices
```

Run on a specific device or emulator:

```bash
flutter run -d <device_id>
```

---

## Testing Guide

### 1. Backend Automated Tests (Pytest)

Run the backend unit, integration, and security test suites inside the Docker container:

```bash
docker compose run --rm -e DJANGO_SETTINGS_MODULE=config.settings.test web pytest -v
```

To run with test coverage reporting:

```bash
docker compose run --rm -e DJANGO_SETTINGS_MODULE=config.settings.test web pytest --cov=apps -v
```

The test suite covers:
- JWT authentication (`/api/token/`, `/api/token/refresh/`)
- Document validation and upload pipeline (`/api/documents/upload/`)
- Celery ingestion and state transitions (`/api/documents/status/`)
- Standard RAG and HyDE query processing (`/api/chat/query/`)
- Per-user ChromaDB collection isolation and multi-tenant access control

### 2. Flutter Unit & Widget Tests

Run the client unit and widget test suite from the `mobile/` directory:

```bash
cd mobile
flutter test
```

### 3. Flutter Integration Tests (E2E)

Run the end-to-end integration tests:

```bash
cd mobile
flutter test integration_test/app_test.dart
```

---

## API Quick Reference

### 1. Obtain JWT Access Token
```bash
curl -s -X POST http://localhost:8000/api/token/ \
  -H "Content-Type: application/json" \
  -d '{"username":"<your_username>","password":"<your_password>"}'
```

### 2. Upload Document (.pdf, .txt, .md)
```bash
curl -s -X POST http://localhost:8000/api/documents/upload/ \
  -H "Authorization: Bearer <access_token>" \
  -F "file=@sample_policy.txt"
```

### 3. Poll Ingestion Status
```bash
curl -s "http://localhost:8000/api/documents/status/?task_id=<task_id>" \
  -H "Authorization: Bearer <access_token>"
```

### 4. Query RAG (Standard / HyDE)
```bash
curl -s -X POST http://localhost:8000/api/chat/query/ \
  -H "Authorization: Bearer <access_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What are the primary policy terms?",
    "use_hyde": false,
    "message_histories": []
  }'
```

---

## Project Structure

```
.
├── backend/                  # Django REST Framework application
│   ├── apps/
│   │   ├── common/           # Exception handlers, middleware, health endpoints
│   │   ├── documents/        # Document models, file upload, deletion views
│   │   ├── rag/              # Ingestion worker, text splitters, Chroma vectorstore
│   │   └── chat/             # Chat endpoints, LLM integration, HyDE query chain
│   ├── config/               # Django settings, Celery config, root URLs
│   ├── tests/                # Backend test suite (Pytest)
│   ├── Dockerfile            # Python 3.11 container definition
│   └── requirements.txt      # Python dependencies
├── mobile/                   # Flutter client application
│   ├── lib/
│   │   ├── core/             # API client, secure storage, UI themes, widgets
│   │   └── features/         # Auth, Document Management, Chat (BLoC + Data + UI)
│   ├── test/                 # Flutter unit & widget tests
│   ├── integration_test/     # Flutter E2E integration tests
│   └── pubspec.yaml          # Flutter dependencies
├── docs/                     # Architectural, database, and specification docs
├── docker-compose.yml        # Multi-container orchestration
├── .env.example              # Environment variable template
└── README.md                 # Project documentation & getting started guide
```
