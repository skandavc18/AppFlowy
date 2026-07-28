import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The ONLYOFFICE document type each office file maps to.
enum OfficeDocumentType {
  word,
  cell,
  slide;

  String get value => switch (this) {
        OfficeDocumentType.word => 'word',
        OfficeDocumentType.cell => 'cell',
        OfficeDocumentType.slide => 'slide',
      };
}

OfficeDocumentType? officeDocumentTypeFor(String name) {
  return switch (name.split('.').last.toLowerCase()) {
    'doc' || 'docx' || 'odt' || 'rtf' || 'txt' => OfficeDocumentType.word,
    'xls' || 'xlsx' || 'ods' || 'csv' => OfficeDocumentType.cell,
    'ppt' || 'pptx' || 'odp' => OfficeDocumentType.slide,
    _ => null,
  };
}

/// Connection details for a self hosted ONLYOFFICE Docs (DocumentServer).
@immutable
class OfficeServerSettings {
  const OfficeServerSettings({
    this.serverUrl = '',
    this.jwtSecret = '',
    this.bridgeHost = '',
  });

  /// Where ONLYOFFICE Docs is reachable from this machine, e.g.
  /// `http://localhost:8080`.
  final String serverUrl;

  /// The `JWT_SECRET` the server was started with. Empty disables signing.
  final String jwtSecret;

  /// The host the document server uses to reach back into AppFlowy.
  ///
  /// A server in Docker cannot resolve `localhost`, so this defaults to
  /// `host.docker.internal` whenever the server itself runs on this machine.
  final String bridgeHost;

  bool get isConfigured => baseUri != null;

  Uri? get baseUri {
    final trimmed = serverUrl.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) {
      return null;
    }
    final normalized = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(
      normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized,
    );
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri;
  }

  /// The host AppFlowy advertises to the document server.
  String resolveBridgeHost() {
    final explicit = bridgeHost.trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final host = baseUri?.host ?? '';
    const loopback = {'localhost', '127.0.0.1', '::1', '0.0.0.0'};
    return loopback.contains(host) ? 'host.docker.internal' : _localAddress;
  }

  OfficeServerSettings copyWith({
    String? serverUrl,
    String? jwtSecret,
    String? bridgeHost,
  }) {
    return OfficeServerSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      jwtSecret: jwtSecret ?? this.jwtSecret,
      bridgeHost: bridgeHost ?? this.bridgeHost,
    );
  }

  Map<String, Object?> toJson() => {
        'server_url': serverUrl,
        'jwt_secret': jwtSecret,
        'bridge_host': bridgeHost,
      };

  static OfficeServerSettings fromJson(Map<String, dynamic> json) {
    return OfficeServerSettings(
      serverUrl: json['server_url'] as String? ?? '',
      jwtSecret: json['jwt_secret'] as String? ?? '',
      bridgeHost: json['bridge_host'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OfficeServerSettings &&
      other.serverUrl == serverUrl &&
      other.jwtSecret == jwtSecret &&
      other.bridgeHost == bridgeHost;

  @override
  int get hashCode => Object.hash(serverUrl, jwtSecret, bridgeHost);
}

String? validateOfficeServerUrl(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return 'Enter the address of your document server.';
  }
  if (OfficeServerSettings(serverUrl: trimmed).baseUri == null) {
    return 'Enter a valid HTTP or HTTPS server address.';
  }
  return null;
}

/// The address the bridge binds to when the document server is not local.
///
/// Anything other than a loopback needs a routable address; the caller can
/// override it through [OfficeServerSettings.bridgeHost].
String _localAddress = 'host.docker.internal';

const String kOfficeServerSettingsKey = 'appflowy_office_document_server';

class OfficeServerStore {
  const OfficeServerStore();

  Future<OfficeServerSettings> read() async {
    final raw = await getIt<KeyValueStorage>().get(kOfficeServerSettingsKey);
    if (raw == null || raw.isEmpty) {
      return const OfficeServerSettings();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return OfficeServerSettings.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } on FormatException catch (error) {
      Log.error('Unable to read the document server settings: $error');
    }
    return const OfficeServerSettings();
  }

  Future<void> write(OfficeServerSettings settings) async {
    await getIt<KeyValueStorage>().set(
      kOfficeServerSettingsKey,
      jsonEncode(settings.toJson()),
    );
  }
}

enum OfficeServerStatus {
  unconfigured,
  connecting,
  connected,
  unreachable,
}

typedef OfficeServerProbe = Future<bool> Function(
  OfficeServerSettings settings,
);

/// Asks the document server whether it is alive.
///
/// ONLYOFFICE answers `true` on `/healthcheck`; anything else means the editor
/// cannot be loaded and the file has to fall back to a read only preview.
Future<bool> probeOfficeServer(
  OfficeServerSettings settings, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 6),
}) async {
  final base = settings.baseUri;
  if (base == null) {
    return false;
  }
  final owned = client == null;
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(base.replace(path: '${base.path}/healthcheck'))
        .timeout(timeout);
    return response.statusCode == 200 &&
        response.body.trim().toLowerCase().contains('true');
  } catch (error) {
    Log.info('Document server health check failed: $error');
    return false;
  } finally {
    if (owned) {
      httpClient.close();
    }
  }
}
