# Implementation Tasks: Mobile Integration

## Phase 1: Backend Prerequisites

- [ ] 1.1 Implement `DocumentListView` in `backend/apps/documents/views.py` — `GET /api/documents/` returning `Document.objects.filter(owner=request.user)` serialized via existing `DocumentSerializer`. Permission: `IsAuthenticated`.
- [ ] 1.2 Implement `DocumentDeleteView` in `backend/apps/documents/views.py` — `DELETE /api/documents/<int:pk>/` deleting the document only if `owner == request.user`, returning HTTP `204 No Content`. Return `404` if not found or not owned. Permission: `IsAuthenticated`.
- [ ] 1.3 Wire routes in `backend/apps/documents/urls.py`: `path("", DocumentListView.as_view(), name="document-list")` and `path("<int:pk>/", DocumentDeleteView.as_view(), name="document-delete")`.
- [ ] 1.4 Write tests for `GET /api/documents/` (owner-scoped list, empty list) and `DELETE /api/documents/<id>/` (success, not-found, foreign-user 404).
- [ ] 1.5 Update `docs/02-mobile/architecture.md` — change "Email and password form" to "Username and password form" to align with backend `auth.User` model and OpenSpec artifacts.

## Phase 2: Flutter Project Scaffold & Core Setup

- [ ] 2.1 Initialize Flutter project under `mobile/` with `flutter create` and configure `pubspec.yaml` with dependencies: `flutter_bloc`, `bloc`, `equatable`, `dio`, `flutter_secure_storage`, `file_picker`, `get_it`, `uuid`.
- [ ] 2.2 Set up directory structure: `lib/core/{api,events,storage,theme,widgets}`, `lib/features/{auth,documents,chat}/{data,bloc,presentation}`, `test/{auth,documents,chat}`.
- [ ] 2.3 Implement `core/storage/secure_storage.dart` — wrapper around `flutter_secure_storage` with methods: `writeAccessToken`, `writeRefreshToken`, `readAccessToken`, `readRefreshToken`, `clearAll`. Tokens MUST ONLY be stored via this service (no `SharedPreferences` fallback).
- [ ] 2.4 Implement `core/events/unauthenticated_event.dart` — broadcast `StreamController<void>` for decoupled logout signaling between Dio interceptor and AuthBloc.
- [ ] 2.5 Implement `core/api/api_client.dart` — Dio factory with configurable base URL, 15s connect timeout, 30s default receive timeout. Chat repository uses per-request 90s receive timeout override for `POST /api/chat/query/`.
- [ ] 2.6 Implement `core/api/auth_interceptor.dart` — unified `AuthQueuedInterceptor` extending `QueuedInterceptor`. Injects `Authorization: Bearer <token>` on all requests. On 401: acquires mutex, performs single `POST /api/token/refresh/`, replays queued requests on success, signals logout via unauthenticated event stream on failure. No direct dependency on `AuthBloc`.
- [ ] 2.7 Set up `get_it` dependency injection in `main.dart`. Registration order: (1) `StreamController<void>` (unauthenticated events), (2) `SecureStorageService`, (3) `Dio` via `createDio()`, (4) repositories (`AuthRepository`, `DocumentRepository`, `ChatRepository`), (5) BLoCs (`AuthBloc` subscribes to unauthenticated stream, `DocumentBloc`, `ChatBloc`).
- [ ] 2.8 Create `app.dart` with `MaterialApp`, app theme (`core/theme/app_theme.dart`), and router that conditionally renders: `AuthCheckInProgress` → branded splash screen, `Unauthenticated` → `LoginScreen`, `Authenticated` → main scaffold.
- [ ] 2.9 Implement `core/widgets/empty_state.dart` — reusable empty-state placeholder widget accepting a message string and optional icon.

## Phase 3: Authentication Feature

> **Constraint:** No registration/sign-up UI or logic. Users are created via Django admin or shell. Do not implement any screen, route, repository method, or BLoC event related to user registration.

- [ ] 3.1 Implement `features/auth/data/auth_repository.dart` — `login(username, password)` calling `POST /api/token/`, `refreshToken()` calling `POST /api/token/refresh/`, both persisting tokens to secure storage.
- [ ] 3.2 Implement `features/auth/bloc/auth_event.dart` — events: `AppStarted`, `LoginRequested(username, password)`, `LogoutRequested`, `TokenExpired`.
- [ ] 3.3 Implement `features/auth/bloc/auth_bloc.dart` — states: `AuthInitial`, `AuthCheckInProgress`, `AuthLoading`, `Authenticated`, `Unauthenticated(error?)`. On `AppStarted`: emit `AuthCheckInProgress` (branded splash) → read stored tokens → parse JWT `exp` locally → if expired or <5 min remaining, proactively refresh → emit `Authenticated` or `Unauthenticated`. Subscribe to unauthenticated event stream for interceptor-driven logout. On `LogoutRequested`/`TokenExpired`: clear storage → dispatch `ChatReset` to `ChatBloc` and `DocumentReset` to `DocumentBloc` → emit `Unauthenticated`.
- [ ] 3.4 Implement `features/auth/presentation/login_screen.dart` — username and password `TextFormField` with validation (non-empty, password ≥ 8 chars), "Login" button, error display snackbar/inline, loading state.

## Phase 4: Document Management Feature

- [ ] 4.1 Implement `features/documents/data/document_repository.dart` — `fetchDocuments()` calling `GET /api/documents/`, `uploadDocument(File)` sending multipart/form-data to `POST /api/documents/upload/`, `checkIngestionStatus(taskId)` calling `GET /api/documents/status/?task_id=<id>`, `deleteDocument(int documentId)` calling `DELETE /api/documents/<id>/`.
- [ ] 4.2 Implement `features/documents/bloc/document_event.dart` and `features/documents/bloc/document_bloc.dart` — events: `LoadDocuments`, `UploadRequested(file)`, `PollStatus(taskId)`, `DeleteDocument(documentId)`, `DocumentReset`. States: `DocumentInitial`, `DocumentLoading`, `DocumentLoaded(documents, isEmpty)`, `DocumentUploading`, `DocumentPolling(taskId)`, `DocumentSuccess`, `DocumentFailure(error)`. Polling logic with 2-second periodic timer and **2-minute max duration** (60 ticks). Cancel timer subscription on widget disposal or new event. On timeout, emit `DocumentFailure("Ingestion timed out. Please check again later.")`. On `DocumentReset`: clear in-memory document list, cancel active polling timers.
- [ ] 4.3 Implement `features/documents/presentation/document_screen.dart` — file picker button (filtered to pdf/txt/md), upload progress, ingestion status badges (spinner for PROCESSING, green checkmark for SUCCESS, error banner for FAILURE), document list with delete action, empty-state placeholder when list is empty.

## Phase 5: Chat Interface Feature

- [ ] 5.1 Implement `features/chat/data/models/message.dart` — `Message` class with `id` (String, UUID), `content`, `role` (user/assistant), `status` (sending/delivered/failed), `timestamp`.
- [ ] 5.2 Implement `features/chat/data/chat_repository.dart` — `sendQuery(query, messageHistories, useHyde)` calling `POST /api/chat/query/` with `Options(receiveTimeout: Duration(seconds: 90))` and returning the answer string.
- [ ] 5.3 Implement `features/chat/bloc/chat_event.dart` and `features/chat/bloc/chat_bloc.dart` — events: `SendMessage(text)`, `RetryMessage(messageId)`, `ToggleHyde(enabled)`, `ChatReset`. States manage message list with optimistic updates. On send: add user message (status: sending) → call repository → update to delivered + add assistant response, or update to failed. **Context injection**: filter conversation for `status == MessageStatus.delivered` only, take last 6, map to `List<Map<String, String>>` matching `[{"role": "user"|"assistant", "content": "..."}]`. On `ChatReset`: clear all in-memory messages.
- [ ] 5.4 Implement `features/chat/presentation/widgets/message_bubble.dart` — user messages right-aligned with primary accent, assistant messages left-aligned with neutral card styling.
- [ ] 5.5 Implement `features/chat/presentation/widgets/message_status.dart` — icon widget: spinner for sending, checkmark for delivered, red alert for failed (tappable).
- [ ] 5.6 Implement `features/chat/presentation/chat_screen.dart` — `ListView` with auto-scroll to bottom on new messages, `Scaffold(resizeToAvoidBottomInset: true)` with `ScrollController` animating to bottom on keyboard appearance, fixed bottom input bar with multi-line `TextField`, send button (disabled when empty OR when any message is in `sending` state), HyDE toggle switch in AppBar, empty-state placeholder when no messages exist.

## Phase 6: Navigation & Integration

- [ ] 6.1 Wire main scaffold with bottom navigation bar: Documents tab → `DocumentScreen`, Chat tab → `ChatScreen`.
- [ ] 6.2 Implement conditional routing: `AuthCheckInProgress` → branded splash screen, `Unauthenticated` → `LoginScreen`, `Authenticated` → main scaffold.
- [ ] 6.3 Add logout action accessible from the app bar on main screens, triggering `LogoutRequested` event (which cascades `ChatReset` and `DocumentReset` to all BLoCs before clearing auth state).

## Phase 7: Testing

- [ ] 7.1 Write unit tests for `AuthBloc`: login success/failure, auto-login with valid/expired token (proactive refresh at <5 min), auto-login with no stored token, logout cascading reset to ChatBloc/DocumentBloc, concurrent 401 handling via queued interceptor.
- [ ] 7.2 Write unit tests for `DocumentBloc`: load documents (populated/empty), upload success → polling → success/failure lifecycle, polling timeout at 2 minutes, upload rejection handling, delete success/failure, `DocumentReset` event.
- [ ] 7.3 Write unit tests for `ChatBloc`: send message optimistic update, delivery success, delivery failure + retry, HyDE toggle, context injection (last 6 **delivered** messages only — verify sending/failed excluded), `ChatReset` event.
- [ ] 7.4 Write widget tests for `LoginScreen`: form validation, button state, error display.
- [ ] 7.5 Write integration tests for backend prerequisite endpoints: `GET /api/documents/` (owner-scoped), `DELETE /api/documents/<id>/` (owner-scoped, 404 for foreign user).
