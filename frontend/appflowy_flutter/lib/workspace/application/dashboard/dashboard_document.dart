import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:flutter/foundation.dart';

/// How a dashboard is being used at this moment.
///
/// There is no reading mode. A dashboard is a thing you build while you use
/// it, so everything is always movable; only a wall display is read-only.
enum DashboardMode {
  /// Everything can be moved, resized, configured and added.
  edit,

  /// The dashboard fills the application window.
  focus,

  /// Fullscreen, larger type, nothing but the content — for a wall display.
  presentation;

  static DashboardMode fromValue(Object? value) =>
      DashboardMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => DashboardMode.edit,
      );

  bool get isEditable => this != DashboardMode.presentation;

  bool get isImmersive =>
      this == DashboardMode.focus || this == DashboardMode.presentation;
}

/// How much room a dashboard gives its widgets.
enum DashboardDensity {
  compact,
  comfortable,
  spacious;

  static DashboardDensity fromValue(Object? value) =>
      DashboardDensity.values.firstWhere(
        (density) => density.name == value,
        orElse: () => DashboardDensity.comfortable,
      );

  double get gap => switch (this) {
        DashboardDensity.compact => 10,
        DashboardDensity.comfortable => 14,
        DashboardDensity.spacious => 20,
      };

  /// The height of one row unit.
  double get rowHeight => switch (this) {
        DashboardDensity.compact => 40,
        DashboardDensity.comfortable => 46,
        DashboardDensity.spacious => 54,
      };
}

/// What the canvas is printed on.
enum DashboardBackground {
  /// The page's own colour.
  canvas,

  /// A faint wash of the dashboard's accent.
  tinted,

  /// A quiet dot grid, so the arrangement is legible while it is being built.
  grid;

  static DashboardBackground fromValue(Object? value) =>
      DashboardBackground.values.firstWhere(
        (background) => background.name == value,
        orElse: () => DashboardBackground.canvas,
      );
}

/// The dashboard's own preferences.
@immutable
class DashboardSettings {
  const DashboardSettings({
    this.density = DashboardDensity.comfortable,
    this.background = DashboardBackground.canvas,
    this.accent = DashboardAccent.neutral,
    this.showHeader = true,
    this.showControlBar = true,
    this.maxWidth = 0,
    this.columns = 0,
    this.reduceMotion = false,
    this.refreshSeconds = 0,
  });

  factory DashboardSettings.fromJson(Map<String, Object?> json) =>
      DashboardSettings(
        density: DashboardDensity.fromValue(json['density']),
        background: DashboardBackground.fromValue(json['background']),
        accent: DashboardAccent.fromValue(json['accent']),
        showHeader: json['header'] != false,
        showControlBar: json['controls'] != false,
        maxWidth: (json['max_width'] as num?)?.toDouble() ?? 0,
        columns: (json['columns'] as num?)?.round() ?? 0,
        reduceMotion: json['still'] == true,
        refreshSeconds: (json['refresh'] as num?)?.round() ?? 0,
      );

  final DashboardDensity density;
  final DashboardBackground background;
  final DashboardAccent accent;
  final bool showHeader;

  /// Whether the variables bar is drawn when the dashboard has variables.
  final bool showControlBar;

  /// 0 means "as wide as the window".
  final double maxWidth;

  /// 0 means "as many as the width allows".
  final int columns;

  /// Nothing moves on its own: no slideshows, no cycling previews.
  final bool reduceMotion;

  final int refreshSeconds;

  DashboardSettings copyWith({
    DashboardDensity? density,
    DashboardBackground? background,
    DashboardAccent? accent,
    bool? showHeader,
    bool? showControlBar,
    double? maxWidth,
    int? columns,
    bool? reduceMotion,
    int? refreshSeconds,
  }) =>
      DashboardSettings(
        density: density ?? this.density,
        background: background ?? this.background,
        accent: accent ?? this.accent,
        showHeader: showHeader ?? this.showHeader,
        showControlBar: showControlBar ?? this.showControlBar,
        maxWidth: maxWidth ?? this.maxWidth,
        columns: columns ?? this.columns,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        refreshSeconds: refreshSeconds ?? this.refreshSeconds,
      );

  Map<String, Object?> toJson() => {
        if (density != DashboardDensity.comfortable) 'density': density.name,
        if (background != DashboardBackground.canvas)
          'background': background.name,
        if (accent != DashboardAccent.neutral) 'accent': accent.name,
        if (!showHeader) 'header': false,
        if (!showControlBar) 'controls': false,
        if (maxWidth > 0) 'max_width': maxWidth,
        if (columns > 0) 'columns': columns,
        if (reduceMotion) 'still': true,
        if (refreshSeconds > 0) 'refresh': refreshSeconds,
      };

  @override
  bool operator ==(Object other) =>
      other is DashboardSettings &&
      other.density == density &&
      other.background == background &&
      other.accent == accent &&
      other.showHeader == showHeader &&
      other.showControlBar == showControlBar &&
      other.maxWidth == maxWidth &&
      other.columns == columns &&
      other.reduceMotion == reduceMotion &&
      other.refreshSeconds == refreshSeconds;

  @override
  int get hashCode => Object.hash(
        density,
        background,
        accent,
        showHeader,
        showControlBar,
        maxWidth,
        columns,
        reduceMotion,
        refreshSeconds,
      );
}

/// A whole dashboard: what it holds, what state it keeps and how it looks.
///
/// This is the only thing persisted. It is deliberately independent of every
/// data source — a dashboard that reads nothing is still a complete document.
@immutable
class DashboardDocument {
  const DashboardDocument({
    this.sections = const [],
    this.variables = const [],
    this.settings = const DashboardSettings(),
    this.subtitle = '',
    this.icon = '',
  });

  factory DashboardDocument.fromJson(Map<String, Object?> json) =>
      DashboardDocument(
        sections: [
          for (final entry in (json['sections'] as List? ?? const []))
            if (entry is Map)
              DashboardSection.fromJson(Map<String, Object?>.from(entry)),
        ],
        variables: [
          for (final entry in (json['variables'] as List? ?? const []))
            if (entry is Map)
              DashboardVariable.fromJson(Map<String, Object?>.from(entry)),
        ],
        settings: json['settings'] is Map
            ? DashboardSettings.fromJson(
                Map<String, Object?>.from(json['settings']! as Map),
              )
            : const DashboardSettings(),
        subtitle: json['subtitle'] as String? ?? '',
        icon: json['icon'] as String? ?? '',
      );

  /// A dashboard with one unnamed section, ready to be built in.
  factory DashboardDocument.blank() => DashboardDocument(
        sections: [DashboardSection(id: newDashboardId('section'))],
      );

  final List<DashboardSection> sections;
  final List<DashboardVariable> variables;
  final DashboardSettings settings;
  final String subtitle;
  final String icon;

  bool get isEmpty =>
      sections.every((section) => section.widgets.isEmpty) && variables.isEmpty;

  int get widgetCount {
    var count = 0;
    for (final section in sections) {
      count += section.widgets.length;
    }
    return count;
  }

  Iterable<DashboardWidgetSpec> get allWidgets sync* {
    for (final section in sections) {
      yield* section.widgets;
    }
  }

  DashboardSection? sectionById(String id) {
    for (final section in sections) {
      if (section.id == id) {
        return section;
      }
    }
    return null;
  }

  /// The section holding [widgetId], if any.
  DashboardSection? sectionOf(String widgetId) {
    for (final section in sections) {
      if (section.widgetById(widgetId) != null) {
        return section;
      }
    }
    return null;
  }

  DashboardWidgetSpec? widgetById(String id) {
    for (final section in sections) {
      final widget = section.widgetById(id);
      if (widget != null) {
        return widget;
      }
    }
    return null;
  }

  DashboardVariable? variableFor(String key) {
    for (final variable in variables) {
      if (variable.key == key) {
        return variable;
      }
    }
    return null;
  }

  DashboardDocument copyWith({
    List<DashboardSection>? sections,
    List<DashboardVariable>? variables,
    DashboardSettings? settings,
    String? subtitle,
    String? icon,
  }) =>
      DashboardDocument(
        sections: sections ?? this.sections,
        variables: variables ?? this.variables,
        settings: settings ?? this.settings,
        subtitle: subtitle ?? this.subtitle,
        icon: icon ?? this.icon,
      );

  DashboardDocument withSection(DashboardSection section) => copyWith(
        sections: [
          for (final existing in sections)
            if (existing.id == section.id) section else existing,
        ],
      );

  /// Replace one widget wherever it lives.
  DashboardDocument withWidget(DashboardWidgetSpec widget) => copyWith(
        sections: [
          for (final section in sections)
            if (section.widgetById(widget.id) != null)
              section.withWidget(widget)
            else
              section,
        ],
      );

  DashboardDocument withoutWidget(String id) => copyWith(
        sections: [
          for (final section in sections) section.withoutWidget(id),
        ],
      );

  /// Add [widget] to [sectionId], or to the last section when it is not named.
  DashboardDocument addWidget(
    DashboardWidgetSpec widget, {
    String sectionId = '',
  }) {
    if (sections.isEmpty) {
      return copyWith(
        sections: [
          DashboardSection(
            id: newDashboardId('section'),
            widgets: [widget],
          ),
        ],
      );
    }
    final target = sectionId.isEmpty ? sections.last.id : sectionId;
    return copyWith(
      sections: [
        for (final section in sections)
          if (section.id == target)
            section.copyWith(widgets: [...section.widgets, widget])
          else
            section,
      ],
    );
  }

  /// Move [widgetId] into [sectionId], keeping its configuration.
  DashboardDocument moveWidget(String widgetId, String sectionId) {
    final widget = widgetById(widgetId);
    if (widget == null || sectionOf(widgetId)?.id == sectionId) {
      return this;
    }
    return withoutWidget(widgetId).addWidget(widget, sectionId: sectionId);
  }

  DashboardDocument withVariable(DashboardVariable variable) {
    final exists = variables.any((existing) => existing.key == variable.key);
    return copyWith(
      variables: exists
          ? [
              for (final existing in variables)
                if (existing.key == variable.key) variable else existing,
            ]
          : [...variables, variable],
    );
  }

  DashboardDocument withoutVariable(String key) => copyWith(
        variables: [
          for (final variable in variables)
            if (variable.key != key) variable,
        ],
        // A binding onto a variable that is gone would silently do nothing,
        // so it is dropped with it.
        sections: [
          for (final section in sections)
            section.copyWith(
              widgets: [
                for (final widget in section.widgets)
                  widget.copyWith(
                    bindings: {
                      for (final entry in widget.bindings.entries)
                        if (entry.value != key) entry.key: entry.value,
                    },
                  ),
              ],
            ),
        ],
      );

  /// The slots one section contributes to the grid.
  List<DashboardSlot> slotsFor(DashboardSection section) => [
        for (final widget in section.widgets)
          DashboardSlot(id: widget.id, placement: widget.placement),
      ];

  Map<String, Object?> toJson() => {
        'sections': [for (final section in sections) section.toJson()],
        if (variables.isNotEmpty)
          'variables': [for (final variable in variables) variable.toJson()],
        if (settings.toJson().isNotEmpty) 'settings': settings.toJson(),
        if (subtitle.isNotEmpty) 'subtitle': subtitle,
        if (icon.isNotEmpty) 'icon': icon,
      };

  @override
  bool operator ==(Object other) =>
      other is DashboardDocument &&
      listEquals(other.sections, sections) &&
      listEquals(other.variables, variables) &&
      other.settings == settings &&
      other.subtitle == subtitle &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(sections),
        Object.hashAll(variables),
        settings,
        subtitle,
        icon,
      );
}

/// Whether something whose visibility reads `key` or `key=value` should be
/// drawn against [state].
///
/// An empty rule always shows. A bare key means "when this is truthy", which
/// is what a toggle wants; `key=value` compares, which is what a selector
/// driving a section wants.
bool dashboardVisibilityHolds(String rule, DashboardStateValues state) {
  if (rule.isEmpty) {
    return true;
  }
  final negate = rule.startsWith('!');
  final body = negate ? rule.substring(1) : rule;
  final separator = body.indexOf('=');
  final bool holds;
  if (separator < 0) {
    final value = state[body];
    holds = value != null &&
        value != false &&
        value != '' &&
        !(value is List && value.isEmpty);
  } else {
    final key = body.substring(0, separator);
    final expected = body.substring(separator + 1);
    final value = state[key];
    holds =
        value is List ? value.contains(expected) : '${value ?? ''}' == expected;
  }
  return negate ? !holds : holds;
}

var _idCounter = 0;

/// A short, unique-enough id for a section or a widget.
///
/// Ids only have to be unique inside one dashboard, so the clock plus a
/// counter is enough and keeps the stored document readable.
String newDashboardId(String prefix) {
  _idCounter = (_idCounter + 1) % 100000;
  final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  return '$prefix-$stamp-$_idCounter';
}
