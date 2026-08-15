import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The wire format a provider speaks.
///
/// Four shapes cover every service worth offering: almost everybody now serves
/// the OpenAI chat-completions API (OpenAI itself, LM Studio, llama.cpp, vLLM,
/// OpenRouter, Groq …), while Anthropic, Google, Microsoft and Ollama each keep
/// one of their own.
enum AIProviderProtocol { openAI, azureOpenAI, anthropic, gemini, ollama }

/// A service AppFlowy knows how to talk to.
enum AIProviderKind {
  openAI(
    id: 'openai',
    label: 'OpenAI',
    protocol: AIProviderProtocol.openAI,
    defaultBaseUrl: 'https://api.openai.com/v1',
    needsApiKey: true,
    suggestedModels: ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'gpt-4.1-mini'],
    credentialsUrl: 'https://platform.openai.com/api-keys',
    icon: Icons.auto_awesome_rounded,
  ),
  anthropic(
    id: 'anthropic',
    label: 'Anthropic Claude',
    protocol: AIProviderProtocol.anthropic,
    defaultBaseUrl: 'https://api.anthropic.com/v1',
    needsApiKey: true,
    suggestedModels: [
      'claude-sonnet-4-20250514',
      'claude-3-7-sonnet-latest',
      'claude-3-5-haiku-latest',
    ],
    credentialsUrl: 'https://console.anthropic.com/settings/keys',
    icon: Icons.psychology_rounded,
  ),
  gemini(
    id: 'gemini',
    label: 'Google Gemini',
    protocol: AIProviderProtocol.gemini,
    defaultBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    needsApiKey: true,
    suggestedModels: [
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-2.0-flash',
    ],
    credentialsUrl: 'https://aistudio.google.com/app/apikey',
    icon: Icons.blur_on_rounded,
  ),
  microsoftCopilot(
    id: 'microsoft',
    label: 'Microsoft Copilot (Azure OpenAI / AI Foundry)',
    protocol: AIProviderProtocol.azureOpenAI,
    defaultBaseUrl: 'https://YOUR-RESOURCE.openai.azure.com/openai/deployments/'
        'YOUR-DEPLOYMENT/chat/completions?api-version=2024-10-21',
    needsApiKey: true,
    // Azure answers for a DEPLOYMENT you named, not for a model id.
    suggestedModels: [],
    credentialsUrl: 'https://ai.azure.com',
    icon: Icons.window_rounded,
  ),
  ollama(
    id: 'ollama',
    label: 'Ollama',
    protocol: AIProviderProtocol.ollama,
    defaultBaseUrl: 'http://localhost:11434',
    needsApiKey: false,
    suggestedModels: ['llama3.2', 'qwen2.5', 'mistral'],
    credentialsUrl: 'https://ollama.com/download',
    icon: Icons.dns_rounded,
  ),
  openAICompatible(
    id: 'openai_compatible',
    label: 'Any OpenAI-compatible server',
    protocol: AIProviderProtocol.openAI,
    defaultBaseUrl: 'http://localhost:1234/v1',
    needsApiKey: false,
    suggestedModels: [],
    credentialsUrl: '',
    icon: Icons.lan_rounded,
  );

  const AIProviderKind({
    required this.id,
    required this.label,
    required this.protocol,
    required this.defaultBaseUrl,
    required this.needsApiKey,
    required this.suggestedModels,
    required this.credentialsUrl,
    required this.icon,
  });

  final String id;
  final String label;
  final AIProviderProtocol protocol;
  final String defaultBaseUrl;

  /// Whether the service refuses to answer without a key. A local server
  /// usually does not, so its key field is optional rather than required.
  final bool needsApiKey;
  final List<String> suggestedModels;
  final String credentialsUrl;
  final IconData icon;

  /// Azure hands out one "Target URI" per deployment, api-version and all, so
  /// the address field takes that whole address rather than a server root.
  bool get usesTargetUri => protocol == AIProviderProtocol.azureOpenAI;

  static AIProviderKind fromId(String id) => values.firstWhere(
        (kind) => kind.id == id,
        orElse: () => AIProviderKind.openAICompatible,
      );
}

/// True when an address points at this machine, which is what tells a local
/// model apart from a hosted one without asking anybody to declare it.
bool isLoopbackEndpoint(String baseUrl) {
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '::1' ||
      host == '0.0.0.0' ||
      host.endsWith('.local');
}

/// One configured service, as the person set it up.
///
/// The API key is deliberately NOT part of this object: it lives in the
/// platform secret store, so a configuration that is written to plain
/// key-value storage can never carry one.
@immutable
class CustomAIProvider {
  const CustomAIProvider({
    required this.id,
    required this.kind,
    required this.name,
    required this.baseUrl,
    required this.models,
  });

  factory CustomAIProvider.fromJson(Map<String, dynamic> json) {
    final models = (json['models'] as List?)
            ?.whereType<String>()
            .where((model) => model.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final kind = AIProviderKind.fromId(json['kind'] as String? ?? '');
    return CustomAIProvider(
      id: json['id'] as String? ?? '',
      kind: kind,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : kind.label,
      baseUrl: (json['base_url'] as String?)?.trim().isNotEmpty == true
          ? json['base_url'] as String
          : kind.defaultBaseUrl,
      models: models,
    );
  }

  final String id;
  final AIProviderKind kind;
  final String name;
  final String baseUrl;
  final List<String> models;

  bool get runsLocally => isLoopbackEndpoint(baseUrl);

  /// The address with any trailing slash removed, so paths can be appended
  /// without ever producing a double slash.
  String get normalizedBaseUrl {
    var url = baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.id,
        'name': name,
        'base_url': baseUrl,
        'models': models,
      };

  CustomAIProvider copyWith({String? id}) => CustomAIProvider(
        id: id ?? this.id,
        kind: kind,
        name: name,
        baseUrl: baseUrl,
        models: models,
      );

  @override
  bool operator ==(Object other) =>
      other is CustomAIProvider &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.baseUrl == baseUrl &&
      listEquals(other.models, models);

  @override
  int get hashCode => Object.hash(id, kind, name, baseUrl, models);
}

/// How a model of a configured provider is named in the model picker.
///
/// `AIModelPB` carries one string, so the provider and the model have to share
/// it. The provider id never contains a slash and a model name may, so the
/// FIRST slash after the prefix is the separator.
class CustomAIModelName {
  const CustomAIModelName(this.providerId, this.model);

  static const prefix = 'appflowy_custom_ai:';

  final String providerId;
  final String model;

  static String encode(String providerId, String model) =>
      '$prefix$providerId/$model';

  static bool isCustom(String name) => name.startsWith(prefix);

  static CustomAIModelName? decode(String name) {
    if (!isCustom(name)) {
      return null;
    }
    final rest = name.substring(prefix.length);
    final separator = rest.indexOf('/');
    if (separator <= 0 || separator == rest.length - 1) {
      return null;
    }
    return CustomAIModelName(
      rest.substring(0, separator),
      rest.substring(separator + 1),
    );
  }

  String get encoded => encode(providerId, model);
}
