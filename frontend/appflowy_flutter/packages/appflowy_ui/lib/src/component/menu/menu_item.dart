import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

/// Menu item widget
class AFMenuItem extends StatelessWidget {
  /// Creates a menu item.
  ///
  /// [title] and [onTap] are required. Optionally provide [leading], [subtitle], [selected], and [trailing].
  const AFMenuItem({
    super.key,
    required this.title,
    this.onTap,
    this.leading,
    this.subtitle,
    this.selected = false,
    this.trailing,
    this.padding,
    this.showSelectedBackground = true,
    this.selectedBackgroundColor,
  });

  /// Row geometry shared with every other menu in the application.
  static const double rowRadius = 8;
  static const double iconGap = 10;
  static const EdgeInsets rowPadding = EdgeInsets.symmetric(
    horizontal: 9,
    vertical: 6,
  );

  /// Widget to display before the title (e.g., an icon or avatar).
  final Widget? leading;

  /// The main text of the menu item.
  final Widget title;

  /// Optional secondary text displayed below the title.
  final Widget? subtitle;

  /// Whether the menu item is selected.
  final bool selected;

  /// Whether to show the selected background color.
  final bool showSelectedBackground;

  /// Optional background color used when this item is selected.
  final Color? selectedBackgroundColor;

  /// Called when the menu item is tapped.
  final VoidCallback? onTap;

  /// Widget to display after the title (e.g., a trailing icon).
  final Widget? trailing;

  /// Padding of the menu item.
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final effectivePadding = padding ?? rowPadding;

    return AFBaseButton(
      onTap: onTap,
      padding: effectivePadding,
      borderRadius: rowRadius,
      borderColor: (context, isHovering, disabled, isFocused) {
        return Colors.transparent;
      },
      backgroundColor: (context, isHovering, disabled) {
        final theme = AppFlowyTheme.of(context);
        if (disabled) {
          return theme.fillColorScheme.content;
        }
        if (selected && showSelectedBackground) {
          return selectedBackgroundColor ?? theme.fillColorScheme.themeSelect;
        }
        if (isHovering && onTap != null) {
          return theme.fillColorScheme.contentHover;
        }
        return theme.fillColorScheme.content;
      },
      builder: (context, isHovering, disabled) {
        return Row(
          children: [
            // Leading widget (icon/avatar), if provided
            if (leading != null) ...[
              leading!,
              const SizedBox(width: iconGap),
            ],
            // Main content: title and optional subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title text
                  title,
                  // Subtitle text, if provided
                  if (subtitle != null) subtitle!,
                ],
              ),
            ),
            // Trailing widget (e.g., icon), if provided
            if (trailing != null) trailing!,
          ],
        );
      },
    );
  }
}
