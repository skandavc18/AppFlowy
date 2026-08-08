import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

/// The app name used in the local notification.
///
/// DO NOT Use i18n here, because the i18n plugin is not ready
///   before the local notification is initialized.
const _localNotifierAppName = 'AppFlowy';

/// Manages Local Notifications
///
/// Currently supports:
///  - MacOS
///  - Windows
///  - Linux
///
class NotificationService {
  /// Whether the operating system can actually be asked to show a
  /// notification.
  ///
  /// Windows answers no until the shortcut below exists; every `show()` is a
  /// silent no-op in that state, so anything that must not go unheard needs
  /// to announce itself another way.
  static bool get isReady => _isReady;
  static bool _isReady = true;

  static Future<void> initialize() async {
    // Windows shows nothing from a Win32 application until a Start Menu
    // shortcut carries its AppUserModelID: WinToast refuses to initialise
    // without one, and neither the plugin nor `show()` says so. Creating it
    // is the library's default; opting out of that assumed the installer had
    // left a suitable shortcut behind, and its shortcut carries no id.
    await localNotifier.setup(appName: _localNotifierAppName);
    _isReady = _hasNotificationShortcut();
  }

  static bool _hasNotificationShortcut() {
    if (!Platform.isWindows) {
      return true;
    }
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      return false;
    }
    final shortcut = File(
      '$appData\\Microsoft\\Windows\\Start Menu\\Programs'
      '\\$_localNotifierAppName.lnk',
    );
    if (shortcut.existsSync()) {
      return true;
    }
    Log.warn(
      'Windows would not register AppFlowy for notifications, so nothing '
      'will be shown outside the window.',
    );
    return false;
  }
}

/// Creates and shows a Notification
///
class NotificationMessage {
  NotificationMessage({
    required String title,
    required String body,
    String? identifier,
    VoidCallback? onClick,
  }) {
    _notification = LocalNotification(
      identifier: identifier,
      title: title,
      body: body,
    )..onClick = onClick;

    _show();
  }

  late final LocalNotification _notification;

  void _show() => _notification.show();
}
