# Docker And Compose Design

## Objective

Define the container topology, dependency graph, and runtime environment for the local R.A.V.I.D. RAG backend stack to ensure reviewers can run the complete backend with a single `docker compose up --build` command.

---

## Services

### web

- Django REST Framework API service.
- Exposes port `8000` to the host for client traffic and Swagger UI access.
- In-process embedding generation for user queries via HuggingFace `all-MiniLM-L6-v2`.
- Depends on healthy `db`, `redis`, and `chroma` services.

### db

- PostgreSQL relational database (`postgres:16-alpine`).
- Persists user accounts, document metadata, and ingestion task status.
- Configured with health check (`pg_isready -U $POSTGRES_USER -d $POSTGRES_DB`).

### redis

- In-memory data store (`redis:7-alpine`).
- Acts as Celery message broker and result backend.
- Configured with health check (`redis-cli ping`).

### celery

- Celery asynchronous worker process.
- Executes the document ingestion pipeline: file loading, text splitting, embedding generation, and Chroma upsert.
- Shares the `media` volume with `web` to access uploaded files.
- In-process embedding generation via HuggingFace `all-MiniLM-L6-v2`.
- Depends on healthy `db`, `redis`, and `chroma` services.

### chroma

- Chroma vector database service (`chromadb/chroma:latest` or standalone).
- Persists per-user isolated vector collections (`user_{user_id}`) on a named volume.
- Configured with health check (heartbeat / `/api/v1/heartbeat` endpoint).

---

## Exposed Ports

Infra services bind to loopback (`127.0.0.1`) where appropriate to prevent port collisions on host machines:

- `web`: `8000` (Application API & Swagger UI)
- `postgres`: `127.0.0.1:5432:5432` (Relational database)
- `redis`: `127.0.0.1:6379:6379` (Celery broker)
- `chroma`: `127.0.0.1:8001:8000` (Chroma vector store, host port `8001` mapped to container `8000`)

---

## Startup Ordering

The stack uses healthcheck-gated `depends_on` (`condition: service_healthy`):

```
            ┌────────────────┐        ┌────────────────┐        ┌────────────────┐
            │   PostgreSQL   │        │     Redis      │        │   Chroma DB    │
            │   (Healthy)    │        │   (Healthy)    │        │   (Healthy)    │
            └───────┬────────┘        └───────┬────────┘        └───────┬────────┘
                    │                         │                         │
                    └─────────────────────────┼─────────────────────────┘
                                              │
                             ┌────────────────┴────────────────┐
                             │                                 │
                             ▼                                 ▼
                    ┌─────────────────┐               ┌─────────────────┐
                    │  Django API     │               │  Celery Worker  │
                    │  (web:8000)     │               │  (celery)       │
                    └─────────────────┘               └─────────────────┘
```

---

## Volume Strategy

Named Docker volumes for persistent state:

- `pg_data` — PostgreSQL database storage.
- `media` — Shared file storage (`uploads/user_{user_id}/`), mounted to both `web` and `celery`.
- `chroma_data` — Chroma vector embeddings and collection metadata storage.

---

## Environment Variables

### Django & Application
- `DJANGO_SECRET_KEY`: Secret key for cryptographic signing.
- `DJANGO_DEBUG`: Debug mode toggle (`True` for local development, `False` for production).
- `DJANGO_ALLOWED_HOSTS`: Comma-separated list of allowed hostnames (default `localhost,127.0.0.1,0.0.0.0,10.0.2.2`).

### PostgreSQL Database
- `POSTGRES_DB`: Name of the PostgreSQL database (e.g. `ravid_db`).
- `POSTGRES_USER`: PostgreSQL username (e.g. `ravid_user`).
- `POSTGRES_PASSWORD`: PostgreSQL password.
- `POSTGRES_HOST`: Hostname of the database container (`db`).
- `POSTGRES_PORT`: Port of the database container (`5432`).

### Redis & Celery
- `REDIS_URL`: URL for Redis connection (`redis://redis:6379/0`).
- `CELERY_BROKER_URL`: Celery broker connection string (`redis://redis:6379/0`).
- `CELERY_RESULT_BACKEND`: Celery result backend connection string (`redis://redis:6379/0`).

### Chroma Vector Store
- `CHROMA_HOST`: Hostname of the Chroma container (`chroma` or in-process directory).
- `CHROMA_PORT`: Port of the Chroma container (`8000`).

### OpenRouter (LLM Gateway)
- `OPENROUTER_API_KEY`: API key for OpenRouter gateway (free tier).
- `OPENROUTER_BASE_URL`: Base URL (`https://openrouter.ai/api/v1`).
- `OPENROUTER_MODEL`: LLM model slug (e.g. `google/gemma-2-9b-it:free`, `mistralai/mistral-7b-instruct:free`).

---

## Reviewer Workflow Goal

A reviewer can bootstrap and exercise the entire backend stack with minimal steps:

```bash
# 1. Copy environment template and fill in OpenRouter API key
cp .env.example .env

# 2. Start container stack
docker compose up --build

# 3. Access Swagger UI in browser
open http://localhost:8000/api/docs/
```
