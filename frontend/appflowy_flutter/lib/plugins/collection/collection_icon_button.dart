import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/material.dart';

/// A collection's identity is editable just like a page's. Read the saved icon
/// first, and share the sidebar's fallback instead of drawing a fixed type icon.
class CollectionIconButton extends StatelessWidget {
  const CollectionIconButton({
    super.key,
    required this.view,
    required this.onViewChanged,
  });

  final ViewPB view;
  final ValueChanged<ViewPB> onViewChanged;

  @override
  Widget build(BuildContext context) {
    final kind = view.collection?.kind ?? CollectionKind.book;
    final palette = CollectionPalette.of(context, kind);
    final saved = view.icon.toEmojiIconData();
    final icon = SizedBox.square(
      dimension: WorkspaceChrome.controlHeight,
      child: Center(
        child: saved.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: RawEmojiIconWidget(
                  emoji: saved,
                  emojiSize: CollectionMetrics.identityIconSize,
                  lineHeight: 1,
                ),
              )
            : SidebarGlyph(
                sidebarCollectionIcon(kind),
                size: CollectionMetrics.identityIconSize,
                color: palette.accent,
              ),
      ),
    );
    if (view.isLocked) {
      return icon;
    }
    return ViewIconPicker(
      view: view,
      onViewChanged: onViewChanged,
      child: FlowyHover(
        resetHoverOnRebuild: false,
        style: HoverStyle(
          hoverColor: palette.hover,
          backgroundColor: palette.hover.withValues(alpha: 0),
        ),
        child: icon,
      ),
    );
  }
}
