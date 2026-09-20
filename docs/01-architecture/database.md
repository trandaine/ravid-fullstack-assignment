# Database Design

## Objective

Define the relational schema in PostgreSQL for the Django backend as well as the local persistence schema in SQLite/Hive for the Flutter mobile application.

PostgreSQL is the server-side system of record for user accounts, document metadata, and asynchronous ingestion tracking. Binary file data is persisted on the shared media volume, and dense vector embeddings live in the Chroma vector database. On mobile, SQLite/Hive maintains local chat threads, message histories, and offline caches.

---

## Backend Relational Models (PostgreSQL)

### User

Django's standard authentication user model (`auth_user`) provides identity management.

Core attributes:
- `id` (Integer, Primary Key)
- `username` (VarChar(150), Unique)
- `email` (VarChar(254), Unique, Indexed)
- `password` (VarChar(128), Hashed)
- `is_active` (Boolean, Default True)
- `date_joined` (DateTime)

### Document

Represents an uploaded private document belonging to an authenticated user.

Fields:
- `id` (BigAutoField, Primary Key)
- `owner` (ForeignKey to `User`, `on_delete=CASCADE`, `db_index=True`)
- `original_name` (VarChar(255))
- `storage_path` (VarChar(512), e.g. `uploads/user_{user_id}/<uuid>_<filename>`)
- `content_type` (VarChar(100), e.g. `application/pdf`, `text/plain`, `text/markdown`)
- `size_bytes` (PositiveIntegerField)
- `uploaded_at` (DateTimeField, `auto_now_add=True`)

Responsibilities:
- Maintain source document metadata and storage references.
- Enforce strict ownership boundaries for document listing and deletion.

### IngestionJob

Tracks the background ingestion pipeline lifecycle executed by Celery.

Fields:
- `id` (BigAutoField, Primary Key)
- `owner` (ForeignKey to `User`, `on_delete=CASCADE`, `db_index=True`)
- `source_document` (ForeignKey to `Document`, `on_delete=CASCADE`)
- `celery_task_id` (CharField(255), Unique, `db_index=True`)
- `status` (CharField(32), Default `PENDING`, Choices: `PENDING`, `STARTED`, `SUCCESS`, `FAILURE`)
- `chunk_count` (PositiveIntegerField, Default 0)
- `error_message` (TextField, Nullable, Blank)
- `created_at` (DateTimeField, `auto_now_add=True`)
- `updated_at` (DateTimeField, `auto_now=True`)

Responsibilities:
- Provide the system of record for the polling endpoint `GET /api/documents/status/?task_id=<task_id>`.
- Capture failure context (`error_message`) and ingestion statistics (`chunk_count`).

---

## Mobile Local Storage Schema (SQLite / Hive)

### ChatThread

Represents a local conversation session on the mobile client.

Fields:
- `id` (TEXT / String, Primary Key, UUID v4)
- `title` (TEXT, e.g., "First Question..." or custom title)
- `created_at` (INTEGER / ISO8601 Timestamp)
- `updated_at` (INTEGER / ISO8601 Timestamp, Indexed)

### ChatMessage

Represents individual chat turns within a thread.

Fields:
- `id` (TEXT / String, Primary Key, UUID v4)
- `thread_id` (TEXT, ForeignKey to `ChatThread.id`, `ON DELETE CASCADE`, Indexed)
- `sender` (TEXT, `'user'` | `'assistant'`)
- `content` (TEXT)
- `status` (TEXT, `'sending'` | `'delivered'` | `'failed'`)
- `timestamp` (INTEGER / ISO8601 Timestamp)

---

## Entity Relationship Diagrams

### Backend Entity Relationships (PostgreSQL)

```
  ┌──────────────────┐
  │   auth_user      │
  │──────────────────│
  │ id (PK)          │
  │ email            │
  │ password         │
  └────────┬─────────┘
           │ 1
           │
           │ has many
           ▼ *
  ┌──────────────────┐          1 ┌───────────────────────────┐
  │   Document       │◄───────────┤   IngestionJob            │
  │──────────────────│            │───────────────────────────│
  │ id (PK)          │            │ id (PK)                   │
  │ owner_id (FK)    │            │ owner_id (FK)             │
  │ original_name    │            │ source_document_id (FK)   │
  │ storage_path     │            │ celery_task_id (Unique)   │
  │ content_type     │            │ status                    │
  │ size_bytes       │            │ chunk_count               │
  │ uploaded_at      │            │ error_message             │
  └──────────────────┘            └───────────────────────────┘
```

### Mobile Local Entity Relationships (SQLite / Hive)

```
  ┌──────────────────┐
  │   ChatThread     │
  │──────────────────│
  │ id (PK, UUID)    │
  │ title            │
  │ created_at       │
  │ updated_at (idx) │
  └────────┬─────────┘
           │ 1
           │
           │ has many (cascade delete)
           ▼ *
  ┌───────────────────────────┐
  │   ChatMessage             │
  │───────────────────────────│
  │ id (PK, UUID)             │
  │ thread_id (FK -> Thread)  │
  │ sender (user | assistant) │
  │ content                   │
  │ status (sending/deliv/err)│
  │ timestamp                 │
  └───────────────────────────┘
```

---

## Ingestion Status Mapping

| Celery Internal State | `IngestionJob.status` (DB) | Public Status API Output | Description |
|---|---|---|---|
| `PENDING` | `PENDING` | `PROCESSING` | Task enqueued in Redis, waiting for worker |
| `STARTED` | `STARTED` | `PROCESSING` | Worker actively extracting, chunking, or embedding |
| `RETRY` | `STARTED` | `PROCESSING` | Worker retrying transient error |
| `SUCCESS` | `SUCCESS` | `SUCCESS` | Document successfully chunked, embedded, and indexed in Chroma |
| `FAILURE` / `REVOKED` | `FAILURE` | `FAILURE` | Processing failed; `error_message` is populated |

---

## Indexing & Isolation Policies

1. **Owner-Scoped Queries:** All PostgreSQL queries filter by `owner=request.user`.
2. **Indexed Lookups:**
   - `IngestionJob.celery_task_id`: Unique index for fast status retrieval by `task_id`.
   - `Document.owner_id` & `IngestionJob.owner_id`: Indexed foreign keys for fast user-specific filtering.
   - `ChatThread.updated_at`: Indexed locally on mobile for instant drawer ordering.
   - `ChatMessage.thread_id`: Indexed locally for sub-millisecond thread message loading.
3. **Chroma Vector Store Isolation:** Vector collections are named `user_{user_id}`. Chroma queries are strictly restricted to the caller's collection.
