import 'package:equatable/equatable.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class SendMessage extends ChatEvent {
  final String text;

  const SendMessage({required this.text});

  @override
  List<Object?> get props => [text];
}

class RetryMessage extends ChatEvent {
  final String messageId;

  const RetryMessage({required this.messageId});

  @override
  List<Object?> get props => [messageId];
}

class ToggleHyde extends ChatEvent {
  final bool enabled;

  const ToggleHyde({required this.enabled});

  @override
  List<Object?> get props => [enabled];
}

class ChatReset extends ChatEvent {
  const ChatReset();
}
