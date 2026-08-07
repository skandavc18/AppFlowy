import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/maps/map_metadata.dart';
import 'package:appflowy/workspace/application/slides/slide_metadata.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// How tall a table that opens as something other than a grid stands inside a
/// document, until somebody drags it. Tall enough to read, short enough to
/// scroll past.
const double embeddedDatabaseViewHeight = 460;

/// Whether this table's reading is written as a full page rather than as a
/// widget that can shrink to its content.
///
/// Only these have a height to give: a grid, a board and a calendar grow with
/// what they hold, and forcing a shorter box on them only clips the rows.
bool embeddedDatabaseViewFillsItsBox(ViewPB view) =>
    view.isChart ||
    view.isMap ||
    view.isSlideDeck ||
    view.tableViewKind != null;

class DatabaseViewWidget extends StatefulWidget {
  const DatabaseViewWidget({
    super.key,
    required this.view,
    this.shrinkWrap = true,
    required this.showActions,
    required this.node,
    this.actionBuilder,
  });

  final ViewPB view;
  final bool shrinkWrap;
  final BlockComponentActionBuilder? actionBuilder;
  final bool showActions;
  final Node node;

  @override
  State<DatabaseViewWidget> createState() => _DatabaseViewWidgetState();
}

class _DatabaseViewWidgetState extends State<DatabaseViewWidget> {
  /// Listens to the view updates.
  late final ViewListener _listener;

  /// Notifies the view layout type changes. When the layout type changes,
  /// the widget of the view will be updated.
  late final ValueNotifier<ViewLayoutPB> _layoutTypeChangeNotifier;

  /// The view will be updated by the [ViewListener].
  late ViewPB view;

  late Plugin viewPlugin;

  @override
  void initState() {
    super.initState();
    view = widget.view;
    viewPlugin = view.plugin()..init();
    _listenOnViewUpdated();
  }

  @override
  void dispose() {
    _layoutTypeChangeNotifier.dispose();
    _listener.stop();
    viewPlugin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double? horizontalPadding = 0.0;
    final databasePluginWidgetBuilderSize =
        Provider.of<DatabasePluginWidgetBuilderSize?>(context);
    if (view.layout == ViewLayoutPB.Grid || view.layout == ViewLayoutPB.Board) {
      horizontalPadding = 40.0;
    }
    if (databasePluginWidgetBuilderSize != null) {
      horizontalPadding = databasePluginWidgetBuilderSize.horizontalPadding;
    }

    return ValueListenableBuilder<ViewLayoutPB>(
      valueListenable: _layoutTypeChangeNotifier,
      builder: (_, __, ___) => viewPlugin.widgetBuilder.buildWidget(
        shrinkWrap: widget.shrinkWrap,
        context: PluginContext(),
        data: {
          kDatabasePluginWidgetBuilderHorizontalPadding: horizontalPadding,
          kDatabasePluginWidgetBuilderActionBuilder: widget.actionBuilder,
          kDatabasePluginWidgetBuilderShowActions: widget.showActions,
          kDatabasePluginWidgetBuilderNode: widget.node,
        },
      ),
    );
  }

  void _listenOnViewUpdated() {
    _listener = ViewListener(viewId: widget.view.id)
      ..start(
        onViewUpdated: (updatedView) {
          if (mounted) {
            view = updatedView;
            _layoutTypeChangeNotifier.value = view.layout;
          }
        },
      );

    _layoutTypeChangeNotifier = ValueNotifier(widget.view.layout);
  }
}
