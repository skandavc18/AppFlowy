import 'dart:async';
import 'dart:convert';

import 'package:appflowy/ai/providers/ai_provider_stream.dart';
import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy_backend/log.dart';
import 'package:http/http.dart' as http;
import 'package:nanoid/nanoid.dart';

import 'ai_provider.dart';

/// Raised when a provider refuses or cannot be reached. The message is written
/// for the person reading it, never a raw response body.
class AIProviderException implements Exception {
  AIProviderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Talks to one configured provider.
///
/// Everything here is streaming: a chat answer arrives as a series of small
/// deltas, and the caller is handed them as they land rather than after the
/// whole answer has been written.
class AIProviderClient {
  AIProviderClient({
    required this.provider,
    required this.apiKey,
    http.Client? httpClient,
  }) : _client = httpClient;

  /// A stranger's endpoint can answer for ever; nothing is allowed to grow
  /// without bound in this process.
  static const maxAnswerCharacters = 400000;
  static const connectTimeout = Duration(seconds: 45);

  /// How long the answer may go quiet before it is called off.
  ///
  /// A connection that is accepted and then never written to would otherwise
  /// leave the chat answering for ever, with no text and no error to show.
  static const answerIdleTimeout = Duration(minutes: 3);

  /// Azure names a dated contract rather than a path version.
  static const azureApiVersion = '2024-10-21';
  static const azureDeploymentsApiVersion = '2023-03-15-preview';

  final CustomAIProvider provider;
  final String? apiKey;
  final http.Client? _client;

  http.Client _newClient() => _client ?? http.Client();

  Uri _endpoint(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('${provider.normalizedBaseUrl}$path');
    if (query == null || query.isEmpty) {
      return uri;
    }
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  /// The address one Azure chat request goes to.
  ///
  /// The person pastes the Target URI their deployment was given, which already
  /// carries the deployment name and the api-version. Only the deployment is
  /// substituted, so naming a second deployment in the model list works without
  /// pasting a second address. An address that is only a resource root is given
  /// the documented path instead.
  Uri _azureChatUri(String model) {
    final target = Uri.parse(provider.normalizedBaseUrl);
    final segments =
        target.pathSegments.where((segment) => segment.isNotEmpty).toList();
    final isChatEndpoint = segments.length >= 2 &&
        segments[segments.length - 2] == 'chat' &&
        segments.last == 'completions';

    if (!isChatEndpoint) {
      return target.replace(
        pathSegments: [
          ...segments,
          'openai',
          'deployments',
          model,
          'chat',
          'completions',
        ],
        queryParameters: {
          ...target.queryParameters,
          if (!target.queryParameters.containsKey('api-version'))
            'api-version': azureApiVersion,
        },
      );
    }

    final deploymentAt = segments.indexOf('deployments');
    if (deploymentAt >= 0 && deploymentAt + 1 < segments.length) {
      segments[deploymentAt + 1] = model;
      return target.replace(pathSegments: segments);
    }
    return target;
  }

  /// True when the address itself names the deployment, in which case the body
  /// must not name a model as well.
  bool get _azureNamesDeploymentInPath =>
      Uri.parse(provider.normalizedBaseUrl).pathSegments.contains('deployments');

  Map<String, String> _headers({bool streaming = true}) {    final headers = <String, String>{
      'content-type': 'application/json',
      if (streaming) 'accept': 'text/event-stream',
    };

    final key = apiKey?.trim();
    switch (provider.kind.protocol) {
      case AIProviderProtocol.openAI:
        if (key != null && key.isNotEmpty) {
          headers['authorization'] = 'Bearer $key';
        }
      case AIProviderProtocol.azureOpenAI:
        if (key != null && key.isNotEmpty) {
          headers['api-key'] = key;
        }
      case AIProviderProtocol.anthropic:
        if (key != null && key.isNotEmpty) {
          headers['x-api-key'] = key;
        }
        headers['anthropic-version'] = '2023-06-01';
      case AIProviderProtocol.gemini:
        if (key != null && key.isNotEmpty) {
          // The header form keeps the key out of the request line, where it
          // would end up in every proxy log along the way.
          headers['x-goog-api-key'] = key;
        }
      case AIProviderProtocol.ollama:
        if (key != null && key.isNotEmpty) {
          headers['authorization'] = 'Bearer $key';
        }
    }
    return headers;
  }

  /// Asks the service which models it holds. Returns an empty list rather than
  /// throwing when the service offers no listing.
  Future<List<String>> listModels() async {
    final client = _newClient();
    try {
      final (uri, headers) = switch (provider.kind.protocol) {
        AIProviderProtocol.ollama => (
            _endpoint('/api/tags'),
            _headers(streaming: false),
          ),
        AIProviderProtocol.azureOpenAI => (
            Uri.parse(provider.normalizedBaseUrl).replace(
              pathSegments: ['openai', 'deployments'],
              queryParameters: {'api-version': azureDeploymentsApiVersion},
            ),
            _headers(streaming: false),
          ),
        _ => (_endpoint('/models'), _headers(streaming: false)),
      };

      final response = await client.get(uri, headers: headers).timeout(
            connectTimeout,
          );
      if (response.statusCode != 200) {
        throw AIProviderException(
          _refusalMessage(response.statusCode, response.body),
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const [];
      }

      final names = <String>[];
      switch (provider.kind.protocol) {
        case AIProviderProtocol.ollama:
          for (final entry in (decoded['models'] as List? ?? const [])) {
            final name = (entry as Map?)?['name'];
            if (name is String) names.add(name);
          }
        case AIProviderProtocol.gemini:
          for (final entry in (decoded['models'] as List? ?? const [])) {
            final name = (entry as Map?)?['name'];
            if (name is String) {
              names.add(name.startsWith('models/') ? name.substring(7) : name);
            }
          }
        case AIProviderProtocol.openAI:
        case AIProviderProtocol.azureOpenAI:
        case AIProviderProtocol.anthropic:
          for (final entry in (decoded['data'] as List? ?? const [])) {
            final name = (entry as Map?)?['id'];
            if (name is String) names.add(name);
          }
      }
      names.sort();
      return names;
    } on AIProviderException {
      rethrow;
    } catch (error) {
      throw AIProviderException(_reachMessage(error));
    } finally {
      if (_client == null) client.close();
    }
  }

  /// Streams an answer for [turns], newest turn last.
  ///
  /// When [tools] are offered the model may ask for one instead of, or as well
  /// as, writing text; those requests arrive as [AIToolCallRequested] once the
  /// whole call has been read.
  Stream<AIStreamEvent> streamChat({
    required String model,
    required List<AIChatTurn> turns,
    String? systemPrompt,
    List<AITool> tools = const [],
  }) async* {
    final client = _newClient();
    final calls = _ToolCallAccumulator();
    var written = 0;
    try {
      final request = _buildRequest(
        model: model,
        turns: turns,
        systemPrompt: systemPrompt,
        tools: tools,
      );

      final response = await client.send(request).timeout(connectTimeout);
      if (response.statusCode != 200) {
        final body = await response.stream.bytesToString();
        throw AIProviderException(_refusalMessage(response.statusCode, body));
      }

      final lines = response.stream
          .timeout(
            answerIdleTimeout,
            onTimeout: (sink) => sink.addError(
              AIProviderException(
                '${provider.name} stopped sending the answer. Nothing arrived '
                'for ${answerIdleTimeout.inMinutes} minutes, so AppFlowy gave '
                'up waiting.',
              ),
            ),
          )
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lines) {
        for (final delta in _readDeltas(line, calls)) {
          if (delta.isEmpty) {
            continue;
          }
          written += delta.length;
          if (written > maxAnswerCharacters) {
            return;
          }
          yield AITextDelta(delta);
        }
      }

      for (final call in calls.finish()) {
        yield AIToolCallRequested(call);
      }
    } on AIProviderException {
      rethrow;
    } catch (error) {
      throw AIProviderException(_reachMessage(error));
    } finally {
      if (_client == null) client.close();
    }
  }

  /// The tool list as this protocol declares it.
  Object? _declareTools(List<AITool> tools) {
    if (tools.isEmpty) {
      return null;
    }
    return switch (provider.kind.protocol) {
      AIProviderProtocol.openAI ||
      AIProviderProtocol.azureOpenAI ||
      AIProviderProtocol.ollama =>
        [
          for (final tool in tools)
            {
              'type': 'function',
              'function': {
                'name': tool.qualifiedName,
                'description': tool.description,
                'parameters': tool.schema,
              },
            },
        ],
      AIProviderProtocol.anthropic => [
          for (final tool in tools)
            {
              'name': tool.qualifiedName,
              'description': tool.description,
              'input_schema': tool.schema,
            },
        ],
      AIProviderProtocol.gemini => [
          {
            'functionDeclarations': [
              for (final tool in tools)
                {
                  'name': tool.qualifiedName,
                  'description': tool.description,
                  'parameters': _geminiSchema(tool.schema),
                },
            ],
          },
        ],
    };
  }

  /// Gemini refuses schema keywords it does not know, so only the ones it
  /// documents are passed on.
  static Map<String, dynamic> _geminiSchema(Map<String, dynamic> schema) {
    const allowed = {
      'type',
      'description',
      'properties',
      'required',
      'items',
      'enum',
    };
    final cleaned = <String, dynamic>{};
    for (final entry in schema.entries) {
      if (!allowed.contains(entry.key)) {
        continue;
      }
      final value = entry.value;
      if (entry.key == 'properties' && value is Map) {
        cleaned['properties'] = {
          for (final property in value.entries)
            '${property.key}': property.value is Map
                ? _geminiSchema((property.value as Map).cast())
                : property.value,
        };
      } else {
        cleaned[entry.key] = value;
      }
    }
    // A function with no properties still has to declare an object.
    cleaned.putIfAbsent('type', () => 'object');
    return cleaned;
  }

  http.Request _buildRequest({
    required String model,
    required List<AIChatTurn> turns,
    String? systemPrompt,
    List<AITool> tools = const [],
  }) {
    final uri = switch (provider.kind.protocol) {
      AIProviderProtocol.openAI => _endpoint('/chat/completions'),
      AIProviderProtocol.azureOpenAI => _azureChatUri(model),
      AIProviderProtocol.anthropic => _endpoint('/messages'),
      AIProviderProtocol.gemini => _endpoint(
          '/models/$model:streamGenerateContent',
          {'alt': 'sse'},
        ),
      AIProviderProtocol.ollama => _endpoint('/api/chat'),
    };

    final declared = _declareTools(tools);

    final body = switch (provider.kind.protocol) {
      AIProviderProtocol.openAI || AIProviderProtocol.azureOpenAI => {
          if (provider.kind.protocol == AIProviderProtocol.openAI ||
              !_azureNamesDeploymentInPath)
            'model': model,
          'stream': true,
          if (declared != null) 'tools': declared,
          'messages': [
            if (systemPrompt != null && systemPrompt.isNotEmpty)
              {'role': 'system', 'content': systemPrompt},
            for (final turn in turns) ..._openAIMessages(turn),
          ],
        },
      AIProviderProtocol.anthropic => {
          'model': model,
          'stream': true,
          'max_tokens': 4096,
          if (systemPrompt != null && systemPrompt.isNotEmpty)
            'system': systemPrompt,
          if (declared != null) 'tools': declared,
          // Anthropic keeps the system prompt out of the turn list entirely.
          'messages': [
            for (final turn in turns.where(
              (turn) => turn.role != AIChatRole.system,
            ))
              _anthropicMessage(turn),
          ],
        },
      AIProviderProtocol.gemini => {
          if (systemPrompt != null && systemPrompt.isNotEmpty)
            'systemInstruction': {
              'parts': [
                {'text': systemPrompt},
              ],
            },
          if (declared != null) 'tools': declared,
          'contents': [
            for (final turn in turns.where(
              (turn) => turn.role != AIChatRole.system,
            ))
              _geminiContent(turn),
          ],
        },
      AIProviderProtocol.ollama => {
          'model': model,
          'stream': true,
          if (declared != null) 'tools': declared,
          'messages': [
            if (systemPrompt != null && systemPrompt.isNotEmpty)
              {'role': 'system', 'content': systemPrompt},
            for (final turn in turns) ..._openAIMessages(turn),
          ],
        },
    };

    return http.Request('POST', uri)
      ..headers.addAll(_headers())
      ..bodyBytes = utf8.encode(jsonEncode(body));
  }

  static List<Map<String, dynamic>> _openAIMessages(AIChatTurn turn) {
    if (turn.role == AIChatRole.tool) {
      return [
        {
          'role': 'tool',
          'tool_call_id': turn.toolCallId ?? '',
          if (turn.toolName != null) 'name': turn.toolName,
          'content': turn.text,
        },
      ];
    }
    return [
      {
        'role': _openAIRole(turn.role),
        'content': turn.text,
        if (turn.toolCalls.isNotEmpty)
          'tool_calls': [
            for (final call in turn.toolCalls)
              {
                'id': call.id,
                'type': 'function',
                'function': {
                  'name': call.name,
                  'arguments': jsonEncode(call.arguments),
                },
              },
          ],
      },
    ];
  }

  static Map<String, dynamic> _anthropicMessage(AIChatTurn turn) {
    if (turn.role == AIChatRole.tool) {
      // Anthropic files a tool's answer as something the person said.
      return {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': turn.toolCallId ?? '',
            'content': turn.text,
          },
        ],
      };
    }
    if (turn.role == AIChatRole.assistant && turn.toolCalls.isNotEmpty) {
      return {
        'role': 'assistant',
        'content': [
          if (turn.text.isNotEmpty) {'type': 'text', 'text': turn.text},
          for (final call in turn.toolCalls)
            {
              'type': 'tool_use',
              'id': call.id,
              'name': call.name,
              'input': call.arguments,
            },
        ],
      };
    }
    return {
      'role': turn.role == AIChatRole.assistant ? 'assistant' : 'user',
      'content': turn.text,
    };
  }

  static Map<String, dynamic> _geminiContent(AIChatTurn turn) {
    if (turn.role == AIChatRole.tool) {
      return {
        'role': 'user',
        'parts': [
          {
            'functionResponse': {
              'name': turn.toolName ?? '',
              'response': {'result': turn.text},
            },
          },
        ],
      };
    }
    if (turn.role == AIChatRole.assistant && turn.toolCalls.isNotEmpty) {
      return {
        'role': 'model',
        'parts': [
          if (turn.text.isNotEmpty) {'text': turn.text},
          for (final call in turn.toolCalls)
            {
              'functionCall': {'name': call.name, 'args': call.arguments},
            },
        ],
      };
    }
    return {
      'role': turn.role == AIChatRole.assistant ? 'model' : 'user',
      'parts': [
        {'text': turn.text},
      ],
    };
  }

  static String _openAIRole(AIChatRole role) => switch (role) {
        AIChatRole.system => 'system',
        AIChatRole.user => 'user',
        AIChatRole.assistant => 'assistant',
        AIChatRole.tool => 'tool',
      };

  /// Reads whatever text one line of the response carries.
  ///
  /// Three of the four protocols are server-sent events (`data: {json}`);
  /// Ollama answers with one JSON object per line and no prefix at all.
  Iterable<String> _readDeltas(String line, _ToolCallAccumulator calls) sync* {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      return;
    }

    String payload;
    if (provider.kind.protocol == AIProviderProtocol.ollama) {
      payload = trimmed;
    } else if (trimmed.startsWith('data:')) {
      payload = trimmed.substring(5).trim();
    } else {
      // `event:` / `id:` / a comment: nothing to read.
      return;
    }

    if (payload.isEmpty || payload == '[DONE]') {
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final error = decoded['error'];
    if (error != null) {
      final message = error is Map ? error['message'] : error;
      throw AIProviderException('$message');
    }

    switch (provider.kind.protocol) {
      case AIProviderProtocol.openAI:
      case AIProviderProtocol.azureOpenAI:
        final choices = decoded['choices'];
        if (choices is List) {
          for (final choice in choices) {
            final delta = (choice as Map?)?['delta'];
            final content = (delta as Map?)?['content'];
            if (content is String) yield content;
            // Arguments arrive a fragment at a time, keyed by position.
            final requested = delta?['tool_calls'];
            if (requested is List) {
              for (final entry in requested) {
                if (entry is! Map) continue;
                final function = entry['function'];
                calls.openAI(
                  index: entry['index'] is int ? entry['index'] as int : 0,
                  id: entry['id'] as String?,
                  name: (function as Map?)?['name'] as String?,
                  argumentFragment: function?['arguments'] as String?,
                );
              }
            }
          }
        }
      case AIProviderProtocol.anthropic:
        switch (decoded['type']) {
          case 'content_block_start':
            final block = decoded['content_block'];
            if (block is Map && block['type'] == 'tool_use') {
              calls.anthropicStart(
                index: decoded['index'] is int ? decoded['index'] as int : 0,
                id: '${block['id']}',
                name: '${block['name']}',
              );
            }
          case 'content_block_delta':
            final delta = decoded['delta'];
            if (delta is! Map) break;
            final text = delta['text'];
            if (text is String) yield text;
            final partial = delta['partial_json'];
            if (partial is String) {
              calls.anthropicArguments(
                index: decoded['index'] is int ? decoded['index'] as int : 0,
                fragment: partial,
              );
            }
        }
      case AIProviderProtocol.gemini:
        final candidates = decoded['candidates'];
        if (candidates is List) {
          for (final candidate in candidates) {
            final parts = ((candidate as Map?)?['content'] as Map?)?['parts'];
            if (parts is List) {
              for (final part in parts) {
                if (part is! Map) continue;
                final text = part['text'];
                if (text is String) yield text;
                final function = part['functionCall'];
                if (function is Map) {
                  calls.whole(
                    name: '${function['name']}',
                    arguments: function['args'] is Map
                        ? (function['args'] as Map).cast<String, dynamic>()
                        : const {},
                  );
                }
              }
            }
          }
        }
      case AIProviderProtocol.ollama:
        final message = decoded['message'];
        final content = (message as Map?)?['content'];
        if (content is String) yield content;
        final requested = message?['tool_calls'];
        if (requested is List) {
          for (final entry in requested) {
            final function = (entry as Map?)?['function'];
            if (function is! Map) continue;
            final arguments = function['arguments'];
            calls.whole(
              name: '${function['name']}',
              arguments: arguments is Map
                  ? arguments.cast<String, dynamic>()
                  : _decodeArguments('$arguments'),
            );
          }
        }
    }
  }

  static Map<String, dynamic> _decodeArguments(String raw) {
    if (raw.trim().isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Turns a refusal into a sentence, without ever printing the raw body at
  /// somebody — it routinely carries the key back.
  String _refusalMessage(int status, String body) {
    Log.warn('AI provider ${provider.kind.id} answered $status');
    final detail = _readErrorDetail(body);
    final sentence = switch (status) {
      401 || 403 => 'The API key was refused by ${provider.name}.',
      404 =>
        'That model or address was not found on ${provider.name}. Check the '
            'model name and the server address.',
      429 => '${provider.name} is rate limiting this key. Try again shortly.',
      >= 500 => '${provider.name} could not answer right now.',
      _ => '${provider.name} refused the request.',
    };
    return detail == null ? sentence : '$sentence $detail';
  }

  static String? _readErrorDetail(String body) {
    if (body.isEmpty || body.length > 4000) {
      return null;
    }
    try {
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      final message = error is Map ? error['message'] : error;
      if (message is String && message.isNotEmpty) {
        return message.length > 240 ? '${message.substring(0, 240)}…' : message;
      }
    } catch (_) {
      // Not JSON; the status alone has to explain it.
    }
    return null;
  }

  String _reachMessage(Object error) {
    Log.warn('AI provider ${provider.kind.id} could not be reached: $error');
    if (provider.runsLocally) {
      return 'AppFlowy could not reach ${provider.name} at '
          '${provider.normalizedBaseUrl}. Is the server running?';
    }
    return 'AppFlowy could not reach ${provider.name}. Check the server '
        'address and your connection.';
  }
}

/// Gathers a tool call that arrives in pieces.
///
/// OpenAI streams the arguments as text fragments keyed by position, Anthropic
/// as JSON fragments keyed by content block, and Gemini and Ollama hand the
/// whole call over at once. All four end up here.
class _ToolCallAccumulator {
  final Map<int, _PartialCall> _partial = {};
  final List<AIToolCall> _whole = [];

  void openAI({
    required int index,
    String? id,
    String? name,
    String? argumentFragment,
  }) {
    final call = _partial.putIfAbsent(index, _PartialCall.new);
    if (id != null && id.isNotEmpty) call.id = id;
    if (name != null && name.isNotEmpty) call.name = name;
    if (argumentFragment != null) call.arguments.write(argumentFragment);
  }

  void anthropicStart({
    required int index,
    required String id,
    required String name,
  }) {
    final call = _partial.putIfAbsent(index, _PartialCall.new)
      ..id = id
      ..name = name;
    call.arguments.clear();
  }

  void anthropicArguments({required int index, required String fragment}) {
    _partial.putIfAbsent(index, _PartialCall.new).arguments.write(fragment);
  }

  void whole({required String name, required Map<String, dynamic> arguments}) {
    if (name.isEmpty) return;
    _whole.add(
      AIToolCall(id: 'call_${nanoid(8)}', name: name, arguments: arguments),
    );
  }

  List<AIToolCall> finish() {
    final calls = <AIToolCall>[..._whole];
    final indexes = _partial.keys.toList()..sort();
    for (final index in indexes) {
      final call = _partial[index]!;
      if (call.name.isEmpty) continue;
      calls.add(
        AIToolCall(
          id: call.id.isEmpty ? 'call_${nanoid(8)}' : call.id,
          name: call.name,
          arguments: AIProviderClient._decodeArguments(
            call.arguments.toString(),
          ),
        ),
      );
    }
    _partial.clear();
    _whole.clear();
    return calls;
  }
}

class _PartialCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
}
