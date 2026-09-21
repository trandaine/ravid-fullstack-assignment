import 'package:dio/dio.dart';
import 'models/search_result.dart';

class SearchRepository {
  final Dio _dio;

  SearchRepository({required Dio dio}) : _dio = dio;

  Future<SearchResponse> search({
    required String query,
    int topK = 5,
    double scoreThreshold = 0.5,
  }) async {
    final response = await _dio.get(
      '/api/search/',
      queryParameters: {
        'query': query,
        'top_k': topK,
        'score_threshold': scoreThreshold,
      },
    );

    return SearchResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
