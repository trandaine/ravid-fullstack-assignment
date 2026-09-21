# Design: Mobile Integration

## Overview

Build a Flutter 3.x mobile application under `mobile/` consuming the existing RAVID Django backend. The app follows Clean Architecture with BLoC state management, Dio for HTTP, and `flutter_secure_storage` for credential persistence. Three feature modules — auth, documents, and chat — each own their presentation, BLoC, repository, and data source layers.

A small backend prerequisite must be completed first: wire `GET /api/documents/` (list) and `DELETE /api/documents/<id>/` (delete) views using the existing `DocumentSerializer`, scoped to the authenticated user.

## Architecture

### Directory Structure

```
mobile/
├── pubspec.yaml
├── lib/
│   ├── main.dart                       # App bootstrap, DI setup (get_it), initial route
│   ├── app.dart                        # MaterialApp, theme, router
│   ├── core/
│   │   ├── api/
│   │   │   ├── api_client.dart         # Dio singleton factory with base URL, two-tier timeouts
│   │   │   └── auth_interceptor.dart   # QueuedInterceptor: injects Bearer token, handles 401 refresh with mutex
│   │   ├── events/
│   │   │   └── unauthenticated_event.dart  # StreamController<void> for logout signaling (decouples Dio from AuthBloc)
│   │   ├── storage/
│   │   │   └── secure_storage.dart     # flutter_secure_storage wrapper (read/write/clear tokens)
│   │   ├── theme/
│   │   │   └── app_theme.dart          # Colors, typography, layout constants
│   │   └── widgets/
│   │       ├── loading_indicator.dart
│   │       ├── error_banner.dart
│   │       └── empty_state.dart        # Reusable empty-state placeholder widget
│   └── features/
│       ├── auth/
│       │   ├── data/
│       │   │   └── auth_repository.dart     # POST /api/token/, POST /api/token/refresh/
│       │   ├── bloc/
│       │   │   ├── auth_bloc.dart           # States: initial, checkInProgress, loading, authenticated, unauthenticated
│       │   │   └── auth_event.dart          # LoginRequested, LogoutRequested, AppStarted, TokenExpired
│       │   └── presentation/
│       │       └── login_screen.dart        # Username/password form, validation, error display
│       ├── documents/
│       │   ├── data/
│       │   │   └── document_repository.dart # GET /api/documents/, POST .../upload/, GET .../status/, DELETE .../<id>/
│       │   ├── bloc/
│       │   │   ├── document_bloc.dart       # States: initial, loading, loaded, uploading, polling, success, failure
│       │   │   └── document_event.dart      # LoadDocuments, UploadRequested, PollStatus, PollCompleted, DeleteDocument, DocumentReset
│       │   └── presentation/
│       │       └── document_screen.dart     # File picker, upload button, status badges, doc list, delete, empty state
│       └── chat/
│           ├── data/
│           │   ├── chat_repository.dart     # POST /api/chat/query/ with message_histories (90s receive timeout)
│           │   └── models/
│           │       └── message.dart         # Message model: id, content, role, status enum
│           ├── bloc/
│           │   ├── chat_bloc.dart           # States: initial, sending, messagesUpdated
│           │   └── chat_event.dart          # SendMessage, RetryMessage, ToggleHyde, ChatReset
│           └── presentation/
│               ├── chat_screen.dart         # Message list, input bar, HyDE toggle, empty state, keyboard inset handling
│               └── widgets/
│                   ├── message_bubble.dart  # User (right, accent) vs assistant (left, neutral)
│                   └── message_status.dart  # Sending/Delivered/Failed icons
└── test/
    ├── auth/
    │   └── auth_bloc_test.dart
    ├── documents/
    │   └── document_bloc_test.dart
    └── chat/
        └── chat_bloc_test.dart
```

### Component Interaction

```
┌─────────────────────────────────────────────────────────┐
│                    MaterialApp (app.dart)                │
│     Router: checkInProgress → SplashScreen (branded)    │
│             unauthenticated → LoginScreen               │
│             authenticated   → MainScreen (tabs/nav)     │
└──────────────────────────┬──────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
   LoginScreen      DocumentScreen       ChatScreen
        │                  │                  │
        ▼                  ▼                  ▼
    AuthBloc          DocumentBloc        ChatBloc
        │                  │                  │
        ▼                  ▼                  ▼
  AuthRepository    DocumentRepository  ChatRepository
        │                  │                  │
        ▼                  ▼                  ▼
   Dio + SecureStorage   Dio              Dio (90s override)
        │                  │                  │
        └──────────────────┼──────────────────┘
                           ▼
              Backend API (Django REST)
```

## Key Design Decisions

### 1. Dio HTTP Client — Two-Tier Timeout (`core/api/api_client.dart`)

Single Dio instance configured via `get_it` DI. Global timeouts: 15s connect, 30s default receive. Chat queries override to 90s per-request to accommodate LLM/HyDE latency.

```dart
Dio createDio(String baseUrl, StreamController<void> unauthenticatedStream) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    contentType: 'application/json',
  ));
  dio.interceptors.add(
    AuthQueuedInterceptor(
      storage: getIt<SecureStorageService>(),
      unauthenticatedStream: unauthenticatedStream,
      refreshEndpoint: '/api/token/refresh/',
    ),
  );
  return dio;
}
```

### 2. Unified Auth Queued Interceptor (`core/api/auth_interceptor.dart`)

Replaces the previous separated `AuthInterceptor` + `ErrorInterceptor` to eliminate the token-refresh race condition (C2) and the circular dependency on `AuthBloc` (A1).

Extends `QueuedInterceptor` — Dio queues subsequent requests while the interceptor is processing, ensuring only one refresh attempt occurs at a time.

```dart
class AuthQueuedInterceptor extends QueuedInterceptor {
  final SecureStorageService _storage;
  final StreamController<void> _unauthenticatedStream;
  final String _refreshEndpoint;
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  AuthQueuedInterceptor({
    required SecureStorageService storage,
    required StreamController<void> unauthenticatedStream,
    required String refreshEndpoint,
  })  : _storage = storage,
        _unauthenticatedStream = unauthenticatedStream,
        _refreshEndpoint = refreshEndpoint;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    // Deduplicated refresh: if already refreshing, wait for the existing attempt
    if (_isRefreshing) {
      final success = await _refreshCompleter!.future;
      if (success) {
        // Retry the original request with the new token
        final token = await _storage.readAccessToken();
        err.requestOptions.headers['Authorization'] = 'Bearer $token';
        final response = await Dio().fetch(err.requestOptions);
        return handler.resolve(response);
      } else {
        return handler.next(err);
      }
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await _storage.readRefreshToken();
      if (refreshToken == null) {
        _refreshCompleter!.complete(false);
        _unauthenticatedStream.add(null); // signal logout
        return handler.next(err);
      }

      // Use a fresh Dio instance to avoid interceptor recursion
      final response = await Dio(BaseOptions(
        baseUrl: err.requestOptions.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      )).post(_refreshEndpoint, data: {'refresh': refreshToken});

      final newAccess = response.data['access'] as String;
      await _storage.writeAccessToken(newAccess);
      _refreshCompleter!.complete(true);

      // Retry the original request
      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final retryResponse = await Dio().fetch(err.requestOptions);
      return handler.resolve(retryResponse);
    } catch (_) {
      _refreshCompleter!.complete(false);
      await _storage.clearAll();
      _unauthenticatedStream.add(null); // signal logout
      return handler.next(err);
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }
}
```

### 3. Unauthenticated Event Stream (`core/events/unauthenticated_event.dart`)

Decouples Dio interceptor from `AuthBloc` to eliminate circular dependency (A1). The interceptor writes to the stream; `AuthBloc` subscribes after initialization.

```dart
// Registered as a singleton in get_it before Dio and AuthBloc
final unauthenticatedEventStream = StreamController<void>.broadcast();
```

### 4. Auth Flow (`features/auth/`)

`AuthBloc` state machine with dedicated `AuthCheckInProgress` state to prevent splash flash (U1):

- `AppStarted` → emit `AuthCheckInProgress` (render branded splash screen) → read tokens from secure storage → if present:
  1. Parse JWT `exp` claim locally.
  2. If expired or expiring within 5 minutes, proactively call `POST /api/token/refresh/`.
  3. If refresh succeeds, store new token → emit `Authenticated`.
  4. If refresh fails, clear storage → emit `Unauthenticated`.
  - If tokens absent → emit `Unauthenticated`.
- `LoginRequested(username, password)` → `POST /api/token/` → store tokens → `Authenticated`
- `LogoutRequested` / `TokenExpired` → clear secure storage → dispatch `ChatReset` to `ChatBloc` and `DocumentReset` to `DocumentBloc` to sanitize all in-memory state (S2) → emit `Unauthenticated`

`AuthBloc` subscribes to `unauthenticatedEventStream` in its constructor. On stream event, it processes the same flow as `TokenExpired`.

Token refresh: `AuthRepository.refreshToken()` calls `POST /api/token/refresh/` with stored refresh token. On success, stores new access token. On failure, returns error (interceptor handles logout signaling).

States: `AuthInitial`, `AuthCheckInProgress`, `AuthLoading`, `Authenticated`, `Unauthenticated(error?)`

### 5. Document Management (`features/documents/`)

`DocumentBloc` manages the full document lifecycle:

- `LoadDocuments` → `GET /api/documents/` → emit `DocumentLoaded(documents)`. On empty list, emit state with `isEmpty: true` for empty-state placeholder: _"No documents uploaded. Tap below to upload a PDF, TXT, or MD file."_
- `UploadRequested(file)` → multipart POST → on 202, emit `Polling(taskId)` → start periodic timer (2s) **with 2-minute maximum** (60 ticks). Cancel subscription on widget disposal or new event (A2).
  - Each poll tick: `GET /api/documents/status/?task_id=<id>` → if PROCESSING, continue; if SUCCESS, emit `UploadSuccess` + re-fetch document list; if FAILURE, emit `UploadFailure(error)`.
  - If 60 ticks elapse without terminal status, cancel polling and emit `UploadFailure("Ingestion timed out. Please check again later.")`.
- `DeleteDocument(documentId)` → `DELETE /api/documents/<id>/` → on 204/200, re-fetch document list; on error, emit `DocumentFailure(error)`.
- `DocumentReset` → clear in-memory document list, cancel active polling timers (S2).
- File picker configured with `FileType.custom` and `allowedExtensions: ['pdf', 'txt', 'md']`.

`DocumentRepository` methods:
- `fetchDocuments()` → `GET /api/documents/` → returns `List<Document>` (uses `DocumentSerializer` fields: `id` (int), `original_name`, `content_type`, `size_bytes`, `status`, `uploaded_at`).
- `uploadDocument(File file)` → `POST /api/documents/upload/` (multipart/form-data).
- `checkIngestionStatus(String taskId)` → `GET /api/documents/status/?task_id=<taskId>`.
- `deleteDocument(int documentId)` → `DELETE /api/documents/<documentId>/`.

### 6. Chat Message Flow (`features/chat/`)

`ChatBloc` manages the message lifecycle:
- `SendMessage(text)` → add user message with `MessageStatus.sending` (optimistic) → **disable send button** while any message is in `sending` state (A4) → POST to `/api/chat/query/` **with 90s receive timeout override** (C1) with message + last 6 **delivered** history entries (A3) → on 200, update to `MessageStatus.delivered` + add assistant message → on error, update to `MessageStatus.failed`
- `RetryMessage(messageId)` → re-send the failed message's query
- `ToggleHyde(enabled)` → update BLoC state; subsequent sends include `use_hyde: true`
- `ChatReset` → clear all in-memory messages and conversation state (S2)

Context injection filtering (A3): Before packaging `message_histories`, filter the conversation list for messages with `status == MessageStatus.delivered` only. Exclude any message in `sending` or `failed` state. Then take the last N=6 entries and map to `List<Map<String, String>>` matching `[{"role": "user"|"assistant", "content": "..."}]`.

Chat repository per-request timeout override:
```dart
class ChatRepository {
  final Dio _dio;

  Future<String> sendQuery(String query, List<Map<String, String>> messageHistories, bool useHyde) async {
    final response = await _dio.post(
      '/api/chat/query/',
      data: {
        'query': query,
        'message_histories': messageHistories,
        if (useHyde) 'use_hyde': true,
      },
      options: Options(receiveTimeout: const Duration(seconds: 90)),
    );
    return response.data['answer'] as String;
  }
}
```

Chat screen keyboard handling (U2): Configure `Scaffold(resizeToAvoidBottomInset: true)`. Attach a `ScrollController` to the message `ListView` and animate to bottom when the keyboard appears (listen to `WidgetsBindingObserver.didChangeMetrics` or `FocusNode` focus events).

Empty state (U3): When the message list is empty, display a centered placeholder: _"No messages yet. Ask a question about your uploaded documents!"_

Message model:
```dart
enum MessageStatus { sending, delivered, failed }
enum MessageRole { user, assistant }

class Message {
  final String id;           // UUID (client-generated)
  final String content;
  final MessageRole role;
  final MessageStatus status;
  final DateTime timestamp;
}
```

### 7. Navigation / Routing

Conditional routing based on `AuthBloc` state:
- `AuthCheckInProgress` → Branded splash screen with loading indicator (U1)
- `Unauthenticated` → `LoginScreen`
- `Authenticated` → Main scaffold with bottom navigation: Documents tab, Chat tab
- Logout from any screen → back to `LoginScreen`

### 8. Dependency Injection

`get_it` for service locator pattern. Registration order avoids circular dependencies (A1):

1. `StreamController<void>` — unauthenticated event stream (broadcast)
2. `SecureStorageService` — `flutter_secure_storage` wrapper
3. `Dio` — via `createDio(baseUrl, unauthenticatedStream)` (references stream + storage, no BLoC dependency)
4. `AuthRepository`, `DocumentRepository`, `ChatRepository` — depend on Dio
5. `AuthBloc` — depends on `AuthRepository` + subscribes to unauthenticated stream
6. `DocumentBloc` — depends on `DocumentRepository`
7. `ChatBloc` — depends on `ChatRepository`

Initialize in `main.dart` before `runApp()`.

## Dependencies

- **New (Flutter packages)**: `flutter_bloc`, `bloc`, `equatable`, `dio`, `flutter_secure_storage`, `file_picker`, `get_it`, `uuid`
- **Existing reused**: Backend endpoints (`/api/token/`, `/api/token/refresh/`, `/api/documents/`, `/api/documents/upload/`, `/api/documents/status/`, `/api/documents/<id>/`, `/api/chat/query/`)

## Non-Goals

- User registration screen (backend `/api/register/` endpoint is not yet wired)
- Multi-thread chat management with local SQLite/Hive persistence (bonus, out of scope for initial implementation)
- Streaming/WebSocket responses
- Offline document caching
- Push notifications
