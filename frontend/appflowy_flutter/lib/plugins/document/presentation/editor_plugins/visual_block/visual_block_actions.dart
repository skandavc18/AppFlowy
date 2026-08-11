import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a visual block offers in the shared three-dot menu.
///
/// Each block fills in the parts that apply to it and leaves the rest null,
/// so the four of them share one menu rather than growing four designs.
class VisualBlockActions {
  const VisualBlockActions({
    this.onEdit,
    this.editLabel,
    this.onFullscreen,
    this.onCopySource,
    this.copySourceLabel,
    this.exports = const <VisualBlockExport>[],
    this.onDuplicate,
    this.onDelete,
    this.extra = const <AppMenuEntry>[],
    this.editable = true,
  });

  final VoidCallback? onEdit;
  final String? editLabel;
  final VoidCallback? onFullscreen;
  final VoidCallback? onCopySource;
  final String? copySourceLabel;
  final List<VisualBlockExport> exports;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  /// Rows unique to one block — "Add child node", "Insert symbol".
  final List<AppMenuEntry> extra;

  final bool editable;
}

/// One entry in the Export submenu.
class VisualBlockExport {
  const VisualBlockExport({
    required this.label,
    required this.icon,
    required this.run,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() run;
}

/// Builds the unified menu from a block's declared actions.
List<AppMenuEntry> visualBlockMenuEntries(VisualBlockActions actions) {
  final entries = <AppMenuEntry>[];

  if (actions.onEdit != null && actions.editable) {
    entries.add(
      AppMenuItem(
        label: actions.editLabel ?? LocaleKeys.button_edit.tr(),
        icon: Icons.edit_rounded,
        onSelected: actions.onEdit,
      ),
    );
  }
  if (actions.onFullscreen != null) {
    entries.add(
      AppMenuItem(
        label: LocaleKeys.diagrams_common_fullscreen.tr(),
        icon: Icons.open_in_full_rounded,
        onSelected: actions.onFullscreen,
      ),
    );
  }
  if (actions.extra.isNotEmpty) {
    entries
      ..add(const AppMenuSeparator())
      ..addAll(actions.extra);
  }

  entries.add(const AppMenuSeparator());

  if (actions.onCopySource != null) {
    entries.add(
      AppMenuItem(
        label: actions.copySourceLabel ??
            LocaleKeys.diagrams_common_copySource.tr(),
        icon: Icons.content_copy_rounded,
        onSelected: actions.onCopySource,
      ),
    );
  }
  if (actions.onDuplicate != null && actions.editable) {
    entries.add(
      AppMenuItem(
        label: LocaleKeys.button_duplicate.tr(),
        icon: Icons.control_point_duplicate_rounded,
        onSelected: actions.onDuplicate,
      ),
    );
  }
  if (actions.exports.isNotEmpty) {
    entries.add(
      AppMenuItem(
        label: LocaleKeys.diagrams_common_export.tr(),
        icon: Icons.ios_share_rounded,
        submenu: [
          for (final export in actions.exports)
            AppMenuItem(
              label: export.label,
              icon: export.icon,
              onSelected: () => unawaited(export.run()),
            ),
        ],
      ),
    );
  }

  if (actions.onDelete != null && actions.editable) {
    entries
      ..add(const AppMenuSeparator())
      ..add(
        AppMenuItem(
          label: LocaleKeys.button_delete.tr(),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: actions.onDelete,
        ),
      );
  }

  return normalizeAppMenuEntries(entries);
}

/// Inserts a copy of [node] straight after it.
///
/// Because the whole of a visual block lives in the node's attributes, a copy
/// is a genuine duplicate — the diagram, the equation or the drawing comes
/// with it and stays editable.
Future<void> duplicateVisualBlock(EditorState editorState, Node node) async {
  final transaction = editorState.transaction
    ..insertNode(node.path.next, node.deepCopy());
  await editorState.apply(transaction);
}

Future<void> deleteVisualBlock(EditorState editorState, Node node) async {
  final transaction = editorState.transaction..deleteNode(node);
  await editorState.apply(transaction);
}

/// Puts text on the clipboard and says so.
Future<void> copyVisualBlockText(
  BuildContext context,
  String text, {
  String? message,
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) {
    return;
  }
  _toast(context, message ?? LocaleKeys.diagrams_common_copied.tr());
}

/// Offers to save bytes, reporting the outcome rather than failing silently.
Future<void> exportVisualBlockBytes(
  BuildContext context,
  Uint8List? bytes,
  String fileName,
) async {
  if (bytes == null || bytes.isEmpty) {
    if (context.mounted) {
      _toast(context, LocaleKeys.diagrams_common_exportFailed.tr());
    }
    return;
  }
  final saved = await saveMediaBytes(bytes: bytes, name: fileName);
  if (!context.mounted) {
    return;
  }
  _toast(
    context,
    saved
        ? LocaleKeys.diagrams_common_exported.tr()
        : LocaleKeys.diagrams_common_exportFailed.tr(),
  );
}

Future<void> exportVisualBlockText(
  BuildContext context,
  String text,
  String fileName,
) =>
    exportVisualBlockBytes(
      context,
      Uint8List.fromList(utf8.encode(text)),
      fileName,
    );

void _toast(BuildContext context, String message) {
  showToastNotification(context: context, message: message);
}
