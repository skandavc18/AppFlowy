import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum SidebarRootCreateKind {
  folder,
  page,
  table,
}

class FolderHeader extends StatefulWidget {
  const FolderHeader({
    super.key,
    required this.title,
    required this.expandButtonTooltip,
    required this.addButtonTooltip,
    required this.onPressed,
    required this.onCreate,
    required this.isExpanded,
    this.leading,
    this.onRename,
  });

  final String title;
  final String expandButtonTooltip;
  final String addButtonTooltip;
  final VoidCallback onPressed;
  final ValueChanged<SidebarRootCreateKind> onCreate;
  final bool isExpanded;
  final Widget? leading;
  final Future<bool> Function(String name)? onRename;

  @override
  State<FolderHeader> createState() => _FolderHeaderState();
}

class _FolderHeaderState extends State<FolderHeader> {
  final isHovered = ValueNotifier(false);
  final popoverController = PopoverController();
  final focusNode = FocusNode(debugLabel: 'workspace-root-header');
  bool isRenaming = false;

  @override
  void dispose() {
    isHovered.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rootStyle = SidebarTypography.textStyle(
      context,
      color: Theme.of(context).colorScheme.onSecondary,
      role: SidebarTextRole.page,
    );
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            !isRenaming &&
            widget.onRename != null &&
            isWorkspaceRenameShortcut(
              Theme.of(context).platform,
              event.logicalKey,
            )) {
          _beginRename();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopoverActionList<SidebarRootAction>(
        controller: popoverController,
        direction: PopoverDirection.bottomWithLeftAligned,
        offset: const Offset(0, 6),
        constraints: const BoxConstraints(minWidth: 190),
        showAtCursor: true,
        actions: SidebarRootCreateKind.values
            .map(SidebarRootCreateAction.new)
            .toList(growable: false),
        onSelected: (action, popover) {
          if (action is SidebarRootCreateAction) {
            widget.onCreate(action.kind);
          }
          popover.close();
        },
        buildChild: (popover) => SizedBox(
          height: HomeSizes.workspaceSectionHeight,
          child: MouseRegion(
            onEnter: (_) => isHovered.value = true,
            onExit: (_) => isHovered.value = false,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (event.buttons == kSecondaryMouseButton) {
                  popover.showAt(event.position);
                }
              },
              child: FlowyButton(
                onTap: isRenaming
                    ? null
                    : () {
                        focusNode.requestFocus();
                        widget.onPressed();
                      },
                margin: const EdgeInsets.only(left: 6.0, right: 4.0),
                leftIcon: widget.leading,
                leftIconSize: widget.leading == null
                    ? const Size.square(16)
                    : const Size.square(22),
                rightIcon: ValueListenableBuilder(
                  valueListenable: isHovered,
                  builder: (context, onHover, child) =>
                      Opacity(opacity: onHover ? 1 : 0, child: child),
                  child: FlowyIconButton(
                    width: 24,
                    iconPadding: const EdgeInsets.all(4.0),
                    tooltipText: widget.addButtonTooltip,
                    icon: const FlowySvg(FlowySvgs.view_item_add_s),
                    onPressed: popover.show,
                  ),
                ),
                text: widget.onRename == null
                    ? SidebarText.section(widget.title)
                    : WorkspaceInlineEditableText(
                        key: const ValueKey('workspace-root-title'),
                        text: widget.title,
                        editing: isRenaming,
                        onSubmitted: _submitRename,
                        onCancelled: _cancelRename,
                        onDoubleTap: _beginRename,
                        style: rootStyle,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _beginRename() {
    if (!isRenaming && widget.onRename != null) {
      setState(() => isRenaming = true);
    }
  }

  void _cancelRename() {
    if (isRenaming && mounted) {
      setState(() => isRenaming = false);
    }
  }

  Future<bool> _submitRename(String name) async {
    final onRename = widget.onRename;
    if (onRename == null) {
      return false;
    }
    final success = await onRename(name);
    if (mounted && success) {
      setState(() => isRenaming = false);
    }
    return success;
  }
}

sealed class SidebarRootAction extends ActionCell {}

class SidebarRootCreateAction extends SidebarRootAction {
  SidebarRootCreateAction(this.kind);

  final SidebarRootCreateKind kind;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        switch (kind) {
          SidebarRootCreateKind.folder => Icons.create_new_folder_outlined,
          SidebarRootCreateKind.page => Icons.description_outlined,
          SidebarRootCreateKind.table => Icons.table_chart_outlined,
        },
        color: iconColor,
        size: 17,
      );

  @override
  String get name => switch (kind) {
        SidebarRootCreateKind.folder =>
          LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
        SidebarRootCreateKind.page =>
          LocaleKeys.workspaceFolderExplorer_newPage.tr(),
        SidebarRootCreateKind.table =>
          LocaleKeys.workspaceFolderExplorer_newTable.tr(),
      };
}

class SidebarRootPasteAction extends SidebarRootAction {
  @override
  Widget? leftIcon(Color iconColor) => Icon(
        Icons.content_paste_outlined,
        color: iconColor,
        size: 17,
      );

  @override
  String get name => LocaleKeys.workspaceFolderExplorer_paste.tr();
}
