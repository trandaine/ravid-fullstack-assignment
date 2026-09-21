# Implementation Tasks: Mobile Integration

## Phase 1: Flutter Project Scaffold & Core Setup

- [ ] 1.1 Initialize Flutter project under `mobile/` with `flutter create` and configure `pubspec.yaml` with dependencies: `flutter_bloc`, `bloc`, `equatable`, `dio`, `flutter_secure_storage`, `file_picker`, `get_it`, `uuid`.
- [ ] 1.2 Set up directory structure: `lib/core/{api,storage,theme,widgets}`, `lib/features/{auth,documents,chat}/{data,bloc,presentation}`, `test/{auth,documents,chat}`.
- [ ] 1.3 Implement `core/storage/secure_storage.dart` — wrapper around `flutter_secure_storage` with methods: `writeAccessToken`, `writeRefreshToken`, `readAccessToken`, `readRefreshToken`, `clearAll`.
- [ ] 1.4 Implement `core/api/api_client.dart` — Dio factory with base URL (configurable), 15s connect/receive timeouts.
- [ ] 1.5 Implement `core/api/auth_interceptor.dart` — reads access token from secure storage, attaches `Authorization: Bearer <token>` header.
- [ ] 1.6 Implement `core/api/error_interceptor.dart` — parses backend `{"error": "..."}` responses, broadcasts `TokenExpired` to `AuthBloc` on unrecoverable 401.
- [ ] 1.7 Set up `get_it` dependency injection in `main.dart` — register all services, repositories, and BLoCs.
- [ ] 1.8 Create `app.dart` with `MaterialApp`, app theme (`core/theme/app_theme.dart`), and router that conditionally renders `LoginScreen` or main scaffold based on `AuthBloc` state.

## Phase 2: Authentication Feature

> **Constraint:** No registration/sign-up UI or logic. Users are created via Django admin or shell. Do not implement any screen, route, repository method, or BLoC event related to user registration.

- [ ] 2.1 Implement `features/auth/data/auth_repository.dart` — `login(username, password)` calling `POST /api/token/`, `refreshToken()` calling `POST /api/token/refresh/`, both persisting tokens to secure storage.
- [ ] 2.2 Implement `features/auth/bloc/auth_event.dart` — events: `AppStarted`, `LoginRequested(username, password)`, `LogoutRequested`, `TokenExpired`.
- [ ] 2.3 Implement `features/auth/bloc/auth_bloc.dart` — states: `AuthInitial`, `AuthLoading`, `Authenticated`, `Unauthenticated(error?)`. On `AppStarted`: check stored token → validate/refresh → emit `Authenticated` or `Unauthenticated`. On `LoginRequested`: call repository → emit result. On `LogoutRequested`/`TokenExpired`: clear storage → emit `Unauthenticated`.
- [ ] 2.4 Implement `features/auth/presentation/login_screen.dart` — username and password `TextFormField` with validation (non-empty, password ≥ 8 chars), "Login" button, error display snackbar/inline, loading state.

## Phase 3: Document Management Feature

- [ ] 3.1 Implement `features/documents/data/document_repository.dart` — `uploadDocument(File)` sending multipart/form-data to `POST /api/documents/upload/`, `checkIngestionStatus(taskId)` calling `GET /api/documents/status/?task_id=<id>`.
- [ ] 3.2 Implement `features/documents/bloc/document_event.dart` and `features/documents/bloc/document_bloc.dart` — events: `UploadRequested(file)`, `PollStatus(taskId)`. States: `DocumentInitial`, `DocumentUploading`, `DocumentPolling(taskId)`, `DocumentSuccess`, `DocumentFailure(error)`. Polling logic with 2-second periodic timer.
- [ ] 3.3 Implement `features/documents/presentation/document_screen.dart` — file picker button (filtered to pdf/txt/md), upload progress, ingestion status badges (spinner for PROCESSING, green checkmark for SUCCESS, error banner for FAILURE).

## Phase 4: Chat Interface Feature

- [ ] 4.1 Implement `features/chat/data/models/message.dart` — `Message` class with `id`, `content`, `role` (user/assistant), `status` (sending/delivered/failed), `timestamp`.
- [ ] 4.2 Implement `features/chat/data/chat_repository.dart` — `sendQuery(query, messageHistories, useHyde)` calling `POST /api/chat/query/` and returning the answer string.
- [ ] 4.3 Implement `features/chat/bloc/chat_event.dart` and `features/chat/bloc/chat_bloc.dart` — events: `SendMessage(text)`, `RetryMessage(messageId)`, `ToggleHyde(enabled)`. States manage message list with optimistic updates. On send: add user message (status: sending) → call repository → update to delivered + add assistant response, or update to failed. Inject last 6 messages as `message_histories`.
- [ ] 4.4 Implement `features/chat/presentation/widgets/message_bubble.dart` — user messages right-aligned with primary accent, assistant messages left-aligned with neutral card styling.
- [ ] 4.5 Implement `features/chat/presentation/widgets/message_status.dart` — icon widget: spinner for sending, checkmark for delivered, red alert for failed (tappable).
- [ ] 4.6 Implement `features/chat/presentation/chat_screen.dart` — `ListView` with auto-scroll to bottom on new messages, fixed bottom input bar with multi-line `TextField`, send button (disabled when empty), HyDE toggle switch in AppBar.

## Phase 5: Navigation & Integration

- [ ] 5.1 Wire main scaffold with bottom navigation bar: Documents tab → `DocumentScreen`, Chat tab → `ChatScreen`.
- [ ] 5.2 Implement conditional routing: `AuthBloc` → `Unauthenticated` shows `LoginScreen`, `Authenticated` shows main scaffold.
- [ ] 5.3 Add logout action accessible from the app bar on main screens, triggering `LogoutRequested` event.

## Phase 6: Testing

- [ ] 6.1 Write unit tests for `AuthBloc`: login success/failure, auto-login with valid/expired token, logout, token expiry event.
- [ ] 6.2 Write unit tests for `DocumentBloc`: upload success → polling → success/failure lifecycle, upload rejection handling.
- [ ] 6.3 Write unit tests for `ChatBloc`: send message optimistic update, delivery success, delivery failure + retry, HyDE toggle, context injection (last 6 messages).
- [ ] 6.4 Write widget tests for `LoginScreen`: form validation, button state, error display.
