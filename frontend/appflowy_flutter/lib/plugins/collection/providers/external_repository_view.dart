import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// What a repository is being looked at through.
enum RepositoryPane {
  code,
  commits,
  issues,
  pullRequests,
  releases;

  String get label => switch (this) {
        RepositoryPane.code => LocaleKeys.providers_repo_code.tr(),
        RepositoryPane.commits => LocaleKeys.providers_repo_commits.tr(),
        RepositoryPane.issues => LocaleKeys.providers_repo_issues.tr(),
        RepositoryPane.pullRequests =>
          LocaleKeys.providers_repo_pullRequests.tr(),
        RepositoryPane.releases => LocaleKeys.providers_repo_releases.tr(),
      };
}

/// A GitHub or GitLab repository, read as an AppFlowy Repository collection.
///
/// The tree on the left and the file on the right are the same two panes the
/// local repository collection uses, and a file opens in the same viewers. What
/// this adds is what only a hosted repository can answer: branches, commits,
/// issues, merge requests, releases and the README.
class ExternalRepositoryView extends StatefulWidget {
  const ExternalRepositoryView({
    super.key,
    required this.controller,
    required this.palette,
    required this.source,
  });

  final ProviderController controller;
  final CollectionPalette palette;
  final CollectionSource source;

  @override
  State<ExternalRepositoryView> createState() => _ExternalRepositoryViewState();
}

class _ExternalRepositoryViewState extends State<ExternalRepositoryView> {
  RepositoryProvider? provider;
  RepoSummary? summary;
  List<RepoRef> branches = const <RepoRef>[];
  List<RepoCommit> commits = const <RepoCommit>[];
  List<RepoTicket> issues = const <RepoTicket>[];
  List<RepoTicket> pulls = const <RepoTicket>[];
  List<RepoRelease> releases = const <RepoRelease>[];
  Map<String, int> languages = const <String, int>{};
  String? readme;

  RepositoryPane pane = RepositoryPane.code;
  ProviderNode? selected;
  String? selectedPath;
  String filter = '';
  final Set<String> expanded = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    provider?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final created = ProviderRegistry.create(widget.source);
      if (created is! RepositoryProvider) {
        return;
      }
      provider = created;
      await created.ensureReady();

      final results = await Future.wait([
        created.summary(),
        created.branches(),
        created.readme(),
        created.languages(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        summary = results[0] as RepoSummary?;
        branches = results[1] as List<RepoRef>;
        readme = results[2] as String?;
        languages = results[3] as Map<String, int>;
      });
      unawaited(_loadPane(RepositoryPane.commits));
    } catch (error) {
      Log.warn('Unable to read a hosted repository: $error');
    }
  }

  Future<void> _loadPane(RepositoryPane target) async {
    final repository = provider;
    if (repository == null) {
      return;
    }
    try {
      switch (target) {
        case RepositoryPane.commits:
          final loaded = await repository.commits();
          if (mounted) {
            setState(() => commits = loaded);
          }
        case RepositoryPane.issues:
          final loaded = await repository.issues();
          if (mounted) {
            setState(() => issues = loaded);
          }
        case RepositoryPane.pullRequests:
          final loaded = await repository.pullRequests();
          if (mounted) {
            setState(() => pulls = loaded);
          }
        case RepositoryPane.releases:
          final loaded = await repository.releases();
          if (mounted) {
            setState(() => releases = loaded);
          }
        case RepositoryPane.code:
          break;
      }
    } catch (error) {
      Log.warn('Unable to read repository detail: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(
          palette: palette,
          source: widget.source,
          summary: summary,
          languages: languages,
          branches: branches,
          branch: provider?.branch ?? '',
          pane: pane,
          controller: widget.controller,
          onPane: (next) {
            setState(() => pane = next);
            unawaited(_loadPane(next));
          },
          onBranch: _switchBranch,
        ),
        Expanded(
          child: switch (pane) {
            RepositoryPane.code => _code(palette),
            RepositoryPane.commits =>
              _CommitList(commits: commits, palette: palette),
            RepositoryPane.issues => _TicketList(
                tickets: issues,
                palette: palette,
                emptyLabel: LocaleKeys.providers_repo_noIssues.tr(),
              ),
            RepositoryPane.pullRequests => _TicketList(
                tickets: pulls,
                palette: palette,
                emptyLabel: LocaleKeys.providers_repo_noPullRequests.tr(),
              ),
            RepositoryPane.releases =>
              _ReleaseList(releases: releases, palette: palette),
          },
        ),
      ],
    );
  }

  Widget _code(CollectionPalette palette) {
    final all = widget.controller.childrenOf(null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 300,
            child: _Tree(
              nodes: all,
              palette: palette,
              filter: filter,
              expanded: expanded,
              selectedPath: selectedPath,
              onFilter: (value) => setState(() => filter = value),
              onToggle: (path) => setState(() {
                if (!expanded.remove(path)) {
                  expanded.add(path);
                }
              }),
              onOpen: (node) => setState(() {
                selected = node;
                selectedPath = node.path;
              }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: selected == null
                ? _Readme(
                    markdown: readme,
                    palette: palette,
                    name: summary?.fullName ?? widget.source.remoteName,
                  )
                : _FileStage(
                    key: ValueKey('repo-file-${selected!.id}'),
                    node: selected!,
                    controller: widget.controller,
                    palette: palette,
                  ),
          ),
        ],
      ),
    );
  }

  void _switchBranch(String branch) {
    // The branch lives on the collection's own source, so the choice survives
    // closing the collection and every view agrees on it.
    final next = widget.source.withOption('branch', branch);
    provider?.dispose();
    provider = null;
    setState(() {
      selected = null;
      selectedPath = null;
      expanded.clear();
    });
    ProviderSourceUpdate.of(context)?.call(next);
    unawaited(widget.controller.resync());
    unawaited(_load());
  }
}

/// Lets a view ask the collection page to persist a change to its binding.
class ProviderSourceUpdate extends InheritedWidget {
  const ProviderSourceUpdate({
    super.key,
    required this.onChanged,
    required super.child,
  });

  final void Function(CollectionSource source) onChanged;

  static void Function(CollectionSource source)? of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ProviderSourceUpdate>()
          ?.onChanged;

  @override
  bool updateShouldNotify(ProviderSourceUpdate oldWidget) =>
      onChanged != oldWidget.onChanged;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.palette,
    required this.source,
    required this.summary,
    required this.languages,
    required this.branches,
    required this.branch,
    required this.pane,
    required this.controller,
    required this.onPane,
    required this.onBranch,
  });

  final CollectionPalette palette;
  final CollectionSource source;
  final RepoSummary? summary;
  final Map<String, int> languages;
  final List<RepoRef> branches;
  final String branch;
  final RepositoryPane pane;
  final ProviderController controller;
  final ValueChanged<RepositoryPane> onPane;
  final ValueChanged<String> onBranch;

  @override
  Widget build(BuildContext context) {
    final primary = _primaryLanguage();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProviderBadge(
                source: source,
                palette: palette,
                detail: summary?.fullName ?? source.remoteName,
              ),
              if (summary?.isPrivate ?? false) ...[
                const SizedBox(width: 8),
                _Meta(
                  palette: palette,
                  label: LocaleKeys.providers_private.tr(),
                ),
              ],
              if (primary != null) ...[
                const SizedBox(width: 10),
                _Meta(palette: palette, label: primary, dot: true),
              ],
              if ((summary?.stars ?? 0) > 0) ...[
                const SizedBox(width: 10),
                _Meta(
                  palette: palette,
                  label: LocaleKeys.providers_repo_stars
                      .tr(args: ['${summary!.stars}']),
                ),
              ],
              const Spacer(),
              if ((summary?.webUrl ?? '').isNotEmpty)
                _FlatButton(
                  palette: palette,
                  icon: Icons.open_in_new_rounded,
                  label: LocaleKeys.providers_openInSource.tr(),
                  onPressed: () => unawaited(
                    launchUrl(
                      Uri.parse(summary!.webUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              ProviderSyncStrip(
                palette: palette,
                status: controller.status,
                lastSyncedAt: controller.lastSyncedAt,
                onSync: () => unawaited(controller.resync()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _BranchSelector(
                palette: palette,
                branch: branch,
                branches: branches,
                onSelected: onBranch,
              ),
              const SizedBox(width: 14),
              for (final option in RepositoryPane.values) ...[
                _PaneTab(
                  palette: palette,
                  label: option.label,
                  count: switch (option) {
                    RepositoryPane.issues => summary?.openIssues,
                    _ => null,
                  },
                  selected: option == pane,
                  onTap: () => onPane(option),
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String? _primaryLanguage() {
    if (languages.isEmpty) {
      return null;
    }
    final total = languages.values.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) {
      return null;
    }
    final top = languages.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final share = (top.value / total * 100).round();
    return '${top.key} $share%';
  }
}

/// `main ▾` — compact, and the only place a branch is chosen.
class _BranchSelector extends StatelessWidget {
  const _BranchSelector({
    required this.palette,
    required this.branch,
    required this.branches,
    required this.onSelected,
  });

  final CollectionPalette palette;
  final String branch;
  final List<RepoRef> branches;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: LocaleKeys.providers_repo_switchBranch.tr(),
        position: PopupMenuPosition.under,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final ref in branches)
            PopupMenuItem<String>(
              value: ref.name,
              height: 34,
              child: Row(
                children: [
                  Icon(
                    ref.name == branch
                        ? Icons.check_rounded
                        : Icons.commit_rounded,
                    size: 14,
                    color:
                        ref.name == branch ? palette.accent : palette.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ref.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  if (ref.isDefault)
                    Text(
                      LocaleKeys.providers_repo_defaultBranch.tr(),
                      style:
                          TextStyle(fontSize: 10.5, color: palette.textMuted),
                    ),
                ],
              ),
            ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: palette.hover,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_tree_rounded, size: 13, color: palette.accent),
              const SizedBox(width: 6),
              Text(
                branch.isEmpty ? '—' : branch,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12,
                  fontVariations: const [FontVariation.weight(570)],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 15,
                color: palette.textMuted,
              ),
            ],
          ),
        ),
      );
}

class _Tree extends StatelessWidget {
  const _Tree({
    required this.nodes,
    required this.palette,
    required this.filter,
    required this.expanded,
    required this.selectedPath,
    required this.onFilter,
    required this.onToggle,
    required this.onOpen,
  });

  final List<ProviderNode> nodes;
  final CollectionPalette palette;
  final String filter;
  final Set<String> expanded;
  final String? selectedPath;
  final ValueChanged<String> onFilter;
  final ValueChanged<String> onToggle;
  final ValueChanged<ProviderNode> onOpen;

  @override
  Widget build(BuildContext context) {
    final needle = filter.trim().toLowerCase();
    // While a filter is running every branch is open, because a match three
    // folders down is invisible otherwise.
    final visible = <ProviderNode>[
      for (final node in nodes)
        if (needle.isEmpty
            ? _isVisible(node)
            : node.path.toLowerCase().contains(needle))
          node,
    ];

    return ViewerCard(
      color: palette.surface,
      reactsToPointer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              onChanged: onFilter,
              style: TextStyle(color: palette.textPrimary, fontSize: 12.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: LocaleKeys.providers_repo_findFile.tr(),
                hintStyle: TextStyle(color: palette.textMuted, fontSize: 12.5),
                filled: true,
                fillColor: palette.background,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              itemExtent: 27,
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final node = visible[index];
                final depth = needle.isEmpty ? _depthOf(node.path) : 0;
                return _TreeRow(
                  node: node,
                  depth: depth,
                  palette: palette,
                  open: expanded.contains(node.path),
                  selected: node.path == selectedPath,
                  onTap: () =>
                      node.isFolder ? onToggle(node.path) : onOpen(node),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _isVisible(ProviderNode node) {
    final parent = node.parentId;
    if (parent == null || parent.isEmpty) {
      return true;
    }
    // Every folder above it has to be open, not just its own parent.
    var current = parent;
    while (current.isNotEmpty) {
      if (!expanded.contains(current)) {
        return false;
      }
      final slash = current.lastIndexOf('/');
      current = slash < 0 ? '' : current.substring(0, slash);
    }
    return true;
  }

  static int _depthOf(String path) =>
      path.isEmpty ? 0 : path.split('/').length - 1;
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.node,
    required this.depth,
    required this.palette,
    required this.open,
    required this.selected,
    required this.onTap,
  });

  final ProviderNode node;
  final int depth;
  final CollectionPalette palette;
  final bool open;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final node = widget.node;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: EdgeInsets.only(left: 6 + widget.depth * 15.0, right: 8),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.selected
                : palette.hover.withValues(alpha: hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: node.isFolder
                    ? AnimatedRotation(
                        turns: widget.open ? 0.25 : 0,
                        duration: const Duration(milliseconds: 140),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 14,
                          color: palette.textMuted,
                        ),
                      )
                    : null,
              ),
              Icon(
                providerNodeGlyph(node),
                size: 14,
                color: node.isFolder ? palette.accent : palette.textMuted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileStage extends StatefulWidget {
  const _FileStage({
    super.key,
    required this.node,
    required this.controller,
    required this.palette,
  });

  final ProviderNode node;
  final ProviderController controller;
  final CollectionPalette palette;

  @override
  State<_FileStage> createState() => _FileStageState();
}

class _FileStageState extends State<_FileStage> {
  String? path;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  Future<void> _fetch() async {
    final resolved = await widget.controller.materialize(widget.node);
    if (mounted) {
      setState(() {
        path = resolved;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return ViewerCard(
      color: palette.surface,
      reactsToPointer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                Icon(
                  providerNodeGlyph(widget.node),
                  size: 15,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.node.path.isEmpty
                        ? widget.node.name
                        : widget.node.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                if ((widget.node.webUrl ?? '').isNotEmpty)
                  IconButton(
                    tooltip: LocaleKeys.providers_openInSource.tr(),
                    onPressed: () => unawaited(
                      launchUrl(
                        Uri.parse(widget.node.webUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                    color: palette.textMuted,
                    splashRadius: 15,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : path == null
                    ? Center(
                        child: Text(
                          LocaleKeys.providers_cannotOpen.tr(),
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      )
                    : externalFileRenderer(
                        node: widget.node,
                        path: path!,
                        palette: FolderExplorerPalette.of(context),
                      ),
          ),
        ],
      ),
    );
  }
}

/// The README, rendered.
///
/// A README is markdown with a great deal of raw HTML in it — badge rows,
/// centred headings, picture elements — so it goes through the application's
/// own markdown viewer rather than being printed as text.
class _Readme extends StatefulWidget {
  const _Readme({
    required this.markdown,
    required this.palette,
    required this.name,
  });

  final String? markdown;
  final CollectionPalette palette;
  final String name;

  @override
  State<_Readme> createState() => _ReadmeState();
}

class _ReadmeState extends State<_Readme> {
  File? file;

  @override
  void initState() {
    super.initState();
    unawaited(_write());
  }

  @override
  void didUpdateWidget(_Readme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      unawaited(_write());
    }
  }

  /// The viewer reads a file, so the fetched source is staged as one.
  Future<void> _write() async {
    final source = widget.markdown;
    if (source == null || source.trim().isEmpty) {
      return;
    }
    try {
      final directory = await ProviderCache.instance.directoryFor(
        'readme-${widget.name}',
      );
      final staged = File(p.join(directory.path, 'README.md'));
      await staged.writeAsString(source, flush: true);
      if (mounted) {
        setState(() => file = staged);
      }
    } catch (error) {
      Log.warn('Unable to stage a README: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    if (widget.markdown == null || widget.markdown!.trim().isEmpty) {
      return ViewerCard(
        color: palette.surface,
        reactsToPointer: false,
        child: Center(
          child: Text(
            LocaleKeys.providers_repo_noReadme.tr(),
            style: TextStyle(color: palette.textMuted, fontSize: 12.5),
          ),
        ),
      );
    }

    final staged = file;
    return ViewerCard(
      color: palette.surface,
      reactsToPointer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(
              widget.name,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12,
                fontVariations: const [FontVariation.weight(600)],
              ),
            ),
          ),
          Expanded(
            child: staged == null
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : FilePreview(
                    key: ValueKey('readme-${widget.name}-${staged.path}'),
                    file: staged,
                    name: 'README.md',
                    kind: FilePreviewKind.markdown,
                    bare: true,
                    editable: false,
                    metadata: const {},
                    onMetadataChanged: (_) {},
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommitList extends StatelessWidget {
  const _CommitList({required this.commits, required this.palette});

  final List<RepoCommit> commits;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) {
    if (commits.isEmpty) {
      return Center(
        child: Text(
          LocaleKeys.providers_repo_noCommits.tr(),
          style: TextStyle(color: palette.textMuted, fontSize: 12.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: commits.length,
      itemBuilder: (context, index) {
        final commit = commits[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.commit_rounded, size: 15, color: palette.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      commit.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontVariations: const [FontVariation.weight(550)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${commit.authorName} · ${providerRelativeTime(commit.authoredAt)}',
                      style:
                          TextStyle(color: palette.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                commit.shortSha,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TicketList extends StatelessWidget {
  const _TicketList({
    required this.tickets,
    required this.palette,
    required this.emptyLabel,
  });

  final List<RepoTicket> tickets;
  final CollectionPalette palette;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return Center(
        child: Text(
          emptyLabel,
          style: TextStyle(color: palette.textMuted, fontSize: 12.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: tickets.length,
      itemBuilder: (context, index) {
        final ticket = tickets[index];
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: ticket.webUrl.isEmpty
                ? null
                : () => unawaited(
                      launchUrl(
                        Uri.parse(ticket.webUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ticket.isMerged
                        ? Icons.merge_rounded
                        : ticket.isDraft
                            ? Icons.edit_note_rounded
                            : Icons.adjust_rounded,
                    size: 15,
                    color: ticket.isOpen
                        ? const Color(0xFF2DA44E)
                        : palette.textMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ticket.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: 13,
                            fontVariations: const [FontVariation.weight(550)],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            '#${ticket.number}',
                            if (ticket.authorName.isNotEmpty) ticket.authorName,
                            providerRelativeTime(
                              ticket.updatedAt ?? ticket.createdAt,
                            ),
                            if (ticket.sourceBranch.isNotEmpty)
                              '${ticket.sourceBranch} → ${ticket.targetBranch}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReleaseList extends StatelessWidget {
  const _ReleaseList({required this.releases, required this.palette});

  final List<RepoRelease> releases;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) {
    if (releases.isEmpty) {
      return Center(
        child: Text(
          LocaleKeys.providers_repo_noReleases.tr(),
          style: TextStyle(color: palette.textMuted, fontSize: 12.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: releases.length,
      itemBuilder: (context, index) {
        final release = releases[index];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.local_offer_rounded,
                    size: 14,
                    color: palette.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    release.name,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 13.5,
                      fontVariations: const [FontVariation.weight(600)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    providerRelativeTime(release.publishedAt),
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
              if (release.body.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  release.body.trim(),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontSize: 12.5,
                    height: 1.55,
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

class _PaneTab extends StatelessWidget {
  const _PaneTab({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final CollectionPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? palette.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? palette.accent : palette.textSecondary,
                    fontSize: 12,
                    fontVariations: [
                      FontVariation.weight(selected ? 620 : 545),
                    ],
                  ),
                ),
                if (count != null && count! > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: TextStyle(color: palette.textMuted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.palette,
    required this.label,
    this.dot = false,
  });

  final CollectionPalette palette;
  final String label;
  final bool dot;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(color: palette.textMuted, fontSize: 11.5),
          ),
        ],
      );
}

class _FlatButton extends StatefulWidget {
  const _FlatButton({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final CollectionPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  State<_FlatButton> createState() => _FlatButtonState();
}

class _FlatButtonState extends State<_FlatButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: widget.palette.hover.withValues(alpha: hovered ? 1 : 0),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 13,
                  color: widget.palette.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.palette.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
