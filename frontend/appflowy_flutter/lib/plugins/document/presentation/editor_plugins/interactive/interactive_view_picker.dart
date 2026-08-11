import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_picker_dialog.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Choose any object in the workspace — a page, a file, a table or a
/// collection.
///
/// It is the application's own picker in a card, so an interactive block asks
/// the same question the rest of AppFlowy asks.
Future<ViewPB?> showInteractiveViewPicker(
  BuildContext context, {
  String? selectedViewId,
  bool Function(ViewPB view)? filter,
}) {
  return showDialog<ViewPB>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (context) {
      final palette = interactivePaletteOf(context);
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Container(
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: palette.border.withValues(alpha: 0.34),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: palette.isDark ? 0.46 : 0.14),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                  spreadRadius: -12,
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: WorkspaceViewPickerMenu(
              title: LocaleKeys.interactive_button_chooseTarget.tr(),
              searchHint: LocaleKeys.interactive_selector_search.tr(),
              emptyMessage: LocaleKeys.interactive_selector_noMatches.tr(),
              errorMessage:
                  LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
              selectedViewId: selectedViewId,
              viewFilter: filter ?? (_) => true,
              leadingBuilder: (context, view, explorerPalette) =>
                  WorkspaceItemIcon.fromView(
                view: view,
                size: 17,
                color: explorerPalette.textSecondary,
              ),
              onSelected: (view) => Navigator.of(context).pop(view),
            ),
          ),
        ),
      );
    },
  );
}

/// Kept so a caller can name the palette type without importing the explorer.
typedef InteractivePickerPalette = FolderExplorerPalette;
