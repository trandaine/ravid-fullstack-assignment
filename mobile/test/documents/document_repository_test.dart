import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/documents/data/document_repository.dart';

class MockDio extends Mock implements Dio {}
class MockFile extends Mock implements File {}

void main() {
  late MockDio mockDio;
  late DocumentRepository repository;

  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(FormData());
  });

  setUp(() {
    mockDio = MockDio();
    repository = DocumentRepository(dio: mockDio);
  });

  group('DocumentRepository', () {
    test('fetchDocuments parses list of DocumentItem', () async {
      when(() => mockDio.get('/api/documents/')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/documents/'),
          statusCode: 200,
          data: [
            {
              'id': 1,
              'original_name': 'test.pdf',
              'content_type': 'application/pdf',
              'size_bytes': 2048,
              'status': 'SUCCESS',
              'uploaded_at': '2026-09-21T10:00:00Z',
            },
            {
              'id': 2,
              'original_name': 'notes.txt',
              'content_type': 'text/plain',
              'size_bytes': 512,
              'status': 'PENDING',
              'uploaded_at': '2026-09-21T10:05:00Z',
            }
          ],
        ),
      );

      final result = await repository.fetchDocuments();

      expect(result.length, equals(2));
      expect(result[0].id, equals(1));
      expect(result[0].originalName, equals('test.pdf'));
      expect(result[0].contentType, equals('application/pdf'));
      expect(result[0].sizeBytes, equals(2048));
      expect(result[0].status, equals('SUCCESS'));
      expect(result[1].id, equals(2));
      expect(result[1].status, equals('PENDING'));
    });

    test('uploadDocument posts FormData and returns UploadDocumentResult', () async {
      // Create a temporary file for testing
      final tempDir = Directory.systemTemp.createTempSync();
      final testFile = File('${tempDir.path}/test_upload.pdf');
      testFile.writeAsStringSync('dummy pdf content');

      when(() => mockDio.post(
            '/api/documents/upload/',
            data: any(named: 'data'),
          )).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/documents/upload/'),
          statusCode: 202,
          data: {
            'document_id': 42,
            'task_id': 'celery-task-999',
            'message': 'Ingestion scheduled',
          },
        ),
      );

      final result = await repository.uploadDocument(testFile);

      expect(result.documentId, equals(42));
      expect(result.taskId, equals('celery-task-999'));
      expect(result.message, equals('Ingestion scheduled'));

      // Clean up
      tempDir.deleteSync(recursive: true);
    });

    test('checkIngestionStatus queries with task_id and parses IngestionStatusResult', () async {
      when(() => mockDio.get(
            '/api/documents/status/',
            queryParameters: {'task_id': 'task-abc'},
          )).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/documents/status/'),
          statusCode: 200,
          data: {
            'status': 'SUCCESS',
            'error': null,
          },
        ),
      );

      final result = await repository.checkIngestionStatus('task-abc');

      expect(result.status, equals('SUCCESS'));
      expect(result.error, isNull);
    });

    test('deleteDocument issues DELETE request with correct endpoint', () async {
      when(() => mockDio.delete('/api/documents/123/')).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/api/documents/123/'),
          statusCode: 204,
        ),
      );

      await repository.deleteDocument(123);

      verify(() => mockDio.delete('/api/documents/123/')).called(1);
    });

    test('propagates DioException on network failure', () async {
      when(() => mockDio.get('/api/documents/')).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/documents/'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      expect(() => repository.fetchDocuments(), throwsA(isA<DioException>()));
    });
  });
}
