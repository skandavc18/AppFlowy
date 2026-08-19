import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_kind_menu.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/encryption/encryption_dialogs.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
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
  canvas,
  dashboard,
  table,
  board,
  calendar,
  chat,
}

class FolderHeader extends StatefulWidget {
  const FolderHeader({
    super.key,
    required this.title,
    required this.expandButtonTooltip,
    required this.addButtonTooltip,
    required this.onPressed,
    required this.onCreate,
    required this.onCreateFile,
    required this.onCreateCollection,
    required this.isExpanded,
    this.leading,
    this.onToggleExpanded,
    this.onRename,
  });

  final String title;
  final String expandButtonTooltip;
  final String addButtonTooltip;
  final VoidCallback onPressed;
  final ValueChanged<SidebarRootCreateKind> onCreate;
  final ValueChanged<WorkspaceFileMenuAction> onCreateFile;
  final ValueChanged<CollectionKind> onCreateCollection;
  final bool isExpanded;
  final Widget? leading;

  /// Supplied when the header is a real root folder, so the chevron can hide
  /// everything under it the way a page row does.
  final VoidCallback? onToggleExpanded;
  final Future<bool> Function(String name)? onRename;

  @override
  State<FolderHeader> createState() => _FolderHeaderState();
}

class _FolderHeaderState extends State<FolderHeader> {
  final popoverController = PopoverController();
  final focusNode = FocusNode(debugLabel: 'workspace-root-header');
  bool isRenaming = false;

  /// The trailing actions are built only while the row is hovered, and opening
  /// a menu moves the pointer off the row — which would unmount the button the
  /// menu is anchored to.
  bool isMenuOpen = false;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    final rootStyle = SidebarTypography.textStyle(
      context,
      color: palette.textPrimary,
      role: SidebarTextRole.heading,
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
      child: PopoverActionList<PopoverAction>(
        controller: popoverController,
        direction: PopoverDirection.bottomWithLeftAligned,
        offset: const Offset(0, 6),
        constraints: const BoxConstraints(minWidth: 200),
        showAtCursor: true,
        onClosed: () => _setMenuOpen(false),
        actions: sidebarRootCreateActions(
          onCreateFile: widget.onCreateFile,
          onCreateCollection: widget.onCreateCollection,
        ),
        onSelected: (action, popover) {
          if (action is SidebarRootCreateAction) {
            widget.onCreate(action.kind);
          }
          popover.close();
        },
        buildChild: (popover) => SidebarRow(
          dimIcon: false,
          active: isMenuOpen,
          icon: widget.leading,
          leading: widget.onToggleExpanded == null
              ? null
              : SidebarDisclosure(
                  expanded: widget.isExpanded,
                  tooltip: widget.expandButtonTooltip,
                  onTap: widget.onToggleExpanded!,
                ),
          onTap: isRenaming
              ? null
              : () {
                  focusNode.requestFocus();
                  widget.onPressed();
                },
          onSecondaryPointerDown: (event) {
            if (event.buttons == kSecondaryMouseButton) {
              _setMenuOpen(true);
              popover.showAt(event.position);
            }
          },
          trailingSlots: 2,
          trailingBuilder: (_) => [
            _FolderHeaderMoreButton(
              onRename: widget.onRename == null ? null : _beginRename,
              onOpenChanged: _setMenuOpen,
            ),
            const SizedBox(width: SidebarMetrics.actionGap),
            SidebarIconButton(
              icon: SidebarIcon.add,
              tooltip: widget.addButtonTooltip,
              onPressed: () {
                _setMenuOpen(true);
                popover.show();
              },
            ),
          ],
          label: widget.onRename == null
              ? SidebarSectionLabel(widget.title)
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
    );
  }

  void _setMenuOpen(bool open) {
    if (mounted && isMenuOpen != open) {
      setState(() => isMenuOpen = open);
    }
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

/// The `⋯` beside the workspace's own row.
///
/// A folder and a file each have one; the workspace they all sit in did not,
/// so the things that apply to the whole of it had nowhere to be asked for.
class _FolderHeaderMoreButton extends StatefulWidget {
  const _FolderHeaderMoreButton({this.onRename, this.onOpenChanged});

  final VoidCallback? onRename;

  /// Lets the row hold its actions open for as long as this menu is.
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<_FolderHeaderMoreButton> createState() =>
      _FolderHeaderMoreButtonState();
}

class _FolderHeaderMoreButtonState extends State<_FolderHeaderMoreButton> {
  final PopoverController controller = PopoverController();

  EncryptionVault get _vault => EncryptionVault.instance;

  @override
  void initState() {
    super.initState();
    _vault.addListener(_onVaultChanged);
    unawaited(_vault.ensureLoaded());
  }

  @override
  void dispose() {
    _vault.removeListener(_onVaultChanged);
    super.dispose();
  }

  void _onVaultChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final gated = _vault.policy.gateWholeWorkspace && _vault.isConfigured;

    return PopoverActionList<PopoverAction>(
      controller: controller,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 220),
      onClosed: () => widget.onOpenChanged?.call(false),
      actions: [
        if (widget.onRename != null)
          SidebarRootMoreAction(SidebarRootMoreKind.rename),
        SidebarRootMoreAction(
          gated ? SidebarRootMoreKind.unprotect : SidebarRootMoreKind.protect,
        ),
        if (_vault.isUnlocked) SidebarRootMoreAction(SidebarRootMoreKind.lock),
      ],
      onSelected: (action, popover) {
        popover.close();
        if (action is SidebarRootMoreAction) {
          unawaited(_run(action.kind));
        }
      },
      buildChild: (popover) => SidebarIconButton(
        icon: SidebarIcon.more,
        tooltip: LocaleKeys.button_more.tr(),
        onPressed: () {
          widget.onOpenChanged?.call(true);
          popover.show();
        },
      ),
    );
  }

  Future<void> _run(SidebarRootMoreKind kind) async {
    switch (kind) {
      case SidebarRootMoreKind.rename:
        widget.onRename?.call();
      case SidebarRootMoreKind.protect:
        await protectWholeWorkspace(context);
      case SidebarRootMoreKind.unprotect:
        await stopProtectingWholeWorkspace(context);
      case SidebarRootMoreKind.lock:
        _vault.lock();
    }
  }
}

enum SidebarRootMoreKind { rename, protect, unprotect, lock }

class SidebarRootMoreAction extends SidebarRootAction {
  SidebarRootMoreAction(this.kind);

  final SidebarRootMoreKind kind;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        switch (kind) {
          SidebarRootMoreKind.rename => Icons.drive_file_rename_outline_rounded,
          SidebarRootMoreKind.protect => Icons.shield_outlined,
          SidebarRootMoreKind.unprotect => Icons.shield_rounded,
          SidebarRootMoreKind.lock => Icons.lock_rounded,
        },
        color: iconColor,
        size: 17,
      );

  @override
  String get name => switch (kind) {
        SidebarRootMoreKind.rename => LocaleKeys.disclosureAction_rename.tr(),
        SidebarRootMoreKind.protect =>
          LocaleKeys.encryption_protectWorkspace.tr(),
        SidebarRootMoreKind.unprotect =>
          LocaleKeys.encryption_unprotectWorkspace.tr(),
        SidebarRootMoreKind.lock => LocaleKeys.encryption_lockNow.tr(),
      };
}

/// Everything the + button next to a folder offers, for the menus that appear
/// on a right click anywhere else in the sidebar.
List<PopoverAction> sidebarRootCreateActions({
  required ValueChanged<WorkspaceFileMenuAction> onCreateFile,
  required ValueChanged<CollectionKind> onCreateCollection,
  List<PopoverAction> trailing = const [],
}) {
  return [
    SidebarRootCreateAction(SidebarRootCreateKind.folder),
    CollectionAddAction(onCreate: onCreateCollection),
    WorkspaceFileAddAction(onCreate: onCreateFile),
    for (final kind in SidebarRootCreateKind.values)
      if (kind != SidebarRootCreateKind.folder) SidebarRootCreateAction(kind),
    ...trailing,
  ];
}

class SidebarRootCreateAction extends SidebarRootAction {
  SidebarRootCreateAction(this.kind);

  final SidebarRootCreateKind kind;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        switch (kind) {
          SidebarRootCreateKind.folder => workspaceAddFolderIcon,
          SidebarRootCreateKind.page => Icons.description_rounded,
          SidebarRootCreateKind.canvas => Icons.dashboard_customize_rounded,
          SidebarRootCreateKind.dashboard => Icons.dashboard_rounded,
          SidebarRootCreateKind.table => Icons.table_chart_rounded,
          SidebarRootCreateKind.board => Icons.view_kanban_rounded,
          SidebarRootCreateKind.calendar => Icons.calendar_month_rounded,
          SidebarRootCreateKind.chat => Icons.forum_rounded,
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
        SidebarRootCreateKind.canvas => LocaleKeys.canvas_defaultName.tr(),
        SidebarRootCreateKind.dashboard =>
          LocaleKeys.dashboard_newDashboard.tr(),
        SidebarRootCreateKind.table =>
          LocaleKeys.workspaceFolderExplorer_newTable.tr(),
        SidebarRootCreateKind.board => LocaleKeys.board_menuName.tr(),
        SidebarRootCreateKind.calendar => LocaleKeys.calendar_menuName.tr(),
        SidebarRootCreateKind.chat => LocaleKeys.chat_newChat.tr(),
      };
}

class SidebarRootPasteAction extends SidebarRootAction {
  @override
  Widget? leftIcon(Color iconColor) => Icon(
        Icons.content_paste_rounded,
        color: iconColor,
        size: 17,
      );

  @override
  String get name => LocaleKeys.workspaceFolderExplorer_paste.tr();
}
