import 'dart:io';
import 'package:equatable/equatable.dart';

abstract class DocumentEvent extends Equatable {
  const DocumentEvent();

  @override
  List<Object?> get props => [];
}

class LoadDocuments extends DocumentEvent {
  const LoadDocuments();
}

class UploadRequested extends DocumentEvent {
  final File file;

  const UploadRequested({required this.file});

  @override
  List<Object?> get props => [file.path];
}

class PollStatus extends DocumentEvent {
  final String taskId;
  final int tick;

  const PollStatus({required this.taskId, this.tick = 0});

  @override
  List<Object?> get props => [taskId, tick];
}

class DeleteDocument extends DocumentEvent {
  final int documentId;

  const DeleteDocument({required this.documentId});

  @override
  List<Object?> get props => [documentId];
}

class DocumentReset extends DocumentEvent {
  const DocumentReset();
}
