import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/local_path_paste.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/paste_as/paste_choice_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

/// The answers to "copy this into AppFlowy?".
enum LocalPathPasteChoice {
  /// Keep a copy in AppFlowy, in place of the link.
  copy,

  /// Leave the link to where it lives on this computer.
  keepLink,

  /// Leave the path as plain words.
  keepText,
}

/// Asks, beside the caret, whether the file or folder whose path was just
/// pasted should be copied into AppFlowy. Copying is the answer already
/// chosen; dismissing the question keeps the link that was pasted.
void offerToCopyPastedLocalPath(
  EditorState editor,
  PastedLocalLink link,
) {
  if (UniversalPlatform.isMobile) {
    return;
  }
  final context = editor.document.root.context;
  final destination = LocalPathPasteDestination.of(editor);
  if (context == null || !context.mounted || destination == null) {
    return;
  }
  final overlay = PasteChoiceMenuOverlay(context: context, editorState: editor);
  overlay.show(
    choices: LocalPathPasteChoice.values.length,
    builder: (dismiss) => LocalPathPasteMenu(
      editorState: editor,
      item: link.item,
      onDismiss: dismiss,
      onSelect: (choice) {
        dismiss();
        switch (choice) {
          case LocalPathPasteChoice.copy:
            unawaited(
              copyPastedLocalPath(editor, link, destination: destination),
            );
          case LocalPathPasteChoice.keepText:
            unawaited(unlinkPastedLocalPath(editor, link));
          case LocalPathPasteChoice.keepLink:
            break;
        }
      },
    ),
  );
}

/// "Copy “report.pdf” into AppFlowy?", answered by click or by keyboard.
class LocalPathPasteMenu extends StatelessWidget {
  const LocalPathPasteMenu({
    super.key,
    required this.editorState,
    required this.item,
    required this.onSelect,
    required this.onDismiss,
  });

  final EditorState editorState;
  final PastedLocalPath item;
  final ValueChanged<LocalPathPasteChoice> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final size = item.size;
    return PasteChoiceMenu<LocalPathPasteChoice>(
      editorState: editorState,
      leading: Icon(
        item.isDirectory ? Icons.folder_rounded : fileIconForName(item.name),
        size: 16,
        color: theme.iconColorScheme.secondary,
      ),
      title: LocaleKeys.document_plugins_localPathPaste_question.tr(
        args: [shortenLocalPathName(item.name)],
      ),
      choices: [
        PasteChoice(
          value: LocalPathPasteChoice.copy,
          label: LocaleKeys.document_plugins_localPathPaste_copy.tr(),
          trailing: size == null
              ? null
              : FlowyText.regular(
                  formatArchiveBytes(size),
                  fontSize: 12,
                  color: theme.textColorScheme.tertiary,
                ),
        ),
        PasteChoice(
          value: LocalPathPasteChoice.keepLink,
          label: LocaleKeys.document_plugins_localPathPaste_keepLink.tr(),
        ),
        PasteChoice(
          value: LocalPathPasteChoice.keepText,
          label: LocaleKeys.document_plugins_localPathPaste_keepText.tr(),
        ),
      ],
      onSelect: onSelect,
      onDismiss: onDismiss,
    );
  }
}

/// [name] cut down in the middle, so the question still ends in a question
/// mark and an extension stays readable: `Quarterly rep…final.pdf`.
String shortenLocalPathName(String name, {int maximum = 24}) {
  if (name.length <= maximum) {
    return name;
  }
  final tail = (maximum - 1) ~/ 2;
  final head = maximum - 1 - tail;
  return '${name.substring(0, head)}…${name.substring(name.length - tail)}';
}
