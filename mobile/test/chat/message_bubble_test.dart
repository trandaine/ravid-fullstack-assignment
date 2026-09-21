import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/chat/data/models/message.dart';
import 'package:mobile/features/chat/presentation/widgets/message_bubble.dart';

void main() {
  Widget createWidgetUnderTest(Message message, {VoidCallback? onRetry}) {
    return MaterialApp(
      home: Scaffold(
        body: MessageBubble(
          message: message,
          onRetry: onRetry,
        ),
      ),
    );
  }

  group('MessageBubble Widget Tests', () {
    testWidgets('renders user message on the right with person avatar', (tester) async {
      final userMessage = Message(
        id: 'msg-user-1',
        content: 'Hello AI assistant',
        role: MessageRole.user,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(createWidgetUnderTest(userMessage));

      expect(find.text('Hello AI assistant'), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsNothing);

      // Verify row alignment
      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.mainAxisAlignment, equals(MainAxisAlignment.end));
    });

    testWidgets('renders assistant message on the left with bot avatar and copy button', (tester) async {
      final assistantMessage = Message(
        id: 'msg-assistant-1',
        content: 'I am RAVID, your assistant.',
        role: MessageRole.assistant,
        status: MessageStatus.delivered,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(createWidgetUnderTest(assistantMessage));

      expect(find.text('I am RAVID, your assistant.'), findsOneWidget);
      expect(find.byIcon(Icons.smart_toy), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
      expect(find.byIcon(Icons.person), findsNothing);

      // Verify row alignment
      final row = tester.widget<Row>(find.byType(Row).first);
      expect(row.mainAxisAlignment, equals(MainAxisAlignment.start));
    });

    testWidgets('renders failed message with retry button and calls onRetry when tapped', (tester) async {
      bool retryTriggered = false;

      final failedMessage = Message(
        id: 'msg-failed-1',
        content: 'Failed prompt',
        role: MessageRole.user,
        status: MessageStatus.failed,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(createWidgetUnderTest(
        failedMessage,
        onRetry: () => retryTriggered = true,
      ));

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryTriggered, isTrue);
    });
  });
}
