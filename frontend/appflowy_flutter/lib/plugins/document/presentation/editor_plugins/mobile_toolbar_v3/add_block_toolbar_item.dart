import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/base/type_option_menu_item.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mobile_toolbar_v3/aa_menu/_toolbar_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'add_block_menu_item_builder.dart';

@visibleForTesting
const addBlockToolbarItemKey = ValueKey('add_block_toolbar_item');

final addBlockToolbarItem = buildAddBlockToolbarItem();

/// Closes the add-block sheet, then opens the full `/` menu at [selection].
///
/// Closing the sheet hands the caret back, which rebuilds the toolbar and
/// with it the `+` that opened the sheet, so the work after it cannot wait
/// on that button; it is scheduled here, independent of either widget.
void requestAllBlocksMenu(
  BuildContext context, {
  required EditorState editorState,
  required Selection selection,
  required Future<void> Function() showAllBlocks,
}) {
  Navigator.of(context).pop();
  Future.delayed(const Duration(milliseconds: 300), () async {
    // Its future completes only for UI events, so it must not be awaited;
    // the selection itself is set at once.
    unawaited(editorState.updateSelectionWithReason(selection));
    await showAllBlocks();
  });
}

/// The toolbar's `+`. With [showAllBlocks], its sheet also offers "All
/// blocks", which opens the full `/` menu at the caret.
AppFlowyMobileToolbarItem buildAddBlockToolbarItem({
  Future<void> Function()? showAllBlocks,
}) =>
    AppFlowyMobileToolbarItem(
      itemBuilder: (context, editorState, service, __, onAction) {
        return AppFlowyMobileToolbarIconItem(
          key: addBlockToolbarItemKey,
          editorState: editorState,
          icon: FlowySvgs.m_toolbar_add_m,
          onTap: () {
            final selection = editorState.selection;
            service.closeKeyboard();

            // delay to wait the keyboard closed.
            Future.delayed(const Duration(milliseconds: 100), () async {
              unawaited(
                editorState.updateSelectionWithReason(
                  selection,
                  extraInfo: {
                    selectionExtraInfoDisableMobileToolbarKey: true,
                    selectionExtraInfoDisableFloatingToolbar: true,
                    selectionExtraInfoDoNotAttachTextService: true,
                  },
                ),
              );
              keepEditorFocusNotifier.increase();
              final didAddBlock = await showAddBlockMenu(
                AppGlobals.rootNavKey.currentContext!,
                editorState: editorState,
                selection: selection!,
                showAllBlocks: showAllBlocks,
              );
              if (didAddBlock != true) {
                unawaited(editorState.updateSelectionWithReason(selection));
              }
            });
          },
        );
      },
    );

Future<bool?> showAddBlockMenu(
  BuildContext context, {
  required EditorState editorState,
  required Selection selection,
  Future<void> Function()? showAllBlocks,
}) async =>
    showMobileBottomSheet<bool>(
      context,
      showHeader: true,
      showDragHandle: true,
      showCloseButton: true,
      title: LocaleKeys.button_add.tr(),
      barrierColor: Colors.transparent,
      backgroundColor:
          ToolbarColorExtension.of(context).toolbarMenuBackgroundColor,
      elevation: 20,
      enableDraggableScrollable: true,
      builder: (_) => Padding(
        padding: EdgeInsets.all(16 * context.scale),
        child: AddBlockMenu(
          selection: selection,
          editorState: editorState,
          showAllBlocks: showAllBlocks,
        ),
      ),
    );

class AddBlockMenu extends StatelessWidget {
  const AddBlockMenu({
    super.key,
    required this.selection,
    required this.editorState,
    this.showAllBlocks,
  });

  final Selection selection;
  final EditorState editorState;
  final Future<void> Function()? showAllBlocks;

  @override
  Widget build(BuildContext context) {
    final builder = AddBlockMenuItemBuilder(
      editorState: editorState,
      selection: selection,
      showAllBlocks: showAllBlocks,
    );
    return TypeOptionMenu<String>(
      values: builder.buildTypeOptionMenuItemValues(context),
      scaleFactor: context.scale,
    );
  }
}
