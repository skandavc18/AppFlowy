import 'package:flutter/widgets.dart';

/// One entry in an [AppContextMenu].
///
/// Every popup, dropdown, overflow and right-click menu in the application is
/// described with these, so a menu is data rather than a bespoke widget tree.
sealed class AppMenuEntry {
  const AppMenuEntry();
}

/// A selectable row.
///
/// A row with a [submenu] opens it on hover and never needs a click; a row
/// without one runs [onSelected] and closes the menu.
class AppMenuItem extends AppMenuEntry {
  const AppMenuItem({
    required this.label,
    this.icon,
    this.iconWidget,
    this.subtitle,
    this.shortcut,
    this.trailing,
    this.onSelected,
    this.value,
    this.submenu = const <AppMenuEntry>[],
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.closeOnSelect = true,
  });

  final String label;

  /// The glyph shown in the leading slot. Prefer this over [iconWidget] so the
  /// whole application keeps one icon family and one icon size.
  final IconData? icon;

  /// An arbitrary leading widget, for the few rows that show artwork rather
  /// than an icon. Sized to [AppMenuMetrics.iconSlot] by the row.
  final Widget? iconWidget;

  /// A quiet second line, for rows whose label needs qualifying.
  final String? subtitle;

  /// A keyboard hint aligned to the right edge, e.g. `Ctrl+C`.
  final String? shortcut;

  /// Replaces the shortcut slot when a row needs a badge or a checkmark.
  final Widget? trailing;

  final VoidCallback? onSelected;

  /// Returned from `showAppMenu` when this row is chosen.
  final Object? value;

  final List<AppMenuEntry> submenu;

  final bool enabled;

  /// Draws the row as the current choice — a tinted background and an accent
  /// icon, never a heavy highlight.
  final bool selected;

  /// Delete, remove, erase, move to trash. Tints the label and icon a subdued
  /// red without making the row dominant.
  final bool destructive;

  /// Leave the menu open after running [onSelected], for rows that toggle a
  /// setting the user may want to change again.
  final bool closeOnSelect;

  bool get hasSubmenu => submenu.isNotEmpty;

  /// Whether the keyboard and the pointer can land on this row.
  bool get isInteractive => enabled;

  AppMenuItem copyWith({
    String? label,
    IconData? icon,
    String? shortcut,
    bool? enabled,
    bool? selected,
    bool? destructive,
    List<AppMenuEntry>? submenu,
  }) =>
      AppMenuItem(
        label: label ?? this.label,
        icon: icon ?? this.icon,
        iconWidget: iconWidget,
        subtitle: subtitle,
        shortcut: shortcut ?? this.shortcut,
        trailing: trailing,
        onSelected: onSelected,
        value: value,
        submenu: submenu ?? this.submenu,
        enabled: enabled ?? this.enabled,
        selected: selected ?? this.selected,
        destructive: destructive ?? this.destructive,
        closeOnSelect: closeOnSelect,
      );
}

/// A hairline between two groups of rows.
///
/// Consecutive and leading/trailing separators are dropped when the menu is
/// built, so callers can add one after any optional group without checking.
class AppMenuSeparator extends AppMenuEntry {
  const AppMenuSeparator();
}

/// A small uppercase label naming the group beneath it.
class AppMenuHeader extends AppMenuEntry {
  const AppMenuHeader(this.label);

  final String label;
}

/// An arbitrary widget in the menu — colour grids, sliders, previews.
///
/// Use [AppMenuScope.of] inside the builder to close the menu.
class AppMenuCustom extends AppMenuEntry {
  const AppMenuCustom({required this.builder});

  final WidgetBuilder builder;
}

/// Drops separators that would render against nothing: leading, trailing and
/// repeated ones.
List<AppMenuEntry> normalizeAppMenuEntries(List<AppMenuEntry> entries) {
  final result = <AppMenuEntry>[];
  for (final entry in entries) {
    if (entry is AppMenuSeparator) {
      if (result.isEmpty || result.last is AppMenuSeparator) {
        continue;
      }
    }
    result.add(entry);
  }
  while (result.isNotEmpty && result.last is AppMenuSeparator) {
    result.removeLast();
  }
  return result;
}
