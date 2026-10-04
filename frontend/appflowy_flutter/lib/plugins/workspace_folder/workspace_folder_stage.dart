import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/collection/providers/external_folder_stage.dart';
import 'package:appflowy/plugins/collection/providers/source_picker.dart';
import 'package:appflowy/shared/file_browser/file_browser_scroll_view.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_permissions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A workspace folder, wherever its contents actually live.
///
/// An ordinary folder holds what the workspace stores. Connecting one to a
/// service swaps what it lists without changing what it is: same page, same
/// place in the sidebar, same name. That is the whole point of keeping the
/// binding in `ViewPB.extra` rather than inventing a second kind of folder.
class WorkspaceFolderStage extends StatefulWidget {
  const WorkspaceFolderStage({
    super.key,
    required this.view,
    this.repository = const WorkspaceItemService(),
    this.listenerFactory,
    this.providerControllerFactory,
  });

  final ViewPB view;
  final WorkspaceItemRepository repository;
  final ViewListener Function(String)? listenerFactory;
  final ProviderController Function(String, CollectionSource)?
      providerControllerFactory;

  @override
  State<WorkspaceFolderStage> createState() => _WorkspaceFolderStageState();
}

class _WorkspaceFolderStageState extends State<WorkspaceFolderStage> {
  late ViewPB _view = ViewPB.fromBuffer(widget.view.writeToBuffer());
  WorkspaceExplorerController? _identity;
  ViewListener? _listener;
  final _search = TextEditingController();
  int _generation = 0;
  bool _available = true;
  Future<void> _writes = Future.value();

  ViewPB get view => _identity?.viewForId(_view.id) ?? _view;

  bool _sameSourceBinding(CollectionSource a, CollectionSource b) =>
      a.cacheKey == b.cacheKey && a.readOnly == b.readOnly;

  @override
  void initState() {
    super.initState();
    _bindIdentity();
  }

  void _bindIdentity() {
    final generation = ++_generation;
    unawaited(_listener?.stop());
    _identity?.dispose();
    _identity = null;
    _available = true;
    if (!_view.source.isRemote) return;
    // Identity only: seed the real ViewPB already supplied by the page owner.
    // Do not initialize/read native children of a provider-backed folder.
    _identity = WorkspaceExplorerController(
      root: _view,
      repository: widget.repository,
      listenForUpdates: false,
      canWrite: () => _canEditSource && !source.readOnly,
    );
    _listener = (widget.listenerFactory?.call(_view.id) ??
        ViewListener(viewId: _view.id))
      ..start(
        onViewUpdated: (next) {
          if (!mounted ||
              generation != _generation ||
              !_available ||
              next.id != _view.id) {
            return;
          }
          final rebind = !_sameSourceBinding(source, next.source);
          setState(() {
            _view = ViewPB.fromBuffer(next.writeToBuffer());
            if (rebind) {
              _bindIdentity();
            } else {
              _identity?.updateRoot(_view);
            }
          });
        },
        onViewDeleted: (_) {
          if (mounted && generation == _generation) {
            setState(() => _available = false);
          }
        },
        onViewMoveToTrash: (_) {
          if (mounted && generation == _generation) {
            setState(() => _available = false);
          }
        },
      );
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_listener?.stop());
    _identity?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WorkspaceFolderStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      final rebind = oldWidget.view.id != widget.view.id ||
          !_sameSourceBinding(source, widget.view.source);
      _view = ViewPB.fromBuffer(widget.view.writeToBuffer());
      if (rebind) {
        _bindIdentity();
      } else {
        _identity?.updateRoot(_view);
      }
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.listenerFactory != widget.listenerFactory) {
      _view = ViewPB.fromBuffer(view.writeToBuffer());
      _bindIdentity();
    }
  }

  CollectionSource get source => view.source;

  bool get _canEditSource =>
      mounted &&
      _available &&
      canEditFolderExplorerView(
        view,
        pageAccess: context.read<PageAccessLevelBloc?>()?.state,
        workspace: context.read<UserWorkspaceBloc?>()?.state.currentWorkspace,
        identity: true,
      );

  @override
  Widget build(BuildContext context) {
    context.watch<PageAccessLevelBloc?>();
    final workspace = context.watch<UserWorkspaceBloc?>()?.state;
    if (source.isLocal) {
      return FolderExplorer(
        key: ValueKey(view.id),
        rootView: view,
        onConnectSource: () => unawaited(_changeSource()),
      );
    }

    final identity = _identity!;
    return FileBrowserPageHeader(
      header: ListenableBuilder(
        listenable: identity,
        builder: (context, _) => FolderGalleryHeader(
          // Retain through provider statuses; invalidate open identity actions
          // only when the actual source/permission binding changes.
          key: ValueKey(
            (
              view.id,
              source.cacheKey,
              source.readOnly,
              _available,
              _canEditSource
            ),
          ),
          controller: identity,
          searchController: _search,
          showControls: false,
          showStatistics: false,
          userProfile: workspace?.userProfile,
          workspace: workspace?.currentWorkspace,
          onSearchChanged: (_) {},
          onNavigate: (_) {},
          onAddFile: (_) {},
          onCreateCollection: (_) {},
          onCreateDatabase: (_) {},
          onMore: (_) {},
        ),
      ),
      child: ExternalFolderStage(
        key: ValueKey(view.id),
        collectionId: view.id,
        source: source,
        controllerFactory: widget.providerControllerFactory,
        canEditSource: () => _canEditSource,
        onSourceChanged: (next) => unawaited(_persist(next)),
        onChangeSource:
            _canEditSource ? () => unawaited(_changeSource()) : null,
        onDisconnect: _canEditSource ? () => unawaited(_disconnect()) : null,
      ),
    );
  }

  Future<void> _changeSource() async {
    if (!_canEditSource) return;
    final viewId = view.id;
    final previous = source;
    final chosen = await showCollectionSourcePicker(
      context,
      kind: CollectionKind.folder,
      current: previous,
    );
    if (chosen == null ||
        !_canEditSource ||
        view.id != viewId ||
        source.cacheKey != previous.cacheKey ||
        chosen.cacheKey == previous.cacheKey) {
      return;
    }
    if (previous.isRemote) {
      unawaited(ProviderCache.instance.evict(previous.cacheKey));
    }
    await _persist(chosen);
  }

  Future<void> _disconnect() async {
    if (!_canEditSource) return;
    final previous = source;
    if (previous.isRemote) {
      unawaited(ProviderCache.instance.evict(previous.cacheKey));
    }
    await _persist(CollectionSource.local);
  }

  Future<void> _persist(CollectionSource next) {
    final generation = _generation;
    final previous = source;
    final operation =
        _writes.then((_) => _writeSource(next, previous, generation));
    _writes = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        Log.error('Unable to save the folder source', error);
      },
    );
    return _writes;
  }

  Future<void> _writeSource(
    CollectionSource next,
    CollectionSource previous,
    int generation,
  ) async {
    if (!_canEditSource) return;
    final viewId = view.id;
    bool current() =>
        _canEditSource &&
        generation == _generation &&
        view.id == viewId &&
        source.cacheKey == previous.cacheKey &&
        source.readOnly == previous.readOnly;
    if (!current()) return;
    final read = await widget.repository.getView(viewId);
    final live = read.fold<ViewPB?>((value) => value, (_) => null);
    if (!current() ||
        live == null ||
        live.id != viewId ||
        live.isLocked ||
        live.source.cacheKey != previous.cacheKey ||
        live.source.readOnly != previous.readOnly) {
      return;
    }
    // A forgiving read codec must not erase malformed unrelated metadata.
    ViewCoverCodec.decodeExtra(live.extra);
    final extra = next.mergeIntoExtra(live.extra);
    final result = await ViewBackendService.updateView(
      viewId: viewId,
      extra: extra,
    );
    if (!current() || result.isFailure) {
      return;
    }
    setState(() {
      _view = ViewPB()
        ..mergeFromMessage(live)
        ..extra = extra;
      if (!_sameSourceBinding(previous, next)) {
        _bindIdentity();
      } else {
        _identity?.updateRoot(_view);
      }
    });
  }
}
