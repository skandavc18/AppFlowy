import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_host.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DashboardWidgetBlockKeys {
  const DashboardWidgetBlockKeys._();

  static const String type = 'dashboard_widget';

  /// The widget itself, exactly as a dashboard stores it.
  static const String spec = 'spec';

  /// How tall and how wide the widget stands in the page.
  static const String height = 'height';
  static const String width = 'width';
}

/// A block holding [spec], ready to go into a page.
Node dashboardWidgetNode(DashboardWidgetSpec spec) => Node(
      type: DashboardWidgetBlockKeys.type,
      attributes: {DashboardWidgetBlockKeys.spec: spec.toJson()},
    );

/// The size a widget is first given in a page: what it would take on a
/// dashboard, on the dashboard's own grid at a page's measure.
Size defaultDashboardWidgetBlockSize(DashboardWidgetSpec spec) {
  const density = DashboardDensity.comfortable;
  const measure = 720.0;
  const columns = 12;
  final column = (measure - (columns - 1) * density.gap) / columns;
  final span = spec.placement.columnSpan.clamp(1, columns);
  final rows = spec.placement.rowSpan < 1 ? 1 : spec.placement.rowSpan;
  return Size(
    (span * column + (span - 1) * density.gap).clamp(280.0, measure),
    rows * density.rowHeight + (rows - 1) * density.gap,
  );
}

/// Any dashboard widget, placed in a page.
///
/// Pages and dashboards offer the same things. Where a page has no block of
/// its own for a widget — a clock, the weather, a metric — this block hosts
/// the dashboard widget itself: the same builder, the same settings, kept in
/// the block's attributes so it travels, copies and undoes with the page.
class DashboardWidgetBlockComponentBuilder extends BlockComponentBuilder {
  DashboardWidgetBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return DashboardWidgetBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class DashboardWidgetBlockComponent extends BlockComponentStatefulWidget {
  const DashboardWidgetBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<DashboardWidgetBlockComponent> createState() =>
      _DashboardWidgetBlockComponentState();
}

class _DashboardWidgetBlockComponentState
    extends State<DashboardWidgetBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  Object? _parsedFrom;
  DashboardWidgetSpec? _parsed;

  /// Read once per stored value: typing into a hosted note rewrites the
  /// attribute, and parsing it again for every other rebuild is waste.
  DashboardWidgetSpec? get _spec {
    final stored = node.attributes[DashboardWidgetBlockKeys.spec];
    if (!identical(stored, _parsedFrom)) {
      _parsedFrom = stored;
      _parsed = stored is Map
          ? DashboardWidgetSpec.fromJson(Map<String, Object?>.from(stored))
          : null;
    }
    return _parsed;
  }

  EditorState get _editorState => context.read<EditorState>();

  double? _dimension(String key) {
    final stored = node.attributes[key];
    return stored is num ? stored.toDouble() : null;
  }

  Future<void> _update(Map<String, Object?> attributes) {
    final transaction = _editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    return _editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _spec;
    final editable = _editorState.editable;
    Widget child;
    if (spec == null) {
      child = const SizedBox.shrink();
    } else {
      final fallback = defaultDashboardWidgetBlockSize(spec);
      final definition = DashboardWidgetRegistry.definitionFor(spec.type);
      child = ResizableMedia(
        width: _dimension(DashboardWidgetBlockKeys.width) ?? fallback.width,
        minWidth: 200,
        height: _dimension(DashboardWidgetBlockKeys.height) ?? fallback.height,
        minHeight: definition == null ? 96 : 72,
        maxHeight: 1600,
        alignment: blockEmbedAlignment(node),
        editable: editable,
        onResize: (value) => _update({DashboardWidgetBlockKeys.width: value}),
        onResizeHeight: (value) =>
            _update({DashboardWidgetBlockKeys.height: value}),
        child: DashboardWidgetHost(
          key: ValueKey('page-widget-host-${node.id}'),
          spec: spec,
          editable: editable,
          keyPrefix: 'page-widget',
          onChanged: (next) =>
              _update({DashboardWidgetBlockKeys.spec: next.toJson()}),
        ),
      );
    }

    child = Padding(padding: padding, child: child);
    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }
    return child;
  }
}
