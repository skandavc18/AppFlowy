import 'dart:async';

import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_stream.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

/// Message id and rendered text-block path. A user turn uses the empty path.
typedef ChatFindId = (String, String);

ChatFindId chatFindTextId(String messageId, List<int> path) =>
    (messageId, path.join('.'));

String chatFindMessageText(TextMessage message) {
  final answer = message.metadata?['$AnswerStream'];
  if (answer is AnswerStream) return answer.text;
  final question = message.metadata?['$QuestionStream'];
  return question is QuestionStream ? question.text : message.text;
}

bool _isAnswer(TextMessage message) =>
    message.author.id == aiResponseUserId ||
    message.author.id == systemUserId ||
    message.author.id.startsWith('streamId:');

/// The same local markdown parser as the answer renderer. Only delta text is
/// indexed, never link destinations, block configs, file metadata or tool output.
List<SurfaceFindEntry> chatFindMessageEntries(TextMessage message) {
  if (!_isConversationMessage(message)) return const [];
  final text = chatFindMessageText(message);
  if (!_isAnswer(message)) {
    return [SurfaceFindEntry((message.id, ''), text)];
  }
  final document = customMarkdownToDocument(text.trim());
  final iterator = NodeIterator(document: document, startNode: document.root);
  final entries = <SurfaceFindEntry>[];
  while (iterator.moveNext()) {
    final node = iterator.current;
    final delta = node.delta;
    if (delta != null) {
      entries.add(
        SurfaceFindEntry(
          chatFindTextId(message.id, node.path),
          delta.toPlainText(),
        ),
      );
    }
  }
  return entries;
}

bool _isConversationMessage(TextMessage message) {
  final type = onetimeMessageTypeFromMeta(message.metadata);
  return type != OnetimeShotType.error &&
      type != OnetimeShotType.relatedQuestion;
}

class _ChatFindIndex {
  _ChatFindIndex(this.chat);
  final ChatController chat;
  final _cache = <String, (String, bool, List<SurfaceFindEntry>)>{};

  List<SurfaceFindMatch> search(String query, FindOptions options) {
    final loaded = chat.messages.whereType<TextMessage>().toList();
    final ids = loaded.map((message) => message.id).toSet();
    _cache.removeWhere((id, _) => !ids.contains(id));
    if (query.isEmpty) return const [];
    final entries = <SurfaceFindEntry>[];
    for (final message in loaded) {
      if (!_isConversationMessage(message)) continue;
      final text = chatFindMessageText(message);
      final answer = _isAnswer(message);
      var cached = _cache[message.id];
      if (cached == null || cached.$1 != text || cached.$2 != answer) {
        cached = (text, answer, chatFindMessageEntries(message));
        _cache[message.id] = cached;
      }
      entries.addAll(cached.$3);
    }
    return searchSurfaceEntries(entries, query, options);
  }
}

/// Observes the loaded conversation without ever writing a message, requesting
/// history, consuming a stream callback, or reading the composer's draft.
class ChatFindController extends SurfaceFindController {
  factory ChatFindController(ChatController chat) =>
      ChatFindController._(chat, _ChatFindIndex(chat));

  ChatFindController._(this.chat, _ChatFindIndex index)
      : super(search: index.search) {
    _operations = chat.operationsStream.listen((_) => _messagesChanged());
    _messagesChanged();
  }

  final ChatController chat;
  late final StreamSubscription<ChatOperation> _operations;
  final Set<ValueListenable<String>> _streams = {};
  Timer? _streamRefresh;
  bool _closed = false;
  void Function(String)? _jumpToMessage;

  void _messagesChanged() {
    if (_closed) return;
    final current = <ValueListenable<String>>{};
    for (final message in chat.messages) {
      final answer = message.metadata?['$AnswerStream'];
      final question = message.metadata?['$QuestionStream'];
      if (answer is AnswerStream && !answer.isDisposed) {
        current.add(answer.textListenable);
      }
      if (question is QuestionStream && !question.isDisposed) {
        current.add(question.textListenable);
      }
    }
    for (final stream in _streams.difference(current)) {
      stream.removeListener(_streamChanged);
    }
    for (final stream in current.difference(_streams)) {
      stream.addListener(_streamChanged);
    }
    _streams
      ..clear()
      ..addAll(current);
    if (isOpen) refresh();
  }

  void _streamChanged() {
    if (_closed || !isOpen || _streamRefresh != null) return;
    _streamRefresh = Timer(const Duration(milliseconds: 32), () {
      _streamRefresh = null;
      if (!_closed && isOpen) refresh();
    });
  }

  void attachList(void Function(String) jumpToMessage) {
    _jumpToMessage = jumpToMessage;
  }

  void detachList(void Function(String) jumpToMessage) {
    if (_jumpToMessage == jumpToMessage) _jumpToMessage = null;
  }

  Future<void> reveal(SurfaceFindMatch hit) async {
    final id = hit.id;
    if (id is! ChatFindId || _closed || !isOpen) return;
    _jumpToMessage?.call(id.$1);
    // The real lazy list mounts the message on the next frame. The shared
    // host then reveals the matching block/word inside that rendered message.
    await WidgetsBinding.instance.endOfFrame;
  }

  @override
  void dispose() {
    _closed = true;
    _streamRefresh?.cancel();
    unawaited(_operations.cancel());
    for (final stream in _streams) {
      stream.removeListener(_streamChanged);
    }
    _streams.clear();
    _jumpToMessage = null;
    super.dispose();
  }
}

class ChatFindHost extends StatefulWidget {
  const ChatFindHost({
    super.key,
    required this.chatController,
    required this.child,
  });

  final ChatController chatController;
  final Widget child;

  @override
  State<ChatFindHost> createState() => _ChatFindHostState();
}

class _ChatFindHostState extends State<ChatFindHost> {
  late ChatFindController _find = ChatFindController(widget.chatController);

  @override
  void didUpdateWidget(ChatFindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatController != widget.chatController) {
      final previous = _find;
      _find = ChatFindController(widget.chatController);
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _find.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SurfaceFindHost(
        controller: _find,
        debugLabel: 'Chat loaded messages',
        hintText: 'Find in loaded messages',
        onReveal: _find.reveal,
        child: widget.child,
      );
}
