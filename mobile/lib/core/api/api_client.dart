import 'dart:async';
import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';
import 'auth_interceptor.dart';

Dio createDio({
  required String baseUrl,
  required SecureStorageService storage,
  required StreamController<void> unauthenticatedStream,
  String refreshEndpoint = '/api/token/refresh/',
  Dio? refreshDio,
}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    AuthQueuedInterceptor(
      storage: storage,
      unauthenticatedStream: unauthenticatedStream,
      refreshEndpoint: refreshEndpoint,
      refreshDio: refreshDio,
    ),
  );

  return dio;
}
