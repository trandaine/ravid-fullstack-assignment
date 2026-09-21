import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/loading_indicator.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/bloc/auth_state.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/chat/bloc/chat_bloc.dart';
import 'features/documents/bloc/document_bloc.dart';
import 'features/shell/presentation/shell_screen.dart';

class RavidApp extends StatelessWidget {
  const RavidApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>.value(value: GetIt.instance<AuthBloc>()),
        BlocProvider<DocumentBloc>.value(value: GetIt.instance<DocumentBloc>()),
        BlocProvider<ChatBloc>.value(value: GetIt.instance<ChatBloc>()),
      ],
      child: MaterialApp(
        title: 'R.A.V.I.D. Mobile',
        theme: AppTheme.lightTheme,
        debugShowCheckedModeBanner: false,
        home: BlocBuilder<AuthBloc, AuthState>(
          builder: (context, state) {
            if (state is AuthInitial || state is AuthCheckInProgress) {
              return const Scaffold(
                body: LoadingIndicator(message: 'Initializing R.A.V.I.D....'),
              );
            }

            if (state is Authenticated) {
              return const ShellScreen();
            }

            return const LoginScreen();
          },
        ),
      ),
    );
  }
}
