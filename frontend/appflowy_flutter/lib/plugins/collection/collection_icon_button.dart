import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
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
    this.iconSize = CollectionMetrics.identityIconSize,
    this.opticalRole,
  });

  final ViewPB view;
  final ValueChanged<ViewPB> onViewChanged;
  final double iconSize;
  final IconOpticalRole? opticalRole;

  @override
  Widget build(BuildContext context) {
    final kind = view.collection?.kind ?? CollectionKind.book;
    final palette = CollectionPalette.of(context, kind);
    final saved = view.icon.toEmojiIconData();
    final role = isColorfulViewIcon(saved) ? opticalRole : null;
    final slotSize = saved.isNotEmpty && role != null
        ? IconOpticalSize.resolve(role: role, baseSize: iconSize).slotSize
        : iconSize;
    Widget icon = SizedBox.square(
      dimension: slotSize < WorkspaceChrome.controlHeight
          ? WorkspaceChrome.controlHeight
          : slotSize,
      child: Center(
        child: saved.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: RawEmojiIconWidget(
                  emoji: saved,
                  emojiSize: iconSize,
                  opticalRole: role,
                  lineHeight: 1,
                ),
              )
            : WorkspaceGlyph.collection(
                kind,
                size: iconSize,
                color: palette.accent,
              ),
      ),
    );
    if (opticalRole != null) {
      icon = MediaQuery.withNoTextScaling(child: icon);
    }
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
