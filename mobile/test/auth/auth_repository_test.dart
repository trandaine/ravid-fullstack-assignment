import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/core/storage/secure_storage.dart';
import 'package:mobile/features/auth/data/auth_repository.dart';

class MockDio extends Mock implements Dio {}
class MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  late MockDio mockDio;
  late MockSecureStorageService mockStorage;
  late AuthRepository repository;

  setUp(() {
    mockDio = MockDio();
    mockStorage = MockSecureStorageService();
    repository = AuthRepository(dio: mockDio, storage: mockStorage);
  });

  group('AuthRepository', () {
    test('login writes access and refresh tokens upon successful authentication', () async {
      when(() => mockDio.post(
            '/api/token/',
            data: {'username': 'alice', 'password': 'password123'},
          )).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/token/'),
          statusCode: 200,
          data: {
            'access': 'access_token_123',
            'refresh': 'refresh_token_456',
          },
        ),
      );
      when(() => mockStorage.writeAccessToken('access_token_123'))
          .thenAnswer((_) async {});
      when(() => mockStorage.writeRefreshToken('refresh_token_456'))
          .thenAnswer((_) async {});

      await repository.login('alice', 'password123');

      verify(() => mockStorage.writeAccessToken('access_token_123')).called(1);
      verify(() => mockStorage.writeRefreshToken('refresh_token_456')).called(1);
    });

    test('refreshToken updates access token and returns true when refresh succeeds', () async {
      when(() => mockStorage.readRefreshToken())
          .thenAnswer((_) async => 'stored_refresh_token');
      when(() => mockDio.post(
            '/api/token/refresh/',
            data: {'refresh': 'stored_refresh_token'},
          )).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/token/refresh/'),
          statusCode: 200,
          data: {'access': 'new_access_token_789'},
        ),
      );
      when(() => mockStorage.writeAccessToken('new_access_token_789'))
          .thenAnswer((_) async {});

      final result = await repository.refreshToken();

      expect(result, isTrue);
      verify(() => mockStorage.writeAccessToken('new_access_token_789')).called(1);
    });

    test('refreshToken returns false immediately when no refresh token stored', () async {
      when(() => mockStorage.readRefreshToken()).thenAnswer((_) async => null);

      final result = await repository.refreshToken();

      expect(result, isFalse);
      verifyNever(() => mockDio.post(any(), data: any(named: 'data')));
    });

    test('refreshToken clears storage and returns false when refresh endpoint fails', () async {
      when(() => mockStorage.readRefreshToken())
          .thenAnswer((_) async => 'expired_refresh_token');
      when(() => mockDio.post(
            '/api/token/refresh/',
            data: {'refresh': 'expired_refresh_token'},
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/token/refresh/'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/token/refresh/'),
            statusCode: 401,
          ),
        ),
      );
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});

      final result = await repository.refreshToken();

      expect(result, isFalse);
      verify(() => mockStorage.clearAll()).called(1);
    });

    test('logout clears all stored credentials', () async {
      when(() => mockStorage.clearAll()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => mockStorage.clearAll()).called(1);
    });
  });
}
