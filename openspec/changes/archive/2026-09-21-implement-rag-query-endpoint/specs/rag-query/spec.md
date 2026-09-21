# Specification Delta: RAG Query Endpoint

## ADDED Requirements

### Requirement: Chat Query Endpoint (`POST /api/chat/query/`)

The system shall provide a JSON endpoint allowing authenticated users to submit natural-language queries against their personal document knowledge base. The endpoint retrieves semantically relevant document chunks from the user's Chroma vector collection, constructs a context-augmented prompt incorporating optional conversation history, sends it to an LLM via OpenRouter, and returns the generated answer.

#### Scenario: Successful RAG query with context retrieval (HTTP 200)
- **GIVEN** an authenticated user with at least one successfully ingested document in their Chroma collection `user_{user_id}`
- **WHEN** the user sends a `POST` request to `/api/chat/query/` with JSON body:
  ```json
  {
    "query": "What is the cancellation policy mentioned in the employee handbook?",
    "message_histories": []
  }
  ```
- **THEN** the system uses LangChain's vector store retriever to search the user's Chroma collection for the top-k most semantically similar chunks to the query
- **AND** constructs a prompt containing the retrieved context chunks and the user's query
- **AND** sends the prompt to the LLM via OpenRouter (LangChain `ChatOpenAI` with `base_url=https://openrouter.ai/api/v1`)
- **AND** returns HTTP `200 OK` with payload:
  ```json
  {
    "answer": "The cancellation policy requires a written notice 14 days prior..."
  }
  ```

#### Scenario: Successful query with conversation history (HTTP 200)
- **GIVEN** an authenticated user with ingested documents
- **WHEN** the user sends a `POST` request to `/api/chat/query/` with JSON body:
  ```json
  {
    "query": "Can you elaborate on the notice period?",
    "message_histories": [
      {"role": "user", "content": "What is the cancellation policy?"},
      {"role": "assistant", "content": "The cancellation policy requires a written notice 14 days prior..."}
    ]
  }
  ```
- **THEN** the system incorporates the `message_histories` into the LLM prompt as prior conversation context
- **AND** performs vector retrieval and LLM generation as in the standard flow
- **AND** returns HTTP `200 OK` with the contextually aware answer in `{"answer": "..."}`

#### Scenario: Query with no matching documents returns LLM-generated fallback (HTTP 200)
- **GIVEN** an authenticated user whose Chroma collection is empty or contains no semantically relevant chunks
- **WHEN** the user sends a valid query to `/api/chat/query/`
- **THEN** the system retrieves zero or low-relevance chunks
- **AND** the LLM generates a response acknowledging limited context (e.g., "I don't have enough information in your documents to answer that question.")
- **AND** returns HTTP `200 OK` with `{"answer": "..."}`

#### Scenario: Missing or empty query field (HTTP 400)
- **GIVEN** an authenticated user
- **WHEN** the user sends a `POST` request to `/api/chat/query/` with a missing `query` field or an empty string `"query": ""`
- **THEN** the system returns HTTP `400 Bad Request` with payload:
  ```json
  {
    "error": "The 'query' field is required and must be a non-empty string."
  }
  ```

#### Scenario: Invalid message_histories format (HTTP 400)
- **GIVEN** an authenticated user
- **WHEN** the user sends a `POST` request with `message_histories` that is not a list, or contains entries missing `role` or `content` keys, or contains invalid `role` values (not `user` or `assistant`)
- **THEN** the system returns HTTP `400 Bad Request` with payload:
  ```json
  {
    "error": "Each entry in 'message_histories' must have 'role' (user|assistant) and 'content' (string)."
  }
  ```

#### Scenario: Unauthenticated request (HTTP 401)
- **GIVEN** a client request lacking a valid `Authorization: Bearer <jwt_token>` header
- **WHEN** the client sends a `POST` request to `/api/chat/query/`
- **THEN** the system returns HTTP `401 Unauthorized` with payload:
  ```json
  {
    "error": "Authentication credentials were not provided or token is invalid."
  }
  ```

#### Scenario: LLM service unavailable or timeout (HTTP 502)
- **GIVEN** an authenticated user with a valid query
- **WHEN** the OpenRouter API is unreachable, returns an error, or the request times out
- **THEN** the system returns HTTP `502 Bad Gateway` with payload:
  ```json
  {
    "error": "The AI service is temporarily unavailable. Please try again later."
  }
  ```

---

### Requirement: HyDE Retrieval Mode (Bonus — Optional)

When the request includes `"use_hyde": true`, the system shall use Hypothetical Document Embeddings to improve retrieval accuracy before performing standard RAG synthesis.

#### Scenario: HyDE-enhanced query (HTTP 200)
- **GIVEN** an authenticated user with ingested documents
- **WHEN** the user sends a `POST` request to `/api/chat/query/` with JSON body:
  ```json
  {
    "query": "What are the overtime compensation rules?",
    "message_histories": [],
    "use_hyde": true
  }
  ```
- **THEN** the system prompts the LLM to generate a hypothetical passage that would answer the query
- **AND** embeds the hypothetical passage using the same embedding model (`all-MiniLM-L6-v2`)
- **AND** uses the hypothetical passage embedding (instead of the raw query embedding) to search the user's Chroma collection
- **AND** passes the real retrieved chunks and original query to the LLM for final answer synthesis
- **AND** returns HTTP `200 OK` with `{"answer": "..."}`

#### Scenario: HyDE fallback on hypothetical generation failure (HTTP 200)
- **GIVEN** an authenticated user sends a query with `"use_hyde": true`
- **WHEN** the initial LLM call to generate the hypothetical passage fails (timeout, API error)
- **THEN** the system falls back to standard vector retrieval using the raw query embedding
- **AND** proceeds with normal RAG synthesis and returns HTTP `200 OK` with `{"answer": "..."}`
- **AND** logs a warning indicating HyDE fallback was triggered

#### Scenario: use_hyde defaults to false
- **GIVEN** a request to `/api/chat/query/` that omits the `use_hyde` field
- **THEN** the system uses standard RAG retrieval (no HyDE) by default
