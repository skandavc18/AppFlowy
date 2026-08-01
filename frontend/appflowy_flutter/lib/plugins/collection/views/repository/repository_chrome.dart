import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_state.dart';
import 'package:appflowy/workspace/application/collections/repository/source_outline.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

export 'package:appflowy/plugins/collection/views/repository/repository_style.dart';

String repoSortLabel(RepoSort sort) => switch (sort) {
      RepoSort.name => LocaleKeys.collections_repository_sorts_name.tr(),
      RepoSort.modified =>
        LocaleKeys.collections_repository_sorts_modified.tr(),
      RepoSort.size => LocaleKeys.collections_repository_sorts_size.tr(),
      RepoSort.type => LocaleKeys.collections_repository_sorts_type.tr(),
    };

String repoGraphLayoutLabel(RepoGraphLayout layout) => switch (layout) {
      RepoGraphLayout.force =>
        LocaleKeys.collections_repository_layouts_force.tr(),
      RepoGraphLayout.radial =>
        LocaleKeys.collections_repository_layouts_radial.tr(),
      RepoGraphLayout.layered =>
        LocaleKeys.collections_repository_layouts_layered.tr(),
    };

String symbolKindLabel(SymbolKind kind) => switch (kind) {
      SymbolKind.module => LocaleKeys.collections_repository_kinds_module.tr(),
      SymbolKind.classType =>
        LocaleKeys.collections_repository_kinds_classType.tr(),
      SymbolKind.interfaceType =>
        LocaleKeys.collections_repository_kinds_interfaceType.tr(),
      SymbolKind.enumType =>
        LocaleKeys.collections_repository_kinds_enumType.tr(),
      SymbolKind.structType =>
        LocaleKeys.collections_repository_kinds_structType.tr(),
      SymbolKind.traitType =>
        LocaleKeys.collections_repository_kinds_traitType.tr(),
      SymbolKind.mixinType =>
        LocaleKeys.collections_repository_kinds_mixinType.tr(),
      SymbolKind.extensionType =>
        LocaleKeys.collections_repository_kinds_extensionType.tr(),
      SymbolKind.typeAlias =>
        LocaleKeys.collections_repository_kinds_typeAlias.tr(),
      SymbolKind.function =>
        LocaleKeys.collections_repository_kinds_function.tr(),
      SymbolKind.constant =>
        LocaleKeys.collections_repository_kinds_constant.tr(),
      SymbolKind.property =>
        LocaleKeys.collections_repository_kinds_property.tr(),
      SymbolKind.heading =>
        LocaleKeys.collections_repository_kinds_heading.tr(),
      SymbolKind.section =>
        LocaleKeys.collections_repository_kinds_section.tr(),
    };

IconData symbolKindIcon(SymbolKind kind) => switch (kind) {
      SymbolKind.module => Icons.workspaces_rounded,
      SymbolKind.classType => Icons.category_rounded,
      SymbolKind.interfaceType => Icons.polyline_rounded,
      SymbolKind.enumType => Icons.format_list_bulleted_rounded,
      SymbolKind.structType => Icons.view_module_rounded,
      SymbolKind.traitType => Icons.extension_rounded,
      SymbolKind.mixinType => Icons.blender_rounded,
      SymbolKind.extensionType => Icons.add_box_rounded,
      SymbolKind.typeAlias => Icons.label_rounded,
      SymbolKind.function => Icons.functions_rounded,
      SymbolKind.constant => Icons.lock_rounded,
      SymbolKind.property => Icons.tag_rounded,
      SymbolKind.heading => Icons.title_rounded,
      SymbolKind.section => Icons.segment_rounded,
    };

/// A stable hue per declaration kind, so an outline is scannable by shape and
/// colour rather than by reading every label.
Color symbolKindColor(SymbolKind kind, RepoTheme theme) => switch (kind) {
      SymbolKind.classType || SymbolKind.structType => const Color(0xFFEAB308),
      SymbolKind.interfaceType ||
      SymbolKind.traitType =>
        const Color(0xFF14B8A6),
      SymbolKind.enumType => const Color(0xFFF97316),
      SymbolKind.mixinType ||
      SymbolKind.extensionType =>
        const Color(0xFFA855F7),
      SymbolKind.function => const Color(0xFF8B5CF6),
      SymbolKind.constant => const Color(0xFF0EA5E9),
      SymbolKind.typeAlias => const Color(0xFF64748B),
      SymbolKind.module => const Color(0xFF3B82F6),
      SymbolKind.property ||
      SymbolKind.heading ||
      SymbolKind.section =>
        theme.textSoft,
    };

String repoByteLabel(int bytes) {
  if (bytes <= 0) {
    return '—';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = ['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}

String repoCountLabel(int count, String oneKey, String manyKey) =>
    count == 1 ? oneKey.tr() : manyKey.tr(args: ['$count']);

String repoGroupedNumber(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

/// The chrome every repository view wears: one quiet strip above the project.
class RepoScaffold extends StatelessWidget {
  const RepoScaffold({
    super.key,
    required this.controller,
    required this.palette,
    required this.child,
    this.leading = const <Widget>[],
    this.trailing = const <Widget>[],
    this.padded = true,
    this.showStats = true,
  });

  final RepositoryController controller;
  final CollectionPalette palette;
  final Widget child;
  final List<Widget> leading;
  final List<Widget> trailing;
  final bool padded;
  final bool showStats;

  @override
  Widget build(BuildContext context) {
    final theme = repoThemeOf(context, palette);
    return ColoredBox(
      color: theme.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RepoToolbar(
            theme: theme,
            controller: controller,
            leading: leading,
            trailing: trailing,
            showStats: showStats,
          ),
          Expanded(
            child: Padding(
              padding: padded
                  ? const EdgeInsets.fromLTRB(
                      RepoMetrics.gutter,
                      RepoMetrics.space4,
                      RepoMetrics.gutter,
                      RepoMetrics.space6,
                    )
                  : EdgeInsets.zero,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepoToolbar extends StatelessWidget {
  const _RepoToolbar({
    required this.theme,
    required this.controller,
    required this.leading,
    required this.trailing,
    required this.showStats,
  });

  final RepoTheme theme;
  final RepositoryController controller;
  final List<Widget> leading;
  final List<Widget> trailing;
  final bool showStats;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;
    final primary = stats.languages.isEmpty ? null : stats.languages.first;
    return SizedBox(
      height: RepoMetrics.toolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RepoMetrics.gutter),
        child: Row(
          children: [
            if (showStats) ...[
              if (controller.isAnalysing)
                _AnalysingMeta(theme: theme, controller: controller)
              else ...[
                if (primary != null) ...[
                  RepoMeta(
                    theme: theme,
                    label: '${primary.label} ${primary.percent}%',
                    dotColor: primary.color,
                    strong: true,
                  ),
                  RepoMetaDot(theme: theme),
                ],
                RepoMeta(
                  theme: theme,
                  label: repoCountLabel(
                    stats.fileCount,
                    LocaleKeys.collections_repository_oneFile,
                    LocaleKeys.collections_repository_fileCount,
                  ),
                ),
                if (stats.lineCount > 0) ...[
                  RepoMetaDot(theme: theme),
                  RepoMeta(
                    theme: theme,
                    label: LocaleKeys.collections_repository_lineCount
                        .tr(args: [repoGroupedNumber(stats.lineCount)]),
                  ),
                ],
              ],
              const SizedBox(width: RepoMetrics.space6),
            ],
            ...leading,
            const Spacer(),
            ...trailing,
          ],
        ),
      ),
    );
  }
}

class _AnalysingMeta extends StatelessWidget {
  const _AnalysingMeta({required this.theme, required this.controller});

  final RepoTheme theme;
  final RepositoryController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            value: controller.analysisProgress == 0
                ? null
                : controller.analysisProgress,
            color: theme.accent,
            backgroundColor: theme.accent.withValues(alpha: 0.18),
          ),
        ),
        const SizedBox(width: RepoMetrics.space2),
        Text(
          LocaleKeys.collections_repository_analysing.tr(
            args: ['${(controller.analysisProgress * 100).round()}'],
          ),
          style: theme.meta,
        ),
      ],
    );
  }
}

/// The listing controls every repository view shares, grouped into one pill.
Widget repoViewControls({
  required BuildContext context,
  required RepositoryController controller,
  required RepoTheme theme,
  bool showSort = true,
}) =>
    RepoActionGroup(
      theme: theme,
      children: [
        if (showSort)
          RepoAnchored(
            builder: (anchor, open) => RepoAction(
              key: anchor,
              theme: theme,
              icon: Icons.swap_vert_rounded,
              tooltip: LocaleKeys.collections_repository_sort.tr(),
              label: repoSortLabel(controller.settings.sort),
              trailingIcon: Icons.expand_more_rounded,
              onPressed: () => open((position) async {
                final choice = await showAppMenu<RepoSort>(
                  context: context,
                  globalPosition: position,
                  entries: [
                    for (final sort in RepoSort.values)
                      AppMenuItem(
                        label: repoSortLabel(sort),
                        value: sort,
                        selected: sort == controller.settings.sort,
                      ),
                  ],
                );
                if (choice != null) {
                  controller.updateSettings(
                    controller.settings.copyWith(sort: choice),
                  );
                }
              }),
            ),
          ),
        RepoAction(
          theme: theme,
          icon: controller.settings.showHidden
              ? Icons.visibility_rounded
              : Icons.visibility_off_rounded,
          tooltip: LocaleKeys.collections_repository_showHidden.tr(),
          selected: controller.settings.showHidden,
          onPressed: () => controller.updateSettings(
            controller.settings
                .copyWith(showHidden: !controller.settings.showHidden),
          ),
        ),
        RepoAction(
          theme: theme,
          icon: Icons.inventory_2_rounded,
          tooltip: LocaleKeys.collections_repository_showIgnored.tr(),
          selected: controller.settings.showIgnored,
          onPressed: () => controller.updateSettings(
            controller.settings
                .copyWith(showIgnored: !controller.settings.showIgnored),
          ),
        ),
      ],
    );

/// Opens a menu underneath whatever control asked for it.
class RepoAnchored extends StatelessWidget {
  const RepoAnchored({super.key, required this.builder});

  final Widget Function(GlobalKey anchor, void Function(ValueChanged<Offset>))
      builder;

  @override
  Widget build(BuildContext context) {
    final anchor = GlobalKey();
    return Builder(
      builder: (context) => builder(anchor, (open) {
        final box = anchor.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) {
          return;
        }
        open(box.localToGlobal(Offset(0, box.size.height + 6)));
      }),
    );
  }
}

/// The bar that says what a repository is written in.
class RepoLanguageBar extends StatelessWidget {
  const RepoLanguageBar({
    super.key,
    required this.shares,
    required this.theme,
    this.height = 6,
  });

  final List<RepoLanguageShare> shares;
  final RepoTheme theme;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (shares.isEmpty) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var index = 0; index < shares.length; index++) ...[
              if (index > 0)
                SizedBox(width: 1.5, child: ColoredBox(color: theme.panel)),
              Expanded(
                flex: (shares[index].fraction * 1000).round().clamp(1, 1000),
                child: ColoredBox(color: shares[index].color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RepoLanguageLegend extends StatelessWidget {
  const RepoLanguageLegend({
    super.key,
    required this.shares,
    required this.theme,
  });

  final List<RepoLanguageShare> shares;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: RepoMetrics.space4,
      runSpacing: RepoMetrics.space2,
      children: [
        for (final share in shares.take(8))
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: share.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                share.label,
                style: theme.face(
                  fontSize: 11.5,
                  color: theme.textBody,
                  axis: 580,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${share.percent}%',
                style: theme.metaFaint.copyWith(fontSize: 11.5),
              ),
            ],
          ),
      ],
    );
  }
}
