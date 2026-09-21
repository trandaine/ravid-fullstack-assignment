import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/core/api/auth_interceptor.dart';
import 'package:mobile/core/storage/secure_storage.dart';

class MockSecureStorageService extends Mock implements SecureStorageService {}
class MockDio extends Mock implements Dio {}
class MockRequestInterceptorHandler extends Mock implements RequestInterceptorHandler {}
class MockErrorInterceptorHandler extends Mock implements ErrorInterceptorHandler {}

void main() {
  late MockSecureStorageService mockStorage;
  late StreamController<void> unauthenticatedStream;
  late MockDio mockRefreshDio;
  late AuthQueuedInterceptor interceptor;

  setUp(() {
    mockStorage = MockSecureStorageService();
    unauthenticatedStream = StreamController<void>.broadcast();
    mockRefreshDio = MockDio();

    interceptor = AuthQueuedInterceptor(
      storage: mockStorage,
      unauthenticatedStream: unauthenticatedStream,
      refreshEndpoint: '/api/token/refresh/',
      refreshDio: mockRefreshDio,
    );
  });

  tearDown(() {
    unauthenticatedStream.close();
  });

  group('AuthQueuedInterceptor - onRequest', () {
    test('attaches Bearer token when accessToken exists in storage', () async {
      when(() => mockStorage.readAccessToken())
          .thenAnswer((_) async => 'valid_access_token');

      final options = RequestOptions(path: '/api/documents/');
      final handler = MockRequestInterceptorHandler();

      interceptor.onRequest(options, handler);
      await Future.delayed(Duration.zero);

      expect(options.headers['Authorization'], equals('Bearer valid_access_token'));
      verify(() => handler.next(options)).called(1);
    });

    test('does not attach Authorization header when accessToken is null', () async {
      when(() => mockStorage.readAccessToken()).thenAnswer((_) async => null);

      final options = RequestOptions(path: '/api/documents/');
      final handler = MockRequestInterceptorHandler();

      interceptor.onRequest(options, handler);
      await Future.delayed(Duration.zero);

      expect(options.headers.containsKey('Authorization'), isFalse);
      verify(() => handler.next(options)).called(1);
    });
  });

  group('AuthQueuedInterceptor - onError (Mutex Queue & 401 Handling)', () {
    test('passes non-401 error directly to next handler', () async {
      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/documents/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/documents/'),
          statusCode: 500,
        ),
      );
      final handler = MockErrorInterceptorHandler();

      interceptor.onError(dioException, handler);
      await Future.delayed(Duration.zero);

      verify(() => handler.next(dioException)).called(1);
      verifyNever(() => mockStorage.readRefreshToken());
    });

    test('on 401 error, refreshes token and resolves retry request', () async {
      when(() => mockStorage.readRefreshToken())
          .thenAnswer((_) async => 'valid_refresh_token');
      when(() => mockRefreshDio.post(
            '/api/token/refresh/',
            data: {'refresh': 'valid_refresh_token'},
          )).thenAnswer((_) async => Response(
            requestOptions: RequestOptions(path: '/api/token/refresh/'),
            statusCode: 200,
            data: {'access': 'new_access_token'},
          ));
      when(() => mockStorage.writeAccessToken('new_access_token'))
          .thenAnswer((_) async {});
      when(() => mockRefreshDio.fetch(any())).thenAnswer((invocation) async {
        final req = invocation.positionalArguments[0] as RequestOptions;
        return Response(
          requestOptions: req,
          statusCode: 200,
          data: {'success': true},
        );
      });

      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/documents/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/documents/'),
          statusCode: 401,
        ),
      );
      final handler = MockErrorInterceptorHandler();

      interceptor.onError(dioException, handler);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(() => mockStorage.writeAccessToken('new_access_token')).called(1);
      verify(() => handler.resolve(any())).called(1);
    });

    test('mutex: concurrent 401 requests trigger refresh endpoint only once and resolve both', () async {
      final refreshCompleter = Completer<Response>();

      when(() => mockStorage.readRefreshToken())
          .thenAnswer((_) async => 'valid_refresh_token');
      when(() => mockStorage.readAccessToken())
          .thenAnswer((_) async => 'new_access_token');
      when(() => mockRefreshDio.post(
            '/api/token/refresh/',
            data: {'refresh': 'valid_refresh_token'},
          )).thenAnswer((_) => refreshCompleter.future);
      when(() => mockStorage.writeAccessToken('new_access_token'))
          .thenAnswer((_) async {});
      when(() => mockRefreshDio.fetch(any())).thenAnswer((invocation) async {
        final req = invocation.positionalArguments[0] as RequestOptions;
        return Response(
          requestOptions: req,
          statusCode: 200,
          data: {'data': 'resolved'},
        );
      });

      final req1 = DioException(
        requestOptions: RequestOptions(path: '/api/documents/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/documents/'),
          statusCode: 401,
        ),
      );
      final req2 = DioException(
        requestOptions: RequestOptions(path: '/api/chat/query/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/chat/query/'),
          statusCode: 401,
        ),
      );

      final handler1 = MockErrorInterceptorHandler();
      final handler2 = MockErrorInterceptorHandler();

      // Trigger first 401 (initiates refresh)
      interceptor.onError(req1, handler1);
      // Trigger second 401 concurrently while refreshing
      interceptor.onError(req2, handler2);

      // Complete the refresh call
      refreshCompleter.complete(Response(
        requestOptions: RequestOptions(path: '/api/token/refresh/'),
        statusCode: 200,
        data: {'access': 'new_access_token'},
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      // Refresh endpoint must only be called ONCE
      verify(() => mockRefreshDio.post('/api/token/refresh/', data: {'refresh': 'valid_refresh_token'})).called(1);
      // Both handlers must be resolved
      verify(() => handler1.resolve(any())).called(1);
      verify(() => handler2.resolve(any())).called(1);
    });

    test('on refresh failure, clears storage and notifies unauthenticatedStream', () async {
      when(() => mockStorage.readRefreshToken())
          .thenAnswer((_) async => 'invalid_refresh_token');
      when(() => mockRefreshDio.post(
            '/api/token/refresh/',
            data: {'refresh': 'invalid_refresh_token'},
          )).thenThrow(DioException(
            requestOptions: RequestOptions(path: '/api/token/refresh/'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/token/refresh/'),
              statusCode: 401,
            ),
          ));
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});

      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/documents/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/documents/'),
          statusCode: 401,
        ),
      );
      final handler = MockErrorInterceptorHandler();

      bool streamNotified = false;
      unauthenticatedStream.stream.listen((_) => streamNotified = true);

      interceptor.onError(dioException, handler);
      await Future.delayed(const Duration(milliseconds: 50));

      verify(() => mockStorage.clearAll()).called(1);
      expect(streamNotified, isTrue);
      verify(() => handler.next(dioException)).called(1);
    });

    test('when refresh token is missing in storage, notifies unauthenticatedStream and passes error', () async {
      when(() => mockStorage.readRefreshToken()).thenAnswer((_) async => null);

      final dioException = DioException(
        requestOptions: RequestOptions(path: '/api/documents/'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/documents/'),
          statusCode: 401,
        ),
      );
      final handler = MockErrorInterceptorHandler();

      bool streamNotified = false;
      unauthenticatedStream.stream.listen((_) => streamNotified = true);

      interceptor.onError(dioException, handler);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(streamNotified, isTrue);
      verify(() => handler.next(dioException)).called(1);
    });
  });
}
