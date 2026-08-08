import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/services/repository_archive.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The key a repository's settings and reading position are stored under,
/// shared by every repository view so they never disagree.
const repositoryStateKey = 'repository';

/// How deep the walker follows nested folders before it stops.
const _maxRepoDepth = 12;

/// Loads a repository's tree once and hands it to whichever view is showing.
class RepositoryHost extends StatefulWidget {
  const RepositoryHost({
    super.key,
    required this.collection,
    required this.builder,
    this.readsSource = false,
  });

  final CollectionViewContext collection;
  final Widget Function(
    BuildContext context,
    RepositoryController controller,
    CollectionPalette palette,
  ) builder;

  /// Whether the view needs every file read up front, which the symbol
  /// explorer and the dependency graph do and a file listing does not.
  final bool readsSource;

  @override
  State<RepositoryHost> createState() => _RepositoryHostState();
}

class _RepositoryHostState extends State<RepositoryHost> {
  late final RepositoryController controller;
  bool walking = false;
  bool walkQueued = false;

  RepositoryProvider? provider;
  RepositoryArchiveProgress? fetching;
  String? fetchError;

  CollectionSource get source => widget.collection.collectionView.source;

  @override
  void initState() {
    super.initState();
    controller = RepositoryController(
      initialState: widget.collection.stateFor(repositoryStateKey),
      onPersist: (state) =>
          widget.collection.onStateChanged(repositoryStateKey, state),
    );
    controller.addListener(_onChanged);
    if (source.isRemote) {
      unawaited(_fetchHosted());
    } else {
      widget.collection.explorer.addListener(_onExplorerChanged);
      unawaited(_walk());
    }
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_onExplorerChanged);
    controller.removeListener(_onChanged);
    controller.dispose();
    provider?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onExplorerChanged() => unawaited(_walk());

  /// Puts a hosted repository on disk, then reads it exactly as a local one.
  ///
  /// The whole tree arrives in one request rather than a file at a time, which
  /// is what lets the symbol outline and the dependency graph work at all.
  Future<void> _fetchHosted() async {
    setState(() {
      fetchError = null;
      fetching = const RepositoryArchiveProgress(
        stage: RepositoryArchiveStage.downloading,
      );
    });

    try {
      await ProviderConnections.instance.ensureLoaded();
      final created = ProviderRegistry.create(source);
      if (created is! RepositoryProvider) {
        throw const ProviderFailure(ProviderStatus.error);
      }
      provider?.dispose();
      provider = created;
      await created.ensureReady();

      final root = await RepositoryArchive().ensure(
        provider: created,
        source: source,
        branch: created.branch,
        onProgress: (progress) {
          if (mounted) {
            setState(() => fetching = progress);
          }
        },
      );
      if (!mounted) {
        return;
      }
      if (root == null) {
        setState(() {
          fetching = null;
          fetchError = LocaleKeys.providers_repo_noArchive.tr();
        });
        return;
      }

      final tree = RepositoryTreeViews(
        rootId: widget.collection.collectionView.id,
        root: root,
      );
      controller.setEntries(
        buildRepoTree(
          rootId: widget.collection.collectionView.id,
          childrenOf: tree.childrenOf,
        ),
      );
      setState(() => fetching = null);

      if (widget.readsSource) {
        unawaited(controller.analyseAll());
      }
    } on ProviderFailure catch (failure) {
      if (mounted) {
        setState(() {
          fetching = null;
          fetchError = switch (failure.status) {
            ProviderStatus.offline => LocaleKeys.providers_state_offlineBody
                .tr(args: [source.info.label]),
            ProviderStatus.authExpired => LocaleKeys.providers_state_expiredBody
                .tr(args: [source.info.label]),
            ProviderStatus.notFound => LocaleKeys.providers_state_missingBody
                .tr(args: [source.info.label]),
            _ => failure.detail.isNotEmpty
                ? failure.detail
                : LocaleKeys.providers_state_errorBody
                    .tr(args: [source.info.label]),
          };
        });
      }
    } catch (error) {
      Log.warn('Unable to read a hosted repository: $error');
      if (mounted) {
        setState(() {
          fetching = null;
          fetchError = LocaleKeys.providers_state_errorBody
              .tr(args: [source.info.label]);
        });
      }
    }
  }

  /// Loads every folder in the repository, then flattens it.
  ///
  /// A collection only ever has its own children loaded, so the nested
  /// folders a project is made of have to be asked for one level at a time.
  Future<void> _walk() async {
    if (walking) {
      walkQueued = true;
      return;
    }
    walking = true;
    try {
      do {
        walkQueued = false;
        final explorer = widget.collection.explorer;
        final rootId = widget.collection.collectionView.id;
        var frontier = <String>[rootId];
        var depth = 0;
        while (frontier.isNotEmpty && depth <= _maxRepoDepth) {
          final pending = [
            for (final id in frontier)
              if (!explorer.hasLoaded(id)) id,
          ];
          if (pending.isNotEmpty) {
            await Future.wait(pending.map(explorer.ensureLoaded));
            if (!mounted) {
              return;
            }
          }
          frontier = [
            for (final id in frontier)
              for (final view in explorer.childrenOf(id))
                if (view.isWorkspaceFolder || view.isCollection) view.id,
          ];
          depth += 1;
        }
        if (!mounted) {
          return;
        }
        controller.setEntries(
          buildRepoTree(
            rootId: rootId,
            childrenOf: explorer.childrenOf,
          ),
        );
      } while (walkQueued);
    } finally {
      walking = false;
    }
    if (widget.readsSource && mounted) {
      unawaited(controller.analyseAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CollectionPalette.of(context, CollectionKind.repository);

    // Nothing has been unpacked yet, so there is no tree for a view to draw.
    if (fetching != null && controller.allEntries.isEmpty) {
      return _FetchingRepository(progress: fetching!, palette: palette);
    }
    if (fetchError != null && controller.allEntries.isEmpty) {
      return _RepositoryUnavailable(
        message: fetchError!,
        palette: palette,
        onRetry: () => unawaited(_fetchHosted()),
      );
    }
    return widget.builder(context, controller, palette);
  }
}

class _FetchingRepository extends StatelessWidget {
  const _FetchingRepository({required this.progress, required this.palette});

  final RepositoryArchiveProgress progress;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 4,
                  backgroundColor: palette.hover,
                  color: palette.accent,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              progress.stage == RepositoryArchiveStage.extracting
                  ? LocaleKeys.providers_repo_unpacking.tr()
                  : LocaleKeys.providers_repo_fetching.tr(),
              style: TextStyle(color: palette.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              LocaleKeys.providers_repo_fetchingHint.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RepositoryUnavailable extends StatelessWidget {
  const _RepositoryUnavailable({
    required this.message,
    required this.palette,
    required this.onRetry,
  });

  final String message;
  final CollectionPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 24,
                color: palette.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: onRetry,
                child: Text(LocaleKeys.providers_tryAgain.tr()),
              ),
            ],
          ),
        ),
      );
}
