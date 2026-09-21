import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/chat/data/chat_repository.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio mockDio;
  late ChatRepository repository;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  setUp(() {
    mockDio = MockDio();
    repository = ChatRepository(dio: mockDio);
  });

  group('ChatRepository', () {
    test('sendQuery sends request with 90s receiveTimeout and returns answer', () async {
      when(() => mockDio.post(
            '/api/chat/query/',
            data: {
              'query': 'What is RAG?',
              'message_histories': [
                {'role': 'user', 'content': 'Hi'},
                {'role': 'assistant', 'content': 'Hello!'},
              ],
              'use_hyde': true,
            },
            options: any(named: 'options'),
          )).thenAnswer((invocation) async {
        final options = invocation.namedArguments[#options] as Options?;
        expect(options?.receiveTimeout, equals(const Duration(seconds: 90)));

        return Response(
          requestOptions: RequestOptions(path: '/api/chat/query/'),
          statusCode: 200,
          data: {
            'answer': 'RAG stands for Retrieval-Augmented Generation.',
            'sources': [],
          },
        );
      });

      final answer = await repository.sendQuery(
        query: 'What is RAG?',
        messageHistories: [
          {'role': 'user', 'content': 'Hi'},
          {'role': 'assistant', 'content': 'Hello!'},
        ],
        useHyde: true,
      );

      expect(answer, equals('RAG stands for Retrieval-Augmented Generation.'));
    });

    test('sendQuery works with default optional parameters', () async {
      when(() => mockDio.post(
            '/api/chat/query/',
            data: {
              'query': 'Simple question',
              'message_histories': [],
              'use_hyde': false,
            },
            options: any(named: 'options'),
          )).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/chat/query/'),
          statusCode: 200,
          data: {'answer': 'Simple answer'},
        ),
      );

      final answer = await repository.sendQuery(query: 'Simple question');

      expect(answer, equals('Simple answer'));
    });

    test('sendQuery propagates DioException on 90s receive timeout', () async {
      when(() => mockDio.post(
            '/api/chat/query/',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/chat/query/'),
          type: DioExceptionType.receiveTimeout,
          message: 'Receiving data took longer than 90 seconds',
        ),
      );

      expect(
        () => repository.sendQuery(query: 'Timeout query'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
