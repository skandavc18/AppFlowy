import 'package:integration_test/integration_test.dart';

import '../../test/widget_test/dashboard_resource_lifecycle_test.dart'
    as dashboard;
import '../../test/widget_test/resource_lifecycle_test.dart' as lifecycle;

// Exercise the same widget/ticker assertions on the real Windows
// engine. No AppFlowy startup, backend, credentials or live preferences.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.reportData = {
    'run': 'resource_lifecycle',
    'scope': 'widget_lifecycle',
  };
  lifecycle.runResourceLifecycleWidgetTests();
  dashboard.runDashboardResourceLifecycleTests();
}
