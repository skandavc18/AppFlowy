import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
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

  @override
  void dispose() {
    _picker.close();
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
      alignment: Alignment.centerLeft,
      editable: _editable,
      onResize: (value) => _update({ChartBlockKeys.width: value}),
      onResizeHeight: (value) => _update({ChartBlockKeys.height: value}),
      child: _viewId.isEmpty
          ? _EmptyFrame(palette: palette, onPick: _picker.show)
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
      triggerActions: PopoverTriggerFlags.none,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      margin: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: 400,
        maxWidth: 400,
        maxHeight: 330,
      ),
      animationDuration: const Duration(milliseconds: 140),
      beginScaleFactor: 0.98,
      asBarrier: true,
      popupBuilder: (_) => WorkspaceViewPickerMenu(
        contentKey: const ValueKey('chart-table-picker-menu'),
        title: LocaleKeys.charts_pickTable.tr(),
        searchHint: LocaleKeys.search_label.tr(),
        emptyMessage: LocaleKeys.charts_noTables.tr(),
        errorMessage: LocaleKeys.document_mobilePageSelector_failedToLoad.tr(),
        selectedViewId: _viewId.isEmpty ? null : _viewId,
        viewFilter: isDatabaseTable,
        leadingBuilder: (context, view, palette) => WorkspaceItemIcon.fromView(
          view: view,
          size: 17,
          color: palette.textSecondary,
        ),
        onSelected: _selectTable,
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

  Widget _pickButton() => _PlainButton(
        icon: Icons.table_chart_rounded,
        label: LocaleKeys.charts_pickTable.tr(),
        onTap: _picker.show,
      );

  Future<void> _selectTable(ViewPB picked) async {
    _picker.close();
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
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(ChartMetrics.cardRadius),
          border: Border.all(color: palette.border),
          boxShadow: chartCardShadow(palette),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
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

class _PlainButton extends StatefulWidget {
  const _PlainButton({
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
  State<_PlainButton> createState() => _PlainButtonState();
}

class _PlainButtonState extends State<_PlainButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: onSurface.withValues(
              alpha: widget.filled
                  ? (_hovered ? 0.13 : 0.09)
                  : (_hovered ? 0.09 : 0.05),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: onSurface.withValues(alpha: 0.62),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style:
                    (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                  fontSize: 11.5,
                  color: onSurface.withValues(alpha: 0.86),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
