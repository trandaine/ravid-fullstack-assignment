import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_banner.dart';
import '../../../core/widgets/loading_indicator.dart';
import '../bloc/document_bloc.dart';
import '../bloc/document_event.dart';
import '../bloc/document_state.dart';
import '../data/models/document.dart';

class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key});

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DocumentBloc>().add(const LoadDocuments());
  }

  Future<void> _pickAndUploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
    );

    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      if (mounted) {
        context.read<DocumentBloc>().add(UploadRequested(file: file));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<DocumentBloc>().add(const LoadDocuments());
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickAndUploadFile,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload Document'),
      ),
      body: BlocConsumer<DocumentBloc, DocumentState>(
        listener: (context, state) {
          if (state is DocumentSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
        builder: (context, state) {
          return Column(
            children: [
              if (state is DocumentUploading)
                const LinearProgressIndicator(),
              if (state is DocumentPolling) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.blue[50],
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Processing document ingestion...',
                        style: TextStyle(color: Colors.blue[900], fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
              if (state is DocumentFailure)
                ErrorBanner(
                  message: state.error,
                  onRetry: () {
                    context.read<DocumentBloc>().add(const LoadDocuments());
                  },
                ),
              Expanded(
                child: _buildBody(state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBody(DocumentState state) {
    if (state is DocumentLoading) {
      return const LoadingIndicator(message: 'Loading documents...');
    }

    if (state is DocumentLoaded) {
      if (state.isEmpty) {
        return EmptyState(
          icon: Icons.description_outlined,
          message:
              'No documents uploaded. Tap below to upload a PDF, TXT, or MD file.',
          action: ElevatedButton.icon(
            onPressed: _pickAndUploadFile,
            icon: const Icon(Icons.add),
            label: const Text('Upload Your First Document'),
          ),
        );
      }

      return RefreshIndicator(
        onRefresh: () async {
          context.read<DocumentBloc>().add(const LoadDocuments());
        },
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: state.documents.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = state.documents[index];
            return _buildDocumentTile(doc);
          },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDocumentTile(DocumentItem doc) {
    Widget statusBadge;
    switch (doc.status.toUpperCase()) {
      case 'SUCCESS':
      case 'READY':
        statusBadge = const Icon(Icons.check_circle, color: Colors.green, size: 20);
        break;
      case 'PROCESSING':
      case 'PENDING':
      case 'UPLOADED':
        statusBadge = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        break;
      case 'FAILURE':
      case 'FAILED':
        statusBadge = const Icon(Icons.error, color: Colors.red, size: 20);
        break;
      default:
        statusBadge = const SizedBox.shrink();
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.insert_drive_file, color: Color(0xFF2563EB)),
      ),
      title: Text(
        doc.originalName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${_formatBytes(doc.sizeBytes)} • ${doc.contentType}',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusBadge,
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _confirmDelete(doc),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(DocumentItem doc) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Document'),
        content: Text('Are you sure you want to delete "${doc.originalName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<DocumentBloc>().add(DeleteDocument(documentId: doc.id));
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
