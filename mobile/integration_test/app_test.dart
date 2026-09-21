import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile/app.dart';
import 'package:mobile/core/storage/secure_storage.dart';
import 'package:mobile/features/auth/bloc/auth_bloc.dart';
import 'package:mobile/features/auth/bloc/auth_event.dart';
import 'package:mobile/features/auth/data/auth_repository.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';
import 'package:mobile/features/chat/bloc/chat_bloc.dart';
import 'package:mobile/features/chat/bloc/chat_event.dart';
import 'package:mobile/features/chat/data/chat_repository.dart';
import 'package:mobile/features/chat/presentation/widgets/message_bubble.dart';
import 'package:mobile/features/documents/bloc/document_bloc.dart';
import 'package:mobile/features/documents/bloc/document_event.dart';
import 'package:mobile/features/documents/data/document_repository.dart';
import 'package:mobile/features/documents/data/models/document.dart';
import 'package:mobile/features/shell/presentation/shell_screen.dart';

class MockAuthRepository extends Mock implements AuthRepository {}
class MockDocumentRepository extends Mock implements DocumentRepository {}
class MockChatRepository extends Mock implements ChatRepository {}
class MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late MockAuthRepository mockAuthRepo;
  late MockDocumentRepository mockDocRepo;
  late MockChatRepository mockChatRepo;
  late MockSecureStorageService mockStorage;
  late StreamController<void> unauthenticatedStream;

  setUp(() {
    GetIt.instance.reset();

    mockAuthRepo = MockAuthRepository();
    mockDocRepo = MockDocumentRepository();
    mockChatRepo = MockChatRepository();
    mockStorage = MockSecureStorageService();
    unauthenticatedStream = StreamController<void>.broadcast();

    // Default mock behaviors
    when(() => mockStorage.readAccessToken()).thenAnswer((_) async => null);
    when(() => mockStorage.readRefreshToken()).thenAnswer((_) async => null);
    when(() => mockStorage.clearAll()).thenAnswer((_) async {});

    when(() => mockDocRepo.fetchDocuments()).thenAnswer((_) async => []);

    // Register mocks in GetIt DI
    final docBloc = DocumentBloc(documentRepository: mockDocRepo);
    final chatBloc = ChatBloc(chatRepository: mockChatRepo);
    final authBloc = AuthBloc(
      authRepository: mockAuthRepo,
      storage: mockStorage,
      unauthenticatedStream: unauthenticatedStream,
      onResetData: () {
        docBloc.add(const DocumentReset());
        chatBloc.add(const ChatReset());
      },
    );

    GetIt.instance.registerSingleton<SecureStorageService>(mockStorage);
    GetIt.instance.registerSingleton<AuthRepository>(mockAuthRepo);
    GetIt.instance.registerSingleton<DocumentRepository>(mockDocRepo);
    GetIt.instance.registerSingleton<ChatRepository>(mockChatRepo);
    GetIt.instance.registerSingleton<DocumentBloc>(docBloc);
    GetIt.instance.registerSingleton<ChatBloc>(chatBloc);
    GetIt.instance.registerSingleton<AuthBloc>(authBloc);
  });

  tearDown(() {
    unauthenticatedStream.close();
    GetIt.instance.reset();
  });

  testWidgets('Complete End-to-End User Journey: Auth -> Documents -> Chat -> Logout', (tester) async {
    // -------------------------------------------------------------
    // STEP 1: Application Launch & Auth Check (Unauthenticated)
    // -------------------------------------------------------------
    when(() => mockAuthRepo.login('alice', 'password123'))
        .thenAnswer((_) async {});

    await tester.pumpWidget(const RavidApp());
    GetIt.instance<AuthBloc>().add(const AppStarted());
    await tester.pumpAndSettle();

    // Verify LoginScreen is shown
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byKey(const Key('username_field')), findsOneWidget);
    expect(find.byKey(const Key('password_field')), findsOneWidget);

    // -------------------------------------------------------------
    // STEP 2: Login Flow
    // -------------------------------------------------------------
    await tester.enterText(find.byKey(const Key('username_field')), 'alice');
    await tester.enterText(find.byKey(const Key('password_field')), 'password123');
    await tester.tap(find.byKey(const Key('login_button')));
    await tester.pumpAndSettle();

    // Verify navigated to ShellScreen
    expect(find.byType(ShellScreen), findsOneWidget);
    expect(find.text('Documents'), findsWidgets);
    expect(find.text('Chat'), findsOneWidget);

    // -------------------------------------------------------------
    // STEP 3: Document Flow (Empty state -> Uploaded item display)
    // -------------------------------------------------------------
    expect(
      find.text('No documents uploaded. Tap below to upload a PDF, TXT, or MD file.'),
      findsOneWidget,
    );

    // Simulate new document loaded
    when(() => mockDocRepo.fetchDocuments()).thenAnswer((_) async => [
          DocumentItem(
            id: 1,
            originalName: 'system_design.pdf',
            contentType: 'application/pdf',
            sizeBytes: 1048576,
            status: 'SUCCESS',
            uploadedAt: DateTime.now(),
          ),
        ]);

    GetIt.instance<DocumentBloc>().add(const LoadDocuments());
    await tester.pumpAndSettle();

    expect(find.text('system_design.pdf'), findsOneWidget);
    expect(find.text('1.0 MB • application/pdf'), findsOneWidget);

    // -------------------------------------------------------------
    // STEP 4: Chat Flow (Navigate to Chat -> Send Query -> Answer)
    // -------------------------------------------------------------
    when(() => mockChatRepo.sendQuery(
          query: 'What is the system design?',
          messageHistories: any(named: 'messageHistories'),
          useHyde: false,
        )).thenAnswer((_) async => 'The system design describes a modular microservice architecture.');

    // Switch to Chat tab
    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();

    // Type and send chat question
    final chatInput = find.byType(TextField);
    await tester.enterText(chatInput, 'What is the system design?');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    // Verify optimistic user message appears immediately
    expect(find.text('What is the system design?'), findsOneWidget);

    // Settle to deliver the assistant response
    await tester.pumpAndSettle();

    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(
      find.text('The system design describes a modular microservice architecture.'),
      findsOneWidget,
    );

    // -------------------------------------------------------------
    // STEP 5: Logout Flow (Drawer -> Confirm -> LoginScreen)
    // -------------------------------------------------------------
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    // Confirm dialog
    expect(find.text('Are you sure you want to log out of R.A.V.I.D.?'), findsOneWidget);
    final confirmLogoutButton = find.widgetWithText(TextButton, 'Log Out');
    await tester.tap(confirmLogoutButton);
    await tester.pumpAndSettle();

    // Verify back to LoginScreen
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(ShellScreen), findsNothing);
  });
}
