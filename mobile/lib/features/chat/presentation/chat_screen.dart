import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_banner.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import '../data/models/message.dart';
import 'widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    context.read<ChatBloc>().add(SendMessage(text: text));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('RAG Chat'),
        actions: [
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (prev, curr) => prev.useHyde != curr.useHyde,
            builder: (context, state) {
              return Row(
                children: [
                  const Text('HyDE', style: TextStyle(fontSize: 12)),
                  Switch(
                    value: state.useHyde,
                    onChanged: (val) {
                      context.read<ChatBloc>().add(ToggleHyde(enabled: val));
                    },
                  ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Chat History',
            onPressed: () {
              context.read<ChatBloc>().add(const ChatReset());
            },
          ),
        ],
      ),
      body: BlocConsumer<ChatBloc, ChatState>(
        listener: (context, state) {
          _scrollToBottom();
        },
        builder: (context, state) {
          final isSending = state.isSending;

          return Column(
            children: [
              if (state is ChatError)
                ErrorBanner(
                  message: state.error,
                  onRetry: () {
                    final failedMessages = state.messages.where((m) => m.status == MessageStatus.failed);
                    if (failedMessages.isNotEmpty) {
                      context
                          .read<ChatBloc>()
                          .add(RetryMessage(messageId: failedMessages.last.id));
                    }
                  },
                ),
              Expanded(
                child: state.messages.isEmpty
                    ? const EmptyState(
                        icon: Icons.chat_outlined,
                        message:
                            'Ask anything about your ingested documents.\nHyDE can be enabled for hypothetically-expanded retrieval.',
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final msg = state.messages[index];
                          return MessageBubble(
                            message: msg,
                            onRetry: msg.status == MessageStatus.failed
                                ? () {
                                    context
                                        .read<ChatBloc>()
                                        .add(RetryMessage(messageId: msg.id));
                                  }
                                : null,
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.white,
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: 'Ask a question...',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          enabled: !isSending,
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        icon: isSending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send, size: 18),
                        onPressed: isSending ? null : _sendMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
