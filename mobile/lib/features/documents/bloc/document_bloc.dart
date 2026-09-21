import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/document_repository.dart';
import '../data/models/document.dart';
import 'document_event.dart';
import 'document_state.dart';

class DocumentBloc extends Bloc<DocumentEvent, DocumentState> {
  final DocumentRepository _documentRepository;
  Timer? _pollingTimer;
  List<DocumentItem> _cachedDocuments = [];

  DocumentBloc({required DocumentRepository documentRepository})
      : _documentRepository = documentRepository,
        super(const DocumentInitial()) {
    on<LoadDocuments>(_onLoadDocuments);
    on<UploadRequested>(_onUploadRequested);
    on<PollStatus>(_onPollStatus);
    on<DeleteDocument>(_onDeleteDocument);
    on<DocumentReset>(_onDocumentReset);
  }

  @override
  Future<void> close() {
    _pollingTimer?.cancel();
    return super.close();
  }

  Future<void> _onLoadDocuments(LoadDocuments event, Emitter<DocumentState> emit) async {
    emit(const DocumentLoading());
    try {
      final documents = await _documentRepository.fetchDocuments();
      _cachedDocuments = List.from(documents);
      emit(DocumentLoaded(
        documents: _cachedDocuments,
        isEmpty: _cachedDocuments.isEmpty,
      ));
    } catch (e) {
      emit(DocumentFailure(error: _parseError(e)));
    }
  }

  Future<void> _onUploadRequested(UploadRequested event, Emitter<DocumentState> emit) async {
    _pollingTimer?.cancel();
    emit(const DocumentUploading());

    try {
      final result = await _documentRepository.uploadDocument(event.file);
      emit(DocumentPolling(taskId: result.taskId, tick: 0));
      _startPolling(result.taskId);
    } catch (e) {
      emit(DocumentFailure(error: _parseError(e)));
    }
  }

  void _startPolling(String taskId) {
    _pollingTimer?.cancel();
    int currentTick = 0;
    const maxTicks = 60; // 2 minutes (60 * 2 seconds)

    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      currentTick++;
      if (currentTick > maxTicks) {
        timer.cancel();
        add(PollStatus(taskId: taskId, tick: currentTick));
      } else {
        add(PollStatus(taskId: taskId, tick: currentTick));
      }
    });
  }

  Future<void> _onPollStatus(PollStatus event, Emitter<DocumentState> emit) async {
    if (event.tick > 60) {
      _pollingTimer?.cancel();
      emit(const DocumentFailure(error: 'Ingestion timed out. Please check again later.'));
      return;
    }

    try {
      final result = await _documentRepository.checkIngestionStatus(event.taskId);
      if (result.status == 'SUCCESS') {
        _pollingTimer?.cancel();
        emit(const DocumentSuccess(message: 'Document processed successfully.'));
        final docs = await _documentRepository.fetchDocuments();
        _cachedDocuments = List.from(docs);
        emit(DocumentLoaded(documents: _cachedDocuments, isEmpty: _cachedDocuments.isEmpty));
      } else if (result.status == 'FAILURE') {
        _pollingTimer?.cancel();
        emit(DocumentFailure(error: result.error ?? 'Ingestion failed.'));
      } else {
        emit(DocumentPolling(taskId: event.taskId, tick: event.tick));
      }
    } catch (e) {
      _pollingTimer?.cancel();
      emit(DocumentFailure(error: _parseError(e)));
    }
  }

  Future<void> _onDeleteDocument(DeleteDocument event, Emitter<DocumentState> emit) async {
    try {
      await _documentRepository.deleteDocument(event.documentId);
      _cachedDocuments.removeWhere((doc) => doc.id == event.documentId);
      emit(DocumentLoaded(
        documents: List.from(_cachedDocuments),
        isEmpty: _cachedDocuments.isEmpty,
      ));
    } catch (e) {
      emit(DocumentFailure(error: _parseError(e)));
    }
  }

  void _onDocumentReset(DocumentReset event, Emitter<DocumentState> emit) {
    _pollingTimer?.cancel();
    _cachedDocuments = [];
    emit(const DocumentInitial());
  }

  String _parseError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data is Map) {
        final data = error.response!.data as Map<String, dynamic>;
        if (data['detail'] != null) return data['detail'].toString();
        if (data['error'] != null) return data['error'].toString();
      }
      if (error.response?.statusCode == 415) return 'Unsupported file type.';
      if (error.response?.statusCode == 413) return 'File too large.';
      if (error.response?.statusCode == 404) return 'Document not found.';
      return error.message ?? 'Network error occurred.';
    }
    return error.toString();
  }
}
