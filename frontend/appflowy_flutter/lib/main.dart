import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:scaled_app/scaled_app.dart';
import 'package:media_kit/media_kit.dart';

import 'startup/startup.dart';
import 'startup/startup_profile.dart';

Future<void> main([List<String> arguments = const []]) async {
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
