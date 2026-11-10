import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker_screen.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/emoji/emoji_actions_command.dart';
import 'package:appflowy/plugins/emoji/emoji_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';

import 'slash_menu_item_builder.dart';

final _keywords = [
  'emoji',
  'reaction',
  'emoticon',
];

// emoji menu item
SelectionMenuItem emojiSlashMenuItem = SelectionMenuItem(
  getName: () => LocaleKeys.document_slashMenu_name_emoji.tr(),
  keywords: _keywords,
  handler: (editorState, menuService, context) => editorState.showEmojiPicker(
    context,
    menuService: menuService,
  ),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.slash_menu_icon_emoji_picker_s,
    isSelected: isSelected,
    style: style,
  ),
);

extension on EditorState {
  Future<void> showEmojiPicker(
    BuildContext context, {
    required SelectionMenuService menuService,
  }) async {
    if (UniversalPlatform.isMobile) {
      return _pickEmojiOnMobile(context, menuService: menuService);
    }
    final container = Overlay.of(context);
    menuService.dismiss();
    if (selection == null) {
      return;
    }

    final node = getNodeAtPath(selection!.end.path);
    final delta = node?.delta;
    if (node == null || delta == null || node.type == CodeBlockKeys.type) {
      return;
    }
    emojiMenuService = EmojiMenu(editorState: this, overlay: container);
    emojiMenuService?.show('');
  }

  /// A phone has no room for the floating picker, so the full-screen one that
  /// page icons use chooses the emoji, which then goes in at the caret.
  Future<void> _pickEmojiOnMobile(
    BuildContext context, {
    required SelectionMenuService menuService,
  }) async {
    // The menu lives in an overlay of its own, outside the app's routes, and
    // closing it can drop the editor's selection. The typed `/` is gone
    // already, so the caret is read now and the root navigator pushes.
    final caret = selection;
    menuService.dismiss();
    final root = AppGlobals.rootNavKey.currentContext;
    if (caret == null || !caret.isCollapsed || root == null) {
      return;
    }
    final picked = await root.push<EmojiIconData>(
      Uri(
        path: MobileEmojiPickerScreen.routeName,
        queryParameters: {
          MobileEmojiPickerScreen.pageTitle:
              LocaleKeys.document_slashMenu_name_emoji.tr(),
          MobileEmojiPickerScreen.selectTabs: [PickerTabType.emoji.name],
        },
      ).toString(),
    );
    if (picked == null ||
        picked.type != FlowyIconType.emoji ||
        picked.emoji.isEmpty) {
      return;
    }
    final node = getNodeAtPath(caret.end.path);
    if (node == null || node.delta == null || node.type == CodeBlockKeys.type) {
      return;
    }
    final offset = caret.end.offset;
    final transaction = this.transaction
      ..insertText(node, offset, picked.emoji)
      ..afterSelection = Selection.collapsed(
        caret.end.copyWith(offset: offset + picked.emoji.length),
      );
    await apply(transaction);
  }
}
