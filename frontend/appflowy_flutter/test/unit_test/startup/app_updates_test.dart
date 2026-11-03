import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a private build never offers a public AppFlowy release', () {
    final current = ApplicationInfo.applicationVersion;
    final latest = ApplicationInfo.latestVersionNotifier.value;
    addTearDown(() {
      ApplicationInfo.applicationVersion = current;
      ApplicationInfo.latestVersionNotifier.value = latest;
    });

    ApplicationInfo.applicationVersion = '0.11.4';
    ApplicationInfo.latestVersionNotifier.value = '99.0.0';

    expect(ApplicationInfo.updatesEnabled, isFalse);
    expect(ApplicationInfo.isUpdateAvailable, isFalse);
  });
}
