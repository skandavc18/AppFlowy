import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'mobile_selection_menu_item.dart';

class MobileSelectionMenuItemWidget extends StatelessWidget {
  const MobileSelectionMenuItemWidget({
    super.key,
    required this.editorState,
    required this.menuService,
    required this.item,
    required this.isSelected,
    required this.selectionMenuStyle,
    required this.onTap,
  });

  final EditorState editorState;
  final SelectionMenuService menuService;
  final SelectionMenuItem item;
  final bool isSelected;
  final MobileSelectionMenuStyle selectionMenuStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = selectionMenuStyle;
    final showRightArrow = item is MobileSelectionMenuItem &&
        (item as MobileSelectionMenuItem).isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton.icon(
        icon: item.icon(
          editorState,
          false,
          selectionMenuStyle,
        ),
        style: ButtonStyle(
          alignment: Alignment.centerLeft,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          backgroundColor: isSelected
              ? WidgetStateProperty.all(
                  style.selectionMenuItemSelectedColor,
                )
              : WidgetStateProperty.all(Colors.transparent),
        ),
        label: Row(
          children: [
            item.nameBuilder?.call(item.name, style, false) ??
                Text(
                  item.name,
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    color: style.selectionMenuItemTextColor,
                    fontSize: 16.0,
                  ),
                ),
            if (showRightArrow) ...[
              Spacer(),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: style.selectionMenuItemRightIconColor,
              ),
            ],
          ],
        ),
        onPressed: () {
          onTap.call();
          item.handler(
            editorState,
            menuService,
            context,
          );
        },
      ),
    );
  }
}

class MobileSelectionMenuStyle extends SelectionMenuStyle {
  const MobileSelectionMenuStyle({
    required super.selectionMenuBackgroundColor,
    required super.selectionMenuItemTextColor,
    required super.selectionMenuItemIconColor,
    required super.selectionMenuItemSelectedTextColor,
    required super.selectionMenuItemSelectedIconColor,
    required super.selectionMenuItemSelectedColor,
    required super.selectionMenuUnselectedLabelColor,
    required super.selectionMenuDividerColor,
    required super.selectionMenuLinkBorderColor,
    required super.selectionMenuInvalidLinkColor,
    required super.selectionMenuButtonColor,
    required super.selectionMenuButtonTextColor,
    required super.selectionMenuButtonIconColor,
    required super.selectionMenuButtonBorderColor,
    required super.selectionMenuTabIndicatorColor,
    required this.selectionMenuItemRightIconColor,
  });

  factory MobileSelectionMenuStyle.fromContext(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = PremiumThemeExtension.maybeOf(context);
    final surface = palette?.floatingSurface ?? colors.surfaceContainerLowest;
    final textPrimary = palette?.textPrimary ?? colors.onSurface;
    final textSecondary = palette?.textSecondary ?? colors.onSurfaceVariant;
    final textMuted = palette?.textMuted ?? theme.hintColor;
    final selected = palette?.selected ?? colors.primaryContainer;
    final accent = palette?.accent ?? colors.primary;
    final onAccent = palette?.onAccent ?? colors.onPrimary;
    final border = palette?.border ?? colors.outlineVariant;

    return MobileSelectionMenuStyle(
      selectionMenuBackgroundColor: surface,
      selectionMenuItemTextColor: textPrimary,
      selectionMenuItemIconColor: textSecondary,
      selectionMenuItemSelectedColor: selected,
      selectionMenuItemRightIconColor: textMuted,
      selectionMenuItemSelectedTextColor: accent,
      selectionMenuItemSelectedIconColor: accent,
      selectionMenuUnselectedLabelColor: textSecondary,
      selectionMenuDividerColor: border,
      selectionMenuLinkBorderColor: accent,
      selectionMenuInvalidLinkColor: colors.error,
      selectionMenuButtonColor: accent,
      selectionMenuButtonTextColor: onAccent,
      selectionMenuButtonIconColor: onAccent,
      selectionMenuButtonBorderColor: accent,
      selectionMenuTabIndicatorColor: accent,
    );
  }

  final Color selectionMenuItemRightIconColor;

  static const MobileSelectionMenuStyle light = MobileSelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFFFFFEFA),
    selectionMenuItemTextColor: Color(0xFF252522),
    selectionMenuItemIconColor: Color(0xFF62625D),
    selectionMenuItemSelectedColor: Color(0xFFE8F0F0),
    selectionMenuItemRightIconColor: Color(0xFF8D8C84),
    selectionMenuItemSelectedTextColor: Color(0xFF356B77),
    selectionMenuItemSelectedIconColor: Color(0xFF356B77),
    selectionMenuUnselectedLabelColor: Color(0xFF62625D),
    selectionMenuDividerColor: Color(0x16252522),
    selectionMenuLinkBorderColor: Color(0xFF356B77),
    selectionMenuInvalidLinkColor: Color(0xFFB34C53),
    selectionMenuButtonColor: Color(0xFF356B77),
    selectionMenuButtonTextColor: Color(0xFFFAFAF6),
    selectionMenuButtonIconColor: Color(0xFFFAFAF6),
    selectionMenuButtonBorderColor: Color(0xFF356B77),
    selectionMenuTabIndicatorColor: Color(0xFF356B77),
  );

  static const MobileSelectionMenuStyle dark = MobileSelectionMenuStyle(
    selectionMenuBackgroundColor: Color(0xFF424242),
    selectionMenuItemTextColor: Color(0xFFFFFFFF),
    selectionMenuItemIconColor: Color(0xFFFFFFFF),
    selectionMenuItemSelectedColor: Color(0xFF666666),
    selectionMenuItemRightIconColor: Color(0xB3FFFFFF),
    selectionMenuItemSelectedTextColor: Color(0xFF131720),
    selectionMenuItemSelectedIconColor: Color(0xFF131720),
    selectionMenuUnselectedLabelColor: Color(0xFFBBC3CD),
    selectionMenuDividerColor: Color(0xFF3A3F44),
    selectionMenuLinkBorderColor: Color(0xFF3A3F44),
    selectionMenuInvalidLinkColor: Color(0xFFE53935),
    selectionMenuButtonColor: Color(0xFF00BCF0),
    selectionMenuButtonTextColor: Color(0xFFFFFFFF),
    selectionMenuButtonIconColor: Color(0xFFFFFFFF),
    selectionMenuButtonBorderColor: Color(0xFF00BCF0),
    selectionMenuTabIndicatorColor: Color(0xFF00BCF0),
  );
}
