import 'package:equatable/equatable.dart';
import '../data/models/qa_item.dart';

abstract class QAState extends Equatable {
  final List<ChatMessage> messages;
  final String? sessionId;

  const QAState({
    this.messages = const [],
    this.sessionId,
  });

  @override
  List<Object?> get props => [messages, sessionId];
}

class QAInitial extends QAState {
  const QAInitial({super.messages = const [], super.sessionId});
}

class QALoading extends QAState {
  const QALoading({required super.messages, super.sessionId});
}

class QASuccess extends QAState {
  const QASuccess({required super.messages, super.sessionId});
}

class QAFailure extends QAState {
  final String error;

  const QAFailure({
    required this.error,
    required super.messages,
    super.sessionId,
  });

  @override
  List<Object?> get props => [error, messages, sessionId];
}
