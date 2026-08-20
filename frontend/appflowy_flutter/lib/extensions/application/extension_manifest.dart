import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Strips `//` line comments so a hand-written recipe can be annotated.
///
/// Recipes are written by a person, and plain JSON has no comments. Anything
/// inside a string literal is left alone, which is what stops a `//` in a URL
/// from truncating the file.
String stripJsonComments(String source) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;

  for (var i = 0; i < source.length; i++) {
    final char = source[i];

    if (inString) {
      out.write(char);
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }

    if (char == '"') {
      inString = true;
      out.write(char);
      continue;
    }

    final isComment = char == '/' && i + 1 < source.length;
    if (isComment && source[i + 1] == '/') {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      if (i < source.length) {
        out.write('\n');
      }
      continue;
    }
    if (isComment && source[i + 1] == '*') {
      i += 2;
      while (i + 1 < source.length &&
          !(source[i] == '*' && source[i + 1] == '/')) {
        i++;
      }
      i++;
      continue;
    }

    out.write(char);
  }

  return out.toString();
}

/// Reads a recipe file, tolerating comments and a trailing newline.
Map<String, Object?> decodeExtensionJson(String source) {
  final decoded = jsonDecode(stripJsonComments(source));
  return decoded is Map
      ? Map<String, Object?>.from(decoded)
      : <String, Object?>{};
}

/// What an extension is allowed to reach.
///
/// Declared in the manifest and answered once, then remembered — the same
/// posture the agent's tools already take.
enum ExtensionPermissionKind {
  /// Read and write the extension's own reactive store.
  data,

  /// Read any page's blocks.
  documentRead,

  /// Change a page's blocks.
  documentWrite,

  /// Read and write workspace files.
  files,

  /// Reach one host. The host is carried in [ExtensionPermission.value].
  net,

  /// Raise a toast or a system notification.
  notify,

  /// Create, complete or snooze reminders.
  reminders,

  /// Call a configured MCP server's tools.
  mcp;

  static ExtensionPermissionKind? parse(String name) => switch (name) {
        'data' => ExtensionPermissionKind.data,
        'document' || 'document:read' => ExtensionPermissionKind.documentRead,
        'document:write' => ExtensionPermissionKind.documentWrite,
        'files' => ExtensionPermissionKind.files,
        'net' => ExtensionPermissionKind.net,
        'notify' => ExtensionPermissionKind.notify,
        'reminders' => ExtensionPermissionKind.reminders,
        'mcp' => ExtensionPermissionKind.mcp,
        _ => null,
      };
}

/// One thing an extension asked for.
@immutable
class ExtensionPermission {
  const ExtensionPermission(this.kind, {this.value = ''});

  final ExtensionPermissionKind kind;

  /// The host, for [ExtensionPermissionKind.net]. Empty otherwise.
  final String value;

  /// `net:example.com` / `document:write` / `data`.
  static ExtensionPermission? parse(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final colon = trimmed.indexOf(':');
    if (colon < 0) {
      final kind = ExtensionPermissionKind.parse(trimmed);
      return kind == null ? null : ExtensionPermission(kind);
    }
    final head = trimmed.substring(0, colon);
    final tail = trimmed.substring(colon + 1).trim();
    if (head == 'net') {
      return tail.isEmpty
          ? null
          : ExtensionPermission(ExtensionPermissionKind.net, value: tail);
    }
    final kind = ExtensionPermissionKind.parse(trimmed);
    return kind == null ? null : ExtensionPermission(kind);
  }

  String encode() => switch (kind) {
        ExtensionPermissionKind.net => 'net:$value',
        ExtensionPermissionKind.documentRead => 'document:read',
        ExtensionPermissionKind.documentWrite => 'document:write',
        _ => kind.name,
      };

  @override
  bool operator ==(Object other) =>
      other is ExtensionPermission &&
      other.kind == kind &&
      other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => encode();
}

/// A library the extension's scripts and islands may use.
///
/// Fetched by the host, verified against [integrity], cached and served from
/// the extension's own folder — the page never reaches a CDN itself.
@immutable
class ExtensionLibrary {
  const ExtensionLibrary({
    required this.name,
    required this.version,
    required this.url,
    this.integrity = '',
  });

  final String name;
  final String version;
  final String url;
  final String integrity;

  String get id => version.isEmpty ? name : '$name@$version';

  static ExtensionLibrary? fromJson(Map<String, Object?> values) {
    final name = (values['name'] as String?)?.trim() ?? '';
    final url = (values['url'] as String?)?.trim() ?? '';
    if (name.isEmpty || url.isEmpty) {
      return null;
    }
    return ExtensionLibrary(
      name: name,
      version: (values['version'] as String?)?.trim() ?? '',
      url: url,
      integrity: (values['integrity'] as String?)?.trim() ?? '',
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        if (version.isNotEmpty) 'version': version,
        'url': url,
        if (integrity.isNotEmpty) 'integrity': integrity,
      };
}

/// A page an extension can draw inside a document.
///
/// Declared rather than discovered from the folder, so it can carry a name for
/// the slash menu and a height that suits what it draws.
@immutable
class ExtensionIsland {
  const ExtensionIsland({
    required this.id,
    required this.name,
    this.description = '',
    this.height = 360,
    this.keywords = const [],
  });

  /// The folder under the extension's `web/`.
  final String id;
  final String name;
  final String description;
  final double height;
  final List<String> keywords;

  static ExtensionIsland? fromJson(Map<String, Object?> values) {
    final id = (values['id'] as String?)?.trim() ?? '';
    // ⚠️ The id becomes a path segment, so it may not climb out of `web/`.
    if (id.isEmpty ||
        id.contains('..') ||
        id.contains('/') ||
        id.contains(r'\') ||
        id.contains(':')) {
      return null;
    }
    final keywords = values['keywords'];
    return ExtensionIsland(
      id: id,
      name: (values['name'] as String?)?.trim().isNotEmpty ?? false
          ? (values['name']! as String).trim()
          : id,
      description: (values['description'] as String?)?.trim() ?? '',
      height: (values['height'] as num?)?.toDouble() ?? 360,
      keywords: [
        if (keywords is List)
          for (final entry in keywords)
            if (entry is String && entry.trim().isNotEmpty) entry.trim(),
      ],
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        if (description.isNotEmpty) 'description': description,
        'height': height,
        if (keywords.isNotEmpty) 'keywords': keywords,
      };
}

/// What an extension folder says about itself.
@immutable
class ExtensionManifest {
  const ExtensionManifest({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.apiVersion = currentApiVersion,
    this.description = '',
    this.permissions = const [],
    this.secrets = const [],
    this.libraries = const [],
    this.islands = const [],
  });

  /// Raised when the shape an extension is written against changes.
  static const currentApiVersion = 1;

  final String id;
  final String name;
  final String version;
  final int apiVersion;
  final String description;
  final List<ExtensionPermission> permissions;
  final List<String> secrets;
  final List<ExtensionLibrary> libraries;
  final List<ExtensionIsland> islands;

  bool get isSupported => apiVersion >= 1 && apiVersion <= currentApiVersion;

  bool allows(ExtensionPermissionKind kind) =>
      permissions.any((permission) => permission.kind == kind);

  /// Whether [host] was declared. Matching is on the host alone: a declaration
  /// of `example.com` does not carry `evil.example.com.attacker.net`, so the
  /// comparison is equality or a dot-prefixed suffix.
  bool allowsHost(String host) {
    final wanted = host.toLowerCase();
    for (final permission in permissions) {
      if (permission.kind != ExtensionPermissionKind.net) {
        continue;
      }
      final declared = permission.value.toLowerCase();
      if (declared == wanted || wanted.endsWith('.$declared')) {
        return true;
      }
    }
    return false;
  }

  /// The hosts this extension named, for the settings page.
  List<String> get hosts => [
        for (final permission in permissions)
          if (permission.kind == ExtensionPermissionKind.net) permission.value,
      ];

  static ExtensionManifest? fromJson(Map<String, Object?> values) {
    final id = (values['id'] as String?)?.trim() ?? '';
    if (id.isEmpty || !_idPattern.hasMatch(id)) {
      return null;
    }
    final rawPermissions = values['permissions'];
    final rawSecrets = values['secrets'];
    final rawLibraries = values['libraries'];
    final rawIslands = values['islands'];
    return ExtensionManifest(
      id: id,
      name: (values['name'] as String?)?.trim().isNotEmpty ?? false
          ? (values['name']! as String).trim()
          : id,
      version: (values['version'] as String?)?.trim() ?? '0.0.0',
      apiVersion: values['apiVersion'] is int
          ? values['apiVersion']! as int
          : currentApiVersion,
      description: (values['description'] as String?)?.trim() ?? '',
      permissions: [
        if (rawPermissions is List)
          for (final entry in rawPermissions)
            if (entry is String)
              if (ExtensionPermission.parse(entry) case final parsed?) parsed,
      ],
      secrets: [
        if (rawSecrets is List)
          for (final entry in rawSecrets)
            if (entry is String && entry.trim().isNotEmpty) entry.trim(),
      ],
      libraries: [
        if (rawLibraries is List)
          for (final entry in rawLibraries)
            if (entry is Map)
              if (ExtensionLibrary.fromJson(Map<String, Object?>.from(entry))
                  case final parsed?)
                parsed,
      ],
      islands: [
        if (rawIslands is List)
          for (final entry in rawIslands)
            if (entry is Map)
              if (ExtensionIsland.fromJson(Map<String, Object?>.from(entry))
                  case final parsed?)
                parsed,
      ],
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'apiVersion': apiVersion,
        if (description.isNotEmpty) 'description': description,
        'permissions': [
          for (final permission in permissions) permission.encode(),
        ],
        if (secrets.isNotEmpty) 'secrets': secrets,
        if (libraries.isNotEmpty)
          'libraries': [for (final library in libraries) library.toJson()],
        if (islands.isNotEmpty)
          'islands': [for (final island in islands) island.toJson()],
      };

  /// An id has to be safe in a folder name and in a tool name, because it is
  /// used as both.
  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,47}$');
}
