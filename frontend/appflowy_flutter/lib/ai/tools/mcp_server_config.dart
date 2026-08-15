import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:nanoid/nanoid.dart';

import 'ai_tool.dart';

/// How AppFlowy reaches an MCP server.
enum McpTransport {
  /// A program started by AppFlowy, spoken to over its stdin and stdout.
  stdio,

  /// An address AppFlowy posts to.
  http;

  static McpTransport fromName(String? name) =>
      name == 'http' ? McpTransport.http : McpTransport.stdio;
}

/// One MCP server the person added.
@immutable
class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    this.transport = McpTransport.stdio,
    this.command = '',
    this.args = const [],
    this.env = const {},
    this.workingDirectory = '',
    this.url = '',
    this.headers = const {},
    this.enabled = true,
    this.readOnlyTools = const [],
    this.destructiveTools = const [],
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        id: json['id'] as String? ?? '',
        name: (json['name'] as String?)?.trim().isNotEmpty == true
            ? json['name'] as String
            : 'MCP server',
        transport: McpTransport.fromName(json['transport'] as String?),
        command: json['command'] as String? ?? '',
        args: _stringList(json['args']),
        env: _stringMap(json['env']),
        workingDirectory: json['cwd'] as String? ?? '',
        url: json['url'] as String? ?? '',
        headers: _stringMap(json['headers']),
        enabled: json['enabled'] != false,
        readOnlyTools: _stringList(json['read_only']),
        destructiveTools: _stringList(json['destructive']),
      );

  final String id;
  final String name;
  final McpTransport transport;

  /// stdio
  final String command;
  final List<String> args;
  final Map<String, String> env;
  final String workingDirectory;

  /// http
  final String url;
  final Map<String, String> headers;

  final bool enabled;

  /// Tools the person has said only read, and tools they have said destroy.
  /// A server's own word is not taken for either.
  final List<String> readOnlyTools;
  final List<String> destructiveTools;

  AIToolRisk riskFor(String toolName) {
    if (destructiveTools.contains(toolName)) {
      return AIToolRisk.destructive;
    }
    if (readOnlyTools.contains(toolName)) {
      return AIToolRisk.read;
    }
    return AIToolRisk.write;
  }

  /// What to show under the server's name.
  String get summary => transport == McpTransport.stdio
      ? [command, ...args].where((part) => part.isNotEmpty).join(' ')
      : url;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'transport': transport.name,
        if (command.isNotEmpty) 'command': command,
        if (args.isNotEmpty) 'args': args,
        if (env.isNotEmpty) 'env': env,
        if (workingDirectory.isNotEmpty) 'cwd': workingDirectory,
        if (url.isNotEmpty) 'url': url,
        if (headers.isNotEmpty) 'headers': headers,
        if (!enabled) 'enabled': false,
        if (readOnlyTools.isNotEmpty) 'read_only': readOnlyTools,
        if (destructiveTools.isNotEmpty) 'destructive': destructiveTools,
      };

  McpServerConfig copyWith({
    String? id,
    String? name,
    McpTransport? transport,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    String? workingDirectory,
    String? url,
    Map<String, String>? headers,
    bool? enabled,
    List<String>? readOnlyTools,
    List<String>? destructiveTools,
  }) =>
      McpServerConfig(
        id: id ?? this.id,
        name: name ?? this.name,
        transport: transport ?? this.transport,
        command: command ?? this.command,
        args: args ?? this.args,
        env: env ?? this.env,
        workingDirectory: workingDirectory ?? this.workingDirectory,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        enabled: enabled ?? this.enabled,
        readOnlyTools: readOnlyTools ?? this.readOnlyTools,
        destructiveTools: destructiveTools ?? this.destructiveTools,
      );

  static List<String> _stringList(Object? value) => value is List
      ? value.whereType<String>().where((item) => item.isNotEmpty).toList()
      : const [];

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const {};
    }
    return {
      for (final entry in value.entries) '${entry.key}': '${entry.value}',
    };
  }

  /// Splits a command line into a program and its arguments, honouring quotes
  /// so a path with a space in it survives.
  static (String command, List<String> args) parseCommandLine(String line) {
    final parts = <String>[];
    final buffer = StringBuffer();
    String? quote;

    for (final rune in line.trim().runes) {
      final character = String.fromCharCode(rune);
      if (quote != null) {
        if (character == quote) {
          quote = null;
        } else {
          buffer.write(character);
        }
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        continue;
      }
      if (character == ' ') {
        if (buffer.isNotEmpty) {
          parts.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.write(character);
    }
    if (buffer.isNotEmpty) {
      parts.add(buffer.toString());
    }

    if (parts.isEmpty) {
      return ('', const []);
    }
    return (parts.first, parts.sublist(1));
  }
}

/// Every MCP server the person added.
class McpServerStore extends ChangeNotifier {
  McpServerStore({KeyValueStorage? storage}) : _storage = storage;

  static final McpServerStore instance = McpServerStore();

  static const serversKey = 'appflowy_mcp_servers';

  final KeyValueStorage? _storage;
  final List<McpServerConfig> _servers = [];
  Future<void>? _loading;
  bool _loaded = false;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  List<McpServerConfig> get servers => List.unmodifiable(_servers);

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _kv?.get(serversKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded.whereType<Map>()) {
            final config = McpServerConfig.fromJson(entry.cast());
            if (config.id.isEmpty) {
              continue;
            }
            // Merge rather than replace, so a server added while this read was
            // in flight is not thrown away.
            if (!_servers.any((existing) => existing.id == config.id)) {
              _servers.add(config);
            }
          }
        }
      }
    } catch (error) {
      Log.warn('Could not read the MCP servers: $error');
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  McpServerConfig? serverFor(String id) {
    for (final server in _servers) {
      if (server.id == id) {
        return server;
      }
    }
    return null;
  }

  Future<McpServerConfig> upsert(McpServerConfig config) async {
    await ensureLoaded();
    final resolved =
        config.id.isEmpty ? config.copyWith(id: 'mcp_${nanoid(8)}') : config;
    final index = _servers.indexWhere((entry) => entry.id == resolved.id);
    if (index == -1) {
      _servers.add(resolved);
    } else {
      _servers[index] = resolved;
    }
    await _persist();
    notifyListeners();
    return resolved;
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    _servers.removeWhere((server) => server.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _kv?.set(
      serversKey,
      jsonEncode(_servers.map((server) => server.toJson()).toList()),
    );
  }
}
