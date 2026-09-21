# Specification Delta: Mobile Integration

## ADDED Requirements

### Requirement: Authentication & Session Management

The Flutter mobile application shall provide a login screen and JWT-based session management that authenticates users against the existing backend token endpoints and persists credentials securely on device.

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
- **GIVEN** the app launches and `flutter_secure_storage` contains a previously stored access token
- **WHEN** the `AuthBloc` initializes and reads the stored token
- **THEN** the app validates the token is not expired (JWT `exp` claim check or a test API call)
- **AND** if valid, navigates directly to the main screen bypassing the Login Screen
- **AND** if expired, attempts a silent refresh via `POST /api/token/refresh/` with the stored refresh token
- **AND** if refresh succeeds, stores the new access token and navigates to the main screen
- **AND** if refresh fails, clears stored tokens and navigates to the Login Screen

#### Scenario: Logout clears credentials and redirects
- **GIVEN** the user is authenticated and on any screen
- **WHEN** the user taps the "Logout" action
- **THEN** the app clears all tokens from `flutter_secure_storage`
- **AND** resets application state in `AuthBloc`
- **AND** navigates to the Login Screen

#### Scenario: Automatic logout on 401 response
- **GIVEN** the user is authenticated and making API requests
- **WHEN** any API request returns HTTP `401 Unauthorized` (token expired or revoked) and token refresh also fails
- **THEN** the Dio error interceptor broadcasts a logout event to `AuthBloc`
- **AND** the app clears stored tokens and navigates to the Login Screen

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

The Flutter mobile application shall provide a document management screen that allows users to upload documents and monitor ingestion status by consuming the existing backend document endpoints.

#### Scenario: Successful document upload and ingestion polling
- **GIVEN** the user is on the Document Screen and authenticated
- **WHEN** the user taps "Upload Document", selects a `.pdf`, `.txt`, or `.md` file via the file picker
- **THEN** the app sends a `POST` multipart/form-data request to `/api/documents/upload/` with the selected file and `Authorization: Bearer <token>` header
- **AND** on receiving HTTP `202 Accepted` with `{"document_id": "<uuid>", "task_id": "<uuid>"}`, the app begins polling `GET /api/documents/status/?task_id=<task_id>` every 2 seconds
- **AND** while status is `"PROCESSING"`, displays an animated loading spinner next to the document entry
- **AND** when status is `"SUCCESS"`, stops polling, displays a green checkmark badge, and refreshes the document list
- **AND** when status is `"FAILURE"`, stops polling and displays an error banner with the error message from the backend response

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

The Flutter mobile application shall provide an interactive chat screen where users can submit queries to the backend RAG endpoint and view responses in a threaded message format with delivery status indicators.

#### Scenario: Sending a message and receiving a response
- **GIVEN** the user is on the Chat Screen with an active conversation
- **WHEN** the user types a non-empty message in the input bar and taps "Send"
- **THEN** the message immediately appears in the message thread (optimistic update) aligned to the right with a "Sending" spinner icon
- **AND** the app sends a `POST` request to `/api/chat/query/` with `{"query": "<message>", "message_histories": [<last N messages>]}`
- **AND** the input bar is cleared and the message thread auto-scrolls to the bottom
- **AND** on receiving HTTP `200 OK` with `{"answer": "..."}`, the user message status updates to "Delivered" (checkmark icon) and the assistant's response appears as a new message aligned to the left

#### Scenario: Message delivery failure with retry
- **GIVEN** the user sends a message from the Chat Screen
- **WHEN** the `POST /api/chat/query/` request fails (network error, HTTP `502`, timeout)
- **THEN** the user message status updates to "Failed" with a red alert icon
- **AND** tapping the failed message re-submits the same query to the backend
- **AND** on successful retry, the status updates to "Delivered" and the assistant's response appears

#### Scenario: Context injection with conversation history
- **GIVEN** the user has an active conversation with prior messages
- **WHEN** the user sends a new message
- **THEN** the app includes the last N messages (default N=6, alternating user/assistant roles) from the current conversation in the `message_histories` field of the request payload

#### Scenario: Chat input bar behavior
- **GIVEN** the user is on the Chat Screen
- **WHEN** the input bar is focused
- **THEN** it supports multi-line text input
- **AND** the send button is disabled when the input is empty or whitespace-only
- **AND** after sending, the input bar is cleared and the keyboard remains open

#### Scenario: Auto-scroll to latest message
- **GIVEN** the user is on the Chat Screen
- **WHEN** a new message (user or assistant) is added to the thread
- **THEN** the message list auto-scrolls to the bottom to show the latest message

#### Scenario: HyDE mode toggle (Bonus)
- **GIVEN** the user is on the Chat Screen
- **WHEN** the user enables the HyDE toggle in the app bar
- **THEN** all subsequent queries include `"use_hyde": true` in the request payload to `/api/chat/query/`
- **AND** when the toggle is disabled, queries omit the `use_hyde` field or send `"use_hyde": false`
