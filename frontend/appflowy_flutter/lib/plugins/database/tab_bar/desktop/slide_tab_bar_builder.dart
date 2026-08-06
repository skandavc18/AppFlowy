import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail.dart';
import 'package:appflowy/shared/slides/slide_stage.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/workspace/application/slides/slide_metadata.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A tab that reads the database one row at a time.
///
/// It sits beside the grid, the board and the calendar because it is the same
/// database — only read as a stack of cards rather than as a list.
class SlideTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      SlideTabPage(
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

class SlideTabPage extends StatefulWidget {
  const SlideTabPage({
    super.key,
    required this.view,
    required this.databaseController,
  });

  final ViewPB view;
  final DatabaseController databaseController;

  @override
  State<SlideTabPage> createState() => _SlideTabPageState();
}

class _SlideTabPageState extends State<SlideTabPage> {
  final GlobalKey<SlideStageState> _stage = GlobalKey<SlideStageState>();

  late SlideMetadata _metadata =
      widget.view.slideView ?? const SlideMetadata(spec: SlideSpec());

  @override
  void initState() {
    super.initState();
    // The grid, board and calendar each open the database from their own bloc.
    // The deck has none, so without this its field controller and row cache
    // stay empty and a row opened from a slide comes up with no properties.
    unawaited(_openDatabase());
    // Any row change means a slide may have changed, so the deck re-reads.
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
  void didUpdateWidget(SlideTabPage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _metadata = widget.view.slideView ?? _metadata;
    }
    // Rows may have been edited in another tab while this one was off screen,
    // and a linked view's row cache does not always hear about it.
    _onRows();
  }

  void _onRows() => _stage.currentState?.reload();

  void _save(SlideSpec spec) {
    final next = _metadata.copyWith(spec: spec);
    setState(() => _metadata = next);
    ViewBackendService.updateView(
      viewId: widget.view.id,
      extra: next.mergeIntoExtra(widget.view.extra),
    );
  }

  RowMetaPB? _metaOf(String rowId) =>
      widget.databaseController.rowCache.getRow(rowId)?.rowMeta;

  /// Opens a row the way every other view does.
  ///
  /// A row's own document is only made when its page is first opened, so
  /// sending it straight to the full page asks for a document id that is not
  /// there yet. The page itself carries the button that does that safely.
  void _openRow(String rowId) {
    final rowMeta = _metaOf(rowId);
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
    unawaited(
      FlowyOverlay.show(
        context: context,
        builder: (_) => BlocProvider.value(
          value: context.read<UserWorkspaceBloc>(),
          child: RowDetailPage(
            rowController: rowController,
            databaseController: widget.databaseController,
          ),
        ),
      ).then((_) {
        if (!mounted) {
          return;
        }
        // Whatever was written on the row's page has to be read again, and a
        // page made during the visit had no id to forget.
        RowPageText.forget();
        _onRows();
      }),
    );
  }

  /// Adds a row and opens it, so a new slide is never a blank card nobody
  /// knows how to fill in.
  Future<String?> _addRow() async {
    final created = await RowBackendService.createRow(viewId: widget.view.id);
    if (!mounted) {
      return null;
    }
    return created.fold(
      (rowMeta) {
        _onRows();
        _openRowMeta(rowMeta);
        return rowMeta.id;
      },
      (error) {
        Log.error(error);
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(40, 4, 40, 20),
        child: SlideStage(
          key: _stage,
          viewId: widget.view.id,
          spec: _metadata.spec,
          title: widget.view.name,
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          onSpecChanged: _save,
          onOpenRow: _openRow,
          onEditRow: _openRow,
          onAddRow: _addRow,
        ),
      );
}
