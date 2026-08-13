import 'package:appflowy/plugins/dashboard/presentation/widgets/collection_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/content_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/control_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/data_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/info_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/text_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/time_widgets.dart';

/// Fill the registry with everything AppFlowy ships.
///
/// Called lazily the first time a dashboard is drawn. Adding a widget is one
/// `register` call in one of these files and nothing else: the "Add" panel,
/// the configuration panel, the `/` menu and the persisted document all read
/// the registry, so none of them has to learn about it.
void registerBuiltInDashboardWidgets() {
  registerDashboardTextWidgets();
  registerDashboardDataWidgets();
  registerDashboardContentWidgets();
  registerDashboardCollectionWidgets();
  registerDashboardTimeWidgets();
  registerDashboardControlWidgets();
  registerDashboardInfoWidgets();
}
