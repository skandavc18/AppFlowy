import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/page_versions/page_version.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// What the application has been told about keeping previous states of a page.
///
/// One policy for the whole workspace: a rule that had to be set per page
/// would never be set at all.
class PageVersionSettings extends ChangeNotifier {
  PageVersionSettings._();

  static final PageVersionSettings instance = PageVersionSettings._();

  static const storageKey = 'appflowy_page_versions_policy';

  PageVersionPolicy _policy = const PageVersionPolicy();
  Future<void>? _loading;
  bool _loaded = false;

  PageVersionPolicy get policy => _policy;

  bool get isLoaded => _loaded;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      // Reading nothing must not latch: a settings screen opened later has to
      // be able to try again.
      _loading = null;
      return;
    }
    try {
      final stored = await getIt<KeyValueStorage>().get(storageKey);
      if (stored != null && stored.isNotEmpty) {
        final decoded = jsonDecode(stored);
        if (decoded is Map) {
          _policy = PageVersionPolicy.fromJson(
            Map<String, Object?>.from(decoded),
          );
        }
      }
      _loaded = true;
      notifyListeners();
    } on Object catch (error) {
      _loading = null;
      Log.warn('The page version settings could not be read: $error');
    }
  }

  Future<void> update(PageVersionPolicy policy) async {
    if (policy == _policy) {
      return;
    }
    _policy = policy;
    _loaded = true;
    notifyListeners();
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      await getIt<KeyValueStorage>()
          .set(storageKey, jsonEncode(policy.toJson()));
    } on Object catch (error) {
      Log.warn('The page version settings could not be stored: $error');
    }
  }

  @visibleForTesting
  void seedForTest(PageVersionPolicy policy) {
    _policy = policy;
    _loaded = true;
    _loading = Future<void>.value();
  }
}
