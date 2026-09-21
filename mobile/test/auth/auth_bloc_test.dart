import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'dart:async';
import 'dart:convert';
import 'package:mobile/core/storage/secure_storage.dart';
import 'package:mobile/features/auth/bloc/auth_bloc.dart';
import 'package:mobile/features/auth/bloc/auth_event.dart';
import 'package:mobile/features/auth/bloc/auth_state.dart';
import 'package:mobile/features/auth/data/auth_repository.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSecureStorageService extends Mock implements SecureStorageService {}

String generateJwt({required int expSecondsFromNow}) {
  final header = base64Url.encode(utf8.encode(json.encode({'alg': 'HS256', 'typ': 'JWT'})));
  final exp = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) + expSecondsFromNow;
  final payload = base64Url.encode(utf8.encode(json.encode({'user_id': 1, 'exp': exp})));
  return '$header.$payload.signature';
}

void main() {
  late MockAuthRepository mockAuthRepository;
  late MockSecureStorageService mockStorage;
  late StreamController<void> unauthenticatedStream;
  late bool resetDataCalled;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    mockStorage = MockSecureStorageService();
    unauthenticatedStream = StreamController<void>.broadcast();
    resetDataCalled = false;
  });

  tearDown(() {
    unauthenticatedStream.close();
  });

  AuthBloc buildBloc() {
    return AuthBloc(
      authRepository: mockAuthRepository,
      storage: mockStorage,
      unauthenticatedStream: unauthenticatedStream,
      onResetData: () {
        resetDataCalled = true;
      },
    );
  }

  group('AuthBloc', () {
    test('initial state is AuthInitial', () {
      expect(buildBloc().state, equals(const AuthInitial()));
    });

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, Authenticated] when LoginRequested succeeds',
      build: () {
        when(() => mockAuthRepository.login('alice', 'password123'))
            .thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoginRequested(username: 'alice', password: 'password123')),
      expect: () => [
        const AuthLoading(),
        const Authenticated(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, Unauthenticated] when LoginRequested fails',
      build: () {
        when(() => mockAuthRepository.login('alice', 'wrongpass'))
            .thenThrow(Exception('Invalid credentials'));
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LoginRequested(username: 'alice', password: 'wrongpass')),
      expect: () => [
        const AuthLoading(),
        isA<Unauthenticated>(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthCheckInProgress, Unauthenticated] on AppStarted when no tokens stored',
      build: () {
        when(() => mockStorage.readAccessToken()).thenAnswer((_) async => null);
        when(() => mockStorage.readRefreshToken()).thenAnswer((_) async => null);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [
        const AuthCheckInProgress(),
        const Unauthenticated(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthCheckInProgress, Authenticated] on AppStarted when token is valid and not expiring soon',
      build: () {
        final validToken = generateJwt(expSecondsFromNow: 3600); // 1 hour
        when(() => mockStorage.readAccessToken()).thenAnswer((_) async => validToken);
        when(() => mockStorage.readRefreshToken()).thenAnswer((_) async => 'refresh_token');
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [
        const AuthCheckInProgress(),
        const Authenticated(),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'proactively refreshes and emits Authenticated when token expires in <5 min',
      build: () {
        final expiringToken = generateJwt(expSecondsFromNow: 120); // 2 minutes
        when(() => mockStorage.readAccessToken()).thenAnswer((_) async => expiringToken);
        when(() => mockStorage.readRefreshToken()).thenAnswer((_) async => 'refresh_token');
        when(() => mockAuthRepository.refreshToken()).thenAnswer((_) async => true);
        return buildBloc();
      },
      act: (bloc) => bloc.add(const AppStarted()),
      expect: () => [
        const AuthCheckInProgress(),
        const Authenticated(),
      ],
      verify: (_) {
        verify(() => mockAuthRepository.refreshToken()).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'clears storage, calls onResetData, and emits Unauthenticated on LogoutRequested',
      build: () {
        when(() => mockStorage.clearAll()).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) => bloc.add(const LogoutRequested()),
      expect: () => [
        const Unauthenticated(),
      ],
      verify: (_) {
        verify(() => mockStorage.clearAll()).called(1);
        expect(resetDataCalled, isTrue);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'handles TokenExpired from unauthenticated stream event',
      build: () {
        when(() => mockStorage.clearAll()).thenAnswer((_) async {});
        return buildBloc();
      },
      act: (bloc) {
        unauthenticatedStream.add(null);
      },
      expect: () => [
        const Unauthenticated(error: 'Session expired. Please log in again.'),
      ],
      verify: (_) {
        verify(() => mockStorage.clearAll()).called(1);
        expect(resetDataCalled, isTrue);
      },
    );
  });
}
