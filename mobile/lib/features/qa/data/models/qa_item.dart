import 'package:equatable/equatable.dart';
import '../../search/data/models/search_result.dart';

enum MessageRole { user, assistant }

class ChatMessage extends Equatable {
  final String id;
  final MessageRole role;
  final String content;
  final List<SourceChunk> sources;
  final DateTime timestamp;
  final bool isLoading;
  final bool isError;
  final int? responseTimeMs;
  final double? confidenceScore;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.sources = const [],
    required this.timestamp,
    this.isLoading = false,
    this.isError = false,
    this.responseTimeMs,
    this.confidenceScore,
  });

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    List<SourceChunk>? sources,
    DateTime? timestamp,
    bool? isLoading,
    bool? isError,
    int? responseTimeMs,
    double? confidenceScore,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      sources: sources ?? this.sources,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
      isError: isError ?? this.isError,
      responseTimeMs: responseTimeMs ?? this.responseTimeMs,
      confidenceScore: confidenceScore ?? this.confidenceScore,
    );
  }

  @override
  List<Object?> get props => [
        id,
        role,
        content,
        sources,
        timestamp,
        isLoading,
        isError,
        responseTimeMs,
        confidenceScore,
      ];
}

class QAResponse extends Equatable {
  final String question;
  final String answer;
  final List<SourceChunk> sources;
  final int responseTimeMs;
  final double? confidenceScore;
  final String? sessionId;

  const QAResponse({
    required this.question,
    required this.answer,
    required this.sources,
    required this.responseTimeMs,
    this.confidenceScore,
    this.sessionId,
  });

  factory QAResponse.fromJson(Map<String, dynamic> json) {
    final sourcesList = json['sources'] as List<dynamic>? ?? [];
    final sources = sourcesList
        .map((s) => SourceChunk.fromJson(s as Map<String, dynamic>))
        .toList();

    return QAResponse(
      question: json['question'] as String? ?? '',
      answer: json['answer'] as String? ?? '',
      sources: sources,
      responseTimeMs: (json['response_time_ms'] as num?)?.toInt() ?? 0,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      sessionId: json['session_id'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        question,
        answer,
        sources,
        responseTimeMs,
        confidenceScore,
        sessionId,
      ];
}
