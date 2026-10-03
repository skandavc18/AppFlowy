import 'dart:async';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One line of the notification-area menu.
@immutable
class WorkflowTrayItem {
  const WorkflowTrayItem({
    required this.id,
    required this.label,
    this.checked = false,
  }) : separator = false;

  const WorkflowTrayItem.separator()
      : id = '',
        label = '',
        checked = false,
        separator = true;

  final String id;
  final String label;
  final bool checked;
  final bool separator;

  Map<String, Object?> toMap() => separator
      ? {'separator': true}
      : {'id': id, 'label': label, 'checked': checked};
}

/// The window's life outside the window: the notification-area icon, closing
/// to it instead of quitting, and starting with Windows.
///
/// ⚠️ Windows only. The runner implements the channel; everywhere else every
/// call is a quiet no-op, so callers never need to check twice.
class WorkflowBackground {
  WorkflowBackground._();

  static final WorkflowBackground instance = WorkflowBackground._();

  static const channelName = 'appflowy/background';

  /// Passed by the runner when Windows starts AppFlowy at sign-in.
  static const backgroundFlag = '--background';

  /// Tray menu ids the runner also understands on its own.
  static const openAction = 'open';
  static const quitAction = 'quit';

  static const MethodChannel _channel = MethodChannel(channelName);

  static List<String> _launchArguments = const [];

  static bool get isSupported => !kIsWeb && Platform.isWindows;

  static void recordLaunchArguments(List<String> arguments) {
    _launchArguments = List.unmodifiable(arguments);
  }

  /// Whether this process started without a window, at sign-in.
  static bool get startedInBackground =>
      _launchArguments.contains(backgroundFlag);

  void Function(String action)? _onTrayAction;
  VoidCallback? _onClosedToTray;
  final List<VoidCallback> _shownListeners = [];
  bool _attached = false;

  /// Receives the runner's calls. Safe to call more than once.
  void attach({
    required void Function(String action) onTrayAction,
    required VoidCallback onClosedToTray,
  }) {
    _onTrayAction = onTrayAction;
    _onClosedToTray = onClosedToTray;
    if (_attached || !isSupported) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler(_handle);
  }

  /// Called each time the window comes back after being hidden.
  void addShownListener(VoidCallback listener) => _shownListeners.add(listener);

  void removeShownListener(VoidCallback listener) =>
      _shownListeners.remove(listener);

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'onTrayAction':
        final action = call.arguments;
        if (action is String) {
          _onTrayAction?.call(action);
        }
      case 'onClosedToTray':
        _onClosedToTray?.call();
      case 'onWindowShown':
        for (final listener in List.of(_shownListeners)) {
          listener();
        }
    }
    return null;
  }

  /// Turns closing-to-the-notification-area on or off, and sets what its icon
  /// says and offers. The icon is only there while it is on.
  Future<bool> configure({
    required bool keepRunning,
    required String tooltip,
    required List<WorkflowTrayItem> menu,
  }) =>
      _invoke<bool>('configure', {
        'keepRunning': keepRunning,
        'tooltip': tooltip,
        'menu': [for (final item in menu) item.toMap()],
      }).then((value) => value ?? false);

  Future<bool> isLaunchAtLoginEnabled() =>
      _invoke<bool>('isLaunchAtLoginEnabled').then((value) => value ?? false);

  Future<bool> setLaunchAtLogin(bool enabled) =>
      _invoke<bool>('setLaunchAtLogin', {'enabled': enabled})
          .then((value) => value ?? false);

  /// Brings the window back from the notification area.
  Future<void> showWindow() => _invoke<void>('showWindow');

  /// Hides the window to the notification area.
  Future<void> hideWindow() => _invoke<void>('hideWindow');

  /// Ends the process, tray icon and all.
  Future<void> quit() => _invoke<void>('quit');

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    if (!isSupported) {
      return null;
    }
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      Log.warn('The background channel refused $method: ${error.message}');
      return null;
    }
  }
}
