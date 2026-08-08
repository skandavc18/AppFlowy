import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_context_menu.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_host.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_views.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_markup.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:path/path.dart' as p;

/// The front page of a repository: what it is written in, what it holds, and
/// the readme that explains it.
class RepositoryBrowserView extends StatelessWidget {
  const RepositoryBrowserView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  Widget build(BuildContext context) {
    return RepositoryHost(
      collection: collection,
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
                collection: collection,
                controller: controller,
                parentPath: '',
                primary: true,
              ),
            ],
            child: RepoEmptyState(
              theme: theme,
              icon: Icons.code_rounded,
              title: LocaleKeys.collections_repository_emptyTitle.tr(),
              description:
                  LocaleKeys.collections_repository_emptyDescription.tr(),
            ),
          );
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
              icon: Icons.account_tree_rounded,
              tooltip: LocaleKeys.collections_repository_goToFile.tr(),
              onPressed: () => collection.onOpenView(RepositoryViewIds.tree),
            ),
            const SizedBox(width: 8),
            RepoAddButton(
              theme: theme,
              collection: collection,
              controller: controller,
              parentPath: controller.state.browserPath,
              primary: true,
            ),
          ],
          child: _BrowserBody(
            collection: collection,
            controller: controller,
            theme: theme,
          ),
        );
      },
    );
  }
}

class _BrowserBody extends StatelessWidget {
  const _BrowserBody({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    final readme = controller.readme;
    if (readme != null) {
      controller.ensureAnalysis(readme);
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => showRepoBackgroundMenu(
        context: context,
        collection: collection,
        controller: controller,
        position: details.globalPosition,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          // The listing and the readme share one column and one width, the
          // way a repository page reads: contents, then the document that
          // explains them. The insights sit beside both, never under them.
          final column = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BrowserListing(
                collection: collection,
                controller: controller,
                theme: theme,
              ),
              const SizedBox(height: RepoMetrics.space6),
              _ReadmeCard(
                entry: readme,
                theme: theme,
                collection: collection,
                controller: controller,
              ),
            ],
          );
          final aside = _BrowserAside(controller: controller, theme: theme);
          return RepoScrollArea(
            theme: theme,
            builder: (context, scrollController) => SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                RepoMetrics.gutter,
                RepoMetrics.space4,
                RepoMetrics.gutter,
                RepoMetrics.space8,
              ),
              // A repository page reads best at a fixed measure. Past this the
              // listing turns into a wall of whitespace with a file name lost
              // at each end, so the content centres instead of stretching.
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: RepoMetrics.readingWidth,
                  ),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: column),
                            const SizedBox(width: RepoMetrics.space6),
                            SizedBox(
                              width: 244,
                              child: _BrowserAsideCard(
                                theme: theme,
                                child: aside,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _BrowserAsideCard(theme: theme, child: aside),
                            const SizedBox(height: RepoMetrics.space6),
                            column,
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BrowserAsideCard extends StatelessWidget {
  const _BrowserAsideCard({required this.theme, required this.child});

  final RepoTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepoPanel(
      theme: theme,
      padding: const EdgeInsets.fromLTRB(
        RepoMetrics.space4 + 2,
        RepoMetrics.space4 + 2,
        RepoMetrics.space4 + 2,
        RepoMetrics.space4 + 4,
      ),
      child: child,
    );
  }
}

/// The current folder's contents, with a breadcrumb above them.
class _BrowserListing extends StatelessWidget {
  const _BrowserListing({
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    final path = controller.state.browserPath;
    final children = controller.childrenOfPath(path);
    final parent = path.isEmpty ? null : repoParentPath(path);
    return RepoPanel(
      theme: theme,
      padding: const EdgeInsets.fromLTRB(
        RepoMetrics.space2,
        RepoMetrics.space2,
        RepoMetrics.space2,
        RepoMetrics.space2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ListingHeader(
            theme: theme,
            path: path,
            onOpen: controller.browseTo,
            trailing: RepoAddButton(
              theme: theme,
              collection: collection,
              controller: controller,
              parentPath: path,
            ),
          ),
          if (parent != null) ...[
            RepoRow(
              theme: theme,
              height: RepoMetrics.listRowHeight,
              inset: RepoMetrics.space1,
              onTap: () => controller.browseTo(parent),
              child: Row(
                children: [
                  SizedBox(
                    width: RepoMetrics.iconSlot,
                    child: Icon(
                      Icons.subdirectory_arrow_left_rounded,
                      size: RepoMetrics.iconSize,
                      color: theme.textFaint,
                    ),
                  ),
                  const SizedBox(width: RepoMetrics.iconGap + 2),
                  Text('..', style: theme.rowLabel),
                ],
              ),
            ),
            if (children.isNotEmpty) _RowRule(theme: theme),
          ],
          if (children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: RepoMetrics.space8),
              child: Text(
                LocaleKeys.collections_repository_emptyTitle.tr(),
                textAlign: TextAlign.center,
                style: theme.metaFaint,
              ),
            )
          else
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) _RowRule(theme: theme),
              _BrowserRow(
                entry: children[index],
                collection: collection,
                controller: controller,
                theme: theme,
              ),
            ],
        ],
      ),
    );
  }
}

/// The whisper of a line that tells one file from the next.
///
/// Inset to exactly the width of the hover pill, so the two share one edge.
class _RowRule extends StatelessWidget {
  const _RowRule({required this.theme});

  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RepoMetrics.space1),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: theme.rowRule),
      ),
    );
  }
}

class _ListingHeader extends StatelessWidget {
  const _ListingHeader({
    required this.theme,
    required this.path,
    required this.onOpen,
    required this.trailing,
  });

  final RepoTheme theme;
  final String path;
  final ValueChanged<String> onOpen;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final segments = path.isEmpty ? const <String>[] : path.split('/');
    return Padding(
      padding: const EdgeInsets.only(
        left: RepoMetrics.space1,
        bottom: RepoMetrics.space1,
      ),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _Crumb(
                      theme: theme,
                      label: LocaleKeys.collections_repository_root.tr(),
                      icon: Icons.folder_rounded,
                      active: segments.isEmpty,
                      onTap: () => onOpen(''),
                    ),
                    for (var index = 0; index < segments.length; index++) ...[
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: theme.textFaint.withValues(alpha: 0.7),
                      ),
                      _Crumb(
                        theme: theme,
                        label: segments[index],
                        active: index == segments.length - 1,
                        onTap: () => onOpen(segments.take(index + 1).join('/')),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: RepoMetrics.space2),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _Crumb extends StatefulWidget {
  const _Crumb({
    required this.theme,
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final RepoTheme theme;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  State<_Crumb> createState() => _CrumbState();
}

class _CrumbState extends State<_Crumb> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final color = widget.active
        ? theme.textStrong
        : hovered
            ? theme.accent
            : theme.textBody;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: RepoMetrics.hover,
          curve: RepoMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: hovered && !widget.active
                ? theme.rowHover
                : theme.transparentAs(theme.rowHover),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 13, color: color),
                const SizedBox(width: 5),
              ],
              AnimatedDefaultTextStyle(
                duration: RepoMetrics.hover,
                curve: RepoMetrics.curve,
                style: theme.face(
                  fontSize: 12,
                  color: color,
                  axis: widget.active
                      ? RepoMetrics.strongWeightAxis
                      : RepoMetrics.rowWeightAxis,
                  weight: widget.active ? FontWeight.w600 : FontWeight.w500,
                ),
                child: Text(widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserRow extends StatelessWidget {
  const _BrowserRow({
    required this.entry,
    required this.collection,
    required this.controller,
    required this.theme,
  });

  final RepoEntry entry;
  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    final analysis = controller.analysisFor(entry);
    final size =
        analysis.byteSize > 0 ? analysis.byteSize : entry.byteSize ?? 0;
    return RepoRow(
      theme: theme,
      height: RepoMetrics.listRowHeight,
      inset: RepoMetrics.space1,
      onTap: () => entry.isFolder
          ? controller.browseTo(entry.path)
          : _openInTree(context),
      onSecondaryTap: (position) => showRepoEntryMenu(
        context: context,
        collection: collection,
        controller: controller,
        entry: entry,
        position: position,
      ),
      builder: (context, hovered) {
        final glyph = repoGlyphFor(entry, theme);
        return Row(
          children: [
            RepoGlyphIcon(glyph: glyph, emphasised: hovered),
            const SizedBox(width: RepoMetrics.iconGap + 2),
            // Expanded, not Flexible: a Flexible name leaves its unused space
            // at the end of the row, so the metadata columns would sit at a
            // different offset for every file name length.
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: RepoMetrics.hover,
                curve: RepoMetrics.curve,
                style: theme.face(
                  fontSize: RepoMetrics.rowSize,
                  color: hovered ? theme.accent : theme.textStrong,
                  axis: entry.isFolder
                      ? RepoMetrics.strongWeightAxis
                      : RepoMetrics.rowWeightAxis,
                ),
                child: Text(entry.name, overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: RepoMetrics.space4),
            SizedBox(
              width: 68,
              child: Text(
                entry.isFolder ? '' : repoByteLabel(size),
                textAlign: TextAlign.right,
                style: theme.metaFaint,
              ),
            ),
            SizedBox(
              width: 76,
              child: Text(
                entry.modifiedAt == null
                    ? ''
                    : intl.DateFormat.MMMd().format(entry.modifiedAt!),
                textAlign: TextAlign.right,
                style: theme.metaFaint,
              ),
            ),
          ],
        );
      },
    );
  }

  /// A file opens where it can actually be read: the tree, with the source
  /// beside it. Opening it as a workspace tab would leave the repository.
  void _openInTree(BuildContext context) {
    controller
      ..expandTo(entry.path)
      ..openFile(entry.id)
      ..flush();
    collection.onOpenView(RepositoryViewIds.tree);
  }
}

/// What the repository is made of, in one quiet column.
class _BrowserAside extends StatelessWidget {
  const _BrowserAside({required this.controller, required this.theme});

  final RepositoryController controller;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    final stats = controller.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          LocaleKeys.collections_repository_languages.tr(),
          style: theme.sectionLabel,
        ),
        const SizedBox(height: RepoMetrics.space3),
        if (stats.languages.isEmpty)
          Text(
            LocaleKeys.collections_repository_noLanguages.tr(),
            style: theme.meta,
          )
        else ...[
          RepoLanguageBar(shares: stats.languages, theme: theme),
          const SizedBox(height: RepoMetrics.space4),
          RepoLanguageLegend(shares: stats.languages, theme: theme),
        ],
        const SizedBox(height: RepoMetrics.space8),
        Text(
          LocaleKeys.collections_repository_files.tr(),
          style: theme.sectionLabel,
        ),
        const SizedBox(height: RepoMetrics.space3),
        _AsideStat(
          theme: theme,
          label: LocaleKeys.collections_repository_files.tr(),
          value: repoGroupedNumber(stats.fileCount),
        ),
        _AsideStat(
          theme: theme,
          label: LocaleKeys.collections_repository_symbols.tr(),
          value: repoGroupedNumber(stats.sourceCount),
        ),
        _AsideStat(
          theme: theme,
          label: LocaleKeys.collections_repository_docs.tr(),
          value: repoGroupedNumber(stats.docCount),
        ),
        _AsideStat(
          theme: theme,
          label: LocaleKeys.collections_repository_size.tr(),
          value: repoByteLabel(stats.byteSize),
        ),
      ],
    );
  }
}

class _AsideStat extends StatelessWidget {
  const _AsideStat({
    required this.theme,
    required this.label,
    required this.value,
  });

  final RepoTheme theme;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.meta)),
          Text(
            value,
            style: theme.face(
              fontSize: RepoMetrics.metaSize,
              color: theme.textStrong,
              axis: RepoMetrics.strongWeightAxis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadmeCard extends StatelessWidget {
  const _ReadmeCard({
    required this.entry,
    required this.theme,
    required this.collection,
    required this.controller,
  });

  final RepoEntry? entry;
  final RepoTheme theme;
  final CollectionViewContext collection;
  final RepositoryController controller;

  @override
  Widget build(BuildContext context) {
    final readme = entry;
    // A repository with no readme offers to write one rather than reserving
    // a page of empty card for a document that does not exist.
    if (readme == null) {
      return _AddReadmeRow(
        theme: theme,
        collection: collection,
        controller: controller,
      );
    }
    return RepoPanel(
      theme: theme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RepoMetrics.space4 + 2,
              RepoMetrics.space3,
              RepoMetrics.space2,
              0,
            ),
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 14, color: theme.textFaint),
                const SizedBox(width: RepoMetrics.space2),
                Expanded(
                  child: Text(
                    readme.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.sectionLabel,
                  ),
                ),
                RepoAction(
                  theme: theme,
                  icon: Icons.edit_rounded,
                  tooltip: LocaleKeys.collections_repository_edit.tr(),
                  onPressed: () => openRepoObject(collection, readme.view),
                ),
              ],
            ),
          ),
          _ReadmeDocument(
            entry: readme,
            controller: controller,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

/// The readme, laid out at its true height.
///
/// A boxed viewer would scroll inside a page that also scrolls, so the
/// document is built as widgets and the page's own scroll carries all of it.
/// That is also why this does not go through `RepoFileStage`: the markdown
/// preview is a web view, and a web view has no height of its own.
class _ReadmeDocument extends StatelessWidget {
  const _ReadmeDocument({
    required this.entry,
    required this.controller,
    required this.theme,
  });

  final RepoEntry entry;
  final RepositoryController controller;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    final source = controller.textFor(entry);
    if (source == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: RepoMetrics.space8),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (source.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: RepoMetrics.space8),
        child: Center(
          child: Text(
            LocaleKeys.collections_repository_noReadmeDescription.tr(),
            style: theme.rowLabel.copyWith(color: theme.textFaint),
          ),
        ),
      );
    }

    const padding = EdgeInsets.fromLTRB(
      RepoMetrics.space4 + 2,
      RepoMetrics.space3,
      RepoMetrics.space4 + 2,
      RepoMetrics.space4,
    );
    if (filePreviewKindFromName(entry.name) != FilePreviewKind.markdown) {
      return Padding(
        padding: padding,
        child: SelectableText(
          source,
          style: theme.rowLabel.copyWith(height: 1.6),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: NotebookMarkup(
        source: source,
        palette: CodeBlockPalette.resolve(context),
        // Relative images in a readme point at the folder it sits in.
        baseDirectory: p.dirname(entry.storageUrl),
      ),
    );
  }
}

/// The offer to write the document that explains the project.
class _AddReadmeRow extends StatelessWidget {
  const _AddReadmeRow({
    required this.theme,
    required this.collection,
    required this.controller,
  });

  final RepoTheme theme;
  final CollectionViewContext collection;
  final RepositoryController controller;

  @override
  Widget build(BuildContext context) {
    return RepoPanel(
      theme: theme,
      padding: const EdgeInsets.symmetric(
        horizontal: RepoMetrics.space4 + 2,
        vertical: RepoMetrics.space3,
      ),
      child: Row(
        children: [
          Icon(Icons.menu_book_rounded, size: 15, color: theme.textFaint),
          const SizedBox(width: RepoMetrics.space3),
          Expanded(
            child: Text(
              LocaleKeys.collections_repository_noReadmeDescription.tr(),
              style: theme.meta,
            ),
          ),
          const SizedBox(width: RepoMetrics.space3),
          RepoAction(
            theme: theme,
            icon: Icons.add_rounded,
            tooltip: LocaleKeys.collections_repository_addReadme.tr(),
            label: LocaleKeys.collections_repository_addReadme.tr(),
            primary: true,
            onPressed: () => unawaited(
              createRepoReadme(collection: collection, controller: controller),
            ),
          ),
        ],
      ),
    );
  }
}
