import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/built_in/data_block_extension.dart';
import 'package:appflowy/extensions/dart/built_in/glass_theme_extension.dart';
import 'package:appflowy/extensions/dart/built_in/news_extension.dart';
import 'package:appflowy/extensions/dart/built_in/stock_extension.dart';
import 'package:appflowy/extensions/dart/built_in/tally_table_view_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Every Dart extension compiled into this build.
///
/// ⚠️ This list is the one file that changes to add one. A Dart extension
/// cannot be loaded at runtime — Flutter has no way to — so "installing" one
/// means adding it here and rebuilding. Actions and islands exist for
/// everything that should not need that.
List<AppFlowyExtension> builtInDartExtensions() => [
      DataBlockExtension(),
      GlassThemeExtension(),
      TallyTableViewExtension(),
      StockExtension(),
      NewsExtension(),
    ];

/// Switches Dart extensions on and off, and remembers which are off.
class DartExtensionHost extends ChangeNotifier {
  DartExtensionHost();

  static final DartExtensionHost instance = DartExtensionHost();

  static const disabledKey = 'appflowy_dart_extensions_disabled';
  static const themeKey = 'appflowy_extension_theme';

  final Map<String, AppFlowyExtension> _extensions = {};
  final Map<String, DartExtensionContext> _live = {};
  final Set<String> _disabled = {};

  bool _started = false;

  List<AppFlowyExtension> get extensions =>
      List.unmodifiable(_extensions.values);

  bool isEnabled(String id) => !_disabled.contains(id);

  bool isActive(String id) => _live.containsKey(id);

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    await _readDisabled();

    for (final extension in builtInDartExtensions()) {
      final id = extension.info.id;
      if (_extensions.containsKey(id)) {
        Log.warn('Two Dart extensions both call themselves "$id".');
        continue;
      }
      _extensions[id] = extension;
      if (isEnabled(id)) {
        await _activate(extension);
      }
    }
    // Only once every extension has had its turn to register, or the stored
    // choice would be discarded for not existing yet.
    await _readSelectedTheme();
    notifyListeners();
  }

  /// Chooses an extension theme, or clears the choice with an empty id.
  Future<void> selectTheme(String key) async {
    ExtensionThemeRegistry.selected.value =
        ExtensionThemeRegistry.byKey(key) == null ? '' : key;
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      await getIt<KeyValueStorage>()
          .set(themeKey, ExtensionThemeRegistry.selected.value);
    } on Object catch (error) {
      Log.warn('The chosen extension theme could not be saved: $error');
    }
  }

  Future<void> _readSelectedTheme() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      final stored = await getIt<KeyValueStorage>().get(themeKey);
      if (stored != null && ExtensionThemeRegistry.byKey(stored) != null) {
        ExtensionThemeRegistry.selected.value = stored;
      }
    } on Object catch (error) {
      Log.warn('The chosen extension theme could not be read: $error');
    }
  }

  Future<void> _activate(AppFlowyExtension extension) async {
    final id = extension.info.id;
    if (_live.containsKey(id)) {
      return;
    }
    final context = DartExtensionContext(info: extension.info);
    try {
      await extension.activate(context);
      _live[id] = context;
    } on Object catch (error) {
      // ⚠️ One extension that cannot start must not stop the others, and must
      // not leave half of itself registered.
      context.scope.close();
      Log.warn('Dart extension $id could not be switched on: $error');
    }
  }

  Future<void> _deactivate(String id) async {
    final context = _live.remove(id);
    if (context == null) {
      return;
    }
    try {
      await _extensions[id]?.deactivate();
    } on Object catch (error) {
      Log.warn('Dart extension $id did not switch off cleanly: $error');
    }
    // Everything registered through the context is undone here, whether or not
    // the extension's own deactivate behaved.
    context.scope.close();
    if (ExtensionThemeRegistry.byKey(ExtensionThemeRegistry.selected.value) ==
        null) {
      // The theme in use belonged to this extension. Fall back rather than keep
      // pointing at a theme that is gone.
      ExtensionThemeRegistry.selected.value = '';
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final extension = _extensions[id];
    if (extension == null) {
      return;
    }
    if (enabled) {
      _disabled.remove(id);
      await _activate(extension);
    } else {
      _disabled.add(id);
      await _deactivate(id);
    }
    await _writeDisabled();
    notifyListeners();
  }

  Future<void> stop() async {
    for (final id in _live.keys.toList()) {
      await _deactivate(id);
    }
    _started = false;
    notifyListeners();
  }

  Future<void> _readDisabled() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      final stored = await getIt<KeyValueStorage>().get(disabledKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      _disabled
        ..clear()
        ..addAll(stored.split(',').where((id) => id.trim().isNotEmpty));
    } on Object catch (error) {
      Log.warn('Which Dart extensions are off could not be read: $error');
    }
  }

  Future<void> _writeDisabled() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      await getIt<KeyValueStorage>().set(disabledKey, _disabled.join(','));
    } on Object catch (error) {
      Log.warn('Which Dart extensions are off could not be saved: $error');
    }
  }
}
