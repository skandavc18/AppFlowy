import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/ai_writer_toolbar_item.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/operations/ai_writer_entities.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_copy_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_cut_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_paste_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table_context_menu_entries.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum EditorContextMenuAction {
  copy,
  cut,
  paste,
  pasteAsPlainText,
  askAi,
  table,
}

class EditorContextMenuEntry {
  const EditorContextMenuEntry({
    required this.action,
    required this.getName,
    required this.icon,
    required this.onPressed,
    this.shortcut,
    this.destructive = false,
  });

  final EditorContextMenuAction action;
  final String Function() getName;
  final IconData icon;
  final void Function(EditorState editorState) onPressed;
  final String Function(TargetPlatform platform)? shortcut;
  final bool destructive;
}

final List<List<EditorContextMenuEntry>> editorContextMenuEntries = [
  [
    EditorContextMenuEntry(
      action: EditorContextMenuAction.copy,
      getName: LocaleKeys.document_plugins_contextMenu_copy.tr,
      icon: Icons.copy_rounded,
      shortcut: (platform) => _shortcut(platform, 'C'),
      onPressed: (editorState) => customCopyCommand.execute(editorState),
    ),
    EditorContextMenuEntry(
      action: EditorContextMenuAction.cut,
      getName: LocaleKeys.document_plugins_contextMenu_cut.tr,
      icon: Icons.content_cut_rounded,
      shortcut: (platform) => _shortcut(platform, 'X'),
      onPressed: (editorState) => customCutCommand.execute(editorState),
    ),
    EditorContextMenuEntry(
      action: EditorContextMenuAction.paste,
      getName: LocaleKeys.document_plugins_contextMenu_paste.tr,
      icon: Icons.content_paste_rounded,
      shortcut: (platform) => _shortcut(platform, 'V'),
      onPressed: (editorState) => customPasteCommand.execute(editorState),
    ),
    EditorContextMenuEntry(
      action: EditorContextMenuAction.pasteAsPlainText,
      getName: LocaleKeys.document_plugins_contextMenu_pasteAsPlainText.tr,
      icon: Icons.content_paste_go_rounded,
      shortcut: (platform) => _shortcut(platform, 'V', shift: true),
      onPressed: (editorState) =>
          customPastePlainTextCommand.execute(editorState),
    ),
  ],
  [
    EditorContextMenuEntry(
      action: EditorContextMenuAction.askAi,
      getName: LocaleKeys.document_plugins_smartEdit.tr,
      icon: Icons.auto_awesome_rounded,
      onPressed: (editorState) {
        unawaited(
          insertAiWriterNode(editorState, AiWriterCommand.userQuestion),
        );
      },
    ),
  ],
];

String _shortcut(
  TargetPlatform platform,
  String key, {
  bool shift = false,
}) {
  if (platform == TargetPlatform.macOS) {
    return '${shift ? '⇧' : ''}⌘$key';
  }
  return 'Ctrl+${shift ? 'Shift+' : ''}$key';
}

class EditorContextMenuRegion extends StatefulWidget {
  const EditorContextMenuRegion({
    super.key,
    required this.editorState,
    required this.child,
    this.enabled = true,
  });

  final EditorState editorState;
  final Widget child;
  final bool enabled;

  static void preventForPointer(BuildContext context, int pointer) {
    context
        .findAncestorStateOfType<_EditorContextMenuRegionState>()
        ?._preventForPointer(pointer);
  }

  @override
  State<EditorContextMenuRegion> createState() =>
      _EditorContextMenuRegionState();
}

class _EditorContextMenuRegionState extends State<EditorContextMenuRegion> {
  final Set<int> _preventedPointers = {};

  void _preventForPointer(int pointer) {
    if (widget.enabled) {
      _preventedPointers.add(pointer);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (!widget.enabled || event.buttons & kSecondaryMouseButton == 0) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_preventedPointers.remove(event.pointer)) {
            return;
          }
          if (mounted) {
            _show(event.position);
          }
        });
      },
      child: widget.child,
    );
  }

  void _show(Offset globalPosition) {
    final editorState = widget.editorState;
    _placeCaretUnderPointer(globalPosition);
    final selection = editorState.selection;
    final selectionRects = editorState.selectionRects();
    if (selection == null || selectionRects.isEmpty) {
      return;
    }

    final isWithinSelection = selection.isCollapsed ||
        selectionRects.any(
          (rect) => Rect.fromCenter(
            center: rect.center,
            width: rect.width + 20,
            height: rect.height + 20,
          ).contains(globalPosition),
        );
    if (!isWithinSelection) {
      return;
    }

    final selectedNodes = editorState.getNodesInSelection(selection);
    if (selectedNodes.isEmpty ||
        selectedNodes.any((node) => node.delta == null)) {
      return;
    }

    unawaited(
      showAppMenu<void>(
        context: context,
        globalPosition: globalPosition,
        entries: _entries(context, editorState),
      ),
    );
  }

  List<AppMenuEntry> _entries(BuildContext context, EditorState editorState) {
    final platform = Theme.of(context).platform;
    final entries = <AppMenuEntry>[];

    final groups = [
      ...editorContextMenuEntries,
      ...simpleTableContextMenuGroups(editorState),
    ];
    for (final group in groups) {
      if (group.isEmpty) {
        continue;
      }
      entries.add(const AppMenuSeparator());
      for (final entry in group) {
        entries.add(
          AppMenuItem(
            label: entry.getName(),
            icon: entry.icon,
            shortcut: entry.shortcut?.call(platform),
            destructive: entry.destructive,
            onSelected: () => entry.onPressed(editorState),
          ),
        );
      }
    }

    if (simpleTableContextMenuHasColors(editorState)) {
      entries
        ..add(const AppMenuSeparator())
        ..add(
          AppMenuCustom(
            builder: (menuContext) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: simpleTableContextMenuColors(
                menuContext,
                editorState,
                onDismiss: () => AppMenuScope.maybeOf(menuContext)?.close(),
              ),
            ),
          ),
        );
    }

    return entries;
  }

  /// A right click outside the current selection acts on what is under the
  /// pointer, not on wherever the caret happened to be left.
  void _placeCaretUnderPointer(Offset globalPosition) {
    final editorState = widget.editorState;
    final selection = editorState.selection;
    if (selection != null && !selection.isCollapsed) {
      final rects = editorState.selectionRects();
      final within = rects.any(
        (rect) => Rect.fromCenter(
          center: rect.center,
          width: rect.width + 20,
          height: rect.height + 20,
        ).contains(globalPosition),
      );
      if (within) {
        return;
      }
    }
    final position = editorState.service.selectionService
        .getPositionInOffset(globalPosition);
    if (position != null && position != selection?.start) {
      editorState.updateSelectionWithReason(
        Selection.collapsed(position),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
  }
}
