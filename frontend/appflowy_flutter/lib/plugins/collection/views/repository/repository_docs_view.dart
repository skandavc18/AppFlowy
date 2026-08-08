import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_chrome.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_context_menu.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_file_stage.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_host.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_tree_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The project's prose: every readme, guide and note it carries, with the
/// headings of whichever one is open.
class RepositoryDocsView extends StatefulWidget {
  const RepositoryDocsView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<RepositoryDocsView> createState() => _RepositoryDocsViewState();
}

class _RepositoryDocsViewState extends State<RepositoryDocsView> {
  final Set<String> editing = {};

  @override
  Widget build(BuildContext context) {
    return RepositoryHost(
      collection: widget.collection,
      builder: (context, controller, palette) {
        final theme = repoThemeOf(context, palette);
        final docs = controller.documentationEntries;
        if (docs.isEmpty) {
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
              icon: Icons.menu_book_rounded,
              title: LocaleKeys.collections_repository_noDocs.tr(),
              description:
                  LocaleKeys.collections_repository_noDocsDescription.tr(),
            ),
          );
        }
        final active = _activeDoc(controller, docs);
        controller.ensureAnalysis(active);
        final writable = RepoFileStage.supportsEditing(active);
        final isEditing = editing.contains(active.id);
        return RepoScaffold(
          controller: controller,
          palette: palette,
          padded: false,
          trailing: [
            if (writable && RepoFileStage.needsSourceToggle(active))
              RepoActionGroup(
                theme: theme,
                children: [
                  RepoAction(
                    theme: theme,
                    icon: Icons.visibility_rounded,
                    tooltip: LocaleKeys.collections_repository_preview.tr(),
                    selected: !isEditing,
                    onPressed: isEditing
                        ? () => setState(() => editing.remove(active.id))
                        : null,
                  ),
                  RepoAction(
                    theme: theme,
                    icon: Icons.edit_rounded,
                    tooltip: LocaleKeys.collections_repository_edit.tr(),
                    selected: isEditing,
                    onPressed: isEditing
                        ? null
                        : () => setState(() => editing.add(active.id)),
                  ),
                ],
              ),
            const SizedBox(width: 8),
            RepoAction(
              theme: theme,
              icon: Icons.segment_rounded,
              tooltip: LocaleKeys.collections_repository_contents.tr(),
              selected: controller.settings.showOutline,
              onPressed: () => controller.updateSettings(
                controller.settings
                    .copyWith(showOutline: !controller.settings.showOutline),
              ),
            ),
            RepoAction(
              theme: theme,
              icon: Icons.open_in_new_rounded,
              tooltip: LocaleKeys.collections_repository_openInWorkspace.tr(),
              onPressed: () => widget.collection.onOpen(active.view),
            ),
          ],
          child: _DocsBody(
            collection: widget.collection,
            controller: controller,
            theme: theme,
            docs: docs,
            active: active,
            editing: isEditing,
          ),
        );
      },
    );
  }

  /// The remembered document, its readme, or the first one there is.
  RepoEntry _activeDoc(RepositoryController controller, List<RepoEntry> docs) {
    final remembered = controller.state.activeDocId;
    if (remembered != null) {
      for (final doc in docs) {
        if (doc.id == remembered) {
          return doc;
        }
      }
    }
    return controller.readme ?? docs.first;
  }
}

class _DocsBody extends StatelessWidget {
  const _DocsBody({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.docs,
    required this.active,
    required this.editing,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final List<RepoEntry> docs;
  final RepoEntry active;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final symbols = controller.analysisFor(active).symbols;
    return LayoutBuilder(
      builder: (context, constraints) {
        final showContents =
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
                  child: _DocsList(
                    collection: collection,
                    controller: controller,
                    theme: theme,
                    docs: docs,
                    activeId: active.id,
                  ),
                ),
              ),
              const RepoGap(),
              Expanded(
                child: RepoPanel(
                  theme: theme,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DocHeader(entry: active, theme: theme),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: RepoMetrics.reveal,
                          switchInCurve: RepoMetrics.curve,
                          switchOutCurve: RepoMetrics.curve,
                          child: RepoFileStage(
                            key: ValueKey('repo-doc-${active.id}-$editing'),
                            entry: active,
                            theme: theme,
                            editable: RepoFileStage.supportsEditing(active),
                            editingSource: editing,
                            fetcher: controller.fetcher,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showContents) ...[
                const RepoGap(),
                SizedBox(
                  width: RepoMetrics.railWidth,
                  child: RepoPanel(
                    theme: theme,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RepoPaneHeading(
                          theme: theme,
                          title:
                              LocaleKeys.collections_repository_contents.tr(),
                          trailing: symbols.isEmpty
                              ? null
                              : Padding(
                                  padding: const EdgeInsets.only(
                                    right: RepoMetrics.space2,
                                  ),
                                  child: Text(
                                    '${symbols.length}',
                                    style: theme.metaFaint,
                                  ),
                                ),
                        ),
                        Expanded(
                          child: symbols.isEmpty
                              ? RepoEmptyState(
                                  theme: theme,
                                  icon: Icons.segment_rounded,
                                  title: LocaleKeys
                                      .collections_repository_noOutline
                                      .tr(),
                                  description: LocaleKeys
                                      .collections_repository_noOutlineDescription
                                      .tr(),
                                )
                              : RepoScrollArea(
                                  theme: theme,
                                  builder: (context, scrollController) =>
                                      ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    itemCount: symbols.length,
                                    itemBuilder: (context, index) =>
                                        RepoOutlineRow(
                                      symbol: symbols[index],
                                      theme: theme,
                                    ),
                                  ),
                                ),
                        ),
                      ],
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

class _DocsList extends StatelessWidget {
  const _DocsList({
    required this.collection,
    required this.controller,
    required this.theme,
    required this.docs,
    required this.activeId,
  });

  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final List<RepoEntry> docs;
  final String activeId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => showRepoBackgroundMenu(
        context: context,
        collection: collection,
        controller: controller,
        position: details.globalPosition,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepoPaneHeading(
            theme: theme,
            title: LocaleKeys.collections_repository_documents.tr(),
            trailing: RepoAddButton(
              theme: theme,
              collection: collection,
              controller: controller,
              parentPath: '',
            ),
          ),
          Expanded(
            child: RepoScrollArea(
              theme: theme,
              builder: (context, scrollController) => ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 18, top: 2),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final previous = index == 0 ? null : docs[index - 1];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (previous == null ||
                          previous.parentPath != doc.parentPath)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 13, 16, 5),
                          child: Text(
                            doc.parentPath.isEmpty
                                ? LocaleKeys.collections_repository_root.tr()
                                : doc.parentPath,
                            overflow: TextOverflow.ellipsis,
                            style:
                                theme.sectionLabel.copyWith(letterSpacing: 0.2),
                          ),
                        ),
                      _DocRow(
                        entry: doc,
                        collection: collection,
                        controller: controller,
                        theme: theme,
                        selected: doc.id == activeId,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.entry,
    required this.collection,
    required this.controller,
    required this.theme,
    required this.selected,
  });

  final RepoEntry entry;
  final CollectionViewContext collection;
  final RepositoryController controller;
  final RepoTheme theme;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final glyph = repoGlyphFor(entry, theme);
    return RepoRow(
      theme: theme,
      height: RepoMetrics.symbolRowHeight,
      selected: selected,
      showActiveBar: true,
      onTap: () => controller.openDoc(entry.id),
      onSecondaryTap: (position) => showRepoEntryMenu(
        context: context,
        collection: collection,
        controller: controller,
        entry: entry,
        position: position,
      ),
      builder: (context, hovered) => Row(
        children: [
          RepoGlyphIcon(glyph: glyph, emphasised: hovered || selected),
          const SizedBox(width: RepoMetrics.iconGap),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: RepoMetrics.hover,
              curve: RepoMetrics.curve,
              style: theme.face(
                fontSize: 12.25,
                color: selected || hovered ? theme.textStrong : theme.textBody,
                axis: selected ? RepoMetrics.strongWeightAxis : 545,
                weight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(entry.name, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocHeader extends StatelessWidget {
  const _DocHeader({required this.entry, required this.theme});

  final RepoEntry entry;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    final segments = entry.path.split('/');
    return SizedBox(
      height: RepoMetrics.stageHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RepoMetrics.space4 + 2,
        ),
        child: Row(
          children: [
            Icon(
              Icons.article_rounded,
              size: 15,
              color: const Color(0xFF7C8DA6),
            ),
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
                    TextSpan(text: segments.last, style: theme.rowLabelStrong),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
