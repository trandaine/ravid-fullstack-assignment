import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository _authRepository;
  final SecureStorageService _storage;
  final StreamController<void> _unauthenticatedStream;
  final void Function()? _onResetData;
  StreamSubscription<void>? _unauthenticatedSubscription;

  AuthBloc({
    required AuthRepository authRepository,
    required SecureStorageService storage,
    required StreamController<void> unauthenticatedStream,
    void Function()? onResetData,
  })  : _authRepository = authRepository,
        _storage = storage,
        _unauthenticatedStream = unauthenticatedStream,
        _onResetData = onResetData,
        super(const AuthInitial()) {
    on<AppStarted>(_onAppStarted);
    on<LoginRequested>(_onLoginRequested);
    on<LogoutRequested>(_onLogoutRequested);
    on<TokenExpired>(_onTokenExpired);

    _unauthenticatedSubscription = _unauthenticatedStream.stream.listen((_) {
      add(const TokenExpired());
    });
  }

  @override
  Future<void> close() {
    _unauthenticatedSubscription?.cancel();
    return super.close();
  }

  Future<void> _onAppStarted(AppStarted event, Emitter<AuthState> emit) async {
    emit(const AuthCheckInProgress());

    final accessToken = await _storage.readAccessToken();
    final refreshToken = await _storage.readRefreshToken();

    if (accessToken == null || refreshToken == null) {
      emit(const Unauthenticated());
      return;
    }

    final isExpiredOrExpiringSoon = _checkIfExpiringSoon(accessToken);
    if (!isExpiredOrExpiringSoon) {
      emit(const Authenticated());
      return;
    }

    final success = await _authRepository.refreshToken();
    if (success) {
      emit(const Authenticated());
    } else {
      await _storage.clearAll();
      _onResetData?.call();
      emit(const Unauthenticated());
    }
  }

  bool _checkIfExpiringSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;

      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = json.decode(payload) as Map<String, dynamic>;
      final exp = map['exp'] as int?;
      if (exp == null) return true;

      final expiryTime = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
      final now = DateTime.now().toUtc();
      final difference = expiryTime.difference(now);

      return difference.inMinutes < 5;
    } catch (_) {
      return true;
    }
  }

  Future<void> _onLoginRequested(LoginRequested event, Emitter<AuthState> emit) async {
    emit(const AuthLoading());
    try {
      await _authRepository.login(event.username, event.password);
      emit(const Authenticated());
    } on DioException catch (e) {
      String errorMessage = 'Login failed. Please try again.';
      if (e.response?.statusCode == 401) {
        errorMessage = 'Invalid username or password';
      } else if (e.response?.data is Map && (e.response?.data['detail'] != null || e.response?.data['error'] != null)) {
        errorMessage = (e.response?.data['detail'] ?? e.response?.data['error']).toString();
      }
      emit(Unauthenticated(error: errorMessage));
    } catch (e) {
      emit(Unauthenticated(error: e.toString()));
    }
  }

  Future<void> _onLogoutRequested(LogoutRequested event, Emitter<AuthState> emit) async {
    await _storage.clearAll();
    _onResetData?.call();
    emit(const Unauthenticated());
  }

  Future<void> _onTokenExpired(TokenExpired event, Emitter<AuthState> emit) async {
    await _storage.clearAll();
    _onResetData?.call();
    emit(const Unauthenticated(error: 'Session expired. Please log in again.'));
  }
}
