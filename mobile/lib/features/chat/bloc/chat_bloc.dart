import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../data/chat_repository.dart';
import '../data/models/message.dart';
import 'chat_event.dart';
import 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final ChatRepository _chatRepository;
  final Uuid _uuid;

  ChatBloc({
    required ChatRepository chatRepository,
    Uuid uuid = const Uuid(),
  })  : _chatRepository = chatRepository,
        _uuid = uuid,
        super(const ChatInitial()) {
    on<SendMessage>(_onSendMessage);
    on<RetryMessage>(_onRetryMessage);
    on<ToggleHyde>(_onToggleHyde);
    on<ChatReset>(_onChatReset);
  }

  Future<void> _onSendMessage(
    SendMessage event,
    Emitter<ChatState> emit,
  ) async {
    final queryText = event.text.trim();
    if (queryText.isEmpty) return;

    final userMessageId = _uuid.v4();
    final userMessage = Message(
      id: userMessageId,
      content: queryText,
      role: MessageRole.user,
      status: MessageStatus.sending,
      timestamp: DateTime.now(),
    );

    // Context injection: take last 6 delivered messages
    final deliveredHistory = state.messages
        .where((m) => m.status == MessageStatus.delivered)
        .toList();
    final recentHistory = deliveredHistory.length > 6
        ? deliveredHistory.sublist(deliveredHistory.length - 6)
        : deliveredHistory;
    final messageHistories =
        recentHistory.map((m) => m.toHistoryMap()).toList();

    final currentMessages = List<Message>.from(state.messages)..add(userMessage);
    emit(ChatLoaded(messages: currentMessages, useHyde: state.useHyde));

    try {
      final answer = await _chatRepository.sendQuery(
        query: queryText,
        messageHistories: messageHistories,
        useHyde: state.useHyde,
      );

      final updatedMessages = state.messages.map((m) {
        if (m.id == userMessageId) {
          return m.copyWith(status: MessageStatus.delivered);
        }
        return m;
      }).toList();

      final assistantMessage = Message(
        id: _uuid.v4(),
        content: answer,
        role: MessageRole.assistant,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
      );

      updatedMessages.add(assistantMessage);
      emit(ChatLoaded(messages: updatedMessages, useHyde: state.useHyde));
    } catch (e) {
      final failedMessages = state.messages.map((m) {
        if (m.id == userMessageId) {
          return m.copyWith(status: MessageStatus.failed);
        }
        return m;
      }).toList();

      emit(ChatError(
        error: _parseError(e),
        messages: failedMessages,
        useHyde: state.useHyde,
      ));
    }
  }

  Future<void> _onRetryMessage(
    RetryMessage event,
    Emitter<ChatState> emit,
  ) async {
    final failedIndex =
        state.messages.indexWhere((m) => m.id == event.messageId);
    if (failedIndex < 0) return;

    final messageToRetry = state.messages[failedIndex];
    if (messageToRetry.role != MessageRole.user) return;

    // Remove the failed message and re-send it
    final updatedMessages = List<Message>.from(state.messages)
      ..removeAt(failedIndex);

    emit(ChatLoaded(messages: updatedMessages, useHyde: state.useHyde));

    add(SendMessage(text: messageToRetry.content));
  }

  void _onToggleHyde(ToggleHyde event, Emitter<ChatState> emit) {
    emit(ChatLoaded(messages: state.messages, useHyde: event.enabled));
  }

  void _onChatReset(ChatReset event, Emitter<ChatState> emit) {
    emit(const ChatInitial(messages: [], useHyde: false));
  }

  String _parseError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data is Map) {
        final data = error.response!.data as Map<String, dynamic>;
        if (data['detail'] != null) return data['detail'].toString();
        if (data['error'] != null) return data['error'].toString();
      }
      if (error.type == DioExceptionType.receiveTimeout) {
        return 'Request timed out. The LLM service took too long to respond.';
      }
      return error.message ?? 'An error occurred during chat query.';
    }
    return error.toString();
  }
}
