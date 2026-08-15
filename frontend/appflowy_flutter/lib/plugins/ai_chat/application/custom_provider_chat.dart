import 'dart:async';

import 'package:appflowy/ai/ai.dart';
import 'package:appflowy/ai/providers/ai_providers.dart';
import 'package:appflowy/ai/skills/ai_skill.dart';
import 'package:appflowy/ai/tools/tool_approval_dialog.dart';
import 'package:appflowy/ai/tools/tool_permissions.dart';
import 'package:appflowy/ai/tools/tool_registry.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_entity.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_message_stream.dart';
import 'package:appflowy_backend/protobuf/flowy-ai/entities.pb.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:nanoid/nanoid.dart';

/// Answers a chat from an AI service the person configured themselves.
///
/// The AppFlowy backend knows nothing about these conversations, so this owns
/// the whole round trip: it builds the history, streams the answer into the
/// same [AnswerStream] the built-in path uses, and keeps a transcript on disk
/// so reopening the page does not lose the conversation.
class CustomProviderChat {
  CustomProviderChat({
    required this.chatId,
    required this.userId,
    required this.chatController,
  });

  /// How many earlier turns are sent along with a question. Long enough to
  /// hold a conversation, short enough not to spend somebody's tokens on a
  /// transcript they stopped reading days ago.
  static const historyTurnLimit = 20;

  final String chatId;
  final String userId;
  final ChatController chatController;

  final CustomAIChatRunner _runner = CustomAIChatRunner();
  final Map<String, String> _text = {};

  AnswerStream? _answerStream;
  String? _answerMessageId;
  bool _streaming = false;

  /// The last thing that was asked, so regenerating picks the same skills.
  String _lastRequest = '';

  CustomAIProviderStore get _store => CustomAIProviderStore.instance;

  /// Whether the chat should answer from a configured provider rather than
  /// from AppFlowy's own backend.
  ({CustomAIProvider provider, String model})? get selection =>
      _store.activeSelection;

  bool get isActive => selection != null;

  bool get isRunning => _runner.isRunning;

  /// Whether [messageId] is a turn this side wrote. A backend answer cannot be
  /// regenerated from here, and one of these cannot be regenerated there.
  bool owns(String messageId) =>
      messageId.startsWith('custom_') || _text.containsKey(messageId);

  Future<void> dispose() async {
    await _runner.dispose();
    await _answerStream?.dispose();
    _answerStream = null;
    AIToolPermissionStore.instance.endChat(chatId);
  }

  /// Reads the conversation this side answered, as chat messages.
  Future<List<Message>> loadTranscript() async {
    final entries = await CustomAIChatTranscript.read(chatId);
    return entries.map((entry) {
      _text[entry.id] = entry.text;
      return TextMessage(
        id: entry.id,
        text: entry.text,
        createdAt: entry.createdAt.toLocal(),
        author: User(
          id: entry.role == CustomAIChatRole.assistant
              ? aiResponseUserId
              : userId,
        ),
      );
    }).toList();
  }

  /// Asks the configured provider, inserting the question and the streaming
  /// answer into the chat as it goes.
  Future<void> send({
    required String message,
    required void Function(Message message) onMessage,
    required void Function() onSendingFinished,
    required void Function() onAnswerFinished,
  }) async {
    final active = selection;
    if (active == null) {
      // The chat has already been put into its answering state, so it has to be
      // let out again even when there turns out to be nothing to ask.
      onSendingFinished();
      onAnswerFinished();
      return;
    }

    final now = DateTime.now();
    final questionId = 'custom_q_${nanoid(10)}';
    final question = TextMessage(
      id: questionId,
      text: message,
      author: User(id: userId),
      createdAt: now,
    );
    _text[questionId] = message;
    onMessage(question);

    await CustomAIChatTranscript.upsert(
      chatId,
      CustomAIChatEntry(
        id: questionId,
        role: CustomAIChatRole.user,
        text: message,
        createdAt: now,
        model: active.model,
      ),
    );

    await _stream(
      provider: active.provider,
      model: active.model,
      answerId: 'custom_a_${nanoid(10)}',
      request: message,
      onMessage: onMessage,
      onSendingFinished: onSendingFinished,
      onAnswerFinished: onAnswerFinished,
    );
  }

  /// Answers the same question again, replacing [answerMessageId].
  Future<void> regenerate({
    required String answerMessageId,
    required void Function(Message message) onMessage,
    required void Function() onSendingFinished,
    required void Function() onAnswerFinished,
    AIModelPB? model,
  }) async {
    final chosen = model == null ? null : CustomAIModelName.decode(model.name);
    final provider = chosen == null
        ? selection?.provider
        : CustomAIProviderStore.instance.providerFor(chosen.providerId);
    final modelName = chosen?.model ?? selection?.model;
    if (provider == null || modelName == null) {
      return;
    }

    final existing = chatController.messages
        .where((message) => message.id == answerMessageId)
        .toList();
    for (final message in existing) {
      await chatController.remove(message);
    }
    _text.remove(answerMessageId);
    await CustomAIChatTranscript.removeFrom(chatId, {answerMessageId});

    await _stream(
      provider: provider,
      model: modelName,
      answerId: answerMessageId,
      request: _lastRequest,
      onMessage: onMessage,
      onSendingFinished: onSendingFinished,
      onAnswerFinished: onAnswerFinished,
    );
  }

  Future<void> _stream({
    required CustomAIProvider provider,
    required String model,
    required String answerId,
    required void Function(Message message) onMessage,
    required void Function() onSendingFinished,
    required void Function() onAnswerFinished,
    String request = '',
  }) async {
    _lastRequest = request;
    await _answerStream?.dispose();
    final stream = AnswerStream();
    _answerStream = stream;
    _answerMessageId = answerId;
    _streaming = true;

    final createdAt = DateTime.now();
    onMessage(
      TextMessage(
        id: answerId,
        text: '',
        author: User(id: 'streamId:${nanoid()}'),
        createdAt: createdAt,
        metadata: {
          "$AnswerStream": stream,
          'chatId': chatId,
        },
      ),
    );
    onSendingFinished();

    await AIToolRegistry.instance.refresh();
    await AISkillStore.instance.ensureLoaded();

    await _runner.ask(
      provider: provider,
      model: model,
      turns: _history(excluding: answerId),
      systemPrompt: _systemPrompt(request),
      tools: AIToolRegistry.instance.tools,
      chatId: chatId,
      approve: askToRunTool,
      onToolNote: (note) =>
          stream.addEvent('${AIStreamEventPrefix.data}\n\n_${note}_\n\n'),
      onDelta: (delta) => stream.addEvent('${AIStreamEventPrefix.data}$delta'),
      onDone: (answer) async {
        _streaming = false;
        _text[answerId] = answer;
        await CustomAIChatTranscript.upsert(
          chatId,
          CustomAIChatEntry(
            id: answerId,
            role: CustomAIChatRole.assistant,
            text: answer,
            createdAt: createdAt,
            model: model,
          ),
        );
        onAnswerFinished();
      },
      onError: (message) {
        _streaming = false;
        stream.addEvent('${AIStreamEventPrefix.error}$message');
        onAnswerFinished();
      },
    );
  }

  /// Stops the answer being written. What has arrived is kept.
  Future<void> stop() async {
    await _runner.stop();
    if (!_streaming) {
      return;
    }
    _streaming = false;

    final answerId = _answerMessageId;
    final stream = _answerStream;
    if (answerId == null || stream == null) {
      return;
    }

    final partial = stream.text;
    if (partial.trim().isEmpty) {
      final started = chatController.messages
          .where((message) => message.id == answerId)
          .toList();
      for (final message in started) {
        await chatController.remove(message);
      }
      return;
    }

    _text[answerId] = partial;
    await CustomAIChatTranscript.upsert(
      chatId,
      CustomAIChatEntry(
        id: answerId,
        role: CustomAIChatRole.assistant,
        text: partial,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// What the assistant is told before it reads the conversation.
  ///
  /// The skills that suit the request are laid out here rather than being
  /// forced into every answer, so a long list of them cannot crowd out the
  /// question that was actually asked.
  String _systemPrompt(String request) {
    final buffer = StringBuffer()
      ..writeln(
        'You are the assistant inside AppFlowy, a workspace of pages, tables, '
        'folders and files. You can act on that workspace with the tools you '
        'have been given.',
      )
      ..writeln()
      ..writeln('- Use a tool rather than describing what somebody should do.')
      ..writeln('- Never invent an id. Find one with a tool that lists things.')
      ..writeln('- Say plainly what you changed, and where it went.')
      ..writeln(
        '- If a call is refused, stop and say so. Do not look for a way round.',
      );

    final skills = AISkillStore.instance.instructionsFor(request);
    if (skills.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('# How to do this well')
        ..writeln(skills);
    }
    return buffer.toString();
  }

  /// Turns the conversation on screen into what a provider expects to read.
  List<AIChatTurn> _history({required String excluding}) {    final turns = <AIChatTurn>[];
    for (final message in chatController.messages) {
      if (message.id == excluding) {
        continue;
      }
      if (onetimeMessageTypeFromMeta(message.metadata) != null) {
        continue;
      }

      final text = message is TextMessage && message.text.isNotEmpty
          ? message.text
          : _text[message.id] ?? '';
      if (text.trim().isEmpty) {
        continue;
      }

      final authorId = message.author.id;
      final isAnswer =
          authorId == aiResponseUserId || authorId.startsWith('streamId:');
      turns.add(
        isAnswer ? AIChatTurn.assistant(text) : AIChatTurn.user(text),
      );
    }

    if (turns.length > historyTurnLimit) {
      return turns.sublist(turns.length - historyTurnLimit);
    }
    return turns;
  }
}
