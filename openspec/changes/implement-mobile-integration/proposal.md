## Why

The R.A.V.I.D. backend is fully operational — document upload, ingestion pipeline, and RAG chat query endpoints are implemented and tested. However, no mobile client exists yet. Without a Flutter front-end, users have no way to authenticate, manage documents, or interact with the RAG chatbot outside of raw API calls. Part 2 of the assessment requires a complete mobile integration covering authentication (2.1), document management (2.2), and a real-time chat interface (2.3).

## What Changes

- **New Flutter mobile application** scaffolded under `mobile/` following Clean Architecture with BLoC state management, as specified in `docs/02-mobile/architecture.md`.
- **Authentication & Session Management (`features/auth`):**
  - Login screen with username/password fields, basic validation (non-empty, minimum 8 characters).
  - JWT-based authentication against existing `POST /api/token/` and `POST /api/token/refresh/` endpoints.
  - Secure token persistence via `flutter_secure_storage` (iOS Keychain / Android Keystore).
  - Auto-login on app launch if a valid token exists; logout clears credentials and navigates to login.
  - **Constraint:** No user registration screen. The backend `/api/register/` endpoint is not yet wired. User accounts must be created manually via Django admin or management shell. The mobile app provides login only.
- **Document Management (`features/documents`):**
  - Document screen consuming the existing `POST /api/documents/upload/` and `GET /api/documents/status/?task_id=` endpoints.
  - File picker for `.pdf`, `.txt`, `.md` files; multipart upload; polling state machine for ingestion status.
- **Chat Interface (`features/chat`):**
  - Chat screen with responsive message thread (user bubbles right, assistant bubbles left), fixed input bar, auto-scroll.
  - Message status states: Sending (spinner), Delivered (checkmark), Failed (red alert + tap-to-retry).
  - Backend integration with `POST /api/chat/query/`, injecting last N messages as `message_histories`.
- **Bonus:** HyDE mode toggle in the chat UI sending `use_hyde: true` to the query endpoint.

## Capabilities

### New Capabilities
- `mobile-auth`: Flutter authentication module — login screen, JWT token management, secure storage, auto-login, logout.
- `mobile-documents`: Flutter document management module — file picking, upload, ingestion status polling UI.
- `mobile-chat`: Flutter chat interface module — message thread, input bar, status indicators, backend integration, context injection.

### Modified Capabilities
_(none — all backend endpoints are consumed as-is without modification)_

## Impact

- **New directory**: `mobile/` — complete Flutter application scaffold.
- **New files**: `pubspec.yaml`, `main.dart`, and all files under `lib/core/` and `lib/features/{auth,documents,chat}/`.
- **New dependencies**: `flutter_bloc`, `dio`, `flutter_secure_storage`, `file_picker`, `equatable`, `get_it` (DI).
- **Explicit exclusion**: No sign-up/registration flow in the mobile app — the backend lacks a wired registration endpoint.
- **No backend changes required** — the mobile app consumes existing JWT token and API endpoints.
- **External dependency**: Backend must be running and reachable from the mobile device/emulator.
