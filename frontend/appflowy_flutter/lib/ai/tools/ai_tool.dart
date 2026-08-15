import 'package:flutter/foundation.dart';

/// What a tool can do to the workspace, and therefore how much it has to ask.
enum AIToolRisk {
  /// Reads only. Safe to run without asking.
  read,

  /// Creates or changes something. Asked for unless allowed.
  write,

  /// Removes something. Always asked for unless explicitly allowed.
  destructive;

  bool get needsApproval => this != AIToolRisk.read;
}

/// One tool an agent may call.
///
/// The shape is MCP's: a name, a sentence saying what it does, and a JSON
/// Schema for its arguments. A tool provided in AppFlowy and a tool provided by
/// somebody's own MCP server are the same thing here.
@immutable
class AITool {
  const AITool({
    required this.serverId,
    required this.serverLabel,
    required this.name,
    required this.description,
    required this.schema,
    this.risk = AIToolRisk.write,
  });

  /// Which server answers this tool.
  final String serverId;
  final String serverLabel;

  /// The tool's own name, as its server knows it.
  final String name;
  final String description;

  /// JSON Schema for the arguments, as a plain map.
  final Map<String, dynamic> schema;
  final AIToolRisk risk;

  /// The name the model is told, namespaced so two servers can both offer a
  /// tool called `search` without one shadowing the other.
  String get qualifiedName => '${serverId}__$name';

  static const _separator = '__';

  /// Splits a qualified name back into its server and tool.
  static (String server, String tool)? split(String qualifiedName) {
    final at = qualifiedName.indexOf(_separator);
    if (at <= 0 || at + _separator.length >= qualifiedName.length) {
      return null;
    }
    return (
      qualifiedName.substring(0, at),
      qualifiedName.substring(at + _separator.length),
    );
  }
}

/// A model asking for a tool to be run.
@immutable
class AIToolCall {
  const AIToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  /// The id the model gave the call, which its answer has to be filed under.
  final String id;

  /// The qualified tool name.
  final String name;
  final Map<String, dynamic> arguments;
}

/// What running a tool produced.
@immutable
class AIToolResult {
  const AIToolResult(this.text, {this.isError = false});

  const AIToolResult.error(String message) : this(message, isError: true);

  final String text;
  final bool isError;
}

/// Something that offers tools and runs them.
abstract class AIToolServer {
  /// Stable, short, and safe to put in a tool name.
  String get id;

  String get label;

  /// Whether this server is reachable at all right now.
  bool get isAvailable => true;

  Future<List<AITool>> listTools();

  Future<AIToolResult> call(String name, Map<String, dynamic> arguments);

  Future<void> dispose() async {}
}
