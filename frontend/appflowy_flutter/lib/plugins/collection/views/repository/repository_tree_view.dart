import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_context_menu.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_file_stage.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_host.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_source_cache.dart';
import 'package:appflowy/workspace/application/collections/repository/source_outline.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The whole project at once: the tree on the left, the file in the middle,
/// its declarations on the right.
class RepositoryTreeView extends StatefulWidget {
  const RepositoryTreeView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<RepositoryTreeView> createState() => _RepositoryTreeViewState();
}

class _RepositoryTreeViewState extends State<RepositoryTreeView> {
  final TextEditingController filter = TextEditingController();

  /// Files being written to rather than read, by view id. Source opens ready
  /// to type; a rendered kind has to be asked for explicitly.
  final Set<String> editing = {};

  @override
  void dispose() {
    filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryHost(
      collection: widget.collection,
      builder: (context, controller, palette) {
        final theme = repoThemeOf(context, palette);
        if (controller.isEmpty) {
          return RepoScaffold(
            controller: controller,
            palette: palette,
            showStats: false,
            trailing: [
              RepoAddButton(
                theme: theme,
                collection: widget.collection,
                controller: controller,
                parentPath: '',
                primary: true,
              ),
            ],
            child: RepoEmptyState(
              theme: theme,
              icon: Icons.account_tree_rounded,
              title: LocaleKeys.collections_repository_emptyTitle.tr(),
              description:
                  LocaleKeys.collections_repository_emptyDescription.tr(),
            ),
          );
        }
        final active = controller.state.activeFileId == null
            ? null
            : controller.entryForId(controller.state.activeFileId!);
        if (active != null) {
          controller.ensureAnalysis(active);
        }
        return RepoScaffold(
          controller: controller,
          palette: palette,
          padded: false,
          leading: [
            repoViewControls(
              context: context,
              controller: controller,
              theme: theme,
            ),
          ],
          trailing: [
            RepoAction(
              theme: theme,
              icon: Icons.segment_rounded,
              tooltip: LocaleKeys.collections_repository_showOutline.tr(),
              selected: controller.settings.showOutline,
              onPressed: () => controller.updateSettings(
                controller.settings
                    .copyWith(showOutline: !controller.settings.showOutline),
              ),
            ),
            const SizedBox(width: 8),
            RepoAddButton(
              theme: theme,
              collection: widget.collection,
              controller: controller,
              parentPath: active?.parentPath ?? '',
              primary: true,
            ),
          ],
          child: _TreeBody(
            collection: widget.collection,
            controller: controller,
            theme: theme,
            active: active,
            filter: filter,
            editing: editing,
            onFilterChanged: (_) => setState(() {}),
            onToggleEditing: (id) => setState(() {
              if (!editing.remove(id)) {
                editing.add(id);
              }
            }),
          ),
        );
      },
    );
  }
}

class _TreeBody extends StatelessWidget {
  const _TreeBody({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.active,
    required this.filter,
    required this.editing,
    required this.onFilterChanged,
    required this.onToggleEditing,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final RepoEntry? active;
  final TextEditingController filter;
  final Set<String> editing;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onToggleEditing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showOutline =
            controller.settings.showOutline && constraints.maxWidth >= 1100;
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            RepoMetrics.gutter,
            RepoMetrics.space2,
            RepoMetrics.gutter,
            RepoMetrics.space4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: RepoMetrics.paneWidth,
                child: RepoPanel(
                  theme: theme,
                  child: RepoTreePane(
                    collection: collection,
                    controller: controller,
                    theme: theme,
                    activeId: active?.id,
                    filterController: filter,
                    onFilterChanged: onFilterChanged,
                    onOpen: controller.openFile,
                  ),
                ),
              ),
              const RepoGap(),
              Expanded(
                child: RepoPanel(
                  theme: theme,
                  child: _TreeStage(
                    collection: collection,
                    controller: controller,
                    theme: theme,
                    entry: active,
                    editing: active != null && editing.contains(active!.id),
                    onToggleEditing: onToggleEditing,
                  ),
                ),
              ),
              if (showOutline) ...[
                const RepoGap(),
                SizedBox(
                  width: RepoMetrics.railWidth,
                  child: RepoPanel(
                    theme: theme,
                    child: _OutlinePane(
                      controller: controller,
                      theme: theme,
                      entry: active,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The repository's folders and files, indented and collapsible.
class RepoTreePane extends StatelessWidget {
  const RepoTreePane({
    super.key,
    required this.collection,
    required this.controller,
    required this.theme,
    required this.onOpen,
    this.activeId,
    this.filterController,
    this.onFilterChanged,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final ValueChanged<String> onOpen;
  final String? activeId;
  final TextEditingController? filterController;
  final ValueChanged<String>? onFilterChanged;

  @override
  Widget build(BuildContext context) {
    final query = filterController?.text.trim().toLowerCase() ?? '';
    final rows = _rows(query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (filterController != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
            child: RepoSearchField(
              theme: theme,
              controller: filterController!,
              hint: LocaleKeys.collections_repository_filterPlaceholder.tr(),
              onChanged: onFilterChanged ?? (_) {},
              width: double.infinity,
            ),
          ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapDown: (details) => showRepoBackgroundMenu(
              context: context,
              collection: collection,
              controller: controller,
              position: details.globalPosition,
            ),
            child: rows.isEmpty
                ? RepoEmptyState(
                    theme: theme,
                    icon: Icons.search_off_rounded,
                    title: LocaleKeys.collections_repository_noMatches.tr(),
                    description: LocaleKeys
                        .collections_repository_noMatchesDescription
                        .tr(),
                  )
                : RepoScrollArea(
                    theme: theme,
                    builder: (context, scrollController) => ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 16, top: 2),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final entry = rows[index];
                        return _TreeRow(
                          key: ValueKey('repo-tree-${entry.id}'),
                          entry: entry,
                          collection: collection,
                          controller: controller,
                          theme: theme,
                          expanded: controller.state.isExpanded(entry.path),
                          selected: entry.id == activeId,
                          onTap: () => entry.isFolder
                              ? controller.toggleExpanded(entry.path)
                              : onOpen(entry.id),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Only the entries whose folders are all open, so a collapsed branch costs
  /// nothing to keep in the list.
  List<RepoEntry> _rows(String query) {
    final rows = <RepoEntry>[];
    final closed = <String>{};
    final filtering = query.isNotEmpty;
    for (final entry in controller.entries) {
      final hidden = closed.any(
        (root) => entry.path == root || entry.path.startsWith('$root/'),
      );
      if (hidden) {
        continue;
      }
      if (entry.isFolder) {
        // A filter opens the whole tree: a match three folders down is no use
        // if the branch holding it is shut.
        if (!filtering && !controller.state.isExpanded(entry.path)) {
          closed.add(entry.path);
        }
        rows.add(entry);
        continue;
      }
      if (!filtering || entry.name.toLowerCase().contains(query)) {
        rows.add(entry);
      }
    }
    if (!filtering) {
      return rows;
    }
    // A folder with nothing left in it is noise once a filter is on.
    final live = <String>{};
    for (final entry in rows) {
      if (entry.isFolder) {
        continue;
      }
      for (var path = entry.parentPath;
          path.isNotEmpty;
          path = repoParentPath(path)) {
        live.add(path);
      }
    }
    return [
      for (final entry in rows)
        if (!entry.isFolder || live.contains(entry.path)) entry,
    ];
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    super.key,
    required this.entry,
    required this.collection,
    required this.controller,
    required this.theme,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final RepoEntry entry;
  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final glyph = repoGlyphFor(entry, theme, open: entry.isFolder && expanded);
    return RepoRow(
      theme: theme,
      height: RepoMetrics.treeRowHeight,
      padding: 5,
      selected: selected,
      showActiveBar: true,
      onTap: onTap,
      onSecondaryTap: (position) => showRepoEntryMenu(
        context: context,
        collection: collection,
        controller: controller,
        entry: entry,
        position: position,
        onOpen: entry.isFolder ? null : onTap,
      ),
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(left: entry.depth * RepoMetrics.indentWidth),
        child: Row(
          children: [
            SizedBox(
              width: RepoMetrics.chevronSlot,
              child: entry.isFolder
                  ? AnimatedRotation(
                      duration: RepoMetrics.expand,
                      curve: RepoMetrics.curve,
                      turns: expanded ? 0.25 : 0,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: RepoMetrics.chevronSize,
                        color: hovered || selected
                            ? theme.textBody
                            : theme.textFaint,
                      ),
                    )
                  : null,
            ),
            RepoGlyphIcon(
              glyph: glyph,
              emphasised: hovered || selected,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: RepoMetrics.hover,
                curve: RepoMetrics.curve,
                style: theme.face(
                  fontSize: 13,
                  color: selected
                      ? theme.textStrong
                      : hovered
                          ? theme.textStrong
                          : theme.textBody,
                  axis: selected ? RepoMetrics.strongWeightAxis : 545,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(entry.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TreeStage extends StatelessWidget {
  const _TreeStage({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.entry,
    required this.editing,
    required this.onToggleEditing,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final RepoEntry? entry;
  final bool editing;
  final ValueChanged<String> onToggleEditing;

  @override
  Widget build(BuildContext context) {
    final file = entry;
    if (file == null) {
      return RepoEmptyState(
        theme: theme,
        icon: Icons.description_rounded,
        title: LocaleKeys.collections_repository_selectFile.tr(),
        description:
            LocaleKeys.collections_repository_selectFileDescription.tr(),
      );
    }
    final analysis = controller.analysisFor(file);
    final writable = RepoFileStage.supportsEditing(file);
    final togglable = writable && RepoFileStage.needsSourceToggle(file);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StageHeader(
          theme: theme,
          entry: file,
          analysis: analysis,
          writable: writable,
          togglable: togglable,
          editing: editing,
          onToggleEditing: () => onToggleEditing(file.id),
          onOpenInWorkspace: () => collection.onOpen(file.view),
        ),
        if (analysis.truncated)
          _StageNotice(
            theme: theme,
            message: LocaleKeys.collections_repository_truncated.tr(),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: RepoMetrics.reveal,
            switchInCurve: RepoMetrics.curve,
            switchOutCurve: RepoMetrics.curve,
            child: RepoFileStage(
              key: ValueKey('repo-stage-${file.id}-$editing'),
              entry: file,
              theme: theme,
              editable: writable,
              editingSource: editing,
            ),
          ),
        ),
      ],
    );
  }
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({
    required this.theme,
    required this.entry,
    required this.analysis,
    required this.writable,
    required this.togglable,
    required this.editing,
    required this.onToggleEditing,
    required this.onOpenInWorkspace,
  });

  final RepoTheme theme;
  final RepoEntry entry;
  final RepoFileAnalysis analysis;
  final bool writable;
  final bool togglable;
  final bool editing;
  final VoidCallback onToggleEditing;
  final VoidCallback onOpenInWorkspace;

  @override
  Widget build(BuildContext context) {
    final size =
        analysis.byteSize > 0 ? analysis.byteSize : entry.byteSize ?? 0;
    final meta = <String>[
      if (entry.language != null) entry.language!.label,
      if (analysis.lineCount > 0)
        LocaleKeys.collections_repository_lineCount
            .tr(args: [repoGroupedNumber(analysis.lineCount)]),
      if (size > 0) repoByteLabel(size),
    ];
    final segments = entry.path.split('/');
    final glyph = repoGlyphFor(entry, theme);
    return SizedBox(
      height: RepoMetrics.stageHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: RepoMetrics.space4 + 2, right: 8),
        child: Row(
          children: [
            // The identity takes every pixel the actions do not, so the
            // actions sit flush against the right edge whatever the path is.
            Expanded(
              child: Row(
                children: [
                  Icon(glyph.icon, size: 15, color: glyph.color),
                  const SizedBox(width: 9),
                  Flexible(
                    child: RichText(
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      text: TextSpan(
                        children: [
                          if (segments.length > 1)
                            TextSpan(
                              text:
                                  '${segments.sublist(0, segments.length - 1).join(' / ')} / ',
                              style: theme.metaFaint.copyWith(fontSize: 12),
                            ),
                          TextSpan(
                            text: segments.last,
                            style: theme.rowLabelStrong,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(width: RepoMetrics.space3),
                    Flexible(
                      child: Text(
                        meta.join('  ·  '),
                        overflow: TextOverflow.ellipsis,
                        style: theme.metaFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: RepoMetrics.space3),
            if (togglable)
              RepoActionGroup(
                theme: theme,
                children: [
                  RepoAction(
                    theme: theme,
                    icon: Icons.visibility_rounded,
                    tooltip: LocaleKeys.collections_repository_preview.tr(),
                    selected: !editing,
                    onPressed: editing ? onToggleEditing : null,
                  ),
                  RepoAction(
                    theme: theme,
                    icon: Icons.edit_rounded,
                    tooltip: LocaleKeys.collections_repository_edit.tr(),
                    selected: editing,
                    onPressed: editing ? null : onToggleEditing,
                  ),
                ],
              )
            else if (writable)
              RepoMeta(
                theme: theme,
                icon: Icons.edit_rounded,
                label: LocaleKeys.collections_repository_editing.tr(),
              )
            else
              RepoMeta(
                theme: theme,
                icon: Icons.lock_rounded,
                label: LocaleKeys.collections_repository_readOnly.tr(),
              ),
            const SizedBox(width: RepoMetrics.space2),
            RepoAction(
              theme: theme,
              icon: Icons.open_in_new_rounded,
              tooltip: LocaleKeys.collections_repository_openInWorkspace.tr(),
              onPressed: onOpenInWorkspace,
            ),
          ],
        ),
      ),
    );
  }
}

class _StageNotice extends StatelessWidget {
  const _StageNotice({required this.theme, required this.message});

  final RepoTheme theme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RepoMetrics.space4,
        vertical: RepoMetrics.space2,
      ),
      color: theme.accent.withValues(alpha: 0.07),
      child: Row(
        children: [
          Icon(Icons.info_rounded, size: 13, color: theme.accent),
          const SizedBox(width: RepoMetrics.space2),
          Text(message, style: theme.meta),
        ],
      ),
    );
  }
}

class _OutlinePane extends StatelessWidget {
  const _OutlinePane({
    required this.controller,
    required this.theme,
    required this.entry,
  });

  final RepositoryController controller;
  final RepoTheme theme;
  final RepoEntry? entry;

  @override
  Widget build(BuildContext context) {
    final file = entry;
    final symbols = file == null
        ? const <SourceSymbol>[]
        : controller.analysisFor(file).symbols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepoPaneHeading(
          theme: theme,
          title: LocaleKeys.collections_repository_outline.tr(),
          trailing: symbols.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: RepoMetrics.space2),
                  child: Text('${symbols.length}', style: theme.metaFaint),
                ),
        ),
        Expanded(
          child: symbols.isEmpty
              ? RepoEmptyState(
                  theme: theme,
                  icon: Icons.segment_rounded,
                  title: LocaleKeys.collections_repository_noOutline.tr(),
                  description: LocaleKeys
                      .collections_repository_noOutlineDescription
                      .tr(),
                )
              : RepoScrollArea(
                  theme: theme,
                  builder: (context, scrollController) => ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: symbols.length,
                    itemBuilder: (context, index) => RepoOutlineRow(
                      symbol: symbols[index],
                      theme: theme,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// One declaration in an outline: its kind, its name and where it starts.
class RepoOutlineRow extends StatelessWidget {
  const RepoOutlineRow({
    super.key,
    required this.symbol,
    required this.theme,
    this.onTap,
    this.selected = false,
  });

  final SourceSymbol symbol;
  final RepoTheme theme;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = symbolKindColor(symbol.kind, theme);
    return RepoRow(
      theme: theme,
      height: RepoMetrics.treeRowHeight,
      inset: 6,
      padding: 6,
      selected: selected,
      onTap: onTap,
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(left: symbol.depth * 12.0),
        child: Row(
          children: [
            TweenAnimationBuilder<double>(
              duration: RepoMetrics.hover,
              curve: RepoMetrics.curve,
              tween: Tween(end: hovered || selected ? 1.0 : 0.78),
              builder: (context, value, _) => Icon(
                symbolKindIcon(symbol.kind),
                size: 13,
                color: Color.lerp(color.withValues(alpha: 0.7), color, value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                symbol.name,
                overflow: TextOverflow.ellipsis,
                style: theme.face(
                  fontSize: 12,
                  color:
                      selected || hovered ? theme.textStrong : theme.textBody,
                  axis: selected ? RepoMetrics.strongWeightAxis : 545,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${symbol.line}',
              style: theme.metaFaint.copyWith(fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}
