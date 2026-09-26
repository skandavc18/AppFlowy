import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ChartBlockKeys {
  const ChartBlockKeys._();

  static const String type = 'chart';

  /// The table the chart reads.
  static const String viewId = 'view_id';

  /// How that table is plotted.
  static const String spec = 'spec';

  /// How tall the chart stands in the page.
  static const String height = 'height';

  /// How wide it stands.
  static const String width = 'width';
}

Node chartBlockNode({
  String viewId = '',
  ChartSpec? spec,
  double? height,
  double? width,
}) =>
    Node(
      type: ChartBlockKeys.type,
      attributes: {
        ChartBlockKeys.viewId: viewId,
        if (spec != null) ChartBlockKeys.spec: spec.toJson(),
        if (height != null) ChartBlockKeys.height: height,
        if (width != null) ChartBlockKeys.width: width,
      },
    );

/// A chart placed in a page.
///
/// It is not a picture of a table — it is the table, drawn. Change a row and
/// the chart in the page changes with it, and the controls above it are live.
class ChartBlockComponentBuilder extends BlockComponentBuilder {
  ChartBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ChartBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => true;
}

class ChartBlockComponent extends BlockComponentStatefulWidget {
  const ChartBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ChartBlockComponent> createState() => _ChartBlockComponentState();
}

class _ChartBlockComponentState extends State<ChartBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  static const double _minimumHeight = 220;
  static const double _defaultHeight = 320;
  static const double _minimumWidth = 320;
  static const double _defaultWidth = 720;

  final PopoverController _picker = PopoverController();
  VoidCallback? _releasePicker;

  void _openPicker(BuildContext triggerContext) {
    if (_releasePicker != null) return;
    // Programmatic PopoverController.show does not call onOpen. Acquire the
    // hold at the real header trigger, below ResizableMedia's preview scope.
    _releasePicker = PreviewToolbarRegion.hold(triggerContext);
    try {
      _picker.show();
    } catch (_) {
      _closePickerHold();
      rethrow;
    }
  }

  void _closePickerHold() {
    final release = _releasePicker;
    _releasePicker = null;
    release?.call();
  }

  void _retirePicker() {
    final release = _releasePicker;
    _releasePicker = null;
    _picker.close();
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
  }

  @override
  void deactivate() {
    _retirePicker();
    super.deactivate();
  }

  @override
  void dispose() {
    _retirePicker();
    super.dispose();
  }

  String get _viewId => node.attributes[ChartBlockKeys.viewId] as String? ?? '';

  double get _height {
    final stored = node.attributes[ChartBlockKeys.height];
    return stored is num ? stored.toDouble() : _defaultHeight;
  }

  double get _width {
    final stored = node.attributes[ChartBlockKeys.width];
    return stored is num ? stored.toDouble() : _defaultWidth;
  }

  ChartSpec get _spec {
    final stored = node.attributes[ChartBlockKeys.spec];
    return ChartSpec.fromJson(
      stored is Map ? Map<String, dynamic>.from(stored) : const {},
    );
  }

  EditorState get _editorState => context.read<EditorState>();

  bool get _editable => _editorState.editable;

  Future<void> _update(Map<String, Object?> attributes) {
    final transaction = _editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    return _editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final palette = chartPaletteOf(context);
    Widget child = ResizableMedia(
      width: _width,
      minWidth: _minimumWidth,
      height: _height,
      minHeight: _minimumHeight,
      maxHeight: 900,
      alignment: blockEmbedAlignment(node),
      editable: _editable,
      onResize: (value) => _update({ChartBlockKeys.width: value}),
      onResizeHeight: (value) => _update({ChartBlockKeys.height: value}),
      child: _viewId.isEmpty
          ? Builder(
              builder: (context) => _EmptyFrame(
                palette: palette,
                onPick: () => _openPicker(context),
              ),
            )
          : _chart(),
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }

    return AppFlowyPopover(
      controller: _picker,
      onClose: _closePickerHold,
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth:
            math.max(0, math.min(400, MediaQuery.sizeOf(context).width - 16)),
        maxWidth:
            math.max(0, math.min(400, MediaQuery.sizeOf(context).width - 16)),
        maxHeight: 330,
      ),
      decorationColor: palette.surface,
      animationDuration:
          WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
      beginScaleFactor: 0.98,
      asBarrier: true,
      popupBuilder: (_) => SingleChildScrollView(
        primary: false,
        child: WorkspaceViewPickerMenu(
          contentKey: const ValueKey('chart-table-picker-menu'),
          title: LocaleKeys.charts_pickTable.tr(),
          searchHint: LocaleKeys.search_label.tr(),
          emptyMessage: LocaleKeys.charts_noTables.tr(),
          errorMessage:
              LocaleKeys.document_mobilePageSelector_failedToLoad.tr(),
          selectedViewId: _viewId.isEmpty ? null : _viewId,
          viewFilter: isDatabaseTable,
          leadingBuilder: (context, view, palette) =>
              WorkspaceItemIcon.fromView(
            view: view,
            size: 17,
            color: palette.textSecondary,
          ),
          onSelected: _selectTable,
        ),
      ),
      child: child,
    );
  }

  Widget _chart() => ChartStage(
        key: ValueKey(_viewId),
        viewId: _viewId,
        spec: _spec,
        compactToolbar: true,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        onSpecChanged: (spec) => _update({ChartBlockKeys.spec: spec.toJson()}),
        trailing: [_pickButton()],
      );

  Widget _pickButton() => Builder(
        key: const ValueKey('chart-pick-table-slot'),
        builder: (context) => _PlainButton(
          key: const ValueKey('chart-pick-table'),
          icon: Icons.table_chart_rounded,
          label: LocaleKeys.charts_pickTable.tr(),
          onTap: () => _openPicker(context),
        ),
      );

  Future<void> _selectTable(ViewPB picked) async {
    _picker.close();
    _closePickerHold();
    await _update({
      ChartBlockKeys.viewId: picked.id,
      // A new table means the old columns are gone, so the reading starts over.
      ChartBlockKeys.spec: const ChartSpec().toJson(),
    });
  }
}

/// What the block shows before a table has been chosen.
class _EmptyFrame extends StatelessWidget {
  const _EmptyFrame({required this.palette, required this.onPick});

  final ChartPalette palette;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          primary: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkspaceGlyph(
                Icons.insert_chart_outlined_rounded,
                size: 26,
                color: palette.label,
              ),
              const SizedBox(height: 12),
              Text(
                LocaleKeys.charts_chooseTable.tr(),
                style: palette.text(
                  size: 13.5,
                  color: palette.strongLabel,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                LocaleKeys.charts_chooseTableHint.tr(),
                style: palette.text(size: 12, height: 1.4),
              ),
              const SizedBox(height: 16),
              _PlainButton(
                icon: Icons.table_chart_rounded,
                label: LocaleKeys.charts_pickTable.tr(),
                onTap: onPick,
                filled: true,
              ),
            ],
          ),
        ),
      );
}

class _PlainButton extends StatelessWidget {
  const _PlainButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = chartPaletteOf(context);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        minimumSize: const Size(0, ChartMetrics.chipHeight),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: palette.strongLabel,
        backgroundColor:
            filled ? palette.chip : palette.chip.withValues(alpha: 0),
        overlayColor: palette.chipHover,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        ),
      ).copyWith(
        animationDuration:
            WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph(icon, size: 16, color: palette.label),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: palette.text(size: 11.5, color: palette.strongLabel),
            ),
          ),
        ],
      ),
    );
  }
}
