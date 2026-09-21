import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/auth/bloc/auth_bloc.dart';
import 'package:mobile/features/auth/bloc/auth_event.dart';
import 'package:mobile/features/auth/bloc/auth_state.dart';
import 'package:mobile/features/chat/bloc/chat_bloc.dart';
import 'package:mobile/features/chat/bloc/chat_state.dart';
import 'package:mobile/features/documents/bloc/document_bloc.dart';
import 'package:mobile/features/documents/bloc/document_event.dart';
import 'package:mobile/features/documents/bloc/document_state.dart';
import 'package:mobile/features/shell/presentation/shell_screen.dart';

class MockAuthBloc extends Mock implements AuthBloc {}
class MockDocumentBloc extends Mock implements DocumentBloc {}
class MockChatBloc extends Mock implements ChatBloc {}

void main() {
  late MockAuthBloc mockAuthBloc;
  late MockDocumentBloc mockDocumentBloc;
  late MockChatBloc mockChatBloc;

  setUpAll(() {
    registerFallbackValue(const LoadDocuments());
    registerFallbackValue(const LogoutRequested());
  });

  setUp(() {
    mockAuthBloc = MockAuthBloc();
    mockDocumentBloc = MockDocumentBloc();
    mockChatBloc = MockChatBloc();

    when(() => mockAuthBloc.state).thenReturn(const Authenticated());
    when(() => mockAuthBloc.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockDocumentBloc.state).thenReturn(const DocumentInitial());
    when(() => mockDocumentBloc.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockChatBloc.state).thenReturn(const ChatInitial());
    when(() => mockChatBloc.stream).thenAnswer((_) => const Stream.empty());
  });

  Widget createWidgetUnderTest() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: mockAuthBloc),
        BlocProvider<DocumentBloc>.value(value: mockDocumentBloc),
        BlocProvider<ChatBloc>.value(value: mockChatBloc),
      ],
      child: const MaterialApp(
        home: ShellScreen(),
      ),
    );
  }

  group('ShellScreen Widget Tests', () {
    testWidgets('renders NavigationBar destinations: Documents and Chat', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Documents'), findsWidgets);
      expect(find.text('Chat'), findsOneWidget);
    });

    testWidgets('switching navigation tab updates IndexedStack index', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      // Tap on Chat navigation tab
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();

      final indexedStack = tester.widget<IndexedStack>(find.byType(IndexedStack));
      expect(indexedStack.index, equals(1));
    });

    testWidgets('opening drawer shows header and items', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      // Open drawer via Scaffold
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      expect(find.text('R.A.V.I.D. Mobile'), findsOneWidget);
      expect(find.text('Retrieval & Verification'), findsOneWidget);
      expect(find.text('RAG Chat'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
    });

    testWidgets('tapping Log Out in drawer shows confirmation and dispatches LogoutRequested', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());

      // Open drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Tap Log Out tile
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();

      // Verify AlertDialog appeared
      expect(find.text('Are you sure you want to log out of R.A.V.I.D.?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap confirmation 'Log Out' button in dialog
      final logoutDialogButton = find.widgetWithText(TextButton, 'Log Out');
      await tester.tap(logoutDialogButton);
      await tester.pumpAndSettle();

      verify(() => mockAuthBloc.add(const LogoutRequested())).called(1);
    });
  });
}
