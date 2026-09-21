# Specification Delta: Mobile Integration

## ADDED Requirements

### Requirement: Authentication & Session Management

The Flutter mobile application shall provide a login screen and JWT-based session management that authenticates users against the existing backend token endpoints and persists credentials securely on device.

#### Security Constraint: Platform-Encrypted Storage Only

Tokens and session credentials MUST ONLY be stored in platform-encrypted storage via `flutter_secure_storage` (Keychain with `kSecAccessControl` on iOS / EncryptedSharedPreferences backed by Android Keystore on Android). Under no circumstances shall tokens be placed in `SharedPreferences`, `UserDefaults`, plain files, or static singleton instances that outlive the session.

#### Scenario: Successful login with valid credentials
- **GIVEN** the user is on the Login Screen with empty username and password fields
- **WHEN** the user enters a valid username and password (both non-empty, password ≥ 8 characters) and taps the "Login" button
- **THEN** the app sends a `POST` request to `/api/token/` with `{"username": "<username>", "password": "<password>"}`
- **AND** on receiving HTTP `200 OK` with `{"access": "<jwt>", "refresh": "<refresh_token>"}`, stores both tokens in `flutter_secure_storage`
- **AND** navigates the user to the main screen (Chat or Documents)

#### Scenario: Login rejected with invalid credentials
- **GIVEN** the user is on the Login Screen
- **WHEN** the user enters an incorrect username or password and taps "Login"
- **THEN** the app receives HTTP `401 Unauthorized` from `/api/token/`
- **AND** displays an error message "Invalid username or password" beneath the form without clearing the input fields

#### Scenario: Client-side form validation
- **GIVEN** the user is on the Login Screen
- **WHEN** the user taps "Login" with an empty username field, an empty password field, or a password shorter than 8 characters
- **THEN** the app displays inline validation errors ("Username is required", "Password must be at least 8 characters") without making a network request

#### Scenario: Auto-login on app launch with existing session
- **GIVEN** the app launches and the `AuthBloc` receives the `AppStarted` event
- **WHEN** the BLoC emits `AuthCheckInProgress` (rendering a branded splash screen) and reads tokens from `flutter_secure_storage`
- **THEN** if tokens are present, the app parses the JWT `exp` claim locally
- **AND** if the access token is expired or will expire within 5 minutes, the app proactively calls `POST /api/token/refresh/` with the stored refresh token
- **AND** if the refresh succeeds, stores the new access token and navigates to the main screen (emits `Authenticated`)
- **AND** if the access token is still valid (more than 5 minutes remaining), navigates directly to the main screen (emits `Authenticated`)
- **AND** if the refresh fails (HTTP `401` or network error), clears all tokens from `flutter_secure_storage` and navigates to the Login Screen (emits `Unauthenticated`)
- **AND** if no tokens are found in storage, navigates directly to the Login Screen (emits `Unauthenticated`)

#### Scenario: Logout clears all credentials and application state
- **GIVEN** the user is authenticated and on any screen
- **WHEN** the user taps the "Logout" action
- **THEN** the app clears all tokens from `flutter_secure_storage`
- **AND** resets `AuthBloc` to `Unauthenticated` state
- **AND** dispatches `ChatReset` to `ChatBloc`, clearing all in-memory messages and conversation state
- **AND** dispatches `DocumentReset` to `DocumentBloc`, clearing the cached document list and cancelling any active polling timers
- **AND** navigates to the Login Screen

#### Scenario: Automatic token refresh and logout on concurrent 401 responses
- **GIVEN** the user is authenticated and the access token has expired
- **WHEN** one or more API requests return HTTP `401 Unauthorized` concurrently
- **THEN** the unified `AuthQueuedInterceptor` pauses all subsequent requests and executes a single `POST /api/token/refresh/` call (mutex-protected)
- **AND** if the refresh succeeds, stores the new access token, replays all paused requests with the updated token, and the user session continues uninterrupted
- **AND** if the refresh fails (refresh token expired or revoked), flushes the paused request queue with errors, clears all tokens from `flutter_secure_storage`, signals logout via the unauthenticated event stream, and the app navigates to the Login Screen

#### Boundary: No User Registration

The mobile application shall NOT include any sign-up, registration, or account creation flow. The backend `/api/register/` endpoint is not wired in `backend/config/urls.py`. User accounts must be provisioned manually via Django admin (`/admin/`) or `python manage.py createsuperuser` / shell.

#### Scenario: No registration entry point exists in the UI
- **GIVEN** the user is on the Login Screen
- **WHEN** the user views the screen
- **THEN** there is no "Sign Up", "Register", or "Create Account" button, link, or navigation element visible
- **AND** the only authentication action available is "Login" with existing credentials

#### Scenario: No programmatic registration endpoint calls
- **GIVEN** the mobile application codebase
- **WHEN** inspecting all HTTP calls made by `AuthRepository` and Dio interceptors
- **THEN** no request is ever made to `/api/register/` or any registration-related endpoint

---

### Requirement: Document Management UI

The Flutter mobile application shall provide a document management screen that allows users to view their uploaded documents, upload new documents, monitor ingestion status, and delete documents by consuming the backend document endpoints.

#### Scenario: Loading and displaying the document list
- **GIVEN** the user is authenticated and navigates to the Document Screen
- **WHEN** the screen initializes
- **THEN** the app sends a `GET` request to `/api/documents/` with `Authorization: Bearer <token>` header
- **AND** on receiving HTTP `200 OK` with a JSON array of document objects (each containing `id` (int), `original_name`, `content_type`, `size_bytes`, `status`, `uploaded_at`), renders the list on screen
- **AND** if the response array is empty, displays a centered empty-state placeholder: "No documents uploaded. Tap below to upload a PDF, TXT, or MD file."

#### Scenario: Successful document upload and ingestion polling
- **GIVEN** the user is on the Document Screen and authenticated
- **WHEN** the user taps "Upload Document", selects a `.pdf`, `.txt`, or `.md` file via the file picker
- **THEN** the app sends a `POST` multipart/form-data request to `/api/documents/upload/` with the selected file and `Authorization: Bearer <token>` header
- **AND** on receiving HTTP `202 Accepted` with `{"message": "...", "document_id": 1, "task_id": "<uuid>"}` (where `document_id` is an integer), the app begins polling `GET /api/documents/status/?task_id=<task_id>` every 2 seconds
- **AND** while status is `"PROCESSING"`, displays an animated loading spinner next to the document entry
- **AND** when status is `"SUCCESS"`, stops polling, displays a green checkmark badge, and refreshes the document list via `GET /api/documents/`
- **AND** when status is `"FAILURE"`, stops polling and displays an error banner with the error message from the backend response

#### Scenario: Ingestion polling timeout
- **GIVEN** the app is polling `GET /api/documents/status/?task_id=<task_id>` for an active upload
- **WHEN** 2 minutes (60 polling ticks at 2-second intervals) elapse without the status reaching `"SUCCESS"` or `"FAILURE"`
- **THEN** the app stops polling and displays an error message: "Ingestion timed out. Please check again later."
- **AND** the polling timer subscription is cancelled

#### Scenario: Deleting a document
- **GIVEN** the user is on the Document Screen viewing their document list
- **WHEN** the user initiates a delete action on a specific document
- **THEN** the app sends a `DELETE` request to `/api/documents/<id>/` with `Authorization: Bearer <token>` header (where `<id>` is the integer document ID)
- **AND** on receiving HTTP `204 No Content`, removes the document from the displayed list
- **AND** on receiving an error response, displays the error message to the user

#### Scenario: Upload rejected by backend
- **GIVEN** the user selects and uploads a file
- **WHEN** the backend returns HTTP `415` (unsupported type), `413` (too large), or `400` (missing file)
- **THEN** the app displays a user-friendly error message corresponding to the backend's `detail` field without starting the polling flow

#### Scenario: File picker shows only supported formats
- **GIVEN** the user taps "Upload Document"
- **WHEN** the file picker dialog opens
- **THEN** it filters to show only `.pdf`, `.txt`, and `.md` file types

---

### Requirement: Chat Interface

The Flutter mobile application shall provide an interactive chat screen where users can submit queries to the backend RAG endpoint and view responses in a threaded message format with delivery status indicators. The chat query endpoint uses a 90-second receive timeout to accommodate LLM and HyDE processing latency.

#### Scenario: Sending a message and receiving a response
- **GIVEN** the user is on the Chat Screen with an active conversation
- **WHEN** the user types a non-empty message in the input bar and taps "Send"
- **THEN** the message immediately appears in the message thread (optimistic update) aligned to the right with a "Sending" spinner icon
- **AND** the send button is disabled while any message in the conversation is in `sending` state
- **AND** the app sends a `POST` request to `/api/chat/query/` with `{"query": "<message>", "message_histories": [<last N delivered messages>]}` using a 90-second receive timeout
- **AND** the input bar is cleared and the message thread auto-scrolls to the bottom
- **AND** on receiving HTTP `200 OK` with `{"answer": "..."}`, the user message status updates to "Delivered" (checkmark icon) and the assistant's response appears as a new message aligned to the left

#### Scenario: Message delivery failure with retry
- **GIVEN** the user sends a message from the Chat Screen
- **WHEN** the `POST /api/chat/query/` request fails (network error, HTTP `502`, timeout)
- **THEN** the user message status updates to "Failed" with a red alert icon
- **AND** the send button is re-enabled
- **AND** tapping the failed message re-submits the same query to the backend
- **AND** on successful retry, the status updates to "Delivered" and the assistant's response appears

#### Scenario: Context injection with conversation history
- **GIVEN** the user has an active conversation with prior messages
- **WHEN** the user sends a new message
- **THEN** the app filters the current conversation for messages with `status == delivered` only (messages in `sending` or `failed` state are excluded)
- **AND** takes the last N messages (default N=6, alternating user/assistant roles) from the filtered set
- **AND** maps them to `[{"role": "user"|"assistant", "content": "..."}]` and includes them in the `message_histories` field of the request payload

#### Scenario: Chat input bar behavior
- **GIVEN** the user is on the Chat Screen
- **WHEN** the input bar is focused
- **THEN** it supports multi-line text input
- **AND** the send button is disabled when the input is empty or whitespace-only
- **AND** the send button is disabled when any message in the conversation is in `sending` state
- **AND** after sending, the input bar is cleared and the keyboard remains open

#### Scenario: Auto-scroll to latest message
- **GIVEN** the user is on the Chat Screen
- **WHEN** a new message (user or assistant) is added to the thread
- **THEN** the message list auto-scrolls to the bottom to show the latest message

#### Scenario: Empty chat state
- **GIVEN** the user is on the Chat Screen
- **WHEN** there are no messages in the current conversation
- **THEN** the app displays a centered empty-state placeholder: "No messages yet. Ask a question about your uploaded documents!"

#### Scenario: Keyboard does not occlude the input bar
- **GIVEN** the user is on the Chat Screen
- **WHEN** the on-screen keyboard appears
- **THEN** the `Scaffold` resizes to avoid the bottom inset (`resizeToAvoidBottomInset: true`)
- **AND** the message list scrolls to keep the latest message visible above the input bar

#### Scenario: HyDE mode toggle (Bonus)
- **GIVEN** the user is on the Chat Screen
- **WHEN** the user enables the HyDE toggle in the app bar
- **THEN** all subsequent queries include `"use_hyde": true` in the request payload to `/api/chat/query/`
- **AND** when the toggle is disabled, queries omit the `use_hyde` field or send `"use_hyde": false`

---

## MODIFIED Requirements

### Requirement: Backend Document List & Delete Endpoints (Prerequisite)

The backend shall expose two additional owner-scoped endpoints using the existing `DocumentSerializer` to support the mobile Document Management UI.

#### Scenario: Listing the authenticated user's documents
- **GIVEN** an authenticated user with a valid JWT Bearer token who has previously uploaded documents
- **WHEN** the user sends a `GET` request to `/api/documents/`
- **THEN** the system returns HTTP `200 OK` with a JSON array containing only documents owned by the authenticated user (`Document.objects.filter(owner=request.user)`), each serialized with fields: `id` (int), `original_name`, `content_type`, `size_bytes`, `status`, `uploaded_at`
- **AND** if the user has no documents, returns HTTP `200 OK` with an empty JSON array `[]`

#### Scenario: Deleting a document owned by the authenticated user
- **GIVEN** an authenticated user who owns a document with integer ID `<id>`
- **WHEN** the user sends a `DELETE` request to `/api/documents/<id>/`
- **THEN** the system deletes the `Document` record and associated file from storage
- **AND** returns HTTP `204 No Content`

#### Scenario: Attempting to delete another user's document
- **GIVEN** an authenticated user
- **WHEN** the user sends a `DELETE` request to `/api/documents/<id>/` where `<id>` belongs to a different user
- **THEN** the system returns HTTP `404 Not Found` (preventing existence probing)
