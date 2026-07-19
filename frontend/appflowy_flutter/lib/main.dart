import 'package:scaled_app/scaled_app.dart';
import 'package:media_kit/media_kit.dart';

import 'startup/startup.dart';

Future<void> main() async {
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (_) => 1.0,
  );
  MediaKit.ensureInitialized();

  await runAppFlowy();
}
