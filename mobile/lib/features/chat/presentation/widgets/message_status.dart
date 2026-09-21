import 'package:flutter/material.dart';
import '../../data/models/message.dart';

class MessageStatusWidget extends StatelessWidget {
  final MessageStatus status;
  final VoidCallback? onRetry;

  const MessageStatusWidget({
    super.key,
    required this.status,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: Colors.white70,
          ),
        );
      case MessageStatus.delivered:
        return const Icon(
          Icons.check,
          size: 14,
          color: Colors.white70,
        );
      case MessageStatus.failed:
        return InkWell(
          onTap: onRetry,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.error_outline,
                size: 14,
                color: Colors.redAccent,
              ),
              SizedBox(width: 4),
              Text(
                'Retry',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
    }
  }
}
