import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile/features/auth/bloc/auth_bloc.dart';
import 'package:mobile/features/auth/bloc/auth_event.dart';
import 'package:mobile/features/auth/bloc/auth_state.dart';
import 'package:mobile/features/auth/presentation/login_screen.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  late MockAuthBloc mockAuthBloc;

  setUp(() {
    mockAuthBloc = MockAuthBloc();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: BlocProvider<AuthBloc>.value(
        value: mockAuthBloc,
        child: const LoginScreen(),
      ),
    );
  }

  group('LoginScreen', () {
    testWidgets('renders username, password fields and login button', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(const Unauthenticated());
      when(() => mockAuthBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.byKey(const Key('username_field')), findsOneWidget);
      expect(find.byKey(const Key('password_field')), findsOneWidget);
      expect(find.byKey(const Key('login_button')), findsOneWidget);
    });

    testWidgets('shows validation errors when submitting empty form', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(const Unauthenticated());
      when(() => mockAuthBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Username is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('shows validation error for short password', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(const Unauthenticated());
      when(() => mockAuthBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.enterText(find.byKey(const Key('username_field')), 'alice');
      await tester.enterText(find.byKey(const Key('password_field')), 'short');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();

      expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    });

    testWidgets('dispatches LoginRequested when validation succeeds', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(const Unauthenticated());
      when(() => mockAuthBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.enterText(find.byKey(const Key('username_field')), 'alice');
      await tester.enterText(find.byKey(const Key('password_field')), 'password123');
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pump();

      verify(() => mockAuthBloc.add(
            const LoginRequested(username: 'alice', password: 'password123'),
          )).called(1);
    });

    testWidgets('displays error message when in Unauthenticated state with error', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(
        const Unauthenticated(error: 'Invalid username or password'),
      );
      when(() => mockAuthBloc.stream).thenAnswer((_) => const Stream.empty());

      await tester.pumpWidget(createWidgetUnderTest());

      expect(find.text('Invalid username or password'), findsOneWidget);
    });
  });
}
