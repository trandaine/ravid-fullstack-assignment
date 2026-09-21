# Design: RAG Query Endpoint

## Overview

Add a `POST /api/chat/query/` endpoint that performs retrieval-augmented generation against the authenticated user's Chroma document collection. The design reuses existing vector store and embedding infrastructure, adds LLM integration via OpenRouter, and introduces a new `chat` Django app with minimal footprint.

## Architecture

### New Django App: `backend/apps/chat/`

```
backend/apps/chat/
├── __init__.py
├── apps.py            # ChatConfig
├── urls.py            # single route: POST query/
├── serializers.py     # QuerySerializer
├── views.py           # ChatQueryView
├── llm.py             # get_llm() → ChatOpenAI configured for OpenRouter
├── rag_chain.py       # build_rag_chain(), build_hyde_chain()
└── prompts.py         # RAG_SYSTEM_PROMPT, HYDE_PROMPT templates
```

### Component Interaction

```
Request → ChatQueryView
  → QuerySerializer (validate query, message_histories, use_hyde)
  → rag_chain.run_query(user_id, query, history, use_hyde)
    → IF use_hyde:
        → llm.get_llm() → generate hypothetical passage
        → embeddings.get_embeddings() → embed hypothetical
        → vectorstore search with hypothetical embedding
        → (fallback to standard on failure)
    → ELSE:
        → LangChain Chroma retriever (user's collection) → top-k chunks
    → Construct prompt: system prompt + context chunks + history + query
    → llm.get_llm() → generate answer
  → Response {"answer": "..."}
```

## Key Design Decisions

### 1. LLM Integration (`backend/apps/chat/llm.py`)

Use LangChain's `ChatOpenAI` with OpenRouter:

```python
from langchain_openai import ChatOpenAI

def get_llm() -> ChatOpenAI:
    return ChatOpenAI(
        model=settings.OPENROUTER_MODEL,       # e.g. "mistralai/mistral-7b-instruct:free"
        openai_api_key=settings.OPENROUTER_API_KEY,
        openai_api_base="https://openrouter.ai/api/v1",
        temperature=0.3,
        max_tokens=1024,
        timeout=30,
    )
```

Settings added to `base.py`:
```python
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
OPENROUTER_MODEL = os.environ.get("OPENROUTER_MODEL", "mistralai/mistral-7b-instruct:free")
OPENROUTER_TIMEOUT = int(os.environ.get("OPENROUTER_TIMEOUT", "30"))
```

### 2. Vector Retrieval (`backend/apps/chat/rag_chain.py`)

Wrap existing Chroma infrastructure via LangChain's `Chroma` class to get a retriever:

```python
from langchain_community.vectorstores import Chroma
from apps.rag.embeddings import get_embeddings
from apps.rag.vectorstore import get_chroma_client

def get_retriever(user_id: int, k: int = 5):
    client = get_chroma_client()
    collection_name = f"user_{user_id}"
    vectorstore = Chroma(
        client=client,
        collection_name=collection_name,
        embedding_function=get_embeddings(),
    )
    return vectorstore.as_retriever(search_kwargs={"k": k})
```

### 3. Prompt Construction (`backend/apps/chat/prompts.py`)

System prompt template that injects retrieved context and conversation history:

```python
RAG_SYSTEM_PROMPT = """You are a helpful assistant that answers questions based on the user's documents.
Use ONLY the following context to answer. If the context doesn't contain relevant information, say so.

Context:
{context}
"""
```

Conversation history is passed as LangChain message objects (`HumanMessage`, `AIMessage`) derived from `message_histories`.

### 4. Serializer (`backend/apps/chat/serializers.py`)

```python
class MessageHistorySerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=["user", "assistant"])
    content = serializers.CharField()

class QuerySerializer(serializers.Serializer):
    query = serializers.CharField(required=True, min_length=1, max_length=2000)
    message_histories = MessageHistorySerializer(many=True, required=False, default=[])
    use_hyde = serializers.BooleanField(required=False, default=False)
```

### 5. View (`backend/apps/chat/views.py`)

```python
class ChatQueryView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = QuerySerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        try:
            answer = run_query(
                user_id=request.user.id,
                query=data["query"],
                message_histories=data["message_histories"],
                use_hyde=data["use_hyde"],
            )
            return Response({"answer": answer}, status=200)
        except LLMServiceError:
            return Response(
                {"error": "The AI service is temporarily unavailable. Please try again later."},
                status=502,
            )
```

### 6. HyDE Pipeline (Optional Bonus)

When `use_hyde=True`:
1. Call LLM with `HYDE_PROMPT` to generate a hypothetical answer passage.
2. Embed the hypothetical passage using `get_embeddings()`.
3. Use the embedding vector to query Chroma directly (bypassing the text-based retriever).
4. Pass the real retrieved chunks + original query to LLM for final synthesis.

Fallback: If step 1 fails, log a warning and fall back to standard retriever flow.

```python
HYDE_PROMPT = """Given the following question, write a detailed paragraph that would 
directly answer it, as if it were found in an official document. Do not include 
any preamble or meta-commentary.

Question: {query}

Hypothetical answer:"""
```

### 7. Error Handling

- Validation errors (400): Handled by DRF serializer + existing `error_envelope_handler`.
- Auth errors (401): Handled by DRF + SimpleJWT defaults.
- LLM failures (502): Caught in the view, wrapped in a custom `LLMServiceError` exception. Catches `openai.APIError`, `openai.Timeout`, `requests.ConnectionError`.
- Add `502` to `_HANDLED_STATUSES` in `backend/apps/common/exceptions.py` if needed, or handle directly in the view.

### 8. URL Wiring

`backend/apps/chat/urls.py`:
```python
urlpatterns = [path("query/", ChatQueryView.as_view(), name="chat-query")]
```

`backend/config/urls.py` addition:
```python
path("api/chat/", include("apps.chat.urls")),
```

## Dependencies

- **New**: `langchain-openai` (provides `ChatOpenAI`)
- **Existing reused**: `langchain-community` (Chroma wrapper), `apps.rag.embeddings`, `apps.rag.vectorstore`

## Non-Goals

- Chat history persistence (no new models/tables)
- Streaming responses
- Rate limiting on the chat endpoint (can be added later)
