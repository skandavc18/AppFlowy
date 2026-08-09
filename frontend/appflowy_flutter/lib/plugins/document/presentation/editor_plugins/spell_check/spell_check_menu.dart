import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spell_check/spell_check_actions.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The corrections the right click menu offers when it opens on a mistake.
///
/// They ride in the application's own menu rather than a surface of their own,
/// so copy, cut and paste stay where they always were.
List<AppMenuEntry> spellCheckContextMenuEntries(
  EditorState editorState,
  Selection selection,
) {
  if (!selection.isCollapsed && !_isSingleWord(selection)) {
    return const [];
  }
  final actions = spellCheckActionsAt(editorState, selection.end);
  if (actions == null) {
    return const [];
  }

  final entries = <AppMenuEntry>[];
  for (final suggestion in actions.suggestions(limit: 4)) {
    entries.add(
      AppMenuItem(
        label: LocaleKeys.document_spellCheck_replaceWith.tr(
          args: [suggestion.replacement],
        ),
        icon: Icons.spellcheck_rounded,
        onSelected: () => actions.replaceWith(suggestion.replacement),
      ),
    );
  }

  entries.add(
    AppMenuItem(
      label: LocaleKeys.document_spellCheck_ignore.tr(),
      icon: Icons.block_rounded,
      onSelected: actions.ignoreOnce,
    ),
  );
  if (!actions.isIgnoredEverywhere) {
    entries.add(
      AppMenuItem(
        label: LocaleKeys.document_spellCheck_ignoreAll.tr(),
        icon: Icons.done_all_rounded,
        onSelected: actions.ignoreEverywhere,
      ),
    );
  }
  if (actions.canAddToDictionary) {
    entries.add(
      AppMenuItem(
        label: LocaleKeys.document_spellCheck_addToDictionary.tr(),
        icon: Icons.library_add_rounded,
        onSelected: () => actions.addToDictionary(),
      ),
    );
  }
  return entries;
}

bool _isSingleWord(Selection selection) =>
    selection.start.path.equals(selection.end.path) &&
    (selection.end.offset - selection.start.offset).abs() < 64;
