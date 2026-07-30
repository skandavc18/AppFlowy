import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';

export 'menu_item.dart';
export 'section.dart';
export 'text_menu_item.dart';

/// The main menu container widget, supporting sections, menu items.
///
/// Geometry is fixed rather than derived from spacing tokens so this card is
/// interchangeable with the application's context menu surface.
class AFMenu extends StatelessWidget {
  const AFMenu({
    super.key,
    required this.children,
    this.width,
    this.backgroundColor,
  });

  /// Corner radius shared with every other menu in the application.
  static const double cornerRadius = 13;

  /// Inset around the rows.
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: 5,
    vertical: 5,
  );

  /// The list of widgets to display in the menu (sections or menu items).
  final List<Widget> children;

  /// The width of the menu.
  final double? width;

  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.surfaceColorScheme.primary,
        borderRadius: BorderRadius.circular(cornerRadius),
        border: Border.all(
          color: theme.borderColorScheme.primary,
          width: 0.6,
        ),
        boxShadow: theme.shadow.small,
      ),
      width: width,
      padding: cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
