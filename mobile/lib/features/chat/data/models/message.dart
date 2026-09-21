import 'package:equatable/equatable.dart';

enum MessageRole { user, assistant }

enum MessageStatus { sending, delivered, failed }

class Message extends Equatable {
  final String id;
  final String content;
  final MessageRole role;
  final MessageStatus status;
  final DateTime timestamp;

  const Message({
    required this.id,
    required this.content,
    required this.role,
    required this.status,
    required this.timestamp,
  });

  Message copyWith({
    String? id,
    String? content,
    MessageRole? role,
    MessageStatus? status,
    DateTime? timestamp,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      role: role ?? this.role,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, String> toHistoryMap() {
    return {
      'role': role == MessageRole.user ? 'user' : 'assistant',
      'content': content,
    };
  }

  @override
  List<Object?> get props => [id, content, role, status, timestamp];
}
