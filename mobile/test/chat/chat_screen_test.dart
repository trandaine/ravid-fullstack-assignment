import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/core/widgets/empty_state.dart';
import 'package:mobile/features/chat/bloc/chat_bloc.dart';
import 'package:mobile/features/chat/bloc/chat_event.dart';
import 'package:mobile/features/chat/bloc/chat_state.dart';
import 'package:mobile/features/chat/data/models/message.dart';
import 'package:mobile/features/chat/presentation/chat_screen.dart';
import 'package:mobile/features/chat/presentation/widgets/message_bubble.dart';

class MockChatBloc extends Mock implements ChatBloc {}

void main() {
  late MockChatBloc mockChatBloc;

  setUpAll(() {
    registerFallbackValue(const SendMessage(text: ''));
    registerFallbackValue(const ToggleHyde(enabled: false));
    registerFallbackValue(const ChatReset());
  });

  setUp(() {
    mockChatBloc = MockChatBloc();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: BlocProvider<ChatBloc>.value(
        value: mockChatBloc,
        child: const ChatScreen(),
      ),
    );
  }

  final sampleMessages = [
    Message(
      id: 'msg-1',
      content: 'What are the main findings?',
      role: MessageRole.user,
      status: MessageStatus.delivered,
      timestamp: DateTime.now(),
    ),
    Message(
      id: 'msg-2',
      content: 'The findings indicate high accuracy in document ingestion.',
      role: MessageRole.assistant,
      status: MessageStatus.delivered,
      timestamp: DateTime.now(),
    ),
  ];

  group('ChatScreen Widget Tests', () {
    testWidgets('renders EmptyState when message list is empty', (tester) async {
      when(() => mockChatBloc.state).thenReturn(const ChatInitial());
      when(() => mockChatBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(EmptyState), findsOneWidget);
      expect(
        find.textContaining('Ask anything about your ingested documents'),
        findsOneWidget,
      );
    });

    testWidgets('renders MessageBubble widgets when messages are present', (tester) async {
      when(() => mockChatBloc.state).thenReturn(
        ChatLoaded(messages: sampleMessages, useHyde: false),
      );
      when(() => mockChatBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(MessageBubble), findsNWidgets(2));
      expect(find.text('What are the main findings?'), findsOneWidget);
      expect(
        find.text('The findings indicate high accuracy in document ingestion.'),
        findsOneWidget,
      );
    });

    testWidgets('toggling HyDE switch dispatches ToggleHyde event', (tester) async {
      when(() => mockChatBloc.state).thenReturn(
        const ChatLoaded(messages: [], useHyde: false),
      );
      when(() => mockChatBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pump();

      verify(() => mockChatBloc.add(const ToggleHyde(enabled: true))).called(1);
    });

    testWidgets('typing and tapping send dispatches SendMessage event', (tester) async {
      when(() => mockChatBloc.state).thenReturn(
        const ChatLoaded(messages: [], useHyde: false),
      );
      when(() => mockChatBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Explain the quarterly budget');
      await tester.pump();

      final sendButton = find.byIcon(Icons.send);
      await tester.tap(sendButton);
      await tester.pump();

      verify(() => mockChatBloc.add(
            const SendMessage(text: 'Explain the quarterly budget'),
          )).called(1);
    });

    testWidgets('send button is disabled and shows spinner when isSending is true', (tester) async {
      final sendingMessage = Message(
        id: 'msg-sending',
        content: 'Analyzing...',
        role: MessageRole.user,
        status: MessageStatus.sending,
        timestamp: DateTime.now(),
      );

      when(() => mockChatBloc.state).thenReturn(
        ChatLoaded(messages: [sendingMessage], useHyde: false),
      );
      when(() => mockChatBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(CircularProgressIndicator), findsWidgets);
      // Send button with icon should not be active
      expect(find.byIcon(Icons.send), findsNothing);
    });

    testWidgets('clear chat icon button dispatches ChatReset', (tester) async {
      when(() => mockChatBloc.state).thenReturn(
        ChatLoaded(messages: sampleMessages, useHyde: false),
      );
      when(() => mockChatBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      final clearButton = find.byIcon(Icons.delete_sweep_outlined);
      expect(clearButton, findsOneWidget);

      await tester.tap(clearButton);
      await tester.pump();

      verify(() => mockChatBloc.add(const ChatReset())).called(1);
    });
  });
}
