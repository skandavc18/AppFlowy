import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Presentation only. These IDs never describe, or rewrite, file contents.
/// `compact` is the historical folder-embed ID, retained for Thumbnails.
abstract final class FileBrowserViewIds {
  static const gallery = 'gallery';
  static const thumbnails = 'compact';
  static const tiles = 'tiles';
  static const list = 'list';
  static const details = 'details';
  static const columns = 'columns';
  static const tree = 'tree';
}

enum FileBrowserViewMode {
  gallery(
    FileBrowserViewIds.gallery,
    LocaleKeys.collections_embed_styles_gallery,
    Icons.grid_view_rounded,
  ),
  thumbnails(
    FileBrowserViewIds.thumbnails,
    'Thumbnails',
    Icons.view_carousel_rounded,
  ),
  tiles(FileBrowserViewIds.tiles, 'Tiles', Icons.view_module_rounded),
  list(
    FileBrowserViewIds.list,
    LocaleKeys.collections_embed_styles_list,
    Icons.view_list_rounded,
  ),
  details(FileBrowserViewIds.details, 'Details', Icons.table_rows_rounded),
  columns(FileBrowserViewIds.columns, 'Columns', Icons.view_column_rounded),
  tree(
    FileBrowserViewIds.tree,
    LocaleKeys.workspaceFolderExplorer_treeView,
    Icons.account_tree_rounded,
  );

  const FileBrowserViewMode(this.id, this.labelKey, this.icon);

  final String id;
  final String labelKey;
  final IconData icon;

  String get label => labelKey.tr();

  static FileBrowserViewMode fromValue(
    Object? value, {
    FileBrowserViewMode fallback = FileBrowserViewMode.gallery,
  }) {
    if (value == 'thumbnails') return thumbnails;
    for (final mode in values) {
      if (value == mode.id) return mode;
    }
    return fallback;
  }
}

/// Shared key inside an existing node/view preview-metadata map. Folder views
/// use the same key in their extra map; collection embeds keep `style`.
abstract final class FileBrowserViewSettings {
  static const key = 'file_browser_view';

  static FileBrowserViewMode read(
    Map<String, dynamic> metadata, {
    FileBrowserViewMode fallback = FileBrowserViewMode.gallery,
  }) =>
      FileBrowserViewMode.fromValue(metadata[key], fallback: fallback);

  static Map<String, dynamic> withMode(
    Map<String, dynamic> metadata,
    FileBrowserViewMode mode,
  ) =>
      {...metadata, key: mode.id};

  static FileBrowserViewMode fromExtra(
    String extra, {
    FileBrowserViewMode fallback = FileBrowserViewMode.gallery,
  }) {
    try {
      final decoded = extra.isEmpty ? <String, dynamic>{} : jsonDecode(extra);
      return decoded is Map<String, dynamic>
          ? read(decoded, fallback: fallback)
          : fallback;
    } on FormatException {
      return fallback;
    }
  }

  /// Unlike the forgiving reader, refuse malformed extra on a write rather
  /// than discarding unrelated cover, permission, or provider settings.
  static String mergeExtra(String extra, FileBrowserViewMode mode) {
    final decoded = extra.isEmpty ? <String, dynamic>{} : jsonDecode(extra);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid file browser view metadata');
    }
    return jsonEncode(withMode(decoded, mode));
  }
}

List<AppMenuEntry> fileBrowserViewEntries({
  required FileBrowserViewMode selected,
  required ValueChanged<FileBrowserViewMode> onChanged,
}) =>
    [
      for (final mode in FileBrowserViewMode.values)
        AppMenuItem(
          label: mode.label,
          icon: mode.icon,
          selected: selected == mode,
          onSelected: () => onChanged(mode),
        ),
    ];

/// A native keyboard-accessible control; the shared menu owns focus, theme,
/// reduced motion, and the lifetime of preview-toolbar visibility holds.
class FileBrowserViewButton extends StatelessWidget {
  const FileBrowserViewButton({
    super.key,
    required this.mode,
    required this.onChanged,
    this.compact = false,
  });

  final FileBrowserViewMode mode;
  final ValueChanged<FileBrowserViewMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (buttonContext) => WorkspaceControlButton(
          key: const ValueKey('file-browser-view-button'),
          icon: mode.icon,
          label: compact ? null : mode.label,
          tooltip: 'View: ${mode.label}',
          onPressed: () {
            final box = buttonContext.findRenderObject() as RenderBox?;
            if (box == null || !box.hasSize) return;
            unawaited(
              showAppMenu<void>(
                context: buttonContext,
                globalPosition: box.localToGlobal(Offset(0, box.size.height)),
                entries: fileBrowserViewEntries(
                  selected: mode,
                  onChanged: onChanged,
                ),
              ),
            );
          },
        ),
      );
}
