import 'package:dio/dio.dart';

class ChatRepository {
  final Dio _dio;

  ChatRepository({required Dio dio}) : _dio = dio;

  Future<String> sendQuery({
    required String query,
    List<Map<String, String>> messageHistories = const [],
    bool useHyde = false,
  }) async {
    final response = await _dio.post(
      '/api/chat/query/',
      data: {
        'query': query,
        'message_histories': messageHistories,
        'use_hyde': useHyde,
      },
      options: Options(
        receiveTimeout: const Duration(seconds: 90),
      ),
    );

    return response.data['answer'] as String;
  }
}
