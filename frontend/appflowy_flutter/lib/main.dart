import 'dart:async';

import 'package:appflowy/workflows/application/workflow_background.dart';
import 'package:appflowy/workspace/application/sync/android_background_sync.dart';
import 'package:flutter/widgets.dart';
import 'package:scaled_app/scaled_app.dart';
import 'package:media_kit/media_kit.dart';

import 'startup/startup.dart';
import 'startup/startup_profile.dart';

/// Entrypoint invoked by Android's `SyncJobService` when syncing in the
/// background without an active UI window.
@pragma('vm:entry-point')
Future<void> appflowyBackgroundSyncMain() => runAndroidHeadlessSyncRound();

Future<void> main([List<String> arguments = const []]) async {
  // Remembered before anything else: a start at Windows sign-in keeps the
  // window hidden, which the window setup below has to know.
  WorkflowBackground.recordLaunchArguments(arguments);
  startupProfile.start(arguments);
  startupProfile.measureSync(
    'flutter_binding',
    () => ScaledWidgetsFlutterBinding.ensureInitialized(
      scaleFactor: (_) => 1.0,
    ),
  );
  startupProfile.measureSync('media_kit', MediaKit.ensureInitialized);
  if (startupProfile.enabled) {
    unawaited(
      WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
        startupProfile.mark('first_frame_rasterized');
      }),
    );
  }

  await startupProfile.measure('application_launch', runAppFlowy);
}
