import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/album/album_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_content_policy.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a right click on one piece of media offers.
enum AlbumItemAction {
  open,
  slideshowFromHere,
  favourite,
  info,
  openInWorkspace,
  copyCoordinates,
  rename,
  saveCopy,
  delete,
}

/// What a right click on the album itself offers.
enum AlbumBackgroundAction {
  slideshow,
  showNames,
  refresh,
}

/// The actions for [item], run against the album.
///
/// Everything a person can do to a picture is in one place, so the wall, the
/// filmstrip, the playlist and the places strip all offer the same menu.
Future<void> showAlbumItemMenu({
  required BuildContext context,
  required Offset globalPosition,
  required AlbumController controller,
  required CollectionPalette palette,
  required AlbumMediaItem item,
  required VoidCallback onOpen,
  required VoidCallback onOpenInfo,
  required VoidCallback onSlideshowFromHere,
  required ValueChanged<AlbumMediaItem> onOpenInWorkspace,
}) async {
  final favourite = controller.state.isFavourite(item.id);
  final exif = controller.metadataFor(item).exif;
  final action = await showAppMenu<AlbumItemAction>(
    context: context,
    globalPosition: globalPosition,
    entries: [
      AppMenuItem(
        label: LocaleKeys.collections_album_open.tr(),
        icon: Icons.open_in_full_rounded,
        value: AlbumItemAction.open,
      ),
      if (item.kind.isVisual)
        AppMenuItem(
          label: LocaleKeys.collections_album_slideshowFromHere.tr(),
          icon: Icons.slideshow_rounded,
          value: AlbumItemAction.slideshowFromHere,
        ),
      AppMenuItem(
        label: favourite
            ? LocaleKeys.collections_album_unfavourite.tr()
            : LocaleKeys.collections_album_favourite.tr(),
        icon: favourite ? Icons.star_rounded : Icons.star_border_rounded,
        value: AlbumItemAction.favourite,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_album_info.tr(),
        icon: Icons.info_outline_rounded,
        value: AlbumItemAction.info,
      ),
      if (exif.hasLocation)
        AppMenuItem(
          label: LocaleKeys.collections_album_copyCoordinates.tr(),
          icon: Icons.place_rounded,
          value: AlbumItemAction.copyCoordinates,
        ),
      AppMenuItem(
        label: LocaleKeys.collections_album_openInWorkspace.tr(),
        icon: Icons.open_in_new_rounded,
        value: AlbumItemAction.openInWorkspace,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_album_rename.tr(),
        icon: Icons.drive_file_rename_outline_rounded,
        value: AlbumItemAction.rename,
      ),
      if (item.isLocal)
        AppMenuItem(
          label: LocaleKeys.collections_album_saveCopy.tr(),
          icon: Icons.download_rounded,
          value: AlbumItemAction.saveCopy,
        ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_album_delete.tr(),
        icon: Icons.delete_outline_rounded,
        value: AlbumItemAction.delete,
        destructive: true,
      ),
    ],
  );
  if (action == null || !context.mounted) {
    return;
  }

  switch (action) {
    case AlbumItemAction.open:
      onOpen();
    case AlbumItemAction.slideshowFromHere:
      onSlideshowFromHere();
    case AlbumItemAction.favourite:
      controller.toggleFavourite(item.id);
    case AlbumItemAction.info:
      onOpenInfo();
    case AlbumItemAction.openInWorkspace:
      onOpenInWorkspace(item);
    case AlbumItemAction.copyCoordinates:
      await _copyCoordinates(context, exif.latitude!, exif.longitude!);
    case AlbumItemAction.rename:
      await _rename(context, palette, item);
    case AlbumItemAction.saveCopy:
      await _saveCopy(context, item);
    case AlbumItemAction.delete:
      await _delete(context, palette, item);
  }
}

Future<void> showAlbumBackgroundMenu({
  required BuildContext context,
  required Offset globalPosition,
  required AlbumController controller,
  required CollectionPalette palette,
  required String parentViewId,
  required VoidCallback onSlideshow,
  bool showGrouping = false,
  bool showTileSize = true,
}) async {
  AlbumSort? sort;
  AlbumGrouping? grouping;
  AlbumTileSize? tileSize;
  WorkspaceFileMenuAction? media;

  final action = await showAppMenu<AlbumBackgroundAction>(
    context: context,
    globalPosition: globalPosition,
    entries: [
      AppMenuItem(
        label: LocaleKeys.collections_album_addMedia.tr(),
        icon: Icons.add_photo_alternate_rounded,
        submenu: workspaceFileKindEntries(
          kinds: CollectionContentPolicy.of(CollectionKind.album).fileKinds,
          onSelected: (selected) => media = selected,
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_album_playSlideshow.tr(),
        icon: Icons.slideshow_rounded,
        value: AlbumBackgroundAction.slideshow,
        enabled: controller.visual.isNotEmpty,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_album_sort.tr(),
        icon: Icons.swap_vert_rounded,
        submenu: [
          for (final value in AlbumSort.values)
            AppMenuItem(
              label: albumSortLabel(value),
              selected: value == controller.settings.sort,
              onSelected: () => sort = value,
            ),
        ],
      ),
      if (showGrouping)
        AppMenuItem(
          label: LocaleKeys.collections_album_group.tr(),
          icon: Icons.calendar_month_rounded,
          submenu: [
            for (final value in AlbumGrouping.values)
              AppMenuItem(
                label: albumGroupingLabel(value),
                selected: value == controller.settings.grouping,
                onSelected: () => grouping = value,
              ),
          ],
        ),
      if (showTileSize)
        AppMenuItem(
          label: LocaleKeys.collections_album_tileSize.tr(),
          icon: Icons.grid_view_rounded,
          submenu: [
            for (final value in AlbumTileSize.values)
              AppMenuItem(
                label: albumTileSizeLabel(value),
                selected: value == controller.settings.tileSize,
                onSelected: () => tileSize = value,
              ),
          ],
        ),
      AppMenuItem(
        label: LocaleKeys.collections_album_showNames.tr(),
        icon: Icons.title_rounded,
        selected: controller.settings.showNames,
        value: AlbumBackgroundAction.showNames,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_album_refresh.tr(),
        icon: Icons.refresh_rounded,
        value: AlbumBackgroundAction.refresh,
      ),
    ],
  );

  if (media != null) {
    await createWorkspaceFile(parentViewId: parentViewId, action: media!);
    return;
  }
  if (sort != null) {
    controller.updateSettings(controller.settings.copyWith(sort: sort));
    return;
  }
  if (grouping != null) {
    controller.updateSettings(controller.settings.copyWith(grouping: grouping));
    return;
  }
  if (tileSize != null) {
    controller.updateSettings(controller.settings.copyWith(tileSize: tileSize));
    return;
  }
  if (action == null) {
    return;
  }

  switch (action) {
    case AlbumBackgroundAction.slideshow:
      onSlideshow();
    case AlbumBackgroundAction.showNames:
      controller.updateSettings(
        controller.settings.copyWith(showNames: !controller.settings.showNames),
      );
    case AlbumBackgroundAction.refresh:
      controller.metadata.clear();
      await controller.ensureAllMetadata();
  }
}

Future<void> _copyCoordinates(
  BuildContext context,
  double latitude,
  double longitude,
) async {
  final label =
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  await Clipboard.setData(ClipboardData(text: label));
  if (context.mounted) {
    _notify(context, LocaleKeys.collections_album_coordinatesCopied.tr());
  }
}

Future<void> _saveCopy(BuildContext context, AlbumMediaItem item) async {
  try {
    final saved = await saveMediaBytes(
      bytes: await File(item.path).readAsBytes(),
      name: item.name,
    );
    if (saved && context.mounted) {
      _notify(context, LocaleKeys.collections_album_saved.tr());
    }
  } on Object {
    if (context.mounted) {
      _notify(context, LocaleKeys.collections_album_saveFailed.tr());
    }
  }
}

Future<void> _rename(
  BuildContext context,
  CollectionPalette palette,
  AlbumMediaItem item,
) async {
  final controller = TextEditingController(text: item.name);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _AlbumDialog(
      palette: palette,
      title: LocaleKeys.collections_album_renameTitle.tr(),
      confirmLabel: LocaleKeys.collections_album_save.tr(),
      onConfirm: () => Navigator.pop(context, controller.text.trim()),
      body: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
        style: TextStyle(color: palette.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: LocaleKeys.collections_album_renameHint.tr(),
          contentPadding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(color: palette.accent),
          ),
        ),
      ),
    ),
  );
  controller.dispose();
  if (name == null || name.isEmpty || name == item.name) {
    return;
  }
  await const WorkspaceItemService().rename(viewId: item.id, name: name);
}

Future<void> _delete(
  BuildContext context,
  CollectionPalette palette,
  AlbumMediaItem item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _AlbumDialog(
      palette: palette,
      title: LocaleKeys.collections_album_deleteTitle.tr(),
      confirmLabel: LocaleKeys.collections_album_delete.tr(),
      destructive: true,
      onConfirm: () => Navigator.pop(context, true),
      body: Text(
        LocaleKeys.collections_album_deleteDescription.tr(),
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: 12.5,
          height: 1.5,
        ),
      ),
    ),
  );
  if (confirmed ?? false) {
    await const WorkspaceItemService().delete([item.id]);
  }
}

void _notify(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

class _AlbumDialog extends StatelessWidget {
  const _AlbumDialog({
    required this.palette,
    required this.title,
    required this.confirmLabel,
    required this.body,
    required this.onConfirm,
    this.destructive = false,
  });

  final CollectionPalette palette;
  final String title;
  final String confirmLabel;
  final Widget body;
  final VoidCallback onConfirm;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: 380,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          color: palette.floatingSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border, width: 0.6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            body,
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AlbumToolbarButton(
                  palette: palette,
                  icon: Icons.close_rounded,
                  tooltip: LocaleKeys.collections_album_cancel.tr(),
                  label: LocaleKeys.collections_album_cancel.tr(),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 8),
                _ConfirmButton(
                  palette: palette,
                  label: confirmLabel,
                  destructive: destructive,
                  onPressed: onConfirm,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatefulWidget {
  const _ConfirmButton({
    required this.palette,
    required this.label,
    required this.destructive,
    required this.onPressed,
  });

  final CollectionPalette palette;
  final String label;
  final bool destructive;
  final VoidCallback onPressed;

  @override
  State<_ConfirmButton> createState() => _ConfirmButtonState();
}

class _ConfirmButtonState extends State<_ConfirmButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final base =
        widget.destructive ? const Color(0xFFCC5A57) : widget.palette.accent;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: AlbumMetrics.motion,
          curve: AlbumMetrics.curve,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(Colors.black.withValues(alpha: 0.12), base)
                : base,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
