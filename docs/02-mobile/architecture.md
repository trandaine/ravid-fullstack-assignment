# Mobile Client Architecture (Flutter)

## Objective

Define the architectural pattern, state management model, local persistence schema, and UI design specifications for the Flutter mobile application in the R.A.V.I.D. system.

---

## Architectural Pattern

The mobile client adheres to Clean Architecture with the BLoC (Business Logic Component) pattern for predictable state management, testability, and clear separation of concerns.

```
   ┌─────────────────────────────────────────────────────────────┐
   │                     Presentation Layer                      │
   │  Screens (Login, Documents, Chat) + Widgets (Bubbles, Drawer)│
   └──────────────────────────────┬──────────────────────────────┘
                                  │ UI Events / State Changes
                                  ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                   BLoC / State Layer                        │
   │  - AuthBloc          - DocumentBloc          - ChatBloc     │
   └──────────────────────────────┬──────────────────────────────┘
                                  │ Repositories
                                  ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                       Data Layer                            │
   │  - AuthRepository    - DocumentRepository    - ChatRepository│
   └──────────────┬───────────────────────────────┬──────────────┘
                  │                               │
                  ▼                               ▼
   ┌─────────────────────────────┐ ┌─────────────────────────────┐
   │     Local Data Sources      │ │     Remote Data Source      │
   │ - flutter_secure_storage    │ │ - Dio HTTP Client           │
   │ - SQLite / Hive DB          │ │ - Auth Interceptor          │
   └─────────────────────────────┘ └─────────────────────────────┘
```

---

## Feature Modules

### 1. Authentication & Session Management (`features/auth`)

- **LoginScreen:** Email and password form with validation (non-empty, valid format, minimum 8 characters).
- **Secure Persistence:** Tokens are saved in platform-encrypted storage (`flutter_secure_storage` using iOS Keychain and Android Keystore).
- **Auto-Login:** On application start, `AuthBloc` checks for an existing valid token in secure storage:
  - If present: navigates directly to the Main / Chat Screen.
  - If absent/invalid: navigates to the Login Screen.
- **Logout:** Clears all secure storage entries and resets application state.

### 2. Document Management (`features/documents`)

- **DocumentScreen:** Allows selecting `.pdf`, `.txt`, and `.md` files via `file_picker`.
- **Upload Flow:** Sends `multipart/form-data` to `POST /api/documents/upload/`.
- **Polling State Machine:**
  - On receiving `202 Accepted` with `task_id`, starts a periodic timer (every 2 seconds).
  - Queries `GET /api/documents/status/?task_id=<task_id>`.
  - When status is `PROCESSING`, displays an animated loading spinner.
  - When status is `SUCCESS`, updates UI with a green checkmark badge and refreshes the document list.
  - When status is `FAILURE`, halts polling and displays an error banner with the message returned from the backend.

```
   [Select File] ──▶ [POST /api/documents/upload/] ──▶ [Received task_id]
                                                               │
                                                               ▼
   ┌─────────────────────────────────────────────────── [Poll Status] ◄────┐
   │                                                           │           │
   ├─► status == "PROCESSING" ─────────────────────────────────┴───────────┤ (wait 2s)
   │
   ├─► status == "SUCCESS" ──▶ [Show Success Badge] ──▶ [Refresh Doc List]
   │
   └─► status == "FAILURE" ──▶ [Display Error Banner with backend error]
```

### 3. Interactive Chat Interface (`features/chat`)

- **ChatScreen:**
  - Dynamic message list with auto-scrolling to the latest message.
  - User bubbles aligned to the right with primary accent background.
  - Assistant bubbles aligned to the left with neutral/secondary card styling.
  - Fixed bottom input bar with send button and character trimming.
  - **HyDE Mode Toggle:** An accessible toggle switch in the AppBar/settings allowing the user to enable advanced Hypothetical Document Embeddings retrieval (`use_hyde: true`).

#### Message Status Indicator States

```
   [User Types Message]
            │
            ▼
   [Message Sent] ─────────▶ Status: SENDING (clock / spinner icon)
            │
            ├── (HTTP 200) ─▶ Status: DELIVERED (checkmark icon) + Add Assistant Response
            │
            └── (HTTP Err) ─▶ Status: FAILED (red alert icon + Tap-to-Retry action)
```

- **Sending:** Message appears immediately in the UI (optimistic update) with a subtle loading spinner or clock icon.
- **Delivered:** Status updates to a subtle checkmark when the backend returns `200 OK`.
- **Failed:** If network fails or backend errors out, status updates to a red alert icon. Tapping the failed message re-submits the query.

### 4. Multi-Thread Local Management (Bonus)

- **Chat Drawer:** Slide-out drawer displaying all historical chat sessions ordered by `updated_at DESC`.
- **New Thread:** "New Chat" button creates a fresh thread in SQLite/Hive with a new UUID and clears the active message list.
- **Auto-Naming:** On the first turn of a new thread, the thread's title is automatically initialized from the first few words of the user's question.
- **Thread Deletion:** Swiping a thread in the drawer triggers a confirmation modal. Deleting a thread performs a cascading delete of all its messages in local storage.
- **Offline Reading:** When offline, opening any thread from the drawer instantly loads all historical turns from local storage without network access.
- **Context Window Injection:** When posting to `POST /api/chat/query/`, the app packages the last `N = 6` messages (`role: user | assistant`) from the active local thread into `message_histories`.

---

## Networking & Error Handling

- **HTTP Client:** Configured with `Dio` with a 15-second connect and receive timeout.
- **Auth Interceptor:** Automatically appends `Authorization: Bearer <token>` to all protected requests.
- **Error Interceptor:**
  - Automatically parses backend `{ "error": "<message>" }` response bodies.
  - On `401 Unauthorized`, clears local auth tokens and broadcasts a logout event to `AuthBloc` to redirect to the Login Screen.
- **No-Internet Resilience:** Detects network unavailability, flags active messages as `failed`, and allows local thread navigation seamlessly.
