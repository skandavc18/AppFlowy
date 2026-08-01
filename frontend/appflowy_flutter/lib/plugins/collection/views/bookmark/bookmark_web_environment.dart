import 'dart:async';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The renderer a saved page is read in.
///
/// Bookmark browsing gets its own WebView2 environment so its cookies never
/// mix with the previews the editor renders. Chromium keeps its own scroll
/// animation and its own two-finger fling: both run on the compositor thread,
/// which is the only place a page can be moved without a stutter.
class BookmarkWebEnvironment {
  const BookmarkWebEnvironment._();

  static const _browserArguments =
      '--disable-features=CalculateNativeWinOcclusion';

  static Future<WebViewEnvironment?>? _pending;
  static WebViewEnvironment? _environment;
  static bool _failed = false;

  static WebViewEnvironment? get instance => _environment;

  /// Builds the environment once. Returns null when the platform has none, in
  /// which case the default environment is used.
  static Future<WebViewEnvironment?> ensure() {
    if (!Platform.isWindows || _failed) {
      return Future.value(_environment);
    }
    return _pending ??= _create();
  }

  static Future<WebViewEnvironment?> _create() async {
    try {
      final environment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          additionalBrowserArguments: _browserArguments,
          userDataFolder: 'appflowy_bookmarks',
        ),
      );
      return _environment = environment;
    } on Object catch (error) {
      _failed = true;
      Log.warn('Could not create the bookmark browser environment: $error');
      return null;
    }
  }
}
