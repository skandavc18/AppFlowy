import 'package:flutter/foundation.dart';
import 'package:universal_platform/universal_platform.dart';

/// Lets tests, which run on a desktop host, take another platform's path.
///
/// Office code follows the platform AppFlowy actually runs on, as the rest
/// of the app does through [UniversalPlatform], rather than
/// `defaultTargetPlatform`, which flutter_test reports as Android.
@visibleForTesting
TargetPlatform? debugOfficePlatformOverride;

/// Whether AppFlowy runs on Android, whose APK carries the office editor.
bool get officeRunsOnAndroid => switch (debugOfficePlatformOverride) {
      null => UniversalPlatform.isAndroid,
      final platform => platform == TargetPlatform.android,
    };

/// Whether AppFlowy runs its phone and tablet layout.
bool get officeRunsOnMobile => switch (debugOfficePlatformOverride) {
      null => UniversalPlatform.isMobile,
      final platform =>
        platform == TargetPlatform.android || platform == TargetPlatform.iOS,
    };
