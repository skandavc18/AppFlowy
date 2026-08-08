import 'dart:async';

import 'package:appflowy/plugins/collection/providers/external_folder_stage.dart';
import 'package:appflowy/plugins/collection/providers/source_picker.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// A workspace folder, wherever its contents actually live.
///
/// An ordinary folder holds what the workspace stores. Connecting one to a
/// service swaps what it lists without changing what it is: same page, same
/// place in the sidebar, same name. That is the whole point of keeping the
/// binding in `ViewPB.extra` rather than inventing a second kind of folder.
class WorkspaceFolderStage extends StatefulWidget {
  const WorkspaceFolderStage({super.key, required this.view});

  final ViewPB view;

  @override
  State<WorkspaceFolderStage> createState() => _WorkspaceFolderStageState();
}

class _WorkspaceFolderStageState extends State<WorkspaceFolderStage> {
  late ViewPB view = widget.view;

  @override
  void didUpdateWidget(WorkspaceFolderStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      view = widget.view;
    }
  }

  CollectionSource get source => view.source;

  @override
  Widget build(BuildContext context) {
    if (source.isLocal) {
      return FolderExplorer(
        key: ValueKey(view.id),
        rootView: view,
        onConnectSource: () => unawaited(_changeSource()),
      );
    }

    return ExternalFolderStage(
      key: ValueKey('${view.id}-${source.cacheKey}'),
      collectionId: view.id,
      source: source,
      onSourceChanged: (next) => unawaited(_persist(next)),
      onChangeSource: () => unawaited(_changeSource()),
      onDisconnect: () => unawaited(_disconnect()),
    );
  }

  Future<void> _changeSource() async {
    final previous = source;
    final chosen = await showCollectionSourcePicker(
      context,
      kind: CollectionKind.folder,
      current: previous,
    );
    if (chosen == null || !mounted || chosen.cacheKey == previous.cacheKey) {
      return;
    }
    if (previous.isRemote) {
      unawaited(ProviderCache.instance.evict(previous.cacheKey));
    }
    await _persist(chosen);
  }

  Future<void> _disconnect() async {
    final previous = source;
    if (previous.isRemote) {
      unawaited(ProviderCache.instance.evict(previous.cacheKey));
    }
    await _persist(CollectionSource.local);
  }

  Future<void> _persist(CollectionSource next) async {
    final extra = next.mergeIntoExtra(view.extra);
    await ViewBackendService.updateView(viewId: view.id, extra: extra);
    if (!mounted) {
      return;
    }
    setState(() {
      view = ViewPB()
        ..mergeFromMessage(view)
        ..extra = extra;
    });
  }
}
