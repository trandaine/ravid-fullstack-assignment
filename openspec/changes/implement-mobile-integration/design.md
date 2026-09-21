# Design: Mobile Integration

## Overview

Build a Flutter 3.x mobile application under `mobile/` consuming the existing RAVID Django backend. The app follows Clean Architecture with BLoC state management, Dio for HTTP, and `flutter_secure_storage` for credential persistence. Three feature modules — auth, documents, and chat — each own their presentation, BLoC, repository, and data source layers.

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
│   │   │   ├── api_client.dart         # Dio singleton factory with base URL, timeouts
│   │   │   ├── auth_interceptor.dart   # Injects Bearer token from secure storage
│   │   │   └── error_interceptor.dart  # Parses {"error":"..."}, triggers logout on 401
│   │   ├── storage/
│   │   │   └── secure_storage.dart     # flutter_secure_storage wrapper (read/write/clear tokens)
│   │   ├── theme/
│   │   │   └── app_theme.dart          # Colors, typography, layout constants
│   │   └── widgets/
│   │       ├── loading_indicator.dart
│   │       └── error_banner.dart
│   └── features/
│       ├── auth/
│       │   ├── data/
│       │   │   └── auth_repository.dart     # POST /api/token/, POST /api/token/refresh/
│       │   ├── bloc/
│       │   │   ├── auth_bloc.dart           # States: initial, loading, authenticated, unauthenticated
│       │   │   └── auth_event.dart          # LoginRequested, LogoutRequested, AppStarted, TokenExpired
│       │   └── presentation/
│       │       └── login_screen.dart        # Username/password form, validation, error display
│       ├── documents/
│       │   ├── data/
│       │   │   └── document_repository.dart # POST /api/documents/upload/, GET /api/documents/status/
│       │   ├── bloc/
│       │   │   ├── document_bloc.dart       # States: initial, uploading, polling, success, failure
│       │   │   └── document_event.dart      # UploadRequested, PollStatus, PollCompleted
│       │   └── presentation/
│       │       └── document_screen.dart     # File picker, upload button, status badges, doc list
│       └── chat/
│           ├── data/
│           │   ├── chat_repository.dart     # POST /api/chat/query/ with message_histories
│           │   └── models/
│           │       └── message.dart         # Message model: id, content, role, status enum
│           ├── bloc/
│           │   ├── chat_bloc.dart           # States: initial, sending, messagesUpdated
│           │   └── chat_event.dart          # SendMessage, RetryMessage, ToggleHyde
│           └── presentation/
│               ├── chat_screen.dart         # Message list, input bar, HyDE toggle
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
│     Router: unauthenticated → LoginScreen               │
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
   Dio + SecureStorage   Dio              Dio + LocalStore
        │                  │                  │
        └──────────────────┼──────────────────┘
                           ▼
              Backend API (Django REST)
```

## Key Design Decisions

### 1. Dio HTTP Client (`core/api/api_client.dart`)

Single Dio instance configured via `get_it` DI:

```dart
Dio createDio(String baseUrl) {
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    contentType: 'application/json',
  ));
  dio.interceptors.addAll([
    AuthInterceptor(getIt<SecureStorageService>()),
    ErrorInterceptor(getIt<AuthBloc>()),
  ]);
  return dio;
}
```

### 2. Auth Interceptor (`core/api/auth_interceptor.dart`)

Reads the JWT access token from `flutter_secure_storage` and attaches it to every request:

```dart
class AuthInterceptor extends Interceptor {
  final SecureStorageService _storage;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
```

### 3. Error Interceptor (`core/api/error_interceptor.dart`)

On 401 responses (after refresh attempt fails), broadcasts `TokenExpired` to `AuthBloc`:

```dart
class ErrorInterceptor extends Interceptor {
  final AuthBloc _authBloc;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      _authBloc.add(TokenExpired());
    }
    handler.next(err);
  }
}
```

### 4. Auth Flow (`features/auth/`)

`AuthBloc` state machine:
- `AppStarted` → check secure storage for token → if present, validate/refresh → `Authenticated` or `Unauthenticated`
- `LoginRequested(username, password)` → `POST /api/token/` → store tokens → `Authenticated`
- `LogoutRequested` / `TokenExpired` → clear storage → `Unauthenticated`

Token refresh: `AuthRepository.refreshToken()` calls `POST /api/token/refresh/` with stored refresh token. On success, stores new access token. On failure, triggers logout.

### 5. Document Upload & Polling (`features/documents/`)

`DocumentBloc` manages the upload-then-poll lifecycle:
- `UploadRequested(file)` → multipart POST → on 202, emit `Polling(taskId)` → start periodic timer (2s)
- Each poll tick: `GET /api/documents/status/?task_id=<id>` → if PROCESSING, continue; if SUCCESS, emit `UploadSuccess`; if FAILURE, emit `UploadFailure(error)`
- File picker configured with `FileType.custom` and `allowedExtensions: ['pdf', 'txt', 'md']`

### 6. Chat Message Flow (`features/chat/`)

`ChatBloc` manages the message lifecycle:
- `SendMessage(text)` → add user message with `MessageStatus.sending` (optimistic) → POST to `/api/chat/query/` with message + last 6 history entries → on 200, update to `MessageStatus.delivered` + add assistant message → on error, update to `MessageStatus.failed`
- `RetryMessage(messageId)` → re-send the failed message's query
- `ToggleHyde(enabled)` → update BLoC state; subsequent sends include `use_hyde: true`

Message model:
```dart
enum MessageStatus { sending, delivered, failed }
enum MessageRole { user, assistant }

class Message {
  final String id;           // UUID
  final String content;
  final MessageRole role;
  final MessageStatus status;
  final DateTime timestamp;
}
```

### 7. Navigation / Routing

Simple conditional routing based on `AuthBloc` state:
- `Unauthenticated` → `LoginScreen`
- `Authenticated` → Main scaffold with bottom navigation: Documents tab, Chat tab
- Logout from any screen → back to `LoginScreen`

### 8. Dependency Injection

`get_it` for service locator pattern:
- Register: `SecureStorageService`, `Dio`, `AuthRepository`, `DocumentRepository`, `ChatRepository`, `AuthBloc`, `DocumentBloc`, `ChatBloc`
- Initialize in `main.dart` before `runApp()`

## Dependencies

- **New (Flutter packages)**: `flutter_bloc`, `bloc`, `equatable`, `dio`, `flutter_secure_storage`, `file_picker`, `get_it`, `uuid`
- **Existing reused**: Backend endpoints (`/api/token/`, `/api/token/refresh/`, `/api/documents/upload/`, `/api/documents/status/`, `/api/chat/query/`)

## Non-Goals

- User registration screen (backend `/api/register/` endpoint is not yet wired)
- Multi-thread chat management with local SQLite/Hive persistence (bonus, out of scope for initial implementation)
- Streaming/WebSocket responses
- Offline document caching
- Push notifications
