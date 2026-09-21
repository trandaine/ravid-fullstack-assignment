# Test Cases & Verification Report

This document records the automated unit tests, integration tests, and live end-to-end HTTP endpoint test results for the RAVID platform, including the RAG Query Endpoint feature.

---

## Test Environment & Credentials

- **Target Host:** `http://localhost:8000`
- **Username:** `tranquangdai`
- **Password:** `Dai@2018`
- **Django Settings (Test Suite):** `config.settings.test`
- **Vector Storage:** ChromaDB (isolated collections: `user_<id>`)
- **LLM Provider:** OpenRouter API (`nvidia/nemotron-3.5-lightning:free`)

---

## 1. Automated Unit & Integration Test Suite (`pytest`)

**Execution Command:**
```bash
docker compose run --rm -e DJANGO_SETTINGS_MODULE=config.settings.test web pytest -v
```

**Result:** `52 passed in 4.44s` (100% Pass Rate)

| Test Module | Coverage Scope | Status | Passed / Total |
| :--- | :--- | :---: | :---: |
| `tests/test_chat_query.py` | Query serializer validation, message formatting, standard retrieval, HyDE generation & fallback, LLM service error handling, view status codes (200, 400, 401, 502) | PASSED | 23 / 23 |
| `tests/test_phase1_setup.py` | JWT endpoints (`/api/token/`, `/api/token/refresh/`), Celery app config, error envelope formatting | PASSED | 5 / 5 |
| `tests/test_phase2_models.py` | Document & IngestionJob model relationships and lifecycle transitions | PASSED | 1 / 1 |
| `tests/test_phase3_upload.py` | File validators, upload endpoint authentication & payload validations | PASSED | 6 / 6 |
| `tests/test_phase4_pipeline.py` | Chunking, embeddings stub, per-user vectorstore isolation, async Celery ingestion task | PASSED | 4 / 4 |
| `tests/test_phase5_status.py` | Ingestion status polling endpoint, state transitions (PENDING, STARTED, SUCCESS, FAILURE) | PASSED | 4 / 4 |
| `tests/test_phase6_verification.py` | End-to-end upload flow, extraction for PDF/TXT/MD, multi-tenant isolation | PASSED | 9 / 9 |

---

## 2. Live End-to-End HTTP Endpoint Tests

### Test Scenario 1: JWT Authentication
- **Endpoint:** `POST /api/token/`
- **Headers:** `Content-Type: application/json`
- **Request Body:**
  ```json
  {
    "username": "tranquangdai",
    "password": "Dai@2018"
  }
  ```
- **Response Status:** `200 OK`
- **Response Body:**
  ```json
  {
    "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
  ```

---

### Test Scenario 2: Document Upload & Ingestion Pipeline
- **Endpoint:** `POST /api/documents/upload/`
- **Headers:** `Authorization: Bearer <access_token>`
- **Payload:** `multipart/form-data` with sample document `handbook_policy.txt`:
  ```text
  RAVID Company Policy Handbook - Section 4: Cancellation and Leave Notice

  1. Leave Cancellation Policy:
  Employees must provide a written cancellation notice at least 14 days prior to their scheduled leave date to HR. Failure to provide 14 days written notice may result in forfeiture of allocated leave credits.

  2. Overtime Compensation:
  Overtime worked on weekends is compensated at 1.5 times the standard hourly rate. All overtime requests must be approved in advance by department leads.

  3. Remote Work Equipment:
  The company provides a $500 home office stipend for all full-time remote engineers upon completion of their probationary period.
  ```
- **Response Status:** `202 Accepted`
- **Response Body:**
  ```json
  {
    "message": "Document uploaded and ingestion started",
    "document_id": 4,
    "task_id": "bb071864-4b33-4fae-ae3c-01fecf968a0d"
  }
  ```
- **Status Polling:** `GET /api/documents/status/?task_id=bb071864-4b33-4fae-ae3c-01fecf968a0d`
- **Polling Response Status:** `200 OK`
  ```json
  {
    "task_id": "bb071864-4b33-4fae-ae3c-01fecf968a0d",
    "status": "SUCCESS",
    "message": "Document successfully parsed, embedded, and indexed in vector storage."
  }
  ```

---

### Test Scenario 3: Standard RAG Query
- **Endpoint:** `POST /api/chat/query/`
- **Headers:**
  - `Authorization: Bearer <access_token>`
  - `Content-Type: application/json`
- **Request Body:**
  ```json
  {
    "query": "What is the cancellation policy mentioned in the employee handbook?",
    "message_histories": []
  }
  ```
- **Response Status:** `200 OK`
- **Response Body:**
  ```json
  {
    "answer": "According to the RAVID Company Policy Handbook (Section 4: Cancellation and Leave Notice), employees must provide a written cancellation notice at least 14 days prior to their scheduled leave date to HR. Failure to provide this 14-day written notice may result in forfeiture of allocated leave credits."
  }
  ```

---

### Test Scenario 4: Multi-Turn Conversation History
- **Endpoint:** `POST /api/chat/query/`
- **Headers:**
  - `Authorization: Bearer <access_token>`
  - `Content-Type: application/json`
- **Request Body:**
  ```json
  {
    "query": "What about weekend overtime rate?",
    "message_histories": [
      {
        "role": "user",
        "content": "What is the cancellation policy mentioned in the employee handbook?"
      },
      {
        "role": "assistant",
        "content": "Employees must provide a written cancellation notice at least 14 days prior to their scheduled leave date to HR."
      }
    ]
  }
  ```
- **Response Status:** `200 OK`
- **Response Body:**
  ```json
  {
    "answer": "According to the RAVID Company Policy Handbook (Section 4), overtime worked on weekends is compensated at **1.5 times the standard hourly rate**. All overtime requests must also be approved in advance by department leads."
  }
  ```

---

### Test Scenario 5: HyDE Mode (`use_hyde: true`)
- **Endpoint:** `POST /api/chat/query/`
- **Headers:**
  - `Authorization: Bearer <access_token>`
  - `Content-Type: application/json`
- **Request Body:**
  ```json
  {
    "query": "How much stipend do remote engineers receive?",
    "use_hyde": true
  }
  ```
- **Response Status:** `200 OK`
- **Response Body:**
  ```json
  {
    "answer": "According to the RAVID Company Policy Handbook (Section 4, item 3), remote engineers receive a **$500 home office stipend** upon completion of their probationary period."
  }
  ```

---

### Test Scenario 6: Security & Validation Error Handling Matrix

| Scenario | Request Payload / Header | Expected Status | Response Error Body | Status |
| :--- | :--- | :---: | :--- | :---: |
| **Unauthenticated Request** | Omit `Authorization` header | `401 Unauthorized` | `{"error": "Authentication credentials were not provided."}` | PASSED |
| **Missing Query Field** | `{"message_histories": []}` | `400 Bad Request` | `{"error": "The 'query' field is required and must be a non-empty string."}` | PASSED |
| **Empty Query String** | `{"query": "   "}` | `400 Bad Request` | `{"error": "The 'query' field is required and must be a non-empty string."}` | PASSED |
| **Invalid History Role** | `[{"role": "admin", "content": "test"}]` | `400 Bad Request` | `{"error": "An error occurred."}` | PASSED |
| **Blank History Content** | `[{"role": "user", "content": "  "}]` | `400 Bad Request` | `{"error": "An error occurred."}` | PASSED |
| **Upstream LLM Failure** | OpenRouter outage simulation | `502 Bad Gateway` | `{"error": "The AI service is temporarily unavailable. Please try again later."}` | PASSED |
