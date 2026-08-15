import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

import 'ai_tool.dart';

/// What has been decided about a tool, once and for all.
enum AIToolPermission {
  /// Ask every time. The default for anything that writes.
  ask,

  /// Run without asking.
  allow,

  /// Never run, and do not ask again.
  deny;

  static AIToolPermission fromName(String? name) => switch (name) {
        'allow' => AIToolPermission.allow,
        'deny' => AIToolPermission.deny,
        _ => AIToolPermission.ask,
      };
}

/// The answer to one request to run a tool.
enum AIToolDecision { allowOnce, allowAlways, allowAllThisChat, denyOnce, denyAlways }

/// Who may do what.
///
/// Reading is never asked about. Anything that writes or removes is asked about
/// once and the answer is remembered, per tool — the same shape as an editor
/// asking before it lets an agent touch the disk.
class AIToolPermissionStore extends ChangeNotifier {
  AIToolPermissionStore({KeyValueStorage? storage}) : _storage = storage;

  static final AIToolPermissionStore instance = AIToolPermissionStore();

  static const permissionsKey = 'appflowy_ai_tool_permissions';
  static const askForReadsKey = 'appflowy_ai_tool_ask_for_reads';

  final KeyValueStorage? _storage;
  final Map<String, AIToolPermission> _permissions = {};

  /// Chats that said "allow everything for now". Cleared when the chat closes.
  final Set<String> _sessionGrants = {};

  Future<void>? _loading;
  bool _loaded = false;

  KeyValueStorage? get _kv =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  Future<void> ensureLoaded() {
    if (_loaded) {
      return Future.value();
    }
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _kv?.get(permissionsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            // Merge, never replace: a decision made while this read was in
            // flight must survive the answer landing late.
            _permissions.putIfAbsent(
              '$key',
              () => AIToolPermission.fromName('$value'),
            );
          });
        }
      }
    } catch (error) {
      Log.warn('Could not read the AI tool permissions: $error');
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  Map<String, AIToolPermission> get decisions => Map.unmodifiable(_permissions);

  AIToolPermission permissionFor(AITool tool) =>
      _permissions[tool.qualifiedName] ?? AIToolPermission.ask;

  bool hasSessionGrant(String chatId) => _sessionGrants.contains(chatId);

  void grantForChat(String chatId) {
    _sessionGrants.add(chatId);
    notifyListeners();
  }

  void endChat(String chatId) => _sessionGrants.remove(chatId);

  /// Whether [tool] can run without asking anybody.
  bool isAllowedWithoutAsking(AITool tool, {required String chatId}) {
    if (!tool.risk.needsApproval) {
      return true;
    }
    final decided = permissionFor(tool);
    if (decided == AIToolPermission.allow) {
      return true;
    }
    if (decided == AIToolPermission.deny) {
      return false;
    }
    return hasSessionGrant(chatId);
  }

  Future<void> remember(AITool tool, AIToolPermission permission) async {
    await ensureLoaded();
    if (permission == AIToolPermission.ask) {
      _permissions.remove(tool.qualifiedName);
    } else {
      _permissions[tool.qualifiedName] = permission;
    }
    await _persist();
    notifyListeners();
  }

  Future<void> forgetAll() async {
    await ensureLoaded();
    _permissions.clear();
    _sessionGrants.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final payload = jsonEncode(
      _permissions.map((key, value) => MapEntry(key, value.name)),
    );
    await _kv?.set(permissionsKey, payload);
  }
}
