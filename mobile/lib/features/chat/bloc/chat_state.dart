import 'package:equatable/equatable.dart';
import '../data/models/message.dart';

abstract class ChatState extends Equatable {
  final List<Message> messages;
  final bool useHyde;

  const ChatState({
    this.messages = const [],
    this.useHyde = false,
  });

  bool get isSending =>
      messages.any((m) => m.status == MessageStatus.sending);

  @override
  List<Object?> get props => [messages, useHyde];
}

class ChatInitial extends ChatState {
  const ChatInitial({super.messages = const [], super.useHyde = false});
}

class ChatLoaded extends ChatState {
  const ChatLoaded({required super.messages, required super.useHyde});
}

class ChatError extends ChatState {
  final String error;

  const ChatError({
    required this.error,
    required super.messages,
    required super.useHyde,
  });

  @override
  List<Object?> get props => [error, messages, useHyde];
}
