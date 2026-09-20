import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker_screen.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/util/color_generator/color_generator.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';

class WorkspaceIcon extends StatefulWidget {
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
  });

  final String workspaceIcon;
  final String workspaceName;
  final double iconSize;
  final bool isEditable;
  final double fontSize;
  final double? emojiSize;
  final void Function(EmojiIconData) onSelected;
  final double borderRadius;
  final double figmaLineHeight;
  final bool showBorder;

  /// Upload owner for custom images, normally the workspace ID.
  final String? documentId;

  @override
  State<WorkspaceIcon> createState() => _WorkspaceIconState();
}

class _WorkspaceIconState extends State<WorkspaceIcon> {
  final controller = PopoverController();
  int _selectionGeneration = 0;

  @override
  void didUpdateWidget(covariant WorkspaceIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.isEditable != widget.isEditable) {
      _selectionGeneration++;
      controller.close();
    }
  }

  bool _canSelect(int generation) =>
      mounted && widget.isEditable && generation == _selectionGeneration;

  @override
  Widget build(BuildContext context) {
    final (textColor, backgroundColor) =
        ColorGenerator(widget.workspaceName).randomColor();
    final icon = EmojiIconData.fromStorageString(widget.workspaceIcon);
    final emojiSize = widget.emojiSize ?? widget.fontSize;

    Widget child = icon.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: icon,
            emojiSize: emojiSize,
            lineHeight: widget.figmaLineHeight / emojiSize,
          )
        : FlowyText.semibold(
            widget.workspaceName.isEmpty
                ? ''
                : widget.workspaceName.substring(0, 1),
            fontSize: widget.fontSize,
            color: textColor,
          );

    child = Container(
      alignment: Alignment.center,
      width: widget.iconSize,
      height: widget.iconSize,
      decoration: BoxDecoration(
        color: icon.isEmpty ? backgroundColor : null,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.showBorder
            ? Border.all(color: EditorSurfaceStyle.embedBorder(context))
            : null,
      ),
      child: child,
    );

    if (widget.isEditable) {
      child = _buildEditableIcon(child, icon);
    }

    return child;
  }

  Widget _buildEditableIcon(Widget child, EmojiIconData icon) {
    if (UniversalPlatform.isDesktopOrWeb) {
      return AppFlowyPopover(
        offset: const Offset(0, 8),
        controller: controller,
        direction: PopoverDirection.bottomWithLeftAligned,
        constraints: BoxConstraints.loose(const Size(364, 356)),
        clickHandler: PopoverClickHandler.gestureDetector,
        margin: const EdgeInsets.all(0),
        onClose: () => _selectionGeneration++,
        popupBuilder: (_) {
          final generation = _selectionGeneration;
          return FlowyIconEmojiPicker(
            tabs: kAllIconPickerTabs,
            initialType: icon.toPickerTabType(),
            documentId: widget.documentId,
            onSelectedEmoji: (r) {
              if (!_canSelect(generation)) return;
              widget.onSelected(r.data);
              if (!r.keepOpen) {
                controller.close();
              }
            },
          );
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: child,
        ),
      );
    }

    return GestureDetector(
      onTap: () async {
        final generation = _selectionGeneration;
        final result = await context.push<EmojiIconData>(
          Uri(
            path: MobileEmojiPickerScreen.routeName,
            queryParameters: {
              MobileEmojiPickerScreen.pageTitle:
                  LocaleKeys.settings_workspacePage_workspaceIcon_title.tr(),
              MobileEmojiPickerScreen.selectTabs:
                  kAllIconPickerTabs.map((tab) => tab.name).toList(),
              MobileEmojiPickerScreen.iconSelectedType:
                  icon.toPickerTabType()?.name,
              MobileEmojiPickerScreen.uploadDocumentId: widget.documentId,
            },
          ).toString(),
        );
        if (_canSelect(generation) && result != null) {
          widget.onSelected(result);
        }
      },
      child: child,
    );
  }
}
