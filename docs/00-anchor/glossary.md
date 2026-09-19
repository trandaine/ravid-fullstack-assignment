# Glossary

## Core Terms

### Document

A private file uploaded by an authenticated user to build their personal knowledge base. Supported file formats are PDF, TXT, and Markdown, up to 10 MB per file. Every document is strictly owned by exactly one user.

### Chunk

A contextual slice of a document's extracted text produced during the chunking phase. The system utilizes LangChain's `RecursiveCharacterTextSplitter` configured with `chunk_size = 1000` characters and `chunk_overlap = 150` characters. Chunks are the fundamental atomic units that get vectorized, indexed, and retrieved.

### Embedding

A fixed-length dense numerical vector representing the semantic meaning of text, computed by an embedding model. This project uses the open-source HuggingFace `sentence-transformers/all-MiniLM-L6-v2` model running locally in-process, generating 384-dimensional dense vectors without requiring external paid API keys.

### Vector Store

A specialized database engineered to store vector embeddings and perform high-dimensional similarity search. This project uses Chroma as the vector store.

### Collection / Namespace

A logically and physically isolated partition inside the vector store. This project enforces per-user isolation by maintaining dedicated Chroma collections using the naming convention `user_{user_id}`.

### Retrieval

The process of querying a user's isolated vector collection for chunks whose embeddings have the highest cosine similarity to a search vector. Retrieval is always strictly scoped to the authenticated caller's collection.

### Top-K

The maximum number of nearest semantic chunks returned by the retrieval stage for a single query. The standard parameter for this system is `top_k = 4`.

### Cosine Similarity

The geometric distance metric used to quantify the semantic relatedness between query embedding vectors and stored chunk vectors.

### RAG Chain (Retrieval-Augmented Generation)

The end-to-end pipeline that receives a user query, embeds it (or expands it via HyDE), queries the isolated vector store for relevant context chunks, constructs a grounded system prompt, invokes the LLM via OpenRouter, and returns a verified answer.

### HyDE (Hypothetical Document Embeddings)

An advanced retrieval technique where the LLM first generates a zero-shot hypothetical answer passage to the user's question. The embedding of this hypothetical passage is then used to search the vector store instead of the raw query, bridging vocabulary and phrasing mismatches between brief queries and source document content.

### Ingestion Pipeline

The asynchronous background workflow executed by a Celery worker that transforms an uploaded document into searchable vector embeddings: file loading, text extraction, recursive chunking, vector embedding, and Chroma collection upsert.

### Task ID

A unique UUID identifier generated when a document upload is accepted. The mobile client polls `GET /api/documents/status/?task_id=<task_id>` using this identifier to track asynchronous ingestion progress.

### Ingestion Status

The public lifecycle state of an ingestion background task, standardized as `PROCESSING`, `SUCCESS`, or `FAILURE`. Internal Celery task states (`PENDING`, `STARTED`, `RETRY`, `REVOKED`) are mapped directly to these three public states.

### Protected Route

An API endpoint requiring valid authentication credentials (either HTTP Basic Auth or a JWT token passed in the `Authorization: Bearer <token>` header).

### JWT (JSON Web Token)

A digitally signed token issued upon successful login used to authenticate subsequent requests to protected endpoints.

### OpenRouter

The unified LLM gateway (`https://openrouter.ai/api/v1`) providing OpenAI-compatible access to free-tier language models, eliminating the requirement for paid proprietary API keys.

### LangChain

The open-source AI orchestration framework used for document loaders, text chunking splitters, vector store connectors, and retrieval chain assemblies.

### Celery

The distributed asynchronous task execution framework used to process resource-intensive document ingestion off the main Django HTTP request thread.

### Redis

The in-memory data store acting as the message broker and result backend for Celery background tasks.

### Mobile Session Storage

The secure, encrypted persistence layer on mobile devices (`flutter_secure_storage`) backed by the iOS Keychain and Android Keystore/EncryptedSharedPreferences, used to store auth tokens and credentials.

### Chat Thread

A distinct conversational session on the mobile app containing an ordered series of user questions and assistant responses, persisted locally in SQLite/Hive storage.

### Context Injection

The mechanism by which the mobile app includes the last `N` messages of the active chat thread in the `message_histories` request payload, providing conversational continuity to the RAG pipeline.

## Stakeholder Roles

### User

The end user interacting with the Flutter mobile application to upload private documents, manage knowledge bases, and query the AI assistant.

### Candidate

The software engineer authoring the Django backend, Flutter mobile client, and technical documentation.

### Reviewer

The technical evaluator (Truong Vinh Phuoc "Matthew" and team) assessing architecture, code quality, isolation rigor, and delivery execution.
