import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_blocks.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_item_builder.dart';

/// The editor's own `updateSelection` shape, named so it can be passed around.
typedef _AfterInsert = Selection? Function(
  EditorState editorState,
  Path insertPath,
  bool replaced,
  bool insertedBefore,
);

/// Runs [action] on the block that was just inserted at [path].
///
/// Every one of these blocks wants to land ready to use — the sticky note in
/// its body, the selector with its list open — and the state is only reachable
/// once the block has been built.
_AfterInsert _openAfterInsert<T extends State>(
  void Function(T state) action,
) =>
    (editorState, path, _, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = editorState.getNodeAtPath(path)?.key.currentState;
        if (state is T) {
          action(state);
        }
      });
      return null;
    };

SelectionMenuItem _interactiveItem({
  required String Function() getName,
  required List<String> keywords,
  required IconData icon,
  required Node Function() node,
  _AfterInsert? updateSelection,
}) =>
    SelectionMenuItem.node(
      getName: getName,
      keywords: keywords,
      nodeBuilder: (editorState, _) => node(),
      replace: (_, node) => node.delta?.isEmpty ?? false,
      updateSelection: updateSelection,
      nameBuilder: slashMenuItemNameBuilder,
      iconBuilder: (_, isSelected, style) => SelectableIconWidget(
        icon: icon,
        isSelected: isSelected,
        style: style,
      ),
    );

/// `/sticky`
final SelectionMenuItem stickyNoteSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_stickyNote_name.tr(),
  keywords: const ['sticky', 'sticky note', 'note', 'memo', 'postit', 'pin'],
  icon: Icons.sticky_note_2_rounded,
  node: stickyNoteNode,
  updateSelection: _openAfterInsert<StickyNoteBlockComponentState>(
    (state) => state.focusBody(),
  ),
);

/// `/button`
final SelectionMenuItem buttonSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_button_name.tr(),
  keywords: const ['button', 'action', 'cta', 'press', 'click', 'run'],
  icon: Icons.smart_button_rounded,
  node: buttonNode,
  updateSelection: _openAfterInsert<ButtonBlockComponentState>(
      (state) => state.beginRename()),
);

/// `/progress`
final SelectionMenuItem progressSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_progress_name.tr(),
  keywords: const [
    'progress',
    'progress bar',
    'completion',
    'percent',
    'percentage',
    'bar',
    'status',
  ],
  icon: Icons.speed_rounded,
  node: progressNode,
);

/// `/counter`
final SelectionMenuItem counterSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_counter_name.tr(),
  keywords: const [
    'counter',
    'count',
    'number',
    'tally',
    'increment',
    'stepper'
  ],
  icon: Icons.exposure_plus_1_rounded,
  node: counterNode,
);

/// `/memory`
final SelectionMenuItem memorySlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_memory_name.tr(),
  keywords: const [
    'memory',
    'memory card',
    'flashcard',
    'flash card',
    'revision',
    'quiz',
    'learn',
  ],
  icon: Icons.style_rounded,
  node: memoryNode,
);

/// `/input`
final SelectionMenuItem inputSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_input_name.tr(),
  keywords: const [
    'input',
    'input bar',
    'field',
    'text field',
    'entry',
    'form'
  ],
  icon: Icons.edit_note_rounded,
  node: inputNode,
  updateSelection:
      _openAfterInsert<InputBlockComponentState>((state) => state.focusField()),
);

/// `/search`
final SelectionMenuItem searchSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_search_name.tr(),
  keywords: const ['search', 'search bar', 'find', 'filter', 'lookup'],
  icon: Icons.search_rounded,
  node: searchNode,
  updateSelection: _openAfterInsert<SearchBlockComponentState>(
      (state) => state.focusField()),
);

/// `/select`
final SelectionMenuItem selectorSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_selector_name.tr(),
  keywords: const [
    'selector',
    'select',
    'dropdown',
    'choose',
    'option',
    'picker',
  ],
  icon: Icons.arrow_drop_down_circle_rounded,
  node: selectorNode,
);

/// `/radio`
final SelectionMenuItem radioGroupSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_radio_name.tr(),
  keywords: const [
    'radio',
    'radio group',
    'choice',
    'single choice',
    'options'
  ],
  icon: Icons.radio_button_checked_rounded,
  node: radioGroupNode,
);

/// `/multiselect`
final SelectionMenuItem multiSelectSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_multiSelect_name.tr(),
  keywords: const [
    'multiselect',
    'multi select',
    'multi-select',
    'tags',
    'labels',
    'several',
  ],
  icon: Icons.checklist_rounded,
  node: multiSelectNode,
);

/// `/reminder block`
final SelectionMenuItem reminderBlockSlashMenuItem = _interactiveItem(
  getName: () => LocaleKeys.interactive_reminder_name.tr(),
  keywords: const [
    'reminder block',
    'remind',
    'alert',
    'due',
    'notification',
    'schedule',
  ],
  icon: Icons.notifications_active_rounded,
  node: reminderBlockNode,
  updateSelection: _openAfterInsert<ReminderBlockComponentState>(
    (state) => state.compose(),
  ),
);

/// Everything the Interactive section offers, in the order it is shown.
List<SelectionMenuItem> interactiveSlashMenuItems() => [
      stickyNoteSlashMenuItem,
      buttonSlashMenuItem,
      progressSlashMenuItem,
      counterSlashMenuItem,
      memorySlashMenuItem,
      inputSlashMenuItem,
      searchSlashMenuItem,
      selectorSlashMenuItem,
      radioGroupSlashMenuItem,
      multiSelectSlashMenuItem,
      reminderBlockSlashMenuItem,
    ];

/// The quiet second line under each name.
Map<SelectionMenuItem, String> interactiveSlashMenuDescriptions() => {
      stickyNoteSlashMenuItem:
          LocaleKeys.interactive_stickyNote_description.tr(),
      buttonSlashMenuItem: LocaleKeys.interactive_button_description.tr(),
      progressSlashMenuItem: LocaleKeys.interactive_progress_description.tr(),
      counterSlashMenuItem: LocaleKeys.interactive_counter_description.tr(),
      memorySlashMenuItem: LocaleKeys.interactive_memory_description.tr(),
      inputSlashMenuItem: LocaleKeys.interactive_input_description.tr(),
      searchSlashMenuItem: LocaleKeys.interactive_search_description.tr(),
      selectorSlashMenuItem: LocaleKeys.interactive_selector_description.tr(),
      radioGroupSlashMenuItem: LocaleKeys.interactive_radio_description.tr(),
      multiSelectSlashMenuItem:
          LocaleKeys.interactive_multiSelect_description.tr(),
      reminderBlockSlashMenuItem:
          LocaleKeys.interactive_reminder_description.tr(),
    };
