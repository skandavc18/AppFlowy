import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_context_menu.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_file_stage.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_host.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_views.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/source_outline.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Every declaration in the repository, searchable, with the source that
/// defines it beside the list.
class RepositorySymbolsView extends StatefulWidget {
  const RepositorySymbolsView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<RepositorySymbolsView> createState() => _RepositorySymbolsViewState();
}

class _RepositorySymbolsViewState extends State<RepositorySymbolsView> {
  final TextEditingController query = TextEditingController();
  final Set<SymbolKind> kinds = {};
  (RepoEntry, SourceSymbol)? selected;

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryHost(
      collection: widget.collection,
      readsSource: true,
      builder: (context, controller, palette) {
        final theme = repoThemeOf(context, palette);
        final results = controller.symbols(
          query: query.text,
          kinds: kinds.isEmpty ? null : kinds,
        );
        final choice = _resolveSelection(results);
        return RepoScaffold(
          controller: controller,
          palette: palette,
          padded: false,
          leading: [
            RepoSearchField(
              theme: theme,
              controller: query,
              hint: LocaleKeys.collections_repository_searchSymbols.tr(),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(width: 8),
            _KindFilter(
              theme: theme,
              selected: kinds,
              available: {for (final result in results) result.$2.kind},
              onToggle: (kind) => setState(() {
                if (!kinds.remove(kind)) {
                  kinds.add(kind);
                }
              }),
            ),
          ],
          trailing: [
            RepoMeta(
              theme: theme,
              label: repoCountLabel(
                results.length,
                LocaleKeys.collections_repository_oneSymbol,
                LocaleKeys.collections_repository_symbolCount,
              ),
            ),
          ],
          child: results.isEmpty
              ? RepoEmptyState(
                  theme: theme,
                  icon: controller.isAnalysing
                      ? Icons.hourglass_top_rounded
                      : Icons.search_off_rounded,
                  title: controller.isAnalysing
                      ? LocaleKeys.collections_repository_readingSource.tr()
                      : LocaleKeys.collections_repository_noSymbols.tr(),
                  description: LocaleKeys
                      .collections_repository_noSymbolsDescription
                      .tr(),
                )
              : _SymbolsBody(
                  collection: widget.collection,
                  controller: controller,
                  theme: theme,
                  results: results,
                  selected: choice,
                  onSelect: (value) => setState(() => selected = value),
                ),
        );
      },
    );
  }

  /// Keeps the shown declaration alive across a filter change, falling back
  /// to the first result rather than an empty stage.
  (RepoEntry, SourceSymbol)? _resolveSelection(
    List<(RepoEntry, SourceSymbol)> results,
  ) {
    if (results.isEmpty) {
      return null;
    }
    final current = selected;
    if (current != null) {
      for (final result in results) {
        if (result.$1.id == current.$1.id &&
            result.$2.line == current.$2.line) {
          return result;
        }
      }
    }
    return results.first;
  }
}

class _SymbolsBody extends StatelessWidget {
  const _SymbolsBody({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.results,
    required this.selected,
    required this.onSelect,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final List<(RepoEntry, SourceSymbol)> results;
  final (RepoEntry, SourceSymbol)? selected;
  final ValueChanged<(RepoEntry, SourceSymbol)> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showDetail = constraints.maxWidth >= 900;
        final list = RepoPanel(
          theme: theme,
          child: _SymbolList(
            collection: collection,
            controller: controller,
            theme: theme,
            results: results,
            selected: selected,
            onSelect: onSelect,
          ),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            RepoMetrics.gutter,
            RepoMetrics.space2,
            RepoMetrics.gutter,
            RepoMetrics.space4,
          ),
          child: showDetail
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 380, child: list),
                    const RepoGap(),
                    Expanded(
                      child: RepoPanel(
                        theme: theme,
                        child: _SymbolDetail(
                          collection: collection,
                          controller: controller,
                          theme: theme,
                          selection: selected,
                        ),
                      ),
                    ),
                  ],
                )
              : list,
        );
      },
    );
  }
}

class _SymbolList extends StatelessWidget {
  const _SymbolList({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.results,
    required this.selected,
    required this.onSelect,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final List<(RepoEntry, SourceSymbol)> results;
  final (RepoEntry, SourceSymbol)? selected;
  final ValueChanged<(RepoEntry, SourceSymbol)> onSelect;

  @override
  Widget build(BuildContext context) {
    return RepoScrollArea(
      theme: theme,
      builder: (context, scrollController) => ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 18),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final result = results[index];
          final previous = index == 0 ? null : results[index - 1];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (previous == null || previous.$1.id != result.$1.id)
                _FileHeading(entry: result.$1, theme: theme),
              _SymbolRow(
                entry: result.$1,
                symbol: result.$2,
                collection: collection,
                controller: controller,
                theme: theme,
                selected: selected?.$1.id == result.$1.id &&
                    selected?.$2.line == result.$2.line,
                onTap: () => onSelect(result),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FileHeading extends StatelessWidget {
  const _FileHeading({required this.entry, required this.theme});

  final RepoEntry entry;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    final glyph = repoGlyphFor(entry, theme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          Icon(glyph.icon, size: 12.5, color: glyph.color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.path,
              overflow: TextOverflow.ellipsis,
              style: theme.sectionLabel.copyWith(letterSpacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _SymbolRow extends StatelessWidget {
  const _SymbolRow({
    required this.entry,
    required this.symbol,
    required this.collection,
    required this.controller,
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final RepoEntry entry;
  final SourceSymbol symbol;
  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = symbolKindColor(symbol.kind, theme);
    return RepoRow(
      theme: theme,
      height: RepoMetrics.symbolRowHeight,
      inset: 10,
      selected: selected,
      showActiveBar: true,
      onTap: onTap,
      onSecondaryTap: (position) => showRepoEntryMenu(
        context: context,
        collection: collection,
        controller: controller,
        entry: entry,
        position: position,
      ),
      builder: (context, hovered) => Row(
        children: [
          TweenAnimationBuilder<double>(
            duration: RepoMetrics.hover,
            curve: RepoMetrics.curve,
            tween: Tween(end: hovered || selected ? 1.0 : 0.78),
            builder: (context, value, _) => Icon(
              symbolKindIcon(symbol.kind),
              size: 13.5,
              color: Color.lerp(color.withValues(alpha: 0.7), color, value),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            symbol.name,
            style: theme.face(
              fontSize: 12.5,
              color: theme.textStrong,
              axis: RepoMetrics.strongWeightAxis,
              weight: FontWeight.w600,
            ),
          ),
          if (symbol.detail.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                symbol.detail,
                overflow: TextOverflow.ellipsis,
                style: theme.metaFaint,
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 8),
          Text(
            '${symbol.line}',
            style: theme.metaFaint.copyWith(fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

class _SymbolDetail extends StatelessWidget {
  const _SymbolDetail({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.selection,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final (RepoEntry, SourceSymbol)? selection;

  @override
  Widget build(BuildContext context) {
    final choice = selection;
    if (choice == null) {
      return RepoEmptyState(
        theme: theme,
        icon: Icons.data_object_rounded,
        title: LocaleKeys.collections_repository_selectFile.tr(),
        description:
            LocaleKeys.collections_repository_selectFileDescription.tr(),
      );
    }
    final (entry, symbol) = choice;
    final source = controller.textFor(entry);
    final outline = controller.analysisFor(entry).symbols;
    return RepoScrollArea(
      theme: theme,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  symbolKindIcon(symbol.kind),
                  size: 18,
                  color: symbolKindColor(symbol.kind, theme),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    symbol.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.title,
                  ),
                ),
                const SizedBox(width: 10),
                _KindBadge(kind: symbol.kind, theme: theme),
                const Spacer(),
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
                          ..expandTo(entry.path)
                          ..openFile(entry.id)
                          ..flush();
                        collection.onOpenView(RepositoryViewIds.tree);
                      },
                    ),
                    RepoAction(
                      theme: theme,
                      icon: Icons.open_in_new_rounded,
                      tooltip: LocaleKeys.collections_repository_openInWorkspace
                          .tr(),
                      onPressed: () => collection.onOpen(entry.view),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text('${entry.path}:${symbol.line}', style: theme.metaFaint),
            const SizedBox(height: 18),
            if (source == null)
              Text(
                LocaleKeys.collections_repository_unreadable.tr(),
                style: theme.meta,
              )
            else
              RepoSourceExcerpt(
                source: source,
                line: symbol.line,
                theme: theme,
                contextLines: 7,
              ),
            if (outline.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                LocaleKeys.collections_repository_outline.tr(),
                style: theme.sectionLabel,
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final other in outline.take(60))
                    _SymbolChip(
                      symbol: other,
                      theme: theme,
                      selected: other.line == symbol.line,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind, required this.theme});

  final SymbolKind kind;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      symbolKindLabel(kind).toLowerCase(),
      style: theme.face(
        fontSize: 11.5,
        color: symbolKindColor(kind, theme),
        axis: 580,
      ),
    );
  }
}

class _SymbolChip extends StatelessWidget {
  const _SymbolChip({
    required this.symbol,
    required this.theme,
    required this.selected,
  });

  final SourceSymbol symbol;
  final RepoTheme theme;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: RepoMetrics.hover,
      curve: RepoMetrics.curve,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? theme.accentSoft : theme.sunken,
        borderRadius: BorderRadius.circular(RepoMetrics.controlRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            symbolKindIcon(symbol.kind),
            size: 11.5,
            color: symbolKindColor(symbol.kind, theme),
          ),
          const SizedBox(width: 6),
          Text(
            symbol.name,
            style: theme.face(
              fontSize: 11,
              color: selected ? theme.textStrong : theme.textBody,
              axis: selected ? RepoMetrics.strongWeightAxis : 540,
            ),
          ),
        ],
      ),
    );
  }
}

class _KindFilter extends StatelessWidget {
  const _KindFilter({
    required this.theme,
    required this.selected,
    required this.available,
    required this.onToggle,
  });

  final RepoTheme theme;
  final Set<SymbolKind> selected;
  final Set<SymbolKind> available;
  final ValueChanged<SymbolKind> onToggle;

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final kind in SymbolKind.values)
        if (available.contains(kind) || selected.contains(kind)) kind,
    ];
    if (kinds.length < 2) {
      return const SizedBox.shrink();
    }
    return Flexible(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: RepoActionGroup(
          theme: theme,
          children: [
            for (final kind in kinds)
              RepoAction(
                theme: theme,
                icon: symbolKindIcon(kind),
                tooltip: symbolKindLabel(kind),
                selected: selected.contains(kind),
                onPressed: () => onToggle(kind),
              ),
          ],
        ),
      ),
    );
  }
}
