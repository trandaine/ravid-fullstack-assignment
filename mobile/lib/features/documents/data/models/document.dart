import 'package:equatable/equatable.dart';

class DocumentItem extends Equatable {
  final int id;
  final String originalName;
  final String contentType;
  final int sizeBytes;
  final String status;
  final DateTime? uploadedAt;

  const DocumentItem({
    required this.id,
    required this.originalName,
    required this.contentType,
    required this.sizeBytes,
    required this.status,
    this.uploadedAt,
  });

  factory DocumentItem.fromJson(Map<String, dynamic> json) {
    return DocumentItem(
      id: json['id'] as int,
      originalName: json['original_name'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int? ?? 0,
      status: json['status'] as String? ?? '',
      uploadedAt: json['uploaded_at'] != null
          ? DateTime.tryParse(json['uploaded_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'original_name': originalName,
      'content_type': contentType,
      'size_bytes': sizeBytes,
      'status': status,
      'uploaded_at': uploadedAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, originalName, contentType, sizeBytes, status, uploadedAt];
}

class IngestionStatusResult extends Equatable {
  final String status;
  final String? error;

  const IngestionStatusResult({required this.status, this.error});

  factory IngestionStatusResult.fromJson(Map<String, dynamic> json) {
    return IngestionStatusResult(
      status: json['status'] as String? ?? 'UNKNOWN',
      error: json['error'] as String? ?? json['detail'] as String?,
    );
  }

  @override
  List<Object?> get props => [status, error];
}
