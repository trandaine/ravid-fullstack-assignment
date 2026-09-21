import 'package:equatable/equatable.dart';
import '../data/models/document.dart';

abstract class DocumentState extends Equatable {
  const DocumentState();

  @override
  List<Object?> get props => [];
}

class DocumentInitial extends DocumentState {
  const DocumentInitial();
}

class DocumentLoading extends DocumentState {
  const DocumentLoading();
}

class DocumentLoaded extends DocumentState {
  final List<DocumentItem> documents;
  final bool isEmpty;

  const DocumentLoaded({required this.documents, required this.isEmpty});

  @override
  List<Object?> get props => [documents, isEmpty];
}

class DocumentUploading extends DocumentState {
  const DocumentUploading();
}

class DocumentPolling extends DocumentState {
  final String taskId;
  final int tick;

  const DocumentPolling({required this.taskId, required this.tick});

  @override
  List<Object?> get props => [taskId, tick];
}

class DocumentSuccess extends DocumentState {
  final String message;

  const DocumentSuccess({required this.message});

  @override
  List<Object?> get props => [message];
}

class DocumentFailure extends DocumentState {
  final String error;

  const DocumentFailure({required this.error});

  @override
  List<Object?> get props => [error];
}
