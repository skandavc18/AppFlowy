import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/util/color_generator/color_generator.dart';
import 'package:appflowy/workspace/presentation/widgets/user_avatar_button.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class WorkspaceIcon extends StatelessWidget {
  const WorkspaceIcon({
    super.key,
    required this.workspaceIcon,
    required this.workspaceName,
    required this.iconSize,
    required this.isEditable,
    required this.fontSize,
    required this.onSelected,
    required this.borderRadius,
    required this.emojiSize,
    required this.figmaLineHeight,
    this.showBorder = true,
    this.documentId,
    this.isCurrent,
  });

  final String workspaceIcon;
  final String workspaceName;
  final double iconSize;
  final bool isEditable;
  final double fontSize;
  final double? emojiSize;
  final FutureOr<void> Function(EmojiIconData) onSelected;
  final bool Function()? isCurrent;
  final double borderRadius;
  final double figmaLineHeight;
  final bool showBorder;

  /// Upload owner for custom images, normally the workspace ID.
  final String? documentId;

  @override
  Widget build(BuildContext context) {
    final (textColor, backgroundColor) =
        ColorGenerator(workspaceName).randomColor();
    final icon = EmojiIconData.fromStorageString(workspaceIcon);
    final resolvedEmojiSize = emojiSize ?? fontSize;

    Widget child = icon.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: icon,
            emojiSize: resolvedEmojiSize,
            lineHeight: figmaLineHeight / resolvedEmojiSize,
          )
        : FlowyText.semibold(
            workspaceName.isEmpty ? '' : workspaceName.substring(0, 1),
            fontSize: fontSize,
            color: textColor,
          );

    child = Container(
      alignment: Alignment.center,
      width: iconSize,
      height: iconSize,
      decoration: BoxDecoration(
        color: icon.isEmpty ? backgroundColor : null,
        borderRadius: BorderRadius.circular(borderRadius),
        border: showBorder
            ? Border.all(color: EditorSurfaceStyle.embedBorder(context))
            : null,
      ),
      child: child,
    );

    if (isEditable) {
      child = AvatarPickerButton(
        key: ValueKey(documentId),
        identity: documentId ?? workspaceName,
        label: LocaleKeys.settings_workspacePage_workspaceIcon_title.tr(),
        icon: icon,
        documentId: documentId,
        dimension: iconSize,
        isCurrent: isCurrent,
        onSelected: onSelected,
        child: child,
      );
    }

    return child;
  }
}
