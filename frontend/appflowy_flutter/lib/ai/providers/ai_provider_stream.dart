import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:flutter/foundation.dart';

/// One thing that arrived while an answer was being written.
@immutable
sealed class AIStreamEvent {
  const AIStreamEvent();
}

/// More of the answer's text.
class AITextDelta extends AIStreamEvent {
  const AITextDelta(this.text);
  final String text;
}

/// The model asking for a tool to be run. Only reported once the whole call has
/// arrived, because arguments are streamed a fragment at a time.
class AIToolCallRequested extends AIStreamEvent {
  const AIToolCallRequested(this.call);
  final AIToolCall call;
}

/// One turn of the conversation as a provider expects to read it.
@immutable
class AIChatTurn {
  const AIChatTurn._(
    this.role,
    this.text, {
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
  });

  const AIChatTurn.user(String text) : this._(AIChatRole.user, text);
  const AIChatTurn.system(String text) : this._(AIChatRole.system, text);

  const AIChatTurn.assistant(
    String text, {
    List<AIToolCall> toolCalls = const [],
  }) : this._(AIChatRole.assistant, text, toolCalls: toolCalls);

  /// What a tool answered, filed under the call it answers.
  const AIChatTurn.toolResult({
    required String callId,
    required String name,
    required String text,
  }) : this._(AIChatRole.tool, text, toolCallId: callId, toolName: name);

  final AIChatRole role;
  final String text;
  final List<AIToolCall> toolCalls;
  final String? toolCallId;
  final String? toolName;
}

enum AIChatRole { system, user, assistant, tool }
