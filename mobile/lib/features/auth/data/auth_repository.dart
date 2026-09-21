import 'package:dio/dio.dart';
import '../../../core/storage/secure_storage.dart';

class AuthRepository {
  final Dio _dio;
  final SecureStorageService _storage;

  AuthRepository({
    required Dio dio,
    required SecureStorageService storage,
  })  : _dio = dio,
        _storage = storage;

  Future<void> login(String username, String password) async {
    final response = await _dio.post(
      '/api/token/',
      data: {
        'username': username,
        'password': password,
      },
    );

    final access = response.data['access'] as String;
    final refresh = response.data['refresh'] as String;

    await _storage.writeAccessToken(access);
    await _storage.writeRefreshToken(refresh);
  }

  Future<bool> refreshToken() async {
    final refresh = await _storage.readRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      return false;
    }

    try {
      final response = await _dio.post(
        '/api/token/refresh/',
        data: {'refresh': refresh},
      );

      final access = response.data['access'] as String;
      await _storage.writeAccessToken(access);
      return true;
    } catch (_) {
      await _storage.clearAll();
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.clearAll();
  }
}
