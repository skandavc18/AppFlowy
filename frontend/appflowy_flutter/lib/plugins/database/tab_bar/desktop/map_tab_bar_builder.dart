import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_stage.dart';
import 'package:appflowy/workspace/application/maps/map_metadata.dart';
import 'package:appflowy/workspace/application/maps/map_spec.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A tab that places the database instead of listing it.
///
/// It sits beside the grid, the board and the calendar because it is the same
/// database — only read as somewhere rather than as a list.
class MapTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      MapTabPage(
        key: ValueKey(view.id),
        view: view,
        databaseController: controller,
      );

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

class MapTabPage extends StatefulWidget {
  const MapTabPage({
    super.key,
    required this.view,
    required this.databaseController,
  });

  final ViewPB view;
  final DatabaseController databaseController;

  @override
  State<MapTabPage> createState() => _MapTabPageState();
}

class _MapTabPageState extends State<MapTabPage> {
  final GlobalKey<MapStageState> _stage = GlobalKey<MapStageState>();

  late MapMetadata _metadata =
      widget.view.mapView ?? const MapMetadata(spec: MapSpec());

  @override
  void initState() {
    super.initState();
    // The grid, board and calendar each open the database from their own bloc.
    // The map has none, so without this its field controller and row cache stay
    // empty and a row opened from a pin comes up with no properties at all.
    unawaited(_openDatabase());
    // Any row change means a place may have moved, so the map re-reads itself.
    widget.databaseController.rowCache.onRowsChanged((_) => _onRows());
  }

  Future<void> _openDatabase() async {
    final result = await widget.databaseController.open();
    if (!mounted) {
      return;
    }
    result.fold((_) => _onRows(), Log.error);
  }

  @override
  void didUpdateWidget(MapTabPage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _metadata = widget.view.mapView ?? _metadata;
    }
    // Rows may have been edited in another tab while this one was off screen,
    // and a linked view's row cache does not always hear about it.
    _onRows();
  }

  void _onRows() => _stage.currentState?.reload();

  void _save(MapSpec spec) {
    final next = _metadata.copyWith(spec: spec);
    setState(() => _metadata = next);
    ViewBackendService.updateView(
      viewId: widget.view.id,
      extra: next.mergeIntoExtra(widget.view.extra),
    );
  }

  void _openRow(String rowId) {
    final rowMeta = widget.databaseController.rowCache.getRow(rowId)?.rowMeta;
    if (rowMeta == null) {
      return;
    }
    _openRowMeta(rowMeta);
  }

  void _openRowMeta(RowMetaPB rowMeta) {
    final rowController = RowController(
      rowMeta: rowMeta,
      viewId: widget.databaseController.viewId,
      rowCache: widget.databaseController.rowCache,
    );
    FlowyOverlay.show(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<UserWorkspaceBloc>(),
        child: RowDetailPage(
          rowController: rowController,
          databaseController: widget.databaseController,
        ),
      ),
    );
  }

  /// Adds a row that already knows where it is, then opens it to be filled in.
  Future<void> _addRow(LatLng point) async {
    final columns = _metadata.spec.locationColumns;
    final field = widget.databaseController.fieldController.fieldInfos
        .where((info) => columns.contains(info.id))
        .firstOrNull;
    final created = await RowBackendService.createRow(
      viewId: widget.view.id,
      withCells: field == null
          ? null
          : (builder) => builder.insertText(field, point.label),
    );
    if (!mounted) {
      return;
    }
    created.fold(_openRowMeta, Log.error);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 4, 40, 24),
        child: MapStage(
          key: _stage,
          viewId: widget.view.id,
          spec: _metadata.spec,
          title: widget.view.name,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          onSpecChanged: _save,
          onOpenRow: _openRow,
          onAddRow: _addRow,
        ),
      );
}
