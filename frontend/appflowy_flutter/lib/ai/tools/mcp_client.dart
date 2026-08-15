import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;

import 'ai_tool.dart';
import 'mcp_server_config.dart';

/// Raised when a server cannot be reached or refuses.
class McpException implements Exception {
  McpException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks JSON-RPC 2.0 to one Model Context Protocol server.
///
/// Two transports, which is what servers in the wild actually use: a process
/// speaking over its own stdin and stdout, or an HTTP endpoint. Both answer the
/// same three calls — initialize, tools/list, tools/call — so everything above
/// this class is transport-blind.
abstract class McpClient implements AIToolServer {
  McpClient(this.config);

  factory McpClient.of(McpServerConfig config) => switch (config.transport) {
        McpTransport.stdio => _StdioMcpClient(config),
        McpTransport.http => _HttpMcpClient(config),
      };

  static const protocolVersion = '2024-11-05';
  static const callTimeout = Duration(seconds: 60);

  final McpServerConfig config;

  var _nextId = 0;
  bool _started = false;
  String? _failure;
  List<AITool>? _tools;

  @override
  String get id => config.id;

  @override
  String get label => config.name;

  @override
  bool get isAvailable => _failure == null;

  /// Why the server is not answering, if it is not.
  String? get failure => _failure;

  int nextId() => ++_nextId;

  Future<Map<String, dynamic>> send(String method, [Object? params]);

  Future<void> start();

  Future<void> _ensureStarted() async {
    if (_started) {
      return;
    }
    _started = true;
    try {
      await start();
      await send('initialize', {
        'protocolVersion': protocolVersion,
        'capabilities': <String, dynamic>{},
        'clientInfo': {'name': 'AppFlowy', 'version': '1.0'},
      });
      await notify('notifications/initialized');
      _failure = null;
    } catch (error) {
      _failure = '$error';
      rethrow;
    }
  }

  /// A notification expects no answer; the default is to send it as a call and
  /// ignore whatever comes back.
  Future<void> notify(String method, [Object? params]) async {}

  @override
  Future<List<AITool>> listTools() async {
    final cached = _tools;
    if (cached != null) {
      return cached;
    }

    await _ensureStarted();
    final answer = await send('tools/list');
    final declared = answer['tools'];
    if (declared is! List) {
      return const [];
    }

    final tools = <AITool>[];
    for (final entry in declared) {
      if (entry is! Map) {
        continue;
      }
      final name = entry['name'];
      if (name is! String || name.isEmpty) {
        continue;
      }
      final schema = entry['inputSchema'];
      tools.add(
        AITool(
          serverId: config.id,
          serverLabel: config.name,
          name: name,
          description: '${entry['description'] ?? ''}',
          schema: schema is Map
              ? schema.cast<String, dynamic>()
              : const {'type': 'object', 'properties': <String, dynamic>{}},
          // A stranger's server does not get to say its own tools are safe.
          risk: config.riskFor(name),
        ),
      );
    }
    _tools = tools;
    return tools;
  }

  @override
  Future<AIToolResult> call(String name, Map<String, dynamic> arguments) async {
    try {
      await _ensureStarted();
      final answer = await send('tools/call', {
        'name': name,
        'arguments': arguments,
      });
      return AIToolResult(
        _readContent(answer),
        isError: answer['isError'] == true,
      );
    } on McpException catch (error) {
      return AIToolResult.error(error.message);
    } catch (error) {
      return AIToolResult.error('${config.name} could not run that: $error');
    }
  }

  static String _readContent(Map<String, dynamic> answer) {
    final content = answer['content'];
    if (content is! List) {
      return jsonEncode(answer);
    }
    final parts = <String>[];
    for (final entry in content) {
      if (entry is! Map) {
        continue;
      }
      if (entry['type'] == 'text' && entry['text'] is String) {
        parts.add(entry['text'] as String);
      } else {
        parts.add('[${entry['type']}]');
      }
    }
    return parts.isEmpty ? 'Done.' : parts.join('\n');
  }

  /// Reads a JSON-RPC answer, turning a refusal into something readable.
  static Map<String, dynamic> readAnswer(Map<String, dynamic> message) {
    final error = message['error'];
    if (error is Map) {
      throw McpException('${error['message'] ?? 'The server refused.'}');
    }
    final result = message['result'];
    return result is Map ? result.cast<String, dynamic>() : <String, dynamic>{};
  }

  /// Forgets the tool list so a server can be re-read after it was changed.
  void invalidate() {
    _tools = null;
    _started = false;
    _failure = null;
  }
}

/// A server running as a child process, spoken to over its own stdin/stdout.
class _StdioMcpClient extends McpClient {
  _StdioMcpClient(super.config);

  Process? _process;
  StreamSubscription<String>? _lines;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  @override
  Future<void> start() async {
    final command = config.command.trim();
    if (command.isEmpty) {
      throw McpException('${config.name} has no command to run.');
    }

    final process = await Process.start(
      command,
      config.args,
      environment: config.env.isEmpty ? null : config.env,
      workingDirectory:
          config.workingDirectory.isEmpty ? null : config.workingDirectory,
    );
    _process = process;

    _lines = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(_onLine, onError: (Object error) => _failEverything('$error'));

    // A server's own diagnostics belong in the log, not in an answer.
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) => Log.info('[mcp:${config.id}] $line'));

    unawaited(
      process.exitCode.then((code) {
        _failEverything('${config.name} stopped (exit code $code).');
        _process = null;
      }),
    );
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        return;
      }
      final id = decoded['id'];
      if (id is! int) {
        return;
      }
      final waiting = _pending.remove(id);
      if (waiting == null || waiting.isCompleted) {
        return;
      }
      try {
        waiting.complete(McpClient.readAnswer(decoded.cast<String, dynamic>()));
      } on McpException catch (error) {
        waiting.completeError(error);
      }
    } catch (error) {
      Log.warn('[mcp:${config.id}] unreadable line: $error');
    }
  }

  void _failEverything(String reason) {
    _failure = reason;
    for (final waiting in _pending.values) {
      if (!waiting.isCompleted) {
        waiting.completeError(McpException(reason));
      }
    }
    _pending.clear();
  }

  @override
  Future<Map<String, dynamic>> send(String method, [Object? params]) {
    final process = _process;
    if (process == null) {
      return Future.error(McpException('${config.name} is not running.'));
    }

    final id = nextId();
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    process.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      }),
    );

    return completer.future.timeout(
      McpClient.callTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw McpException('${config.name} did not answer in time.');
      },
    );
  }

  @override
  Future<void> notify(String method, [Object? params]) async {
    _process?.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        if (params != null) 'params': params,
      }),
    );
  }

  @override
  Future<void> dispose() async {
    await _lines?.cancel();
    _lines = null;
    _process?.kill();
    _process = null;
    _failEverything('Stopped.');
  }
}

/// A server reached over HTTP, one JSON-RPC message per request.
class _HttpMcpClient extends McpClient {
  _HttpMcpClient(super.config);

  final http.Client _client = http.Client();
  String? _session;

  @override
  Future<void> start() async {
    if (config.url.trim().isEmpty) {
      throw McpException('${config.name} has no address.');
    }
  }

  @override
  Future<Map<String, dynamic>> send(String method, [Object? params]) async {
    final uri = Uri.tryParse(config.url.trim());
    if (uri == null || !uri.hasScheme) {
      throw McpException('${config.name} has no usable address.');
    }

    final response = await _client
        .post(
          uri,
          headers: {
            'content-type': 'application/json',
            'accept': 'application/json, text/event-stream',
            if (_session != null) 'mcp-session-id': _session!,
            ...config.headers,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': nextId(),
            'method': method,
            if (params != null) 'params': params,
          }),
        )
        .timeout(McpClient.callTimeout);

    _session ??= response.headers['mcp-session-id'];

    if (response.statusCode >= 400) {
      throw McpException(
        '${config.name} answered ${response.statusCode}.',
      );
    }

    final body = utf8.decode(response.bodyBytes);
    final payload = _readBody(body);
    if (payload == null) {
      return <String, dynamic>{};
    }
    return McpClient.readAnswer(payload);
  }

  /// A streamable-HTTP server may answer with server-sent events even for a
  /// single call, so the last `data:` line is read when it does.
  static Map<String, dynamic>? _readBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('{')) {
      final decoded = jsonDecode(trimmed);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    }

    Map<String, dynamic>? last;
    for (final line in const LineSplitter().convert(trimmed)) {
      if (!line.startsWith('data:')) {
        continue;
      }
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') {
        continue;
      }
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          last = decoded.cast<String, dynamic>();
        }
      } catch (_) {
        // Not every event carries a message.
      }
    }
    return last;
  }

  @override
  Future<void> notify(String method, [Object? params]) async {
    try {
      await send(method, params);
    } catch (_) {
      // A notification nobody answers is not a failure.
    }
  }

  @override
  Future<void> dispose() async {
    _client.close();
  }
}
