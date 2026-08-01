import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_context_menu.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_host.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_views.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_graph_layout.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// How the repository's files depend on one another, and what it pulls in
/// from outside.
class RepositoryGraphView extends StatefulWidget {
  const RepositoryGraphView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<RepositoryGraphView> createState() => _RepositoryGraphViewState();
}

class _RepositoryGraphViewState extends State<RepositoryGraphView> {
  String? selectedPath;
  String? hoveredPath;

  @override
  Widget build(BuildContext context) {
    return RepositoryHost(
      collection: widget.collection,
      readsSource: true,
      builder: (context, controller, palette) {
        final theme = repoThemeOf(context, palette);
        final graph = controller.graph;
        return RepoScaffold(
          controller: controller,
          palette: palette,
          padded: false,
          leading: [
            RepoActionGroup(
              theme: theme,
              children: [
                RepoAnchored(
                  builder: (anchor, open) => RepoAction(
                    key: anchor,
                    theme: theme,
                    icon: Icons.hub_rounded,
                    tooltip: LocaleKeys.collections_repository_layout.tr(),
                    label:
                        repoGraphLayoutLabel(controller.settings.graphLayout),
                    trailingIcon: Icons.expand_more_rounded,
                    onPressed: () => open((position) async {
                      final choice = await showAppMenu<RepoGraphLayout>(
                        context: context,
                        globalPosition: position,
                        entries: [
                          for (final layout in RepoGraphLayout.values)
                            AppMenuItem(
                              label: repoGraphLayoutLabel(layout),
                              value: layout,
                              selected:
                                  layout == controller.settings.graphLayout,
                            ),
                        ],
                      );
                      if (choice != null) {
                        controller.updateSettings(
                          controller.settings.copyWith(graphLayout: choice),
                        );
                      }
                    }),
                  ),
                ),
                RepoAction(
                  theme: theme,
                  icon: Icons.inventory_rounded,
                  tooltip: LocaleKeys.collections_repository_showExternal.tr(),
                  selected: controller.settings.showExternalDependencies,
                  onPressed: () => controller.updateSettings(
                    controller.settings.copyWith(
                      showExternalDependencies:
                          !controller.settings.showExternalDependencies,
                    ),
                  ),
                ),
              ],
            ),
          ],
          trailing: [
            RepoMeta(
              theme: theme,
              label: LocaleKeys.collections_repository_internalEdges
                  .tr(args: ['${graph.edges.length}']),
            ),
          ],
          child: graph.isEmpty
              ? RepoEmptyState(
                  theme: theme,
                  icon: controller.isAnalysing
                      ? Icons.hourglass_top_rounded
                      : Icons.hub_rounded,
                  title: controller.isAnalysing
                      ? LocaleKeys.collections_repository_readingSource.tr()
                      : LocaleKeys.collections_repository_noDependencies.tr(),
                  description: LocaleKeys
                      .collections_repository_noDependenciesDescription
                      .tr(),
                )
              : _GraphBody(
                  collection: widget.collection,
                  controller: controller,
                  theme: theme,
                  selectedPath: selectedPath,
                  hoveredPath: hoveredPath,
                  onSelect: (path) => setState(() => selectedPath = path),
                  onHover: (path) => setState(() => hoveredPath = path),
                ),
        );
      },
    );
  }
}

class _GraphBody extends StatelessWidget {
  const _GraphBody({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.selectedPath,
    required this.hoveredPath,
    required this.onSelect,
    required this.onHover,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final String? selectedPath;
  final String? hoveredPath;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String?> onHover;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 940;
        final plot = RepoPanel(
          theme: theme,
          child: _GraphPlot(
            collection: collection,
            controller: controller,
            theme: theme,
            selectedPath: selectedPath,
            hoveredPath: hoveredPath,
            onSelect: onSelect,
            onHover: onHover,
          ),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            RepoMetrics.gutter,
            RepoMetrics.space2,
            RepoMetrics.gutter,
            RepoMetrics.space4,
          ),
          child: showRail
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: plot),
                    const RepoGap(),
                    SizedBox(
                      width: 296,
                      child: RepoPanel(
                        theme: theme,
                        child: _GraphRail(
                          collection: collection,
                          controller: controller,
                          theme: theme,
                          selectedPath: selectedPath,
                          onSelect: onSelect,
                        ),
                      ),
                    ),
                  ],
                )
              : plot,
        );
      },
    );
  }
}

class _GraphPlot extends StatefulWidget {
  const _GraphPlot({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.selectedPath,
    required this.hoveredPath,
    required this.onSelect,
    required this.onHover,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final String? selectedPath;
  final String? hoveredPath;
  final ValueChanged<String?> onSelect;
  final ValueChanged<String?> onHover;

  @override
  State<_GraphPlot> createState() => _GraphPlotState();
}

class _GraphPlotState extends State<_GraphPlot> {
  RepoGraphLayoutResult layout = RepoGraphLayoutResult.empty;
  int signature = 0;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = widget.theme;
    final graph = controller.graph;
    return Padding(
      padding: const EdgeInsets.all(RepoMetrics.space4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final result = _layoutFor(graph, size);
          final focus = widget.hoveredPath ?? widget.selectedPath;
          return MouseRegion(
            onHover: (event) =>
                widget.onHover(_hit(result, event.localPosition)),
            onExit: (_) => widget.onHover(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  widget.onSelect(_hit(result, details.localPosition)),
              onSecondaryTapDown: (details) {
                final path = _hit(result, details.localPosition);
                final entry =
                    path == null ? null : controller.entryForPath(path);
                if (entry == null) {
                  showRepoBackgroundMenu(
                    context: context,
                    collection: widget.collection,
                    controller: controller,
                    position: details.globalPosition,
                  );
                  return;
                }
                widget.onSelect(path);
                showRepoEntryMenu(
                  context: context,
                  collection: widget.collection,
                  controller: controller,
                  entry: entry,
                  position: details.globalPosition,
                );
              },
              child: CustomPaint(
                size: size,
                painter: _GraphPainter(
                  result: result,
                  graph: graph,
                  controller: controller,
                  theme: theme,
                  focus: focus,
                  selected: widget.selectedPath,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// The layout is a force simulation over every pair of files; running it
  /// again on a hover would drop frames, so it is only redone when the graph,
  /// the arrangement or the box actually changes.
  RepoGraphLayoutResult _layoutFor(RepoDependencyGraph graph, Size size) {
    final next = Object.hashAll([
      widget.controller.settings.graphLayout,
      size.width.round(),
      size.height.round(),
      graph.edges.length,
      ...graph.nodes.keys,
    ]);
    if (next != signature) {
      signature = next;
      layout = layoutRepoGraph(
        degrees: {
          for (final node in graph.nodes.entries) node.key: node.value.degree,
        },
        edges: graph.edges,
        layout: widget.controller.settings.graphLayout,
        size: size,
      );
    }
    return layout;
  }

  String? _hit(RepoGraphLayoutResult result, Offset position) {
    String? best;
    var bestDistance = double.infinity;
    for (final node in result.nodes.values) {
      final distance = (node.position - position).distance;
      if (distance <= node.radius + 10 && distance < bestDistance) {
        best = node.path;
        bestDistance = distance;
      }
    }
    return best;
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.result,
    required this.graph,
    required this.controller,
    required this.theme,
    required this.focus,
    required this.selected,
  });

  final RepoGraphLayoutResult result;
  final RepoDependencyGraph graph;
  final RepositoryController controller;
  final RepoTheme theme;
  final String? focus;
  final String? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final related = <String>{};
    if (focus != null) {
      related.add(focus!);
      final node = graph.nodes[focus];
      if (node != null) {
        related
          ..addAll(node.dependsOn)
          ..addAll(node.dependedOnBy);
      }
    }

    final dim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 0.9
      ..color = theme.textSoft.withValues(alpha: focus == null ? 0.2 : 0.06);
    final lit = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5
      ..color = theme.accent.withValues(alpha: 0.7);

    for (final edge in result.edges) {
      final from = result.nodes[edge.$1];
      final to = result.nodes[edge.$2];
      if (from == null || to == null) {
        continue;
      }
      final highlighted =
          focus != null && (edge.$1 == focus || edge.$2 == focus);
      canvas.drawPath(
        _curve(from.position, to.position),
        highlighted ? lit : dim,
      );
    }

    for (final node in result.nodes.values) {
      final entry = controller.entryForPath(node.path);
      final base = entry?.language?.color ?? theme.textSoft;
      final faded = focus != null && !related.contains(node.path);
      // A halo in the canvas colour keeps a node readable where edges cross.
      canvas.drawCircle(
        node.position,
        node.radius + 2.5,
        Paint()..color = theme.canvas.withValues(alpha: faded ? 0.5 : 0.95),
      );
      canvas.drawCircle(
        node.position,
        node.radius,
        Paint()..color = base.withValues(alpha: faded ? 0.24 : 0.95),
      );
      if (node.path == selected) {
        canvas.drawCircle(
          node.position,
          node.radius + 5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = theme.accent,
        );
      }
    }

    // Only the file under the pointer is named: a hundred labels at once is
    // the reason most dependency graphs are unreadable.
    final label = focus;
    if (label != null) {
      final node = result.nodes[label];
      if (node != null) {
        _paintLabel(canvas, size, node, label.split('/').last);
      }
    }
  }

  Path _curve(Offset from, Offset to) {
    final middle = (from + to) / 2;
    final normal = Offset(-(to - from).dy, (to - from).dx);
    final length = normal.distance;
    final bow = length == 0 ? Offset.zero : normal / length * (length * 0.08);
    return Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(
        middle.dx + bow.dx,
        middle.dy + bow.dy,
        to.dx,
        to.dy,
      );
  }

  void _paintLabel(
    Canvas canvas,
    Size size,
    RepoGraphNode node,
    String text,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: theme.rowLabelStrong),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: 220);
    final origin = Offset(
      (node.position.dx - painter.width / 2)
          .clamp(6.0, math.max(size.width - painter.width - 6, 6.0)),
      (node.position.dy - node.radius - painter.height - 10)
          .clamp(6.0, math.max(size.height - painter.height - 6, 6.0)),
    );
    final box = Rect.fromLTWH(
      origin.dx - 8,
      origin.dy - 5,
      painter.width + 16,
      painter.height + 10,
    );
    final rounded = RRect.fromRectAndRadius(box, const Radius.circular(8));
    for (final shadow in theme.shadows) {
      canvas.drawRRect(
        rounded.shift(shadow.offset),
        Paint()
          ..color = shadow.color
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, shadow.blurRadius / 2),
      );
    }
    canvas.drawRRect(rounded, Paint()..color = theme.raised);
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.7
        ..color = theme.hairlineColor,
    );
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_GraphPainter oldDelegate) =>
      oldDelegate.result != result ||
      oldDelegate.focus != focus ||
      oldDelegate.selected != selected ||
      oldDelegate.theme != theme;
}

/// What the selected file depends on, and what the project pulls in.
class _GraphRail extends StatelessWidget {
  const _GraphRail({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.selectedPath,
    required this.onSelect,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final String? selectedPath;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final node =
        selectedPath == null ? null : controller.graph.nodes[selectedPath];
    return RepoScrollArea(
      theme: theme,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          if (node != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    node.entry.path,
                    style: theme.rowLabelStrong,
                  ),
                ),
                RepoActionGroup(
                  theme: theme,
                  children: [
                    RepoAction(
                      theme: theme,
                      icon: Icons.account_tree_rounded,
                      tooltip:
                          LocaleKeys.collections_repository_openInTree.tr(),
                      onPressed: () {
                        controller
                          ..expandTo(node.entry.path)
                          ..openFile(node.entry.id)
                          ..flush();
                        collection.onOpenView(RepositoryViewIds.tree);
                      },
                    ),
                    RepoAction(
                      theme: theme,
                      icon: Icons.open_in_new_rounded,
                      tooltip: LocaleKeys.collections_repository_openInWorkspace
                          .tr(),
                      onPressed: () => collection.onOpen(node.entry.view),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _RailSection(
              theme: theme,
              title: LocaleKeys.collections_repository_dependsOn.tr(),
              paths: node.dependsOn.toList()..sort(),
              onSelect: onSelect,
            ),
            _RailSection(
              theme: theme,
              title: LocaleKeys.collections_repository_dependedOnBy.tr(),
              paths: node.dependedOnBy.toList()..sort(),
              onSelect: onSelect,
            ),
            if (node.packages.isNotEmpty)
              _RailSection(
                theme: theme,
                title: LocaleKeys.collections_repository_externalPackages.tr(),
                paths: node.packages.toList()..sort(),
                onSelect: null,
              ),
            Container(height: 0.7, color: theme.separator),
            const SizedBox(height: 16),
          ],
          if (controller.settings.showExternalDependencies) ...[
            Text(
              LocaleKeys.collections_repository_externalPackages.tr(),
              style: theme.sectionLabel,
            ),
            const SizedBox(height: 10),
            if (controller.graph.packages.isEmpty)
              Text(
                LocaleKeys.collections_repository_noExternalPackages.tr(),
                style: theme.meta,
              )
            else
              for (final package in controller.graph.packages.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3.5),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_rounded,
                        size: 13,
                        color: theme.textFaint,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          package.key,
                          overflow: TextOverflow.ellipsis,
                          style: theme.rowLabel,
                        ),
                      ),
                      Text(
                        LocaleKeys.collections_repository_usedByCount
                            .tr(args: ['${package.value}']),
                        style: theme.metaFaint.copyWith(fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _RailSection extends StatelessWidget {
  const _RailSection({
    required this.theme,
    required this.title,
    required this.paths,
    required this.onSelect,
  });

  final RepoTheme theme;
  final String title;
  final List<String> paths;
  final ValueChanged<String?>? onSelect;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.sectionLabel),
          const SizedBox(height: 7),
          for (final path in paths)
            RepoRow(
              theme: theme,
              height: 24,
              inset: 0,
              padding: 6,
              onTap: onSelect == null ? null : () => onSelect!(path),
              builder: (context, hovered) => Text(
                path,
                overflow: TextOverflow.ellipsis,
                style: theme.face(
                  fontSize: 11.5,
                  color: hovered ? theme.textStrong : theme.textBody,
                  axis: 520,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
