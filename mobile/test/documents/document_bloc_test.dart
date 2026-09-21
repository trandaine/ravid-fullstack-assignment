import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/documents/bloc/document_bloc.dart';
import 'package:mobile/features/documents/bloc/document_event.dart';
import 'package:mobile/features/documents/bloc/document_state.dart';
import 'package:mobile/features/documents/data/document_repository.dart';
import 'package:mobile/features/documents/data/models/document.dart';

class MockDocumentRepository extends Mock implements DocumentRepository {}
class MockFile extends Mock implements File {}

void main() {
  late MockDocumentRepository mockDocumentRepository;

  setUpAll(() {
    registerFallbackValue(MockFile());
  });

  setUp(() {
    mockDocumentRepository = MockDocumentRepository();
  });

  final doc1 = DocumentItem(
    id: 1,
    originalName: 'test.pdf',
    contentType: 'application/pdf',
    sizeBytes: 1024,
    status: 'SUCCESS',
    uploadedAt: DateTime.now(),
  );

  group('DocumentBloc', () {
    test('initial state is DocumentInitial', () {
      expect(
        DocumentBloc(documentRepository: mockDocumentRepository).state,
        equals(const DocumentInitial()),
      );
    });

    blocTest<DocumentBloc, DocumentState>(
      'loads documents successfully with non-empty list',
      build: () {
        when(() => mockDocumentRepository.fetchDocuments())
            .thenAnswer((_) async => [doc1]);
        return DocumentBloc(documentRepository: mockDocumentRepository);
      },
      act: (bloc) => bloc.add(const LoadDocuments()),
      expect: () => [
        const DocumentLoading(),
        DocumentLoaded(documents: [doc1], isEmpty: false),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'loads documents successfully with empty list',
      build: () {
        when(() => mockDocumentRepository.fetchDocuments())
            .thenAnswer((_) async => []);
        return DocumentBloc(documentRepository: mockDocumentRepository);
      },
      act: (bloc) => bloc.add(const LoadDocuments()),
      expect: () => [
        const DocumentLoading(),
        const DocumentLoaded(documents: [], isEmpty: true),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'handles upload failure',
      build: () {
        when(() => mockDocumentRepository.uploadDocument(any()))
            .thenThrow(Exception('Upload failed'));
        return DocumentBloc(documentRepository: mockDocumentRepository);
      },
      act: (bloc) => bloc.add(UploadRequested(file: MockFile())),
      expect: () => [
        const DocumentUploading(),
        isA<DocumentFailure>(),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'handles polling success flow',
      build: () {
        when(() => mockDocumentRepository.checkIngestionStatus('task-123'))
            .thenAnswer((_) async => const IngestionStatusResult(status: 'SUCCESS'));
        when(() => mockDocumentRepository.fetchDocuments())
            .thenAnswer((_) async => [doc1]);
        return DocumentBloc(documentRepository: mockDocumentRepository);
      },
      act: (bloc) => bloc.add(const PollStatus(taskId: 'task-123', tick: 1)),
      expect: () => [
        const DocumentSuccess(message: 'Document processed successfully.'),
        DocumentLoaded(documents: [doc1], isEmpty: false),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'handles polling failure flow',
      build: () {
        when(() => mockDocumentRepository.checkIngestionStatus('task-123'))
            .thenAnswer((_) async => const IngestionStatusResult(
                  status: 'FAILURE',
                  error: 'Parsing error',
                ));
        return DocumentBloc(documentRepository: mockDocumentRepository);
      },
      act: (bloc) => bloc.add(const PollStatus(taskId: 'task-123', tick: 1)),
      expect: () => [
        const DocumentFailure(error: 'Parsing error'),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'handles polling timeout at >60 ticks',
      build: () => DocumentBloc(documentRepository: mockDocumentRepository),
      act: (bloc) => bloc.add(const PollStatus(taskId: 'task-123', tick: 61)),
      expect: () => [
        const DocumentFailure(error: 'Ingestion timed out. Please check again later.'),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'handles delete document successfully',
      build: () {
        when(() => mockDocumentRepository.deleteDocument(1))
            .thenAnswer((_) async {});
        return DocumentBloc(documentRepository: mockDocumentRepository);
      },
      seed: () => DocumentLoaded(documents: [doc1], isEmpty: false),
      act: (bloc) => bloc.add(const DeleteDocument(documentId: 1)),
      expect: () => [
        const DocumentLoaded(documents: [], isEmpty: true),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'handles DocumentReset',
      build: () => DocumentBloc(documentRepository: mockDocumentRepository),
      seed: () => DocumentLoaded(documents: [doc1], isEmpty: false),
      act: (bloc) => bloc.add(const DocumentReset()),
      expect: () => [
        const DocumentInitial(),
      ],
    );
  });
}
