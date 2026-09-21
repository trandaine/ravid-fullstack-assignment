## Why

The backend currently supports document upload and vector ingestion but has no endpoint for users to query their indexed knowledge base. Without a RAG query endpoint, the ingestion pipeline produces vectors that sit unused. Part 1.2 of the R.A.V.I.D. assessment requires a `POST /api/chat/query/` endpoint that retrieves relevant document chunks and generates LLM-powered answers, completing the core RAG loop.

## What Changes

- **New REST endpoint** `POST /api/chat/query/` accepting a JSON body with `query` (string), `message_histories` (list of `{role, content}` dicts), and optional `use_hyde` (boolean) fields.
- **LLM integration via OpenRouter**: Configure LangChain's `ChatOpenAI` with `base_url` pointed at OpenRouter's API, using a free-tier model (e.g., Mistral 7B, Gemma).
- **RAG retrieval pipeline**: Use LangChain's vector store retriever to search the authenticated user's Chroma collection (`user_{user_id}`), inject retrieved context into the LLM prompt alongside conversation history, and return the generated answer.
- **HyDE bonus (optional)**: When `use_hyde: true`, generate a hypothetical answer passage via LLM first, embed it, use that embedding for vector search, then synthesize the final answer from real retrieved chunks.
- **New dependency**: `langchain-openai` (for `ChatOpenAI` compatible with OpenRouter).
- **New Django app**: `backend/apps/chat/` to house the query view, serializer, and RAG chain logic.

## Capabilities

### New Capabilities
- `rag-query`: RAG query endpoint (`POST /api/chat/query/`) — vector retrieval, LLM prompt construction, answer generation, conversation history support, and optional HyDE retrieval mode.

### Modified Capabilities
_(none — the existing document-management spec is unaffected; this change consumes vectors produced by the existing ingestion pipeline but does not modify its behavior)_

## Impact

- **New files**: Chat app (`views.py`, `serializers.py`, `urls.py`), LLM service module, RAG chain module.
- **Modified files**: `backend/config/urls.py` (add chat URL include), `backend/config/settings/base.py` (add `apps.chat` to `INSTALLED_APPS`, add OpenRouter config keys), `backend/requirements.txt` / `pyproject.toml` (add `langchain-openai`).
- **Dependencies on existing code**: `backend/apps/rag/vectorstore.py` (Chroma collection access), `backend/apps/rag/embeddings.py` (embedding model for retriever).
- **External dependency**: OpenRouter API (requires `OPENROUTER_API_KEY` env var, free-tier).
- **No database migrations** — no new models required; the endpoint is stateless.
