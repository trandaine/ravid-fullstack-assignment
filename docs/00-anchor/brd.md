# Business Requirements Document

## Project

- Project name: R.A.V.I.D. Fullstack & Mobile Assessment (RAG Document Chatbot)
- Assessment title: Take-Home Assignment — Fullstack Developer — Assessment & Evaluation for Remote Candidates — September 2026
- Assessment type: take-home fullstack exercise (Backend API, RAG implementation, Mobile application)
- Issuing organization: R.A.V.I.D. (Lead: Truong Vinh Phuoc "Matthew")
- Project start date: Friday, September 19th, 2026
- Last submission date: Sunday, September 21st, 2026

## Background

The assessment requires building a fullstack AI chatbot solution composed of a robust backend infrastructure and a responsive mobile application. The system enables users to upload private documents (`.pdf`, `.txt`, `.md`) to construct an isolated personal knowledge base and interactively query those documents using an AI assistant powered by Retrieval-Augmented Generation (RAG).

Concretely, the solution comprises two synchronized components:

1. **Backend Infrastructure (Python / Django / LangChain / OpenRouter / Chroma / Celery / Docker)**:
   - registers and authenticates users via HTTP Basic Auth or JWT bearer tokens
   - protects private document management and chat endpoints behind authentication
   - accepts private document uploads (PDF, TXT, Markdown) per authenticated user
   - processes each upload asynchronously: text extraction, recursive chunking, embedding generation, and vector indexing into an isolated namespace linked to the user
   - exposes ingestion task status for polling (`PROCESSING`, `SUCCESS`, `FAILURE`)
   - answers natural-language queries by retrieving owner-scoped document chunks and synthesizing grounded answers via OpenRouter free-tier LLMs
   - provides advanced retrieval via HyDE (Hypothetical Document Embeddings) to bridge query-document semantic gaps
   - packages all services via Docker and Docker Compose with OpenAPI documentation

2. **Mobile Application (Flutter)**:
   - provides authentication and secure session management (Keychain / Keystore / `flutter_secure_storage`)
   - delivers a document management UI to upload files and monitor ingestion status
   - provides an interactive chat interface with message bubbles, status indicators (Sending, Delivered, Failed with retry), and dynamic conversation context injection
   - supports multi-thread chat management, local persistence, offline reading, and thread deletion with cascade cleanup

## Objective

Deliver a complete, production-minded Fullstack RAG Chatbot system (Django backend + Flutter mobile app) that fulfills all assessment requirements, showcases architectural discipline, and provides an effortless review experience.

## Stakeholders

- Candidate: implements, tests, and documents the fullstack solution
- Primary Reviewer: Mr. Truong Vinh Phuoc "Matthew" (`phuoc.truong@ravid.cloud`) and Senior Technical Stakeholders
- End Users: mobile users who upload private documents to query their personal knowledge base securely

## Business Goals

- Demonstrate practical fullstack proficiency spanning API design, async background pipelines, RAG orchestration, and modern mobile app architecture
- Guarantee per-user data isolation (one user cannot access, index, or retrieve another user's private documents or vectors)
- Provide robust semantic retrieval with standard RAG and advanced HyDE options
- Deliver a clean, state-managed, offline-capable Flutter application
- Ensure seamless containerized local execution and zero-cost operation via OpenRouter free-tier models and local offline embeddings

## In Scope

- user authentication (HTTP Basic Auth and JWT token support)
- authenticated document upload API accepting PDF, TXT, and Markdown files with validation (type allowlist, 10 MB limit)
- asynchronous ingestion via Celery: text extraction (`pypdf`, text loaders), chunking (`RecursiveCharacterTextSplitter`), embedding, and isolated vector storage
- ingestion task status API for client polling (`PROCESSING`, `SUCCESS`, `FAILURE`)
- isolated vector storage namespace per user in Chroma (`user_{user_id}`)
- RAG chat query API (`POST /api/chat/query/`) with dynamic conversation history injection
- HyDE (Hypothetical Document Embeddings) toggle (`use_hyde: true`) with zero-shot query expansion and fallback handling
- OpenAPI 3.0.3 specification and interactive Swagger UI documentation
- complete Docker Compose packaging (Django web, PostgreSQL, Redis, Celery worker, Chroma vector store)
- Flutter mobile client with:
  - Login UI and secure credential/token persistence
  - Document management and upload status tracking screen
  - Real-time chat screen with user/assistant bubbles, sending/delivered/failed states, and auto-scroll
  - Multi-thread session drawer, local cache for offline reading, and thread deletion
- comprehensive documentation: BRD, SRS, Glossary, System Context, Database Design, Docker Design, Project Structure, and Mobile Architecture

## Out Of Scope

- production multi-region cloud deployment
- paid commercial LLM or embedding API subscriptions (must run 100% free of charge)
- cross-user collaborative document sharing or team workspaces
- audio/image OCR extraction beyond standard PDF/TXT/MD text parsing
- third-party OAuth social login providers (Google/Apple SSO)

## Primary Users And Core Journeys

### Mobile Application User

- launches the Flutter application, registers or logs in, and establishes a secure session
- uploads private documents from mobile storage to build a personal knowledge base
- monitors real-time ingestion status until documents are indexed
- creates new chat threads or opens existing threads from the drawer
- asks questions against their documents with standard RAG or HyDE-enhanced retrieval
- reviews past conversations offline from local storage

### Technical Reviewer

- inspects project documentation and architectural specifications
- spins up the backend infrastructure using `docker compose up --build`
- tests backend endpoints via Swagger UI or curl walkthrough
- builds and runs the Flutter application on simulator/emulator or reviews the demo recording/APK
- evaluates code quality, per-user isolation guarantees, and error handling

## Deliverables

- Django backend source code with modular architecture
- Flutter mobile application source code
- Docker and Docker Compose configuration files
- OpenAPI 3.0.3 specification (`api_contract.yaml`) and live Swagger UI
- Architecture and specification suite under `docs/`
- Root `README.md` with reviewer walkthrough, quickstart guide, and architectural topology

## Success Criteria

- all backend endpoints match the assessment specification paths, methods, and payloads exactly
- vector storage strictly isolates documents per user namespace (`user_{user_id}`)
- ingestion runs asynchronously, exposes polling status, and surfaces parse/embed failures gracefully
- RAG query returns grounded answers from user documents and declines gracefully when no relevant context exists
- HyDE pipeline correctly drafts hypothetical passages, embeds them, and retrieves higher-semantic matches
- Flutter mobile app compiles cleanly, persists sessions securely, manages chat threads, and operates offline
- complete backend stack boots with a single `docker compose up --build` command

## Constraints

- strict timeline: project duration September 19th – September 21st, 2026
- zero-cost operational requirement: OpenRouter free-tier LLM gateway and local open-source embedding models
- exact endpoint contracts from the assessment brief must be preserved
- per-user data isolation is non-negotiable

## Risks

- OpenRouter free-tier model availability and rate limits require fallback resilience
- local embedding model initial download during first container build requires pre-caching or clear startup documentation
- mobile-to-backend networking across Docker host and mobile emulators/devices requires clear host IP configuration
- cross-user namespace leakage if user context is improperly passed to vector store queries

## Working Principle

Where requirements contain ambiguities, the architecture chooses clean, robust, and industry-standard defaults, documenting them in the SRS and architectural guides. All provider integrations verify live model slugs at runtime with sensible fallbacks.
