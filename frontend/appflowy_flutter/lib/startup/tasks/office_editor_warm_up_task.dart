import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_embedded_view.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Gets the bundled office editor ready a little after launch, on a device
/// that has opened office documents before, so the first one opens without
/// starting the editor from cold (see [warmUpOfficeEditor]).
class OfficeEditorWarmUpTask extends LaunchTask {
  const OfficeEditorWarmUpTask();

  /// Out of the way of the launch itself and the first workspace sync.
  static const delay = Duration(seconds: 8);

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);
    if (kIsWeb || !Platform.isLinux) {
      return;
    }
    Timer(delay, () {
      warmUpOfficeEditor().catchError((Object error) {
        Log.warn('Unable to warm up the office editor: $error');
      });
    });
  }
}
