import 'package:equatable/equatable.dart';

class SourceChunk extends Equatable {
  final int? chunkId;
  final String content;
  final double score;
  final String documentName;
  final int? documentId;

  const SourceChunk({
    this.chunkId,
    required this.content,
    required this.score,
    required this.documentName,
    this.documentId,
  });

  factory SourceChunk.fromJson(Map<String, dynamic> json) {
    return SourceChunk(
      chunkId: json['chunk_id'] as int?,
      content: json['content'] as String? ?? json['text'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      documentName: json['document_name'] as String? ?? json['document_title'] as String? ?? 'Unknown Document',
      documentId: json['document_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'chunk_id': chunkId,
      'content': content,
      'score': score,
      'document_name': documentName,
      'document_id': documentId,
    };
  }

  @override
  List<Object?> get props => [chunkId, content, score, documentName, documentId];
}

class SearchResponse extends Equatable {
  final String query;
  final List<SourceChunk> results;
  final int count;

  const SearchResponse({
    required this.query,
    required this.results,
    required this.count,
  });

  factory SearchResponse.fromJson(Map<String, dynamic> json) {
    final list = json['results'] as List<dynamic>? ?? [];
    final results = list
        .map((item) => SourceChunk.fromJson(item as Map<String, dynamic>))
        .toList();

    return SearchResponse(
      query: json['query'] as String? ?? '',
      results: results,
      count: json['count'] as int? ?? results.length,
    );
  }

  @override
  List<Object?> get props => [query, results, count];
}
