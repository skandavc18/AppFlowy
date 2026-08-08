// Copying objects out of a service into the workspace.
//
// Binding a collection to a service is the right answer when the service is
// the home of the content. Importing is the right answer when it is not: a
// Google Photos picking session EXPIRES, so an album that only points at one
// eventually shows nothing at all, and a few files wanted out of a Drive are
// not a reason to hand a whole folder over to Google.
//
// What lands in the workspace is an ordinary file. It is read by the same
// viewers, survives the service going away, and works offline.

import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/external_picker.dart';
import 'package:appflowy/plugins/collection/providers/google_photos_picker.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// How far an import has got.
@immutable
class ExternalImportProgress {
  const ExternalImportProgress({
    required this.done,
    required this.total,
    this.name = '',
  });

  final int done;
  final int total;
  final String name;

  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);
}

/// A file this large is not something somebody meant to pull into a note.
const maximumImportBytes = 256 << 20;

/// Asks a service for objects and copies them into [parentViewId].
///
/// Returns how many arrived. Google Photos goes through its own picker
/// because Google no longer lets an application list a library at all.
Future<int> importFromService(
  BuildContext context, {
  required String parentViewId,
  required ProviderServiceInfo info,
}) async {
  await ProviderConnections.instance.ensureLoaded();
  if (!context.mounted) {
    return 0;
  }

  final selection = info.picksExternally
      // ignore: use_build_context_synchronously
      ? await _pickThroughService(context, info: info)
      // ignore: use_build_context_synchronously
      : await showExternalFilePicker(context, info: info);
  if (selection == null || selection.nodes.isEmpty || !context.mounted) {
    return 0;
  }

  return _copyIn(
    context,
    parentViewId: parentViewId,
    source: selection.source,
    nodes: selection.nodes,
    label: info.label,
  );
}

/// Runs Google's own picker, then reads what the session was given.
Future<ExternalSelection?> _pickThroughService(
  BuildContext context, {
  required ProviderServiceInfo info,
}) async {
  var accounts = ProviderConnections.instance.forService(info.service);
  if (accounts.isEmpty) {
    // Being told to connect and then left with nothing to press is a dead
    // end. Google Photos needs its own permission even when the same Google
    // account is already signed in for Drive, so ask for it here.
    final connected = await showProviderConnectDialog(context, info: info);
    if (connected == null) {
      return null;
    }
    accounts = ProviderConnections.instance.forService(info.service);
    if (accounts.isEmpty || !context.mounted) {
      return null;
    }
  }

  final bound = await pickGooglePhotosSelection(
    context,
    connection: accounts.first,
  );
  if (bound == null) {
    return null;
  }

  CollectionProvider? provider;
  try {
    final live = ProviderRegistry.create(bound);
    if (live == null) {
      return null;
    }
    provider = live;
    await live.ensureReady();
    final page = await live.list();
    return ExternalSelection(source: bound, nodes: page.nodes);
  } on ProviderFailure catch (failure) {
    Log.warn('Unable to read a picked selection: ${failure.status.name}');
    return null;
  } catch (error) {
    Log.warn('Unable to read a picked selection: $error');
    return null;
  } finally {
    provider?.dispose();
  }
}

/// Chooses ONE object out of a service, whichever way that service allows.
///
/// A page embeds a thing rather than a place, and Google no longer lets an
/// application list a photo library at all — so a service that picks in its
/// own interface goes through that, and everything else through the browser.
Future<ExternalPick?> chooseExternalObject(
  BuildContext context, {
  required ProviderServiceInfo info,
}) async {
  if (!info.picksExternally) {
    return showExternalPicker(context, info: info);
  }

  await ProviderConnections.instance.ensureLoaded();
  if (!context.mounted) {
    return null;
  }
  // ignore: use_build_context_synchronously
  final selection = await _pickThroughService(context, info: info);
  final nodes = selection?.nodes ?? const <ProviderNode>[];
  if (selection == null || nodes.isEmpty) {
    return null;
  }
  if (nodes.length == 1 || !context.mounted) {
    return ExternalPick(source: selection.source, node: nodes.first);
  }
  // ignore: use_build_context_synchronously
  final one = await showExternalNodePicker(
    context,
    info: info,
    nodes: nodes,
  );
  return one == null ? null : ExternalPick(source: selection.source, node: one);
}

/// Mounts a folder from a service inside [parentViewId].
///
/// A mount is a folder of its own that happens to read somewhere else, rather
/// than a service taking the place of what the workspace already holds — so
/// the folder it lands in keeps its own files and gains a door to the other.
/// Read only until somebody says otherwise: nothing should be able to write
/// to a person's Drive because they browsed it.
Future<ViewPB?> mountExternalFolder(
  BuildContext context, {
  required String parentViewId,
  required ProviderServiceInfo info,
}) async {
  await ProviderConnections.instance.ensureLoaded();
  if (!context.mounted) {
    return null;
  }

  // ignore: use_build_context_synchronously
  final picked = await showExternalPicker(
    context,
    info: info,
    containersOnly: true,
  );
  if (picked == null) {
    return null;
  }

  final created = await const WorkspaceItemService().createFolder(
    parentViewId: parentViewId,
    name: picked.node.name.trim().isEmpty ? info.label : picked.node.name,
  );

  return created.fold(
    (view) async {
      final source = picked.source.copyWith(
        remoteId: picked.node.id,
        remoteName: picked.node.name,
        readOnly: true,
        lastSyncedAt: DateTime.now(),
      );
      await ViewBackendService.updateView(
        viewId: view.id,
        extra: source.mergeIntoExtra(view.extra),
      );
      return view;
    },
    (error) {
      Log.warn('Unable to mount a folder: ${error.msg}');
      return null;
    },
  );
}

/// Downloads [nodes] and files each one under [parentViewId].
Future<int> _copyIn(
  BuildContext context, {
  required String parentViewId,
  required CollectionSource source,
  required List<ProviderNode> nodes,
  required String label,
}) async {
  final wanted = [
    for (final node in nodes)
      if (!node.isFolder) node,
  ];
  if (wanted.isEmpty) {
    return 0;
  }

  final progress = ValueNotifier<ExternalImportProgress>(
    ExternalImportProgress(done: 0, total: wanted.length),
  );
  final cancelled = ValueNotifier<bool>(false);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ImportProgressDialog(
        progress: progress,
        onCancel: () => cancelled.value = true,
        label: label,
      ),
    ),
  );

  final service = const WorkspaceItemService();
  var imported = 0;
  CollectionProvider? provider;
  try {
    final live = ProviderRegistry.create(source);
    if (live == null) {
      throw const ProviderFailure(ProviderStatus.error);
    }
    provider = live;
    await live.ensureReady();

    for (final node in wanted) {
      if (cancelled.value) {
        break;
      }
      progress.value = ExternalImportProgress(
        done: imported,
        total: wanted.length,
        name: node.name,
      );
      if (await _copyOne(service, live, node, parentViewId)) {
        imported++;
      }
    }
  } on ProviderFailure catch (failure) {
    Log.warn('Unable to import from a service: ${failure.status.name}');
  } catch (error) {
    Log.warn('Unable to import from a service: $error');
  } finally {
    provider?.dispose();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    progress.dispose();
    cancelled.dispose();
  }

  if (context.mounted) {
    showToastNotification(
      message: imported == 0
          ? LocaleKeys.providers_import_nothing.tr()
          : LocaleKeys.providers_import_done.tr(args: ['$imported']),
      type: imported == 0
          ? ToastificationType.warning
          : ToastificationType.success,
    );
  }
  return imported;
}

Future<bool> _copyOne(
  WorkspaceItemService service,
  CollectionProvider provider,
  ProviderNode node,
  String parentViewId,
) async {
  try {
    final size = node.byteSize;
    if (size != null && size > maximumImportBytes) {
      return false;
    }
    final path = await provider.materialize(node);
    if (path == null) {
      return false;
    }
    final bytes = await File(path).readAsBytes();
    final name = providerFileNameFor(node);
    final created = await service.createBlankFile(
      parentViewId: parentViewId,
      kind: WorkspaceFileKind.fromName(name) ?? _kindOf(node.kind),
      name: name,
      content: bytes,
    );
    return created.fold((_) => true, (error) {
      Log.warn('Unable to file an imported object: ${error.msg}');
      return false;
    });
  } catch (error) {
    Log.warn('Unable to import "${node.name}": $error');
    return false;
  }
}

WorkspaceFileKind _kindOf(ProviderNodeKind kind) => switch (kind) {
      ProviderNodeKind.image => WorkspaceFileKind.image,
      ProviderNodeKind.video => WorkspaceFileKind.video,
      ProviderNodeKind.audio => WorkspaceFileKind.audio,
      ProviderNodeKind.pdf => WorkspaceFileKind.pdf,
      _ => WorkspaceFileKind.file,
    };

/// A usable file name for [node].
///
/// A photo library names an item `IMG_0042` with no extension at all, so the
/// type it declared is what decides how it will open once it is here.
@visibleForTesting
String importFileNameFor(ProviderNode node) => providerFileNameFor(node);

class _ImportProgressDialog extends StatelessWidget {
  const _ImportProgressDialog({
    required this.progress,
    required this.onCancel,
    required this.label,
  });

  final ValueListenable<ExternalImportProgress> progress;
  final VoidCallback onCancel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: ViewerCard(
          color: palette.floatingSurface,
          reactsToPointer: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
            child: ValueListenableBuilder<ExternalImportProgress>(
              valueListenable: progress,
              builder: (context, value, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    LocaleKeys.providers_import_working.tr(args: [label]),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontVariations: const [FontVariation.weight(620)],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: value.fraction,
                      minHeight: 4,
                      backgroundColor: palette.hover,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value.name.isEmpty
                        ? '${value.done} / ${value.total}'
                        : '${value.done} / ${value.total} · ${value.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textMuted, fontSize: 11.5),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onCancel,
                      child: Text(LocaleKeys.button_cancel.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
