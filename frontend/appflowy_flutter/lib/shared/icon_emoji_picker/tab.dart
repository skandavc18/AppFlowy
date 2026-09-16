import 'package:appflowy/mobile/presentation/home/tab/_round_underline_tab_indicator.dart';
import 'package:flutter/material.dart';

enum PickerTabType {
  emoji,
  icon,
  custom,
  defaultIcons;

  String get tr {
    switch (this) {
      case PickerTabType.emoji:
        return 'Emojis';
      case PickerTabType.icon:
        return 'Icons';
      case PickerTabType.custom:
        return 'Upload';
      case PickerTabType.defaultIcons:
        return 'Default icons';
    }
  }
}

/// Default symbols use the same stored icon type as library icons. Offer them
/// anywhere that accepts icons, including callers with older explicit tab
/// lists. Emoji-only pickers retain their intentional storage restriction.
List<PickerTabType> pickerTabsWithDefaults(List<PickerTabType> tabs) {
  if (!tabs.contains(PickerTabType.icon) ||
      tabs.contains(PickerTabType.defaultIcons)) {
    return tabs;
  }
  return List.unmodifiable([
    for (final tab in tabs) ...[
      if (tab == PickerTabType.icon) PickerTabType.defaultIcons,
      tab,
    ],
  ]);
}

extension StringToPickerTabType on String {
  PickerTabType? toPickerTabType() {
    try {
      return PickerTabType.values.byName(this);
    } on ArgumentError {
      return null;
    }
  }
}

class PickerTab extends StatelessWidget {
  const PickerTab({
    super.key,
    this.onTap,
    required this.controller,
    required this.tabs,
  });

  final List<PickerTabType> tabs;
  final TabController controller;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium;
    final compact = tabs.length > 3;
    final style = baseStyle?.copyWith(
      fontWeight: FontWeight.w500,
      fontSize: compact ? 13.0 : 14.0,
      height: 16.0 / 14.0,
    );
    return TabBar(
      controller: controller,
      indicatorSize: TabBarIndicatorSize.label,
      indicatorColor: Theme.of(context).colorScheme.primary,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      labelStyle: style,
      labelColor: baseStyle?.color,
      labelPadding: EdgeInsets.symmetric(horizontal: compact ? 8.0 : 12.0),
      unselectedLabelStyle: style?.copyWith(
        color: Theme.of(context).hintColor,
      ),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      indicator: RoundUnderlineTabIndicator(
        width: 34.0,
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 3,
        ),
      ),
      onTap: onTap,
      tabs: tabs
          .map(
            (tab) => Tab(
              text: tab.tr,
            ),
          )
          .toList(),
    );
  }
}
