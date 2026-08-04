import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// A tab that draws the database instead of listing it.
///
/// It sits beside the grid, the board and the calendar because it is the same
/// database — only read as a picture.
class ChartTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      ChartTabPage(key: ValueKey(view.id), view: view);

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      const SizedBox.shrink();

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) =>
      const SizedBox.shrink();
}

class ChartTabPage extends StatefulWidget {
  const ChartTabPage({super.key, required this.view});

  final ViewPB view;

  @override
  State<ChartTabPage> createState() => _ChartTabPageState();
}

class _ChartTabPageState extends State<ChartTabPage> {
  late ChartMetadata _metadata =
      widget.view.chart ?? const ChartMetadata(spec: ChartSpec());

  @override
  void didUpdateWidget(covariant ChartTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.extra != widget.view.extra) {
      _metadata = widget.view.chart ?? _metadata;
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 4, 40, 24),
        child: ChartStage(
          viewId: widget.view.id,
          spec: _metadata.spec,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          onSpecChanged: (spec) {
            final next = _metadata.copyWith(spec: spec);
            setState(() => _metadata = next);
            ViewBackendService.updateView(
              viewId: widget.view.id,
              extra: next.mergeIntoExtra(widget.view.extra),
            );
          },
        ),
      );
}
