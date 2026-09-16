import 'package:appflowy/shared/feature_flags.dart';

import '../startup.dart';

class FeatureFlagTask extends LaunchTask {
  const FeatureFlagTask();

  @override
  Future<void> initialize(LaunchContext context) async {
    await super.initialize(context);

    // Saved capabilities must survive switching between Debug and Release.
    await FeatureFlag.initialize();
  }
}
