import 'package:dio/dio.dart';
import 'models/qa_item.dart';

class QARepository {
  final Dio _dio;

  QARepository({required Dio dio}) : _dio = dio;

  Future<QAResponse> askQuestion({
    required String question,
    String? sessionId,
    int topK = 5,
    double scoreThreshold = 0.5,
  }) async {
    final response = await _dio.post(
      '/api/qa/ask/',
      data: {
        'question': question,
        if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        'top_k': topK,
        'score_threshold': scoreThreshold,
      },
    );

    return QAResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
