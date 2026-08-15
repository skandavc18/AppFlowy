import 'dart:async';
import 'dart:convert';

import 'package:appflowy/ai/providers/ai_providers.dart';
import 'package:appflowy/ai/tools/ai_tool.dart';
import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('naming a model of a configured provider', () {
    test('a round trip survives a model name with a slash in it', () {
      final encoded = CustomAIModelName.encode('abc123', 'meta-llama/Llama-3');
      final decoded = CustomAIModelName.decode(encoded);

      expect(decoded, isNotNull);
      expect(decoded!.providerId, 'abc123');
      expect(decoded.model, 'meta-llama/Llama-3');
    });

    test('a built-in model is never read as a custom one', () {
      expect(CustomAIModelName.isCustom('Auto'), isFalse);
      expect(CustomAIModelName.decode('gpt-4o'), isNull);
    });

    test('a malformed name is refused rather than half read', () {
      expect(
          CustomAIModelName.decode('${CustomAIModelName.prefix}abc'), isNull);
      expect(
        CustomAIModelName.decode('${CustomAIModelName.prefix}abc/'),
        isNull,
      );
    });
  });

  group('what counts as a model running on this machine', () {
    test('a loopback address does', () {
      expect(isLoopbackEndpoint('http://localhost:11434'), isTrue);
      expect(isLoopbackEndpoint('http://127.0.0.1:1234/v1'), isTrue);
    });

    test('a hosted service does not', () {
      expect(isLoopbackEndpoint('https://api.openai.com/v1'), isFalse);
      expect(isLoopbackEndpoint('not a url at all'), isFalse);
    });
  });

  group('a configured provider', () {
    test('survives being written down and read back', () {
      const provider = CustomAIProvider(
        id: 'p1',
        kind: AIProviderKind.anthropic,
        name: 'Work Claude',
        baseUrl: 'https://api.anthropic.com/v1/',
        models: ['claude-sonnet-4-20250514'],
      );

      final restored = CustomAIProvider.fromJson(provider.toJson());

      expect(restored, provider);
      expect(restored.normalizedBaseUrl, 'https://api.anthropic.com/v1');
      expect(restored.runsLocally, isFalse);
    });

    test('falls back to its service defaults when nothing was stored', () {
      final restored =
          CustomAIProvider.fromJson({'id': 'p2', 'kind': 'ollama'});

      expect(restored.kind, AIProviderKind.ollama);
      expect(restored.baseUrl, AIProviderKind.ollama.defaultBaseUrl);
      expect(restored.name, AIProviderKind.ollama.label);
      expect(restored.runsLocally, isTrue);
    });
  });

  group('reading an answer as it is written', () {
    Future<List<String>> collect(
      CustomAIProvider provider,
      String body, {
      void Function(http.Request request)? onRequest,
    }) async {
      final client = MockClient.streaming((request, _) async {
        onRequest?.call(request as http.Request);
        return http.StreamedResponse(
          Stream.value(utf8.encode(body)),
          200,
        );
      });

      final events = await AIProviderClient(
        provider: provider,
        apiKey: 'secret',
        httpClient: client,
      ).streamChat(
        model: 'a-model',
        turns: const [AIChatTurn.user('hello')],
      ).toList();

      return events.whereType<AITextDelta>().map((e) => e.text).toList();
    }

    test('OpenAI server-sent events become the text they carry', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.openAI,
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: ['gpt-4o'],
      );

      final deltas = await collect(
        provider,
        'data: {"choices":[{"delta":{"content":"Hel"}}]}\n'
        '\n'
        'data: {"choices":[{"delta":{"content":"lo"}}]}\n'
        'data: [DONE]\n',
      );

      expect(deltas.join(), 'Hello');
    });

    test('Anthropic only reads its content deltas', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.anthropic,
        name: 'Claude',
        baseUrl: 'https://api.anthropic.com/v1',
        models: ['claude'],
      );

      final deltas = await collect(
        provider,
        'event: message_start\n'
        'data: {"type":"message_start"}\n'
        'event: content_block_delta\n'
        'data: {"type":"content_block_delta","delta":'
        '{"type":"text_delta","text":"Hi"}}\n'
        'data: {"type":"message_stop"}\n',
      );

      expect(deltas.join(), 'Hi');
    });

    test('Gemini reads every part of a candidate', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.gemini,
        name: 'Gemini',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        models: ['gemini-2.5-flash'],
      );

      final deltas = await collect(
        provider,
        'data: {"candidates":[{"content":{"parts":'
        '[{"text":"Good "},{"text":"day"}]}}]}\n',
      );

      expect(deltas.join(), 'Good day');
    });

    test('Ollama answers one JSON object per line, with no prefix', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.ollama,
        name: 'Ollama',
        baseUrl: 'http://localhost:11434',
        models: ['llama3.2'],
      );

      final deltas = await collect(
        provider,
        '{"message":{"role":"assistant","content":"lo"},"done":false}\n'
        '{"message":{"role":"assistant","content":"cal"},"done":true}\n',
      );

      expect(deltas.join(), 'local');
    });

    test('the API key never travels in the request line', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.gemini,
        name: 'Gemini',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        models: ['gemini-2.5-flash'],
      );

      http.Request? seen;
      await collect(
        provider,
        'data: {"candidates":[{"content":{"parts":[{"text":"x"}]}}]}\n',
        onRequest: (request) => seen = request,
      );

      expect(seen!.url.toString(), isNot(contains('secret')));
      expect(seen!.headers['x-goog-api-key'], 'secret');
    });

    test('Azure asks its deployment, with the key in its own header', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.microsoftCopilot,
        name: 'Microsoft Copilot',
        baseUrl: 'https://contoso.openai.azure.com/openai/deployments/'
            'my-gpt-4o/chat/completions?api-version=2024-10-21',
        models: ['my-gpt-4o'],
      );

      http.Request? seen;
      final deltas = await collect(
        provider,
        'data: {"choices":[{"delta":{"content":"Hi"}}]}\n'
        'data: [DONE]\n',
        onRequest: (request) => seen = request,
      );

      expect(deltas.join(), 'Hi');
      // The Target URI was pasted whole; only the deployment follows the
      // model that was picked.
      expect(seen!.url.path, '/openai/deployments/a-model/chat/completions');
      expect(seen!.url.queryParameters['api-version'], '2024-10-21');
      expect(seen!.headers['api-key'], 'secret');
      expect(seen!.headers.containsKey('authorization'), isFalse);
      // The deployment is named in the path, so the body must not repeat it.
      expect(seen!.body, isNot(contains('"model"')));
    });

    test('an Azure resource root is given the documented path', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.microsoftCopilot,
        name: 'Microsoft Copilot',
        baseUrl: 'https://contoso.openai.azure.com',
        models: ['my-gpt-4o'],
      );

      http.Request? seen;
      await collect(
        provider,
        'data: {"choices":[{"delta":{"content":"Hi"}}]}\n',
        onRequest: (request) => seen = request,
      );

      expect(seen!.url.path, '/openai/deployments/a-model/chat/completions');
      expect(seen!.url.queryParameters['api-version'], isNotEmpty);
    });

    test('an AI Foundry address names the model in the body', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.microsoftCopilot,
        name: 'AI Foundry',
        baseUrl: 'https://contoso.services.ai.azure.com/models/'
            'chat/completions?api-version=2024-05-01-preview',
        models: ['gpt-4o'],
      );

      http.Request? seen;
      await collect(
        provider,
        'data: {"choices":[{"delta":{"content":"Hi"}}]}\n',
        onRequest: (request) => seen = request,
      );

      expect(seen!.url.path, '/models/chat/completions');
      expect(seen!.url.queryParameters['api-version'], '2024-05-01-preview');
      expect(seen!.body, contains('"model":"a-model"'));
    });
  });

  group('asking for a tool', () {
    const tool = AITool(
      serverId: 'appflowy',
      serverLabel: 'AppFlowy',
      name: 'create_page',
      description: 'Create a page.',
      schema: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
      },
    );

    Future<(List<AIStreamEvent>, http.Request?)> run(
      CustomAIProvider provider,
      String body,
    ) async {
      http.Request? seen;
      final client = MockClient.streaming((request, _) async {
        seen = request as http.Request;
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });

      final events = await AIProviderClient(
        provider: provider,
        apiKey: 'secret',
        httpClient: client,
      ).streamChat(
        model: 'a-model',
        turns: const [AIChatTurn.user('make a page')],
        tools: const [tool],
      ).toList();
      return (events, seen);
    }

    test('OpenAI arguments arriving in fragments are put back together',
        () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.openAI,
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: ['gpt-4o'],
      );

      final (events, request) = await run(
        provider,
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1",'
        '"function":{"name":"appflowy__create_page","arguments":"{\\"na"}}]}}]}\n'
        'data: {"choices":[{"delta":{"tool_calls":[{"index":0,'
        '"function":{"arguments":"me\\":\\"Notes\\"}"}}]}}]}\n'
        'data: [DONE]\n',
      );

      final calls = events.whereType<AIToolCallRequested>().toList();
      expect(calls, hasLength(1));
      expect(calls.single.call.name, 'appflowy__create_page');
      expect(calls.single.call.arguments, {'name': 'Notes'});
      expect(calls.single.call.id, 'call_1');
      // The tool has to be declared for the model to be able to ask for it.
      expect(request!.body, contains('appflowy__create_page'));
    });

    test('Anthropic reports its tool use once the JSON is whole', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.anthropic,
        name: 'Claude',
        baseUrl: 'https://api.anthropic.com/v1',
        models: ['claude'],
      );

      final (events, request) = await run(
        provider,
        'data: {"type":"content_block_start","index":0,"content_block":'
        '{"type":"tool_use","id":"toolu_1","name":"appflowy__create_page"}}\n'
        'data: {"type":"content_block_delta","index":0,"delta":'
        '{"type":"input_json_delta","partial_json":"{\\"name\\":"}}\n'
        'data: {"type":"content_block_delta","index":0,"delta":'
        '{"type":"input_json_delta","partial_json":"\\"Notes\\"}"}}\n'
        'data: {"type":"message_stop"}\n',
      );

      final calls = events.whereType<AIToolCallRequested>().toList();
      expect(calls, hasLength(1));
      expect(calls.single.call.id, 'toolu_1');
      expect(calls.single.call.arguments, {'name': 'Notes'});
      expect(request!.body, contains('input_schema'));
    });

    test('Gemini hands the whole call over at once', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.gemini,
        name: 'Gemini',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        models: ['gemini-2.5-flash'],
      );

      final (events, request) = await run(
        provider,
        'data: {"candidates":[{"content":{"parts":[{"functionCall":'
        '{"name":"appflowy__create_page","args":{"name":"Notes"}}}]}}]}\n',
      );

      final calls = events.whereType<AIToolCallRequested>().toList();
      expect(calls, hasLength(1));
      expect(calls.single.call.arguments, {'name': 'Notes'});
      expect(request!.body, contains('functionDeclarations'));
    });

    test('a tool answer is filed under the call it answers', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.openAI,
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: ['gpt-4o'],
      );

      http.Request? seen;
      final client = MockClient.streaming((request, _) async {
        seen = request as http.Request;
        return http.StreamedResponse(
          Stream.value(utf8.encode('data: [DONE]\n')),
          200,
        );
      });

      await AIProviderClient(
        provider: provider,
        apiKey: 'secret',
        httpClient: client,
      ).streamChat(
        model: 'a-model',
        turns: const [
          AIChatTurn.user('make a page'),
          AIChatTurn.assistant(
            '',
            toolCalls: [
              AIToolCall(
                id: 'call_1',
                name: 'appflowy__create_page',
                arguments: {'name': 'Notes'},
              ),
            ],
          ),
          AIChatTurn.toolResult(
            callId: 'call_1',
            name: 'appflowy__create_page',
            text: 'Created it.',
          ),
        ],
      ).toList();

      expect(seen!.body, contains('"tool_call_id":"call_1"'));
      expect(seen!.body, contains('Created it.'));
    });
  });

  group('when a provider refuses', () {
    test('the sentence explains it without echoing the body back', () async {
      const provider = CustomAIProvider(
        id: 'p',
        kind: AIProviderKind.openAI,
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        models: ['gpt-4o'],
      );

      final client = MockClient.streaming(
        (_, __) async => http.StreamedResponse(
          Stream.value(
            utf8.encode('{"error":{"message":"Incorrect API key provided"}}'),
          ),
          401,
        ),
      );

      await expectLater(
        AIProviderClient(
          provider: provider,
          apiKey: 'wrong',
          httpClient: client,
        ).streamChat(model: 'gpt-4o', turns: const [AIChatTurn.user('hi')]),
        emitsError(
          isA<AIProviderException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('refused'),
              contains('Incorrect API key provided'),
              isNot(contains('wrong')),
            ),
          ),
        ),
      );
    });
  });

  group('remembering which providers were set up', () {
    late _MemoryKeyValue storage;
    late CustomAIProviderStore store;

    setUp(() {
      storage = _MemoryKeyValue();
      store = CustomAIProviderStore(
        storage: storage,
        secrets: ProviderSecretStore(storage: storage),
      );
    });

    test('a provider added before the list is read is not lost', () async {
      // The list loads lazily; a write that lands first must not be undone by
      // the read arriving late.
      unawaited(store.ensureLoaded());
      final saved = await store.upsert(
        const CustomAIProvider(
          id: '',
          kind: AIProviderKind.ollama,
          name: 'Ollama',
          baseUrl: 'http://localhost:11434',
          models: ['llama3.2'],
        ),
      );

      expect(saved.id, isNotEmpty);
      expect(store.providers.map((provider) => provider.id), [saved.id]);
    });

    test('settings that could not be read are read again, not given up on',
        () async {
      // Latching "loaded" after a failed read left the whole session believing
      // no provider was ever set up: the chat reverted to the built-in model,
      // its history went missing and the message box turned read-only.
      final flaky = _FlakyKeyValue(failures: 1);
      await flaky.set(
        CustomAIProviderStore.selectedModelKey,
        CustomAIModelName.encode('p1', 'gpt-4o'),
      );
      final store = CustomAIProviderStore(
        storage: flaky,
        secrets: ProviderSecretStore(storage: flaky),
      );

      await store.ensureLoaded();
      expect(store.isLoaded, isFalse);
      expect(store.selectedModelName, isNull);

      await store.ensureLoaded();
      expect(store.isLoaded, isTrue);
      expect(
        store.selectedModelName,
        CustomAIModelName.encode('p1', 'gpt-4o'),
      );
    });

    test('every model of a provider is offered to the picker', () async {
      final saved = await store.upsert(
        const CustomAIProvider(
          id: '',
          kind: AIProviderKind.openAI,
          name: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          models: ['gpt-4o', 'gpt-4o-mini'],
        ),
      );

      final models = store.models;
      expect(models, hasLength(2));
      expect(models.first.name, CustomAIModelName.encode(saved.id, 'gpt-4o'));
      expect(models.first.desc, 'OpenAI');
      expect(models.first.isLocal, isFalse);
    });

    test('a local server is reported as a local model', () async {
      await store.upsert(
        const CustomAIProvider(
          id: 'local',
          kind: AIProviderKind.openAICompatible,
          name: 'LM Studio',
          baseUrl: 'http://localhost:1234/v1',
          models: ['qwen2.5'],
        ),
      );

      expect(store.models.single.isLocal, isTrue);
    });

    test('removing a provider also drops it as the chosen model', () async {
      await store.upsert(
        const CustomAIProvider(
          id: 'p1',
          kind: AIProviderKind.gemini,
          name: 'Gemini',
          baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
          models: ['gemini-2.5-flash'],
        ),
      );
      await store.select(CustomAIModelName.encode('p1', 'gemini-2.5-flash'));
      expect(store.activeSelection, isNotNull);

      await store.remove('p1');

      expect(store.selectedModelName, isNull);
      expect(store.activeSelection, isNull);
    });

    test('a selection naming a provider that is gone answers nothing',
        () async {
      await store.select(CustomAIModelName.encode('missing', 'gpt-4o'));
      expect(store.activeSelection, isNull);
    });
  });
}

class _MemoryKeyValue implements KeyValueStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> get(String key) async {
    await Future<void>.delayed(Duration.zero);
    return _values[key];
  }

  @override
  Future<void> set(String key, String value) async {
    await Future<void>.delayed(Duration.zero);
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = await get(key);
    return value == null ? null : formatter(value);
  }
}

/// Settings that are not readable the first few times they are asked for, the
/// way they are while the application is still starting up.
class _FlakyKeyValue extends _MemoryKeyValue {
  _FlakyKeyValue({required this.failures});

  int failures;

  @override
  Future<String?> get(String key) {
    if (failures > 0) {
      failures--;
      return Future.error(StateError('settings are not ready'));
    }
    return super.get(key);
  }
}
