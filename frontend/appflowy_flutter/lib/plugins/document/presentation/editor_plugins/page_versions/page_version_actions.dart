import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What can be done with one remembered state.
///
/// PURE — the rows are built with no context so the menu can be tested, and so
/// the rail, the card's own button and the preview popup cannot drift apart.
List<AppMenuEntry> pageVersionMenuEntries({
  required bool editable,
  required VoidCallback onPreview,
  required VoidCallback onRestore,
  required VoidCallback onRename,
  required VoidCallback onDiscard,
}) {
  return [
    AppMenuItem(
      label: LocaleKeys.pageVersions_preview.tr(),
      icon: Icons.visibility_rounded,
      onSelected: onPreview,
    ),
    AppMenuItem(
      label: LocaleKeys.pageVersions_restore.tr(),
      icon: Icons.settings_backup_restore_rounded,
      enabled: editable,
      onSelected: onRestore,
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.pageVersions_rename.tr(),
      icon: Icons.drive_file_rename_outline_rounded,
      onSelected: onRename,
    ),
    AppMenuItem(
      label: LocaleKeys.pageVersions_discard.tr(),
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onSelected: onDiscard,
    ),
  ];
}

Future<void> showPageVersionMenu({
  required BuildContext context,
  required Offset globalPosition,
  required bool editable,
  required VoidCallback onPreview,
  required VoidCallback onRestore,
  required VoidCallback onRename,
  required VoidCallback onDiscard,
}) =>
    showAppMenu<void>(
      context: context,
      globalPosition: globalPosition,
      entries: pageVersionMenuEntries(
        editable: editable,
        onPreview: onPreview,
        onRestore: onRestore,
        onRename: onRename,
        onDiscard: onDiscard,
      ),
    );

Future<void> showPageVersionMenuForWidget({
  required BuildContext context,
  required bool editable,
  required VoidCallback onPreview,
  required VoidCallback onRestore,
  required VoidCallback onRename,
  required VoidCallback onDiscard,
}) =>
    showAppMenuForWidget<void>(
      context: context,
      entries: pageVersionMenuEntries(
        editable: editable,
        onPreview: onPreview,
        onRestore: onRestore,
        onRename: onRename,
        onDiscard: onDiscard,
      ),
    );

/// Asks what a version should be called.
///
/// Returns null when nothing was chosen; an empty string clears the name.
Future<String?> showPageVersionNameDialog(
  BuildContext context, {
  String initialName = '',
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PageVersionNameDialog(initialName: initialName),
    );

/// ⚠️ The field's controller is owned here rather than by the caller: a
/// controller disposed when the dialog's future completes is still being read
/// by the field through the closing animation, and the failed build takes the
/// window with it.
class _PageVersionNameDialog extends StatefulWidget {
  const _PageVersionNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_PageVersionNameDialog> createState() => _PageVersionNameDialogState();
}

class _PageVersionNameDialogState extends State<_PageVersionNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    return AlertDialog(
      backgroundColor: palette.surface,
      title: Text(
        LocaleKeys.pageVersions_nameTitle.tr(),
        style: TextStyle(fontSize: 16, color: palette.textPrimary),
      ),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            hintText: LocaleKeys.pageVersions_nameHint.tr(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(LocaleKeys.button_save.tr()),
        ),
      ],
    );
  }
}
