import 'dart:async';
import 'dart:io';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// How long a page is given to clear its own bot check and settle.
const _browserTimeout = Duration(seconds: 20);

/// Extra time after `load` for a challenge to redirect and for a client-side
/// application to write its metadata into the head.
const _settle = Duration(milliseconds: 1400);

/// Reads a page the way a person would.
///
/// A plain HTTP read of a site behind a bot check comes back as the check
/// itself — "Please wait for verification" with no picture. A real renderer
/// clears it, so the page that gets saved is the page that was meant.
Future<String?> readPageInBrowser(Uri uri) async {
  if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return null;
  }

  final loaded = Completer<void>();
  HeadlessInAppWebView? headless;
  try {
    headless = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(uri.toString())),
      onLoadStop: (_, __) {
        if (!loaded.isCompleted) {
          loaded.complete();
        }
      },
      onReceivedError: (_, __, ___) {
        if (!loaded.isCompleted) {
          loaded.complete();
        }
      },
      // Left unanswered this crashes the renderer on a page with embedded
      // video; a reader needs none of it, so everything is refused.
      onPermissionRequest: (_, request) async =>
          PermissionResponse(resources: request.resources),
    );
    await headless.run();
    await loaded.future.timeout(_browserTimeout);
    await Future<void>.delayed(_settle);
    final html = await headless.webViewController
        ?.evaluateJavascript(source: 'document.documentElement.outerHTML;')
        .timeout(_browserTimeout);
    return html is String && html.isNotEmpty ? html : null;
  } on TimeoutException {
    return null;
  } on PlatformException catch (error) {
    Log.warn('Could not read $uri in a browser: $error');
    return null;
  } on Object catch (error) {
    Log.warn('Could not read $uri in a browser: $error');
    return null;
  } finally {
    unawaited(headless?.dispose());
  }
}
