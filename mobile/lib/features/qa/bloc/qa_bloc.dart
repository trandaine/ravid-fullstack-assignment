import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../data/models/qa_item.dart';
import '../data/qa_repository.dart';
import 'qa_event.dart';
import 'qa_state.dart';

class QABloc extends Bloc<QAEvent, QAState> {
  final QARepository _qaRepository;

  QABloc({required QARepository qaRepository})
      : _qaRepository = qaRepository,
        super(const QAInitial()) {
    on<QuestionSubmitted>(_onQuestionSubmitted);
    on<RetryQuestion>(_onRetryQuestion);
    on<ClearHistory>(_onClearHistory);
    on<QAReset>(_onQAReset);
  }

  Future<void> _onQuestionSubmitted(
    QuestionSubmitted event,
    Emitter<QAState> emit,
  ) async {
    final trimmed = event.question.trim();
    if (trimmed.isEmpty) return;

    final userMsgId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final assistantMsgId = 'assistant_${DateTime.now().millisecondsSinceEpoch}';

    final userMessage = ChatMessage(
      id: userMsgId,
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );

    final pendingAssistantMessage = ChatMessage(
      id: assistantMsgId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isLoading: true,
    );

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..add(userMessage)
      ..add(pendingAssistantMessage);

    emit(QALoading(messages: updatedMessages, sessionId: state.sessionId));

    try {
      final response = await _qaRepository.askQuestion(
        question: trimmed,
        sessionId: state.sessionId,
      );

      final completedAssistantMessage = ChatMessage(
        id: assistantMsgId,
        role: MessageRole.assistant,
        content: response.answer,
        sources: response.sources,
        timestamp: DateTime.now(),
        isLoading: false,
        isError: false,
        responseTimeMs: response.responseTimeMs,
        confidenceScore: response.confidenceScore,
      );

      final finalMessages = List<ChatMessage>.from(updatedMessages)
        ..removeLast()
        ..add(completedAssistantMessage);

      emit(QASuccess(
        messages: finalMessages,
        sessionId: response.sessionId ?? state.sessionId,
      ));
    } catch (e) {
      final errorMsg = _parseError(e);

      final failedAssistantMessage = ChatMessage(
        id: assistantMsgId,
        role: MessageRole.assistant,
        content: errorMsg,
        timestamp: DateTime.now(),
        isLoading: false,
        isError: true,
      );

      final finalMessages = List<ChatMessage>.from(updatedMessages)
        ..removeLast()
        ..add(failedAssistantMessage);

      emit(QAFailure(
        error: errorMsg,
        messages: finalMessages,
        sessionId: state.sessionId,
      ));
    }
  }

  Future<void> _onRetryQuestion(
    RetryQuestion event,
    Emitter<QAState> emit,
  ) async {
    final failedIndex =
        state.messages.indexWhere((m) => m.id == event.messageId);
    if (failedIndex <= 0) return;

    final previousUserMessage = state.messages[failedIndex - 1];
    if (previousUserMessage.role != MessageRole.user) return;

    final updatedMessages = List<ChatMessage>.from(state.messages)
      ..removeAt(failedIndex);

    emit(QAInitial(messages: updatedMessages, sessionId: state.sessionId));

    add(QuestionSubmitted(question: previousUserMessage.content));
  }

  void _onClearHistory(ClearHistory event, Emitter<QAState> emit) {
    emit(const QAInitial(messages: [], sessionId: null));
  }

  void _onQAReset(QAReset event, Emitter<QAState> emit) {
    emit(const QAInitial(messages: [], sessionId: null));
  }

  String _parseError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data is Map) {
        final data = error.response!.data as Map<String, dynamic>;
        if (data['detail'] != null) return data['detail'].toString();
        if (data['error'] != null) return data['error'].toString();
      }
      return error.message ?? 'An error occurred while answering your question.';
    }
    return error.toString();
  }
}
