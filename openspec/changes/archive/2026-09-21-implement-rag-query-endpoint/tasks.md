# Implementation Tasks: RAG Query Endpoint

## Phase 1: Dependencies & Configuration

- [x] 1.1 Add `langchain-openai` to `backend/requirements.txt` and `backend/pyproject.toml`.
- [x] 1.2 Add OpenRouter configuration to `backend/config/settings/base.py`: `OPENROUTER_API_KEY`, `OPENROUTER_MODEL` (default `mistralai/mistral-7b-instruct:free`), `OPENROUTER_TIMEOUT` (default `30`).
- [x] 1.3 Add `OPENROUTER_API_KEY` and `OPENROUTER_MODEL` to `.env.example`.

## Phase 2: Chat App Scaffold

- [x] 2.1 Create `backend/apps/chat/` Django app with `__init__.py`, `apps.py` (`ChatConfig`).
- [x] 2.2 Register `apps.chat.apps.ChatConfig` in `INSTALLED_APPS` in `backend/config/settings/base.py`.
- [x] 2.3 Create `backend/apps/chat/urls.py` with `POST query/` route pointing to `ChatQueryView`.
- [x] 2.4 Wire `path("api/chat/", include("apps.chat.urls"))` into `backend/config/urls.py`.

## Phase 3: LLM & RAG Chain Implementation

- [x] 3.1 Implement `backend/apps/chat/llm.py` with `get_llm()` returning `ChatOpenAI` configured for OpenRouter (model, API key, base URL, temperature, timeout from settings).
- [x] 3.2 Implement `backend/apps/chat/prompts.py` with `RAG_SYSTEM_PROMPT` and `HYDE_PROMPT` templates.
- [x] 3.3 Implement `backend/apps/chat/rag_chain.py`:
  - `get_retriever(user_id, k=5)` wrapping existing Chroma client and embeddings in LangChain `Chroma` retriever.
  - `run_query(user_id, query, message_histories, use_hyde)` orchestrating retrieval → prompt construction → LLM call → answer extraction.
  - Custom `LLMServiceError` exception for upstream LLM failures.

## Phase 4: Serializer & View

- [x] 4.1 Implement `backend/apps/chat/serializers.py` with `MessageHistorySerializer` (`role` ∈ {user, assistant}, `content` string) and `QuerySerializer` (`query` required non-empty string max 2000 chars, `message_histories` list default `[]`, `use_hyde` bool default `False`).
- [x] 4.2 Implement `backend/apps/chat/views.py` with `ChatQueryView` (POST, `IsAuthenticated`, delegates to `run_query`, catches `LLMServiceError` → 502).

## Phase 5: HyDE Bonus (Optional)

- [x] 5.1 Add HyDE retrieval path in `backend/apps/chat/rag_chain.py`: generate hypothetical passage → embed → Chroma similarity search with embedding vector → fallback to standard retriever on failure.
- [x] 5.2 Add warning-level logging when HyDE fallback is triggered.

## Phase 6: Automated Testing

- [x] 6.1 Write unit tests for `QuerySerializer` validation: missing query, empty query, invalid `message_histories` format, valid payloads, `use_hyde` default behavior.
- [x] 6.2 Write unit tests for `run_query` with mocked LLM and mocked Chroma retriever: verify prompt construction, context injection, history inclusion, answer extraction.
- [x] 6.3 Write integration tests for `POST /api/chat/query/`: 200 success with mocked LLM, 400 on invalid input, 401 without auth, 502 on LLM failure.
- [x] 6.4 Write unit tests for HyDE path: hypothetical generation, embedding-based retrieval, fallback behavior on LLM failure.
