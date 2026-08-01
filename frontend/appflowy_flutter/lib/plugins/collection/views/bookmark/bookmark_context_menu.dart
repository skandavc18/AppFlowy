import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_dialogs.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a saved link in the system browser.
Future<void> openBookmarkInBrowser(BookmarkEntry entry) async {
  final uri = Uri.tryParse(entry.url);
  if (uri == null) {
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// The menu behind a right click and behind every card's overflow button.
Future<void> showBookmarkMenu({
  required BuildContext context,
  required BookmarkEntry entry,
  required BookmarkController controller,
  required CollectionViewContext collection,
  Offset? position,
}) async {
  final metadata = entry.metadata;
  final read = metadata.readState == BookmarkReadState.read;

  await showAppMenu<void>(
    context: context,
    globalPosition: position,
    anchor: position == null ? _anchorOf(context) : null,
    entries: [
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_read.tr(),
        icon: Icons.chrome_reader_mode_rounded,
        onSelected: () => openBookmarkReader(
          context: context,
          entry: entry,
          controller: controller,
          collection: collection,
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_openInBrowser.tr(),
        icon: Icons.open_in_new_rounded,
        onSelected: () => openBookmarkInBrowser(entry),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_copyLink.tr(),
        icon: Icons.link_rounded,
        onSelected: () => Clipboard.setData(ClipboardData(text: entry.url)),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: metadata.starred
            ? LocaleKeys.collections_bookmark_unstar.tr()
            : LocaleKeys.collections_bookmark_star.tr(),
        icon:
            metadata.starred ? Icons.star_rounded : Icons.star_outline_rounded,
        onSelected: () => controller.setStarred(entry, !metadata.starred),
      ),
      AppMenuItem(
        label: read
            ? LocaleKeys.collections_bookmark_markUnread.tr()
            : LocaleKeys.collections_bookmark_markRead.tr(),
        icon: read
            ? Icons.mark_email_unread_rounded
            : Icons.mark_email_read_rounded,
        onSelected: () => controller.setReadState(
          entry,
          read ? BookmarkReadState.unread : BookmarkReadState.read,
        ),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_refresh.tr(),
        icon: Icons.refresh_rounded,
        onSelected: () => controller.refresh(entry),
      ),
      if (metadata.hasSnapshot)
        AppMenuItem(
          label: LocaleKeys.collections_bookmark_removeOffline.tr(),
          icon: Icons.cloud_off_rounded,
          onSelected: () => controller.removeSnapshot(entry),
        )
      else
        AppMenuItem(
          label: LocaleKeys.collections_bookmark_saveOffline.tr(),
          icon: Icons.cloud_download_rounded,
          onSelected: () => controller.refresh(entry, snapshot: true),
        ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_rename.tr(),
        icon: Icons.drive_file_rename_outline_rounded,
        onSelected: () =>
            showRenameBookmarkDialog(context: context, entry: entry),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_delete.tr(),
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onSelected: () async {
          if (await confirmDeleteBookmark(context: context, entry: entry)) {
            await const BookmarkService().delete([entry.id]);
          }
        },
      ),
    ],
  );
}

/// The menu behind a right click on empty space.
Future<void> showBookmarkBackgroundMenu({
  required BuildContext context,
  required BookmarkController controller,
  required CollectionViewContext collection,
  required Offset position,
}) async {
  await showAppMenu<void>(
    context: context,
    globalPosition: position,
    entries: [
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_addLink.tr(),
        icon: Icons.add_link_rounded,
        onSelected: () => showAddBookmarkDialog(
          context: context,
          collection: collection,
          controller: controller,
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_refreshAll.tr(),
        icon: Icons.refresh_rounded,
        enabled: controller.entries.isNotEmpty,
        onSelected: controller.refreshAll,
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_autoSnapshot.tr(),
        icon: controller.settings.autoSnapshot
            ? Icons.check_box_rounded
            : Icons.check_box_outline_blank_rounded,
        onSelected: () => controller.updateSettings(
          controller.settings
              .copyWith(autoSnapshot: !controller.settings.autoSnapshot),
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.collections_bookmark_clearFilters.tr(),
        icon: Icons.filter_alt_off_rounded,
        onSelected: controller.clearFilters,
      ),
    ],
  );
}

Rect? _anchorOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) {
    return null;
  }
  return box.localToGlobal(Offset.zero) & box.size;
}

/// The overflow button a card and a feed row both carry.
class BookmarkMenuButton extends StatelessWidget {
  const BookmarkMenuButton({
    super.key,
    required this.entry,
    required this.controller,
    required this.collection,
    required this.theme,
  });

  final BookmarkEntry entry;
  final BookmarkController controller;
  final CollectionViewContext collection;
  final BookmarkTheme theme;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (context) => BookmarkAction(
          icon: Icons.more_horiz_rounded,
          tooltip: LocaleKeys.collections_bookmark_open.tr(),
          theme: theme,
          size: 26,
          onPressed: () => showBookmarkMenu(
            context: context,
            entry: entry,
            controller: controller,
            collection: collection,
          ),
        ),
      );
}
