import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile/features/chat/bloc/chat_bloc.dart';
import 'package:mobile/features/chat/bloc/chat_event.dart';
import 'package:mobile/features/chat/bloc/chat_state.dart';
import 'package:mobile/features/chat/data/chat_repository.dart';
import 'package:mobile/features/chat/data/models/message.dart';

class MockChatRepository extends Mock implements ChatRepository {}
class MockUuid extends Mock implements Uuid {}

void main() {
  late MockChatRepository mockChatRepository;
  late MockUuid mockUuid;

  setUp(() {
    mockChatRepository = MockChatRepository();
    mockUuid = MockUuid();
  });

  group('ChatBloc', () {
    test('initial state is ChatInitial', () {
      expect(
        ChatBloc(chatRepository: mockChatRepository).state,
        equals(const ChatInitial()),
      );
    });

    blocTest<ChatBloc, ChatState>(
      'sends message, updates to sending, then delivers assistant response',
      build: () {
        when(() => mockUuid.v4()).thenReturn('msg-123');
        when(() => mockChatRepository.sendQuery(
              query: 'Hello RAG',
              messageHistories: [],
              useHyde: false,
            )).thenAnswer((_) async => 'Hello human!');
        return ChatBloc(chatRepository: mockChatRepository, uuid: mockUuid);
      },
      act: (bloc) => bloc.add(const SendMessage(text: 'Hello RAG')),
      expect: () => [
        isA<ChatLoaded>().having(
          (s) => s.messages.first.status,
          'status',
          MessageStatus.sending,
        ),
        isA<ChatLoaded>().having(
          (s) => s.messages.length,
          'message count',
          2,
        ),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'handles send query failure and sets message status to failed',
      build: () {
        when(() => mockUuid.v4()).thenReturn('msg-123');
        when(() => mockChatRepository.sendQuery(
              query: 'Hello RAG',
              messageHistories: any(named: 'messageHistories'),
              useHyde: any(named: 'useHyde'),
            )).thenThrow(Exception('AI service unavailable'));
        return ChatBloc(chatRepository: mockChatRepository, uuid: mockUuid);
      },
      act: (bloc) => bloc.add(const SendMessage(text: 'Hello RAG')),
      expect: () => [
        isA<ChatLoaded>(),
        isA<ChatError>().having(
          (s) => s.messages.first.status,
          'status',
          MessageStatus.failed,
        ),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'injects only the last 6 delivered messages as context history',
      build: () {
        when(() => mockUuid.v4()).thenReturn('new-msg');
        when(() => mockChatRepository.sendQuery(
              query: 'Seventh question',
              messageHistories: any(named: 'messageHistories'),
              useHyde: false,
            )).thenAnswer((_) async => 'Seventh answer');
        return ChatBloc(chatRepository: mockChatRepository, uuid: mockUuid);
      },
      seed: () => ChatLoaded(
        messages: [
          Message(id: '1', content: 'Q1', role: MessageRole.user, status: MessageStatus.delivered, timestamp: DateTime.now()),
          Message(id: '2', content: 'A1', role: MessageRole.assistant, status: MessageStatus.delivered, timestamp: DateTime.now()),
          Message(id: '3', content: 'Q2', role: MessageRole.user, status: MessageStatus.delivered, timestamp: DateTime.now()),
          Message(id: '4', content: 'A2', role: MessageRole.assistant, status: MessageStatus.delivered, timestamp: DateTime.now()),
          Message(id: '5', content: 'Q3', role: MessageRole.user, status: MessageStatus.delivered, timestamp: DateTime.now()),
          Message(id: '6', content: 'A3', role: MessageRole.assistant, status: MessageStatus.delivered, timestamp: DateTime.now()),
          Message(id: '7', content: 'Q4', role: MessageRole.user, status: MessageStatus.delivered, timestamp: DateTime.now()),
          Message(id: '8', content: 'Failed Q', role: MessageRole.user, status: MessageStatus.failed, timestamp: DateTime.now()),
        ],
        useHyde: false,
      ),
      act: (bloc) => bloc.add(const SendMessage(text: 'Seventh question')),
      verify: (_) {
        final captured = verify(() => mockChatRepository.sendQuery(
              query: 'Seventh question',
              messageHistories: captureAny(named: 'messageHistories'),
              useHyde: false,
            )).captured.single as List<Map<String, String>>;

        expect(captured.length, equals(6));
        expect(captured.first['content'], equals('A1')); // 7 total delivered, last 6 starts from A1
        expect(captured.any((m) => m['content'] == 'Failed Q'), isFalse);
      },
    );

    blocTest<ChatBloc, ChatState>(
      'toggles HyDE',
      build: () => ChatBloc(chatRepository: mockChatRepository),
      act: (bloc) => bloc.add(const ToggleHyde(enabled: true)),
      expect: () => [
        const ChatLoaded(messages: [], useHyde: true),
      ],
    );

    blocTest<ChatBloc, ChatState>(
      'resets chat state on ChatReset',
      build: () => ChatBloc(chatRepository: mockChatRepository),
      seed: () => ChatLoaded(
        messages: [
          Message(id: '1', content: 'Hi', role: MessageRole.user, status: MessageStatus.delivered, timestamp: DateTime.now()),
        ],
        useHyde: true,
      ),
      act: (bloc) => bloc.add(const ChatReset()),
      expect: () => [
        const ChatInitial(messages: [], useHyde: false),
      ],
    );
  });
}
