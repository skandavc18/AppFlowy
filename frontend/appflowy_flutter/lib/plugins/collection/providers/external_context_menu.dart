// Right-clicking inside a folder that lives in a service.
//
// A mounted Drive folder is browsed like any other folder, so it answers a
// right click like any other folder. What it offers depends on what the
// account can do AND on whether the mount has been allowed to write — a
// read-only mount shows no action that would change somebody's Drive.

import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_clipboard.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

enum _ItemAction {
  open,
  openInService,
  copyLink,
  copy,
  cut,
  saveCopy,
  favourite,
  rename,
  delete,
}

enum _BackgroundAction {
  newFolder,
  upload,
  paste,
  allowChanges,
  refresh,
  openInService,
}

/// The menu for one object inside a service's folder.
Future<void> showExternalItemMenu(
  BuildContext context, {
  required ProviderController controller,
  required ProviderNode node,
  required Offset position,
  required VoidCallback onOpen,
}) async {
  final can = controller.capabilities;
  final writable = !node.readOnly;

  final action = await showAppMenu<_ItemAction>(
    context: context,
    globalPosition: position,
    entries: [
      AppMenuItem(
        label: node.isFolder
            ? LocaleKeys.providers_openFolder.tr()
            : LocaleKeys.providers_open.tr(),
        icon: node.isFolder
            ? Icons.folder_open_rounded
            : Icons.open_in_full_rounded,
        value: _ItemAction.open,
      ),
      if (node.webUrl != null) ...[
        AppMenuItem(
          label: LocaleKeys.providers_openIn
              .tr(args: [controller.source.info.label]),
          icon: Icons.open_in_new_rounded,
          value: _ItemAction.openInService,
        ),
        AppMenuItem(
          label: LocaleKeys.providers_copyLink.tr(),
          icon: Icons.link_rounded,
          value: _ItemAction.copyLink,
        ),
      ],
      if (!node.isFolder && can.canDownload) ...[
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.providers_saveCopy.tr(),
          icon: Icons.download_rounded,
          value: _ItemAction.saveCopy,
        ),
      ],
      if (can.canDownload || can.canMove) ...[
        const AppMenuSeparator(),
        if (can.canDownload)
          AppMenuItem(
            label: LocaleKeys.button_copy.tr(),
            icon: Icons.copy_rounded,
            value: _ItemAction.copy,
          ),
        if (can.canMove && writable)
          AppMenuItem(
            label: LocaleKeys.providers_cut.tr(),
            icon: Icons.content_cut_rounded,
            value: _ItemAction.cut,
          ),
      ],
      if (can.canFavourite && writable)
        AppMenuItem(
          label: node.favourite
              ? LocaleKeys.providers_unfavourite.tr()
              : LocaleKeys.providers_favourite.tr(),
          icon:
              node.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
          value: _ItemAction.favourite,
        ),
      if ((can.canRename || can.canDelete) && writable) ...[
        const AppMenuSeparator(),
        if (can.canRename && writable)
          AppMenuItem(
            label: LocaleKeys.button_rename.tr(),
            icon: Icons.drive_file_rename_outline_rounded,
            value: _ItemAction.rename,
          ),
        if (can.canDelete && writable)
          AppMenuItem(
            label: LocaleKeys.button_delete.tr(),
            icon: Icons.delete_outline_rounded,
            destructive: true,
            value: _ItemAction.delete,
          ),
      ],
    ],
  );
  if (action == null || !context.mounted) {
    return;
  }

  switch (action) {
    case _ItemAction.open:
      onOpen();
    case _ItemAction.openInService:
      await _openInBrowser(node.webUrl);
    case _ItemAction.copyLink:
      await Clipboard.setData(ClipboardData(text: node.webUrl ?? ''));
      if (context.mounted) {
        showToastNotification(message: LocaleKeys.providers_linkCopied.tr());
      }
    case _ItemAction.saveCopy:
      await _saveCopy(context, controller: controller, node: node);
    case _ItemAction.copy:
      ExternalClipboard.instance
          .copy(node, connectionId: controller.source.connectionId);
    case _ItemAction.cut:
      ExternalClipboard.instance
          .cut(node, connectionId: controller.source.connectionId);
    case _ItemAction.favourite:
      await controller.setFavourite(node, !node.favourite);
    case _ItemAction.rename:
      await _rename(context, controller: controller, node: node);
    case _ItemAction.delete:
      await _delete(context, controller: controller, node: node);
  }
}

/// The menu for the empty space inside a service's folder.
Future<void> showExternalBackgroundMenu(
  BuildContext context, {
  required ProviderController controller,
  required String? containerId,
  required Offset position,
  VoidCallback? onAllowChanges,
}) async {
  final can = controller.capabilities;
  final label = controller.source.info.label;
  final waiting = ExternalClipboard.instance.entry;

  final action = await showAppMenu<_BackgroundAction>(
    context: context,
    globalPosition: position,
    entries: [
      if (can.canCreateFolder)
        AppMenuItem(
          label: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          icon: Icons.create_new_folder_rounded,
          value: _BackgroundAction.newFolder,
        ),
      if (can.canUpload)
        AppMenuItem(
          label: LocaleKeys.providers_uploadHere.tr(),
          icon: Icons.upload_rounded,
          value: _BackgroundAction.upload,
        ),
      if (can.canUpload && waiting != null)
        AppMenuItem(
          label: LocaleKeys.providers_pasteHere.tr(args: [waiting.node.name]),
          icon: Icons.content_paste_rounded,
          value: _BackgroundAction.paste,
        ),
      // Nothing above appears while the mount is read only, so this is the
      // only way back to writing — an empty menu would be a dead end.
      if (onAllowChanges != null)
        AppMenuItem(
          label: LocaleKeys.providers_mount_allowChanges.tr(),
          icon: Icons.lock_open_rounded,
          subtitle:
              LocaleKeys.providers_mount_allowChangesBody.tr(args: [label]),
          value: _BackgroundAction.allowChanges,
        ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.workspaceFolderExplorer_refresh.tr(),
        icon: Icons.refresh_rounded,
        value: _BackgroundAction.refresh,
      ),
      AppMenuItem(
        label: LocaleKeys.providers_openIn.tr(args: [label]),
        icon: Icons.open_in_new_rounded,
        value: _BackgroundAction.openInService,
      ),
    ],
  );
  if (action == null || !context.mounted) {
    return;
  }

  switch (action) {
    case _BackgroundAction.newFolder:
      final name = await showAFTextFieldDialog(
        context: context,
        title: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
        initialValue: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
      );
      if (name != null && name.trim().isNotEmpty) {
        await controller.createFolder(name.trim(), parentId: containerId);
      }
    case _BackgroundAction.upload:
      await _upload(controller: controller, containerId: containerId);
    case _BackgroundAction.paste:
      await _paste(controller: controller, containerId: containerId);
    case _BackgroundAction.allowChanges:
      onAllowChanges?.call();
    case _BackgroundAction.refresh:
      await controller.resync();
    case _BackgroundAction.openInService:
      await _openInBrowser(controller.source.remoteUrl);
  }
}

/// Puts whatever was copied or cut into [containerId].
///
/// Moving is asked of the service when it can see both ends; anything else is
/// a real copy of the bytes, which is the only way across two accounts.
Future<void> _paste({
  required ProviderController controller,
  required String? containerId,
}) async {
  final waiting = ExternalClipboard.instance.entry;
  if (waiting == null) {
    return;
  }
  final sameAccount = waiting.connectionId == controller.source.connectionId;

  if (waiting.cut && sameAccount) {
    final target = containerId ?? controller.source.remoteId;
    if (target.isEmpty) {
      return;
    }
    if (await controller.move(waiting.node, parentId: target)) {
      ExternalClipboard.instance.clear();
    }
    return;
  }

  if (waiting.node.isFolder) {
    Log.warn('A folder can only be pasted where it can be moved.');
    return;
  }

  try {
    final path = await controller.materialize(waiting.node);
    if (path == null) {
      return;
    }
    final copied = await controller.upload(
      providerFileNameFor(waiting.node),
      await File(path).readAsBytes(),
      parentId: containerId,
      mimeType: waiting.node.mimeType,
    );
    if (copied && waiting.cut) {
      ExternalClipboard.instance.clear();
    }
  } catch (error) {
    Log.warn('Unable to paste "${waiting.node.name}": $error');
  }
}

Future<void> _openInBrowser(String? url) async {
  if (url == null || url.isEmpty) {
    return;
  }
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

Future<void> _rename(
  BuildContext context, {
  required ProviderController controller,
  required ProviderNode node,
}) async {
  final name = await showAFTextFieldDialog(
    context: context,
    title: LocaleKeys.button_rename.tr(),
    initialValue: node.name,
  );
  final trimmed = name?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == node.name) {
    return;
  }
  await controller.rename(node, trimmed);
}

Future<void> _delete(
  BuildContext context, {
  required ProviderController controller,
  required ProviderNode node,
}) async {
  await showCustomConfirmDialog(
    context: context,
    title: LocaleKeys.button_delete.tr(),
    description: LocaleKeys.providers_deleteBody
        .tr(args: [node.name, controller.source.info.label]),
    builder: (_) => const SizedBox.shrink(),
    confirmLabel: LocaleKeys.button_delete.tr(),
    style: ConfirmPopupStyle.cancelAndOk,
    onConfirm: () => unawaited(controller.delete(node)),
  );
}

/// Writes a copy of [node] somewhere the person chooses.
Future<void> _saveCopy(
  BuildContext context, {
  required ProviderController controller,
  required ProviderNode node,
}) async {
  try {
    final source = await controller.materialize(node);
    if (source == null) {
      if (context.mounted) {
        showToastNotification(
          message: LocaleKeys.providers_cannotOpen.tr(),
          type: ToastificationType.warning,
        );
      }
      return;
    }
    final name = providerFileNameFor(node);
    final target = await GetIt.I<FilePickerService>().saveFile(fileName: name);
    if (target == null) {
      return;
    }
    await File(source).copy(target);
    if (context.mounted) {
      showToastNotification(message: LocaleKeys.providers_savedCopy.tr());
    }
  } catch (error) {
    Log.warn('Unable to save a copy of a remote file: $error');
    if (context.mounted) {
      showToastNotification(
        message: LocaleKeys.providers_cannotOpen.tr(),
        type: ToastificationType.error,
      );
    }
  }
}

Future<void> _upload({
  required ProviderController controller,
  required String? containerId,
}) async {
  final picked = await GetIt.I<FilePickerService>().pickFiles(
    dialogTitle: LocaleKeys.providers_uploadHere.tr(),
    allowMultiple: true,
  );
  for (final file in picked?.files ?? const []) {
    final path = file.path;
    if (path == null) {
      continue;
    }
    try {
      await controller.upload(
        file.name,
        await File(path).readAsBytes(),
        parentId: containerId,
      );
    } catch (error) {
      Log.warn('Unable to upload "${file.name}": $error');
    }
  }
}
