import 'package:equatable/equatable.dart';

abstract class QAEvent extends Equatable {
  const QAEvent();

  @override
  List<Object?> get props => [];
}

class QuestionSubmitted extends QAEvent {
  final String question;

  const QuestionSubmitted({required this.question});

  @override
  List<Object?> get props => [question];
}

class RetryQuestion extends QAEvent {
  final String messageId;

  const RetryQuestion({required this.messageId});

  @override
  List<Object?> get props => [messageId];
}

class ClearHistory extends QAEvent {
  const ClearHistory();
}

class QAReset extends QAEvent {
  const QAReset();
}
