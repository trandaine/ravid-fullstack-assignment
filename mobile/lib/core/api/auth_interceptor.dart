import 'dart:async';
import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';

class AuthQueuedInterceptor extends QueuedInterceptor {
  final SecureStorageService _storage;
  final StreamController<void> _unauthenticatedStream;
  final String _refreshEndpoint;
  final Dio _refreshDio;
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  AuthQueuedInterceptor({
    required SecureStorageService storage,
    required StreamController<void> unauthenticatedStream,
    required String refreshEndpoint,
    Dio? refreshDio,
  })  : _storage = storage,
        _unauthenticatedStream = unauthenticatedStream,
        _refreshEndpoint = refreshEndpoint,
        _refreshDio = refreshDio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.readAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401) {
      return handler.next(err);
    }

    if (_isRefreshing) {
      final success = await _refreshCompleter!.future;
      if (success) {
        try {
          final token = await _storage.readAccessToken();
          err.requestOptions.headers['Authorization'] = 'Bearer $token';
          final response = await _refreshDio.fetch(err.requestOptions);
          return handler.resolve(response);
        } catch (e) {
          return handler.next(err);
        }
      } else {
        return handler.next(err);
      }
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await _storage.readRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        _refreshCompleter!.complete(false);
        _unauthenticatedStream.add(null);
        return handler.next(err);
      }

      final refreshUrl = err.requestOptions.baseUrl.isNotEmpty
          ? '${err.requestOptions.baseUrl}$_refreshEndpoint'
          : _refreshEndpoint;

      final response = await _refreshDio.post(
        refreshUrl,
        data: {'refresh': refreshToken},
      );

      final newAccess = response.data['access'] as String;
      await _storage.writeAccessToken(newAccess);
      _refreshCompleter!.complete(true);

      err.requestOptions.headers['Authorization'] = 'Bearer $newAccess';
      final retryResponse = await _refreshDio.fetch(err.requestOptions);
      return handler.resolve(retryResponse);
    } catch (_) {
      _refreshCompleter!.complete(false);
      await _storage.clearAll();
      _unauthenticatedStream.add(null);
      return handler.next(err);
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }
}
