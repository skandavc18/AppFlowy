import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_menu_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/ai_writer_toolbar_item.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/ai/operations/ai_writer_entities.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_copy_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_cut_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_paste_command.dart';
import 'package:appflowy/shared/context_menu_surface_style.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

enum EditorContextMenuAction {
  copy,
  cut,
  paste,
  pasteAsPlainText,
  askAi,
}

class EditorContextMenuEntry {
  const EditorContextMenuEntry({
    required this.action,
    required this.getName,
    required this.iconBuilder,
    required this.onPressed,
    this.shortcut,
  });

  final EditorContextMenuAction action;
  final String Function() getName;
  final Widget Function(BuildContext context) iconBuilder;
  final void Function(EditorState editorState) onPressed;
  final String Function(TargetPlatform platform)? shortcut;
}

final List<List<EditorContextMenuEntry>> editorContextMenuEntries = [
  [
    EditorContextMenuEntry(
      action: EditorContextMenuAction.copy,
      getName: LocaleKeys.document_plugins_contextMenu_copy.tr,
      iconBuilder: (context) => _menuIcon(
        context,
        FlowySvgs.m_table_quick_action_copy_s,
      ),
      shortcut: (platform) => _shortcut(platform, 'C'),
      onPressed: (editorState) => customCopyCommand.execute(editorState),
    ),
    EditorContextMenuEntry(
      action: EditorContextMenuAction.cut,
      getName: LocaleKeys.document_plugins_contextMenu_cut.tr,
      iconBuilder: (context) => _menuIcon(
        context,
        FlowySvgs.m_table_quick_action_cut_s,
      ),
      shortcut: (platform) => _shortcut(platform, 'X'),
      onPressed: (editorState) => customCutCommand.execute(editorState),
    ),
    EditorContextMenuEntry(
      action: EditorContextMenuAction.paste,
      getName: LocaleKeys.document_plugins_contextMenu_paste.tr,
      iconBuilder: (context) => _menuIcon(
        context,
        FlowySvgs.m_table_quick_action_paste_s,
      ),
      shortcut: (platform) => _shortcut(platform, 'V'),
      onPressed: (editorState) => customPasteCommand.execute(editorState),
    ),
    EditorContextMenuEntry(
      action: EditorContextMenuAction.pasteAsPlainText,
      getName: LocaleKeys.document_plugins_contextMenu_pasteAsPlainText.tr,
      iconBuilder: _pasteAsPlainTextIcon,
      shortcut: (platform) => _shortcut(platform, 'V', shift: true),
      onPressed: (editorState) =>
          customPastePlainTextCommand.execute(editorState),
    ),
  ],
  [
    EditorContextMenuEntry(
      action: EditorContextMenuAction.askAi,
      getName: LocaleKeys.document_plugins_smartEdit.tr,
      iconBuilder: (context) => _menuIcon(
        context,
        FlowySvgs.toolbar_ai_ask_anything_m,
      ),
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

Widget _menuIcon(BuildContext context, FlowySvgData data) {
  final appTheme = AppFlowyTheme.of(context);
  return FlowySvg(
    data,
    size: const Size.square(20),
    color: appTheme.iconColorScheme.primary,
  );
}

Widget _pasteAsPlainTextIcon(BuildContext context) {
  final appTheme = AppFlowyTheme.of(context);
  return SizedBox.square(
    dimension: 20,
    child: Stack(
      alignment: Alignment.center,
      children: [
        FlowySvg(
          FlowySvgs.m_table_quick_action_paste_s,
          size: const Size.square(20),
          color: appTheme.iconColorScheme.primary,
        ),
        Positioned(
          right: 1,
          bottom: 1,
          child: ColoredBox(
            color: appTheme.surfaceColorScheme.primary,
            child: Text(
              'T',
              style:
                  AppFlowyEditorMenuStyle.shortcutTextStyle(context).copyWith(
                color: appTheme.iconColorScheme.primary,
                fontSize: 8,
                height: 1,
              ),
            ),
          ),
        ),
      ],
    ),
  );
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
  OverlayEntry? _overlayEntry;
  final Set<int> _preventedPointers = {};

  void _preventForPointer(int pointer) {
    if (widget.enabled) {
      _preventedPointers.add(pointer);
    }
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
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

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject();
    if (overlayBox is! RenderBox) {
      return;
    }

    _dismiss();
    final pointer = overlayBox.globalToLocal(globalPosition);
    const width = AppFlowyEditorMenuStyle.menuWidth;
    const estimatedHeight = AppFlowyEditorMenuStyle.contextMenuEstimatedHeight;
    const margin = 8.0;
    final left = pointer.dx + margin + width <= overlayBox.size.width
        ? pointer.dx + margin
        : (pointer.dx - width - margin).clamp(
            margin,
            overlayBox.size.width - width - margin,
          );
    final top = pointer.dy + margin + estimatedHeight <= overlayBox.size.height
        ? pointer.dy + margin
        : (pointer.dy - estimatedHeight - margin).clamp(
            margin,
            overlayBox.size.height - estimatedHeight - margin,
          );

    final menu = InheritedTheme.captureAll(
      context,
      _EditorContextMenu(
        editorState: editorState,
        onDismiss: _dismiss,
      ),
    );
    _overlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismiss,
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: menu,
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _dismiss() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _EditorContextMenu extends StatelessWidget {
  const _EditorContextMenu({
    required this.editorState,
    required this.onDismiss,
  });

  final EditorState editorState;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final children = <Widget>[];

    for (final (groupIndex, group) in editorContextMenuEntries.indexed) {
      if (groupIndex > 0) {
        children.add(
          Divider(
            height: 16,
            thickness: 1,
            color: AppFlowyTheme.of(context).borderColorScheme.primary,
          ),
        );
      }
      for (final entry in group) {
        children.add(
          AFMenuItem(
            leading: SizedBox.square(
              dimension: 20,
              child: Center(child: entry.iconBuilder(context)),
            ),
            title: Text(
              entry.getName(),
              style: AppFlowyEditorMenuStyle.itemTextStyle(context),
            ),
            trailing: entry.action == EditorContextMenuAction.askAi
                ? Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppFlowyTheme.of(context).iconColorScheme.tertiary,
                  )
                : Text(
                    entry.shortcut?.call(platform) ?? '',
                    style: AppFlowyEditorMenuStyle.shortcutTextStyle(context),
                  ),
            onTap: () {
              onDismiss();
              entry.onPressed(editorState);
            },
          ),
        );
      }
    }

    return AFMenu(
      width: AppFlowyEditorMenuStyle.menuWidth,
      backgroundColor: ContextMenuSurfaceStyle.background(context),
      children: children,
    );
  }
}
