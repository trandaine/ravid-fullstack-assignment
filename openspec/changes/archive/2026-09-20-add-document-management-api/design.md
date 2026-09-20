# Design: Document Management & Vector Storage Architecture

## Architecture Overview

The Document Management & Vector Storage subsystem provides asynchronous ingestion of user documents into a searchable vector database. The architecture decouples the synchronous HTTP upload request from the compute-intensive extraction, chunking, embedding, and vector upsert pipeline via a Celery worker pool and Redis message broker.

```
┌─────────────────┐       POST /api/documents/upload/        ┌────────────────────────┐
│  Client Device  │ ───────────────────────────────────────► │  Django REST API       │
│  (Mobile/Web)   │ ◄─────────────────────────────────────── │  (Sync Request Handler)│
└────────┬────────┘          202 Accepted (task_id)          └───────────┬────────────┘
         │                                                               │
         │ GET /api/documents/status/?task_id=...                        │ 1. Validate & store file
         ▼                                                               │ 2. Create DB records
┌─────────────────┐                                                      │ 3. Enqueue Celery task
│ Polling Handler │                                                      ▼
│ (Status Check)  │                                          ┌────────────────────────┐
└────────┬────────┘                                          │ Redis Task Broker      │
         │                                                   └───────────┬────────────┘
         │ Read IngestionJob                                             │
         ▼                                                               ▼
┌─────────────────┐                                          ┌────────────────────────┐
│ PostgreSQL DB   │ ◄─────────────────────────────────────── │ Celery Worker          │
│ (State Record)  │          Update status:                  │ (Async Ingestion)      │
│                 │          STARTED → SUCCESS/FAILURE       └───────────┬────────────┘
└─────────────────┘                                                      │
                                                                         │ 1. Extract text
                                                                         │ 2. Chunk (1000/150)
                                                                         │ 3. MiniLM Embeddings
                                                                         ▼
                                                             ┌────────────────────────┐
                                                             │ Chroma Vector DB       │
                                                             │ Collection: user_{id}  │
                                                             └────────────────────────┘
```

---

## Component Details

### 1. File Upload & Validation (`apps/documents/validators.py`)

- **Extension Validation**: Whitelist strictly `.pdf`, `.txt`, and `.md`. Evaluated against file name extension and MIME type.
- **Size Validation**: Maximum 10 MB (`10 * 1024 * 1024` bytes). Evaluated before reading full stream into memory.
- **Storage Strategy**: Files are saved to `MEDIA_ROOT/uploads/user_{user_id}/<uuid4>_<sanitized_filename>`.

### 2. Data Models (`apps/documents/models.py`, `apps/rag/models.py`)

#### `Document` (PostgreSQL)
- `id`: BigAutoField (Primary Key)
- `owner`: ForeignKey(`auth.User`, on_delete=CASCADE, db_index=True)
- `original_name`: CharField(max_length=255)
- `storage_path`: CharField(max_length=512)
- `content_type`: CharField(max_length=100)
- `size_bytes`: PositiveIntegerField()
- `uploaded_at`: DateTimeField(auto_now_add=True)

#### `IngestionJob` (PostgreSQL)
- `id`: BigAutoField (Primary Key)
- `owner`: ForeignKey(`auth.User`, on_delete=CASCADE, db_index=True)
- `source_document`: ForeignKey(`Document`, on_delete=CASCADE)
- `celery_task_id`: CharField(max_length=255, unique=True, db_index=True)
- `status`: CharField(max_length=32, default="PENDING", choices: `PENDING`, `STARTED`, `SUCCESS`, `FAILURE`)
- `chunk_count`: PositiveIntegerField(default=0)
- `error_message`: TextField(null=True, blank=True)
- `created_at`: DateTimeField(auto_now_add=True)
- `updated_at`: DateTimeField(auto_now=True)

### 3. Asynchronous Pipeline Task (`apps/rag/tasks.py`)

```python
@shared_task(bind=True, max_retries=2, default_retry_delay=5)
def ingest_document_task(self, document_id: int, ingestion_job_id: int):
    # 1. Update IngestionJob status to STARTED
    # 2. Extract text based on file extension (PyPDFLoader / TextLoader)
    # 3. Split text into chunks using RecursiveCharacterTextSplitter
    # 4. Generate embeddings via HuggingFaceEmbeddings(all-MiniLM-L6-v2)
    # 5. Upsert chunks into Chroma collection 'user_{user_id}'
    # 6. Update IngestionJob status to SUCCESS (or catch exception -> FAILURE)
```

#### Pipeline Steps:

1. **Text Extraction**:
   - `.pdf`: Loaded via `pypdf` / `langchain_community.document_loaders.PyPDFLoader`.
   - `.txt` / `.md`: Loaded via UTF-8 decoded file read or `TextLoader`.
2. **Chunking**:
   - `RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=150, separators=["\n\n", "\n", " ", ""])`.
   - Each chunk receives metadata: `document_id`, `owner_id`, `chunk_index`, `source_name`.
3. **Embedding Generation**:
   - Model: `sentence-transformers/all-MiniLM-L6-v2` via `langchain_huggingface.HuggingFaceEmbeddings`.
   - 384-dimensional dense output. Runs locally on CPU/GPU without external API dependency.
4. **Vector Storage & Namespace Isolation**:
   - Vector Store: `Chroma` client pointing to persistent storage path.
   - Collection Naming Convention: `user_{user_id}`.
   - Upsert operation assigns deterministic chunk IDs: `doc_{document_id}_chunk_{chunk_index}`.

### 4. Status Mapping Logic (`apps/rag/views.py`)

| `IngestionJob.status` (Internal) | Public API `status` | Accompanying Fields |
|---|---|---|
| `PENDING` | `PROCESSING` | None |
| `STARTED` | `PROCESSING` | None |
| `SUCCESS` | `SUCCESS` | `message: "Document successfully parsed, embedded, and indexed in vector storage."` |
| `FAILURE` | `FAILURE` | `error: "<error_message>"` |

---

## Security & Isolation Strategy

1. **Authentication Boundary**: All endpoints require valid JWT (`Bearer <token>`) or HTTP Basic Auth.
2. **Owner-Scoped Retrieval**: Status queries strictly verify `owner=request.user`. Queries for foreign `task_id` values return `404 Not Found` to prevent task ID probing.
3. **Vector Multi-Tenancy**: Chroma collections are partitioned per user ID (`user_{user_id}`). Chunks from different users never share vector space or collection indices.
4. **Filesystem Isolation**: Uploaded files are partitioned by user directory: `uploads/user_{user_id}/`.
