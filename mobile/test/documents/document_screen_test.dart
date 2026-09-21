import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/core/widgets/empty_state.dart';
import 'package:mobile/core/widgets/error_banner.dart';
import 'package:mobile/core/widgets/loading_indicator.dart';
import 'package:mobile/features/documents/bloc/document_bloc.dart';
import 'package:mobile/features/documents/bloc/document_event.dart';
import 'package:mobile/features/documents/bloc/document_state.dart';
import 'package:mobile/features/documents/data/models/document.dart';
import 'package:mobile/features/documents/presentation/document_screen.dart';

class MockDocumentBloc extends Mock implements DocumentBloc {}

void main() {
  late MockDocumentBloc mockDocumentBloc;

  setUp(() {
    mockDocumentBloc = MockDocumentBloc();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: BlocProvider<DocumentBloc>.value(
        value: mockDocumentBloc,
        child: const DocumentScreen(),
      ),
    );
  }

  final sampleDocs = [
    DocumentItem(
      id: 1,
      originalName: 'report_q3.pdf',
      contentType: 'application/pdf',
      sizeBytes: 1048576, // 1.0 MB
      status: 'SUCCESS',
      uploadedAt: DateTime.now(),
    ),
    DocumentItem(
      id: 2,
      originalName: 'notes.txt',
      contentType: 'text/plain',
      sizeBytes: 2048, // 2.0 KB
      status: 'PENDING',
      uploadedAt: DateTime.now(),
    ),
  ];

  group('DocumentScreen Widget Tests', () {
    testWidgets('renders LoadingIndicator when in DocumentLoading state', (tester) async {
      when(() => mockDocumentBloc.state).thenReturn(const DocumentLoading());
      when(() => mockDocumentBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(LoadingIndicator), findsOneWidget);
      expect(find.text('Loading documents...'), findsOneWidget);
    });

    testWidgets('renders EmptyState when loaded list is empty', (tester) async {
      when(() => mockDocumentBloc.state)
          .thenReturn(const DocumentLoaded(documents: [], isEmpty: true));
      when(() => mockDocumentBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(EmptyState), findsOneWidget);
      expect(
        find.text('No documents uploaded. Tap below to upload a PDF, TXT, or MD file.'),
        findsOneWidget,
      );
      expect(find.text('Upload Your First Document'), findsOneWidget);
    });

    testWidgets('renders document list with items, size, and status', (tester) async {
      when(() => mockDocumentBloc.state)
          .thenReturn(DocumentLoaded(documents: sampleDocs, isEmpty: false));
      when(() => mockDocumentBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('report_q3.pdf'), findsOneWidget);
      expect(find.text('1.0 MB • application/pdf'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('2.0 KB • text/plain'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget); // Success status
    });

    testWidgets('renders FloatingActionButton for upload', (tester) async {
      when(() => mockDocumentBloc.state)
          .thenReturn(DocumentLoaded(documents: sampleDocs, isEmpty: false));
      when(() => mockDocumentBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Upload Document'), findsOneWidget);
    });

    testWidgets('shows delete confirmation dialog and dispatches DeleteDocument', (tester) async {
      when(() => mockDocumentBloc.state)
          .thenReturn(DocumentLoaded(documents: sampleDocs, isEmpty: false));
      when(() => mockDocumentBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      // Find first delete button and tap it
      final deleteButtons = find.byIcon(Icons.delete_outline);
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      // Dialog assertions
      expect(find.text('Delete Document'), findsOneWidget);
      expect(find.text('Are you sure you want to delete "report_q3.pdf"?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap Delete in dialog
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      verify(() => mockDocumentBloc.add(const DeleteDocument(documentId: 1))).called(1);
    });

    testWidgets('renders ErrorBanner and retries on tap', (tester) async {
      when(() => mockDocumentBloc.state)
          .thenReturn(const DocumentFailure(error: 'Network connection lost'));
      when(() => mockDocumentBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('Network connection lost'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      verify(() => mockDocumentBloc.add(const LoadDocuments())).called(greaterThanOrEqualTo(1));
    });
  });
}
