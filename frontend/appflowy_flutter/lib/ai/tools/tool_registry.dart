import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

import 'ai_tool.dart';
import 'mcp_client.dart';
import 'mcp_server_config.dart';
import 'tool_permissions.dart';
import 'workspace_tools.dart';

/// Asked before a tool that changes anything is run.
typedef AIToolApproval = Future<AIToolDecision> Function(
  AITool tool,
  Map<String, dynamic> arguments,
);

/// What happened when a tool call was handled.
@immutable
class AIToolOutcome {
  const AIToolOutcome({
    required this.call,
    required this.result,
    this.tool,
    this.refused = false,
  });

  final AIToolCall call;
  final AIToolResult result;
  final AITool? tool;

  /// True when the person said no, rather than the tool failing.
  final bool refused;
}

/// Every tool available to an agent, from AppFlowy itself and from the MCP
/// servers the person added.
class AIToolRegistry extends ChangeNotifier {
  AIToolRegistry();

  static final AIToolRegistry instance = AIToolRegistry();

  /// How long one tool may take before the chat stops waiting for it.
  ///
  /// A call that never comes back would otherwise leave the chat answering for
  /// ever: the model is not told anything and the person is left with a stop
  /// button and no explanation.
  static const runTimeout = Duration(seconds: 90);

  final WorkspaceToolServer _workspace = WorkspaceToolServer();
  final Map<String, McpClient> _clients = {};

  List<AITool> _tools = [];
  bool _loading = false;

  List<AITool> get tools => List.unmodifiable(_tools);

  bool get isLoading => _loading;

  /// Why a server is not answering, keyed by server id.
  final Map<String, String> failures = {};

  /// Reads every server's tool list. Safe to call again; a server that refuses
  /// is reported rather than left to fail silently at call time.
  Future<void> refresh() async {
    if (_loading) {
      return;
    }
    _loading = true;
    notifyListeners();

    try {
      await McpServerStore.instance.ensureLoaded();
      await AIToolPermissionStore.instance.ensureLoaded();

      final collected = <AITool>[...await _workspace.listTools()];
      failures.clear();

      final configured = McpServerStore.instance.servers
          .where((server) => server.enabled)
          .toList();

      // Drop clients whose server is gone or was turned off.
      for (final id in _clients.keys.toList()) {
        if (!configured.any((server) => server.id == id)) {
          await _clients.remove(id)?.dispose();
        }
      }

      for (final server in configured) {
        final client = _clients.putIfAbsent(
          server.id,
          () => McpClient.of(server),
        );
        try {
          collected.addAll(await client.listTools());
        } catch (error) {
          failures[server.id] = '$error';
          Log.warn('MCP server ${server.name} could not be read: $error');
        }
      }

      _tools = collected;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Throws away every connection so a changed configuration is read afresh.
  Future<void> reload() async {
    for (final client in _clients.values) {
      await client.dispose();
    }
    _clients.clear();
    _tools = [];
    await refresh();
  }

  AITool? toolFor(String qualifiedName) {
    for (final tool in _tools) {
      if (tool.qualifiedName == qualifiedName) {
        return tool;
      }
    }
    return null;
  }

  AIToolServer? _serverFor(String serverId) =>
      serverId == WorkspaceToolServer.serverId
          ? _workspace
          : _clients[serverId];

  /// Runs one call the model asked for, asking first when it has to.
  Future<AIToolOutcome> run(
    AIToolCall call, {
    required String chatId,
    required AIToolApproval approve,
  }) async {
    final tool = toolFor(call.name);
    if (tool == null) {
      return AIToolOutcome(
        call: call,
        result: AIToolResult.error(
          'There is no tool called "${call.name}".',
        ),
      );
    }

    final permissions = AIToolPermissionStore.instance;
    if (!permissions.isAllowedWithoutAsking(tool, chatId: chatId)) {
      if (permissions.permissionFor(tool) == AIToolPermission.deny) {
        return AIToolOutcome(
          call: call,
          tool: tool,
          refused: true,
          result: const AIToolResult.error(
            'The person has not allowed this tool.',
          ),
        );
      }

      final decision = await approve(tool, call.arguments);
      switch (decision) {
        case AIToolDecision.allowOnce:
          break;
        case AIToolDecision.allowAlways:
          await permissions.remember(tool, AIToolPermission.allow);
        case AIToolDecision.allowAllThisChat:
          permissions.grantForChat(chatId);
        case AIToolDecision.denyAlways:
          await permissions.remember(tool, AIToolPermission.deny);
          return AIToolOutcome(
            call: call,
            tool: tool,
            refused: true,
            result: const AIToolResult.error('The person refused this tool.'),
          );
        case AIToolDecision.denyOnce:
          return AIToolOutcome(
            call: call,
            tool: tool,
            refused: true,
            result: const AIToolResult.error(
              'The person refused this call. Do not try it again.',
            ),
          );
      }
    }

    final server = _serverFor(tool.serverId);
    if (server == null) {
      return AIToolOutcome(
        call: call,
        tool: tool,
        result: AIToolResult.error('${tool.serverLabel} is not running.'),
      );
    }

    final result = await server.call(tool.name, call.arguments).timeout(
          runTimeout,
          onTimeout: () => AIToolResult.error(
            '${tool.name} did not answer within ${runTimeout.inSeconds} '
            'seconds. It may or may not have finished, so check before '
            'running it again.',
          ),
        );
    return AIToolOutcome(call: call, tool: tool, result: result);
  }

  @override
  void dispose() {
    for (final client in _clients.values) {
      unawaited(client.dispose());
    }
    _clients.clear();
    super.dispose();
  }
}
