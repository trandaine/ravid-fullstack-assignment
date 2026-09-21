import 'dart:io';
import 'package:dio/dio.dart';
import 'models/document.dart';

class UploadDocumentResult {
  final int documentId;
  final String taskId;
  final String message;

  UploadDocumentResult({
    required this.documentId,
    required this.taskId,
    required this.message,
  });
}

class DocumentRepository {
  final Dio _dio;

  DocumentRepository({required Dio dio}) : _dio = dio;

  Future<List<DocumentItem>> fetchDocuments() async {
    final response = await _dio.get('/api/documents/');
    final list = response.data as List<dynamic>;
    return list
        .map((json) => DocumentItem.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<UploadDocumentResult> uploadDocument(File file) async {
    final fileName = file.path.split(Platform.pathSeparator).last;
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });

    final response = await _dio.post(
      '/api/documents/upload/',
      data: formData,
    );

    return UploadDocumentResult(
      documentId: response.data['document_id'] as int,
      taskId: response.data['task_id'] as String,
      message: response.data['message'] as String? ?? 'Upload accepted',
    );
  }

  Future<IngestionStatusResult> checkIngestionStatus(String taskId) async {
    final response = await _dio.get(
      '/api/documents/status/',
      queryParameters: {'task_id': taskId},
    );
    return IngestionStatusResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> deleteDocument(int documentId) async {
    await _dio.delete('/api/documents/$documentId/');
  }
}
