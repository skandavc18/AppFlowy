import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'slash_menu_items.dart';

final pagePreviewSlashMenuItem = SelectionMenuItem(
  getName: () => LocaleKeys.commandPalette_pagePreview.tr(),
  keywords: const ['page preview', 'preview page', 'embed page'],
  handler: (editorState, _, __) => editorState.insertPagePreviewBlock(),
  nameBuilder: slashMenuItemNameBuilder,
  icon: (_, isSelected, style) => SelectableSvgWidget(
    data: FlowySvgs.page_preview_s,
    isSelected: isSelected,
    style: style,
  ),
);

extension InsertPagePreviewBlock on EditorState {
  Future<void> insertPagePreviewBlock([ViewPB? view]) async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final node = getNodeAtPath(selection.start.path);
    if (node == null) {
      return;
    }

    if (view != null) {
      pageMemorizer[view.id] = view;
    }

    final key = GlobalKey<PagePreviewBlockComponentState>();
    final preview = pagePreviewNode(viewId: view?.id)
      ..extraInfos = {PagePreviewBlockKeys.globalKey: key};
    final transaction = this.transaction;
    if (node.delta?.toPlainText().isEmpty ?? false) {
      transaction
        ..insertNode(node.path, preview)
        ..deleteNode(node);
    } else {
      transaction.insertNode(node.path.next, preview);
    }
    await apply(transaction);
    if (view == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        key.currentState?.showPagePicker();
      });
    }
  }
}
