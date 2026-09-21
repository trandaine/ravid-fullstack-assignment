import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'app.dart';
import 'core/api/api_client.dart';
import 'core/events/unauthenticated_event.dart';
import 'core/storage/secure_storage.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_event.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/chat/bloc/chat_bloc.dart';
import 'features/chat/bloc/chat_event.dart';
import 'features/chat/data/chat_repository.dart';
import 'features/documents/bloc/document_bloc.dart';
import 'features/documents/bloc/document_event.dart';
import 'features/documents/data/document_repository.dart';

final getIt = GetIt.instance;

void setupDependencyInjection() {
  // 1. Unauthenticated broadcast stream controller
  final unauthenticatedController = createUnauthenticatedStreamController();
  getIt.registerSingleton<StreamController<void>>(unauthenticatedController);

  // 2. Secure storage service
  final storage = SecureStorageService();
  getIt.registerSingleton<SecureStorageService>(storage);

  // 3. Dio API Client
  final dio = createDio(
    storage: storage,
    unauthenticatedStream: unauthenticatedController,
  );
  getIt.registerSingleton(dio);

  // 4. Repositories
  final authRepo = AuthRepository(dio: dio, storage: storage);
  final docRepo = DocumentRepository(dio: dio);
  final chatRepo = ChatRepository(dio: dio);

  getIt.registerSingleton<AuthRepository>(authRepo);
  getIt.registerSingleton<DocumentRepository>(docRepo);
  getIt.registerSingleton<ChatRepository>(chatRepo);

  // 5. BLoCs
  final docBloc = DocumentBloc(documentRepository: docRepo);
  final chatBloc = ChatBloc(chatRepository: chatRepo);
  final authBloc = AuthBloc(
    authRepository: authRepo,
    storage: storage,
    unauthenticatedStream: unauthenticatedController,
    onResetData: () {
      docBloc.add(const DocumentReset());
      chatBloc.add(const ChatReset());
    },
  );

  getIt.registerSingleton<DocumentBloc>(docBloc);
  getIt.registerSingleton<ChatBloc>(chatBloc);
  getIt.registerSingleton<AuthBloc>(authBloc);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupDependencyInjection();
  getIt<AuthBloc>().add(const AppStarted());
  runApp(const RavidApp());
}
