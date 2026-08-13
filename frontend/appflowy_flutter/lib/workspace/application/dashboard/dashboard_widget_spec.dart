import 'dart:math' as math;

import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:flutter/foundation.dart';

/// The soft colour ways a dashboard widget can wear.
///
/// Stored by NAME, so the palette can be re-tuned for light, dark and paper
/// without rewriting a single dashboard.
enum DashboardAccent {
  neutral,
  paper,
  blue,
  green,
  amber,
  orange,
  red,
  pink,
  purple,
  teal;

  static DashboardAccent fromValue(Object? value) =>
      DashboardAccent.values.firstWhere(
        (accent) => accent.name == value,
        orElse: () => DashboardAccent.neutral,
      );
}

/// One thing on a dashboard.
///
/// The widget's own behaviour lives in the registry; this is only what was
/// chosen for it — where it sits, what it reads, what it does and how it looks.
/// Anything a particular widget needs beyond that goes in [settings], so a new
/// widget never changes this class.
@immutable
class DashboardWidgetSpec {
  const DashboardWidgetSpec({
    required this.id,
    required this.type,
    this.placement = const DashboardPlacement(),
    this.title = '',
    this.showTitle = true,
    this.accent = DashboardAccent.neutral,
    this.source = DashboardDataSource.none,
    this.settings = const {},
    this.bindings = const {},
    this.actions = const [],
    this.hidden = false,
    this.visibleWhen = '',
    this.collapsed = false,
  });

  factory DashboardWidgetSpec.fromJson(Map<String, Object?> json) =>
      DashboardWidgetSpec(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        placement: json['at'] is Map
            ? DashboardPlacement.fromJson(
                Map<String, Object?>.from(json['at']! as Map),
              )
            : const DashboardPlacement(),
        title: json['title'] as String? ?? '',
        showTitle: json['show_title'] != false,
        accent: DashboardAccent.fromValue(json['accent']),
        source: json['source'] is Map
            ? DashboardDataSource.fromJson(
                Map<String, Object?>.from(json['source']! as Map),
              )
            : DashboardDataSource.none,
        settings: json['settings'] is Map
            ? Map<String, Object?>.from(json['settings']! as Map)
            : const {},
        bindings: json['bindings'] is Map
            ? Map<String, String>.from(json['bindings']! as Map)
            : const {},
        actions: DashboardAction.listFromJson(json['actions']),
        hidden: json['hidden'] == true,
        visibleWhen: json['visible_when'] as String? ?? '',
        collapsed: json['collapsed'] == true,
      );

  final String id;

  /// The registry key. Unknown types are kept and drawn as a placeholder
  /// rather than dropped, so a dashboard made by a newer build survives.
  final String type;
  final DashboardPlacement placement;
  final String title;
  final bool showTitle;
  final DashboardAccent accent;
  final DashboardDataSource source;
  final Map<String, Object?> settings;

  /// Widget setting name -> dashboard variable key.
  ///
  /// This is the join that makes a dashboard interactive: a chart bound on
  /// `filter` follows whatever the project selector holds.
  final Map<String, String> bindings;
  final List<DashboardAction> actions;
  final bool hidden;

  /// `key` or `key=value` — the widget is only drawn when the state agrees.
  final String visibleWhen;
  final bool collapsed;

  DashboardAction get primaryAction =>
      actions.isEmpty ? DashboardAction.none : actions.first;

  String setting(String key, {String fallback = ''}) {
    final value = settings[key];
    return value is String ? value : fallback;
  }

  double number(String key, {required double fallback}) {
    final value = settings[key];
    if (value is num) {
      return value.toDouble();
    }
    return value is String ? (double.tryParse(value) ?? fallback) : fallback;
  }

  int integer(String key, {required int fallback}) =>
      number(key, fallback: fallback.toDouble()).round();

  bool flag(String key, {bool fallback = false}) {
    final value = settings[key];
    return value is bool ? value : fallback;
  }

  List<Object?> list(String key) {
    final value = settings[key];
    return value is List ? value : const [];
  }

  DashboardWidgetSpec copyWith({
    String? id,
    String? type,
    DashboardPlacement? placement,
    String? title,
    bool? showTitle,
    DashboardAccent? accent,
    DashboardDataSource? source,
    Map<String, Object?>? settings,
    Map<String, String>? bindings,
    List<DashboardAction>? actions,
    bool? hidden,
    String? visibleWhen,
    bool? collapsed,
  }) =>
      DashboardWidgetSpec(
        id: id ?? this.id,
        type: type ?? this.type,
        placement: placement ?? this.placement,
        title: title ?? this.title,
        showTitle: showTitle ?? this.showTitle,
        accent: accent ?? this.accent,
        source: source ?? this.source,
        settings: settings ?? this.settings,
        bindings: bindings ?? this.bindings,
        actions: actions ?? this.actions,
        hidden: hidden ?? this.hidden,
        visibleWhen: visibleWhen ?? this.visibleWhen,
        collapsed: collapsed ?? this.collapsed,
      );

  /// Merge [values] into [settings]; a null value removes the key.
  DashboardWidgetSpec withSettings(Map<String, Object?> values) {
    final next = Map<String, Object?>.from(settings);
    for (final entry in values.entries) {
      if (entry.value == null) {
        next.remove(entry.key);
      } else {
        next[entry.key] = entry.value;
      }
    }
    return copyWith(settings: next);
  }

  DashboardWidgetSpec withBinding(String setting, String variableKey) {
    final next = Map<String, String>.from(bindings);
    if (variableKey.isEmpty) {
      next.remove(setting);
    } else {
      next[setting] = variableKey;
    }
    return copyWith(bindings: next);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type,
        'at': placement.toJson(),
        if (title.isNotEmpty) 'title': title,
        if (!showTitle) 'show_title': false,
        if (accent != DashboardAccent.neutral) 'accent': accent.name,
        if (source.kind != DashboardSourceKind.none) 'source': source.toJson(),
        if (settings.isNotEmpty) 'settings': settings,
        if (bindings.isNotEmpty) 'bindings': bindings,
        if (actions.isNotEmpty)
          'actions': [for (final action in actions) action.toJson()],
        if (hidden) 'hidden': true,
        if (visibleWhen.isNotEmpty) 'visible_when': visibleWhen,
        if (collapsed) 'collapsed': true,
      };

  @override
  bool operator ==(Object other) =>
      other is DashboardWidgetSpec &&
      other.id == id &&
      other.type == type &&
      other.placement == placement &&
      other.title == title &&
      other.showTitle == showTitle &&
      other.accent == accent &&
      other.source == source &&
      mapEquals(other.settings, settings) &&
      mapEquals(other.bindings, bindings) &&
      listEquals(other.actions, actions) &&
      other.hidden == hidden &&
      other.visibleWhen == visibleWhen &&
      other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(
        id,
        type,
        placement,
        title,
        showTitle,
        accent,
        source,
        Object.hashAll(settings.keys),
        Object.hashAll(bindings.keys),
        Object.hashAll(actions),
        hidden,
        visibleWhen,
        collapsed,
      );
}

/// The arrangements a section can be snapped to.
///
/// `free` is the canvas — anything can go anywhere. The rest are one-click
/// tidy-ups that re-flow whatever the section already holds.
enum DashboardSectionLayout {
  free,
  oneColumn,
  twoColumn,
  threeColumn,
  fourColumn,

  /// Two columns, the first twice the width of the second.
  asymmetric,

  /// A narrow rail on the left, the rest on the right.
  sidebarLeft,

  /// The rest on the left, a narrow rail on the right.
  sidebarRight;

  static DashboardSectionLayout fromValue(Object? value) =>
      DashboardSectionLayout.values.firstWhere(
        (layout) => layout.name == value,
        orElse: () => DashboardSectionLayout.free,
      );

  /// The column spans one row of this arrangement is made of, measured
  /// against [DashboardPlacement.referenceColumns].
  List<int> get spans => switch (this) {
        DashboardSectionLayout.free => const [],
        DashboardSectionLayout.oneColumn => const [12],
        DashboardSectionLayout.twoColumn => const [6, 6],
        DashboardSectionLayout.threeColumn => const [4, 4, 4],
        DashboardSectionLayout.fourColumn => const [3, 3, 3, 3],
        DashboardSectionLayout.asymmetric => const [8, 4],
        DashboardSectionLayout.sidebarLeft => const [3, 9],
        DashboardSectionLayout.sidebarRight => const [9, 3],
      };
}

/// A band of the dashboard: a heading, an arrangement and the widgets in it.
///
/// Sections are what make a long dashboard readable, and what "collapse this
/// part away" and "show this only when a toggle is on" hang off.
@immutable
class DashboardSection {
  const DashboardSection({
    required this.id,
    this.title = '',
    this.collapsed = false,
    this.layout = DashboardSectionLayout.free,
    this.widgets = const [],
    this.accent = DashboardAccent.neutral,
    this.visibleWhen = '',
    this.showDivider = false,
  });

  factory DashboardSection.fromJson(Map<String, Object?> json) =>
      DashboardSection(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        collapsed: json['collapsed'] == true,
        layout: DashboardSectionLayout.fromValue(json['layout']),
        widgets: [
          for (final entry in (json['widgets'] as List? ?? const []))
            if (entry is Map)
              DashboardWidgetSpec.fromJson(Map<String, Object?>.from(entry)),
        ],
        accent: DashboardAccent.fromValue(json['accent']),
        visibleWhen: json['visible_when'] as String? ?? '',
        showDivider: json['divider'] == true,
      );

  final String id;
  final String title;
  final bool collapsed;
  final DashboardSectionLayout layout;
  final List<DashboardWidgetSpec> widgets;
  final DashboardAccent accent;
  final String visibleWhen;
  final bool showDivider;

  bool get hasHeading => title.isNotEmpty;

  DashboardWidgetSpec? widgetById(String id) {
    for (final widget in widgets) {
      if (widget.id == id) {
        return widget;
      }
    }
    return null;
  }

  DashboardSection copyWith({
    String? id,
    String? title,
    bool? collapsed,
    DashboardSectionLayout? layout,
    List<DashboardWidgetSpec>? widgets,
    DashboardAccent? accent,
    String? visibleWhen,
    bool? showDivider,
  }) =>
      DashboardSection(
        id: id ?? this.id,
        title: title ?? this.title,
        collapsed: collapsed ?? this.collapsed,
        layout: layout ?? this.layout,
        widgets: widgets ?? this.widgets,
        accent: accent ?? this.accent,
        visibleWhen: visibleWhen ?? this.visibleWhen,
        showDivider: showDivider ?? this.showDivider,
      );

  /// Replace one widget, leaving everything else alone.
  DashboardSection withWidget(DashboardWidgetSpec widget) => copyWith(
        widgets: [
          for (final existing in widgets)
            if (existing.id == widget.id) widget else existing,
        ],
      );

  DashboardSection withoutWidget(String id) => copyWith(
        widgets: [
          for (final widget in widgets)
            if (widget.id != id) widget,
        ],
      );

  Map<String, Object?> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (collapsed) 'collapsed': true,
        if (layout != DashboardSectionLayout.free) 'layout': layout.name,
        'widgets': [for (final widget in widgets) widget.toJson()],
        if (accent != DashboardAccent.neutral) 'accent': accent.name,
        if (visibleWhen.isNotEmpty) 'visible_when': visibleWhen,
        if (showDivider) 'divider': true,
      };

  @override
  bool operator ==(Object other) =>
      other is DashboardSection &&
      other.id == id &&
      other.title == title &&
      other.collapsed == collapsed &&
      other.layout == layout &&
      listEquals(other.widgets, widgets) &&
      other.accent == accent &&
      other.visibleWhen == visibleWhen &&
      other.showDivider == showDivider;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        collapsed,
        layout,
        Object.hashAll(widgets),
        accent,
        visibleWhen,
        showDivider,
      );
}

/// Re-flow [widgets] into the arrangement [layout] describes.
///
/// Reading order is preserved: the first widget takes the first slot of the
/// first row, and a row is filled before the next one starts. Heights are kept
/// so a tall widget stays tall.
List<DashboardWidgetSpec> applySectionLayout(
  List<DashboardWidgetSpec> widgets,
  DashboardSectionLayout layout,
) {
  final spans = layout.spans;
  if (spans.isEmpty || widgets.isEmpty) {
    return widgets;
  }
  final ordered = [...widgets]..sort((a, b) {
      final byRow = a.placement.row.compareTo(b.placement.row);
      return byRow != 0
          ? byRow
          : a.placement.column.compareTo(b.placement.column);
    });

  final result = <DashboardWidgetSpec>[];
  var row = 0;
  var index = 0;
  while (index < ordered.length) {
    final slice = ordered.skip(index).take(spans.length).toList();
    var column = 0;
    var tallest = 1;
    for (var i = 0; i < slice.length; i++) {
      final span = spans[i];
      final widget = slice[i];
      tallest = math.max(tallest, widget.placement.rowSpan);
      result.add(
        widget.copyWith(
          placement: widget.placement.copyWith(
            column: column,
            columnSpan: span,
            row: row,
          ),
        ),
      );
      column += span;
    }
    row += tallest;
    index += spans.length;
  }

  // Hand them back in the caller's order so nothing re-mounts needlessly.
  final byId = {for (final widget in result) widget.id: widget};
  return [for (final widget in widgets) byId[widget.id] ?? widget];
}
