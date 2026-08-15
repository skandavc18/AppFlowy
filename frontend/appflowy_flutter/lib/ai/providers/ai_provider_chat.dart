import 'dart:async';

import 'package:appflowy/ai/providers/ai_provider.dart';
import 'package:appflowy/ai/providers/ai_provider_client.dart';
import 'package:appflowy/ai/providers/ai_provider_store.dart';
import 'package:appflowy/ai/providers/ai_provider_stream.dart';
import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/ai/tools/tool_registry.dart';
import 'package:appflowy_backend/log.dart';

/// Runs one answer from a configured provider, including any tools it asks for.
///
/// It exists so the chat only ever holds one in-flight request: asking a second
/// question, or pressing stop, cancels the first, and a cancelled request is
/// never reported as an error.
class CustomAIChatRunner {
  /// How many times the model may ask for tools before the answer is closed.
  /// A loop that has not finished by then is not going to.
  static const maxToolRounds = 8;

  StreamSubscription<AIStreamEvent>? _subscription;
  int _generation = 0;
  bool _cancelled = false;
  bool _running = false;

  bool get isRunning => _running;

  /// Streams an answer for [turns] and reports every delta through [onDelta].
  ///
  /// [onDone] carries the whole answer; [onError] a sentence to show. Exactly
  /// one of the two runs unless the request was cancelled, in which case
  /// neither does.
  Future<void> ask({
    required CustomAIProvider provider,
    required String model,
    required List<AIChatTurn> turns,
    required void Function(String delta) onDelta,
    required void Function(String answer) onDone,
    required void Function(String message) onError,
    String? systemPrompt,
    List<AITool> tools = const [],
    String chatId = '',
    AIToolApproval? approve,
    void Function(String note)? onToolNote,
  }) async {
    await stop();
    final generation = ++_generation;
    _cancelled = false;
    _running = true;

    try {
      final apiKey =
          await CustomAIProviderStore.instance.apiKeyFor(provider.id);
      if (generation != _generation) {
        return;
      }

      if (provider.kind.needsApiKey && (apiKey == null || apiKey.isEmpty)) {
        onError(
          'Add an API key for ${provider.name} in Settings before using it.',
        );
        return;
      }

      final client = AIProviderClient(provider: provider, apiKey: apiKey);
      final history = <AIChatTurn>[...turns];
      final answer = StringBuffer();
      final canUseTools = tools.isNotEmpty && approve != null;

      for (var round = 0; round <= maxToolRounds; round++) {
        final roundText = StringBuffer();
        final requested = <AIToolCall>[];
        final finished = Completer<void>();
        Object? failure;

        _subscription = client
            .streamChat(
          model: model,
          turns: history,
          systemPrompt: systemPrompt,
          tools: canUseTools ? tools : const [],
        )
            .listen(
          (event) {
            if (generation != _generation) {
              return;
            }
            switch (event) {
              case AITextDelta(:final text):
                roundText.write(text);
                answer.write(text);
                onDelta(text);
              case AIToolCallRequested(:final call):
                requested.add(call);
            }
          },
          onError: (Object error) {
            failure = error;
            if (!finished.isCompleted) finished.complete();
          },
          onDone: () {
            if (!finished.isCompleted) finished.complete();
          },
          cancelOnError: true,
        );

        await finished.future;
        _subscription = null;

        if (generation != _generation || _cancelled) {
          return;
        }

        final error = failure;
        if (error != null) {
          final message = error is AIProviderException
              ? error.message
              : 'AppFlowy could not read the answer from ${provider.name}.';
          Log.warn('Custom AI provider failed: $error');
          onError(message);
          return;
        }

        if (requested.isEmpty) {
          final text = answer.toString();
          if (text.trim().isEmpty) {
            onError('${provider.name} returned an empty answer.');
          } else {
            onDone(text);
          }
          return;
        }

        if (round == maxToolRounds) {
          const note = '\n\n_Stopped after too many rounds of tool calls._';
          answer.write(note);
          onDelta(note);
          onDone(answer.toString());
          return;
        }

        history.add(
          AIChatTurn.assistant(roundText.toString(), toolCalls: requested),
        );

        for (final call in requested) {
          if (generation != _generation || _cancelled) {
            return;
          }
          final outcome = await AIToolRegistry.instance.run(
            call,
            chatId: chatId,
            approve: approve!,
          );
          onToolNote?.call(_noteFor(outcome));
          history.add(
            AIChatTurn.toolResult(
              callId: call.id,
              name: call.name,
              text: outcome.result.text,
            ),
          );
        }
      }
    } finally {
      if (generation == _generation) {
        _running = false;
      }
    }
  }

  static String _noteFor(AIToolOutcome outcome) {
    final name = outcome.tool?.name ?? outcome.call.name;
    if (outcome.refused) {
      return 'Refused $name';
    }
    return outcome.result.isError ? '$name failed' : 'Ran $name';
  }

  /// Stops whatever is in flight. The answer already on screen is kept.
  Future<void> stop() async {
    _generation++;
    _cancelled = true;
    _running = false;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  Future<void> dispose() => stop();
}
