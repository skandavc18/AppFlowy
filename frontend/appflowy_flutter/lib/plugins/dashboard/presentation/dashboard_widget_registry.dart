import 'package:appflowy/plugins/dashboard/presentation/dashboard_actions.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_builtin_widgets.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// Everything a dashboard widget is handed when it is drawn.
///
/// A widget never reaches for the controller's internals: it reads its own
/// spec, reads dashboard state, and writes back through [update]. That is what
/// keeps a widget from having to know it is on a dashboard at all.
@immutable
class DashboardWidgetContext {
  const DashboardWidgetContext({
    required this.context,
    required this.controller,
    required this.spec,
    required this.palette,
  });

  final BuildContext context;
  final DashboardController controller;
  final DashboardWidgetSpec spec;
  final DashboardPalette palette;

  DashboardMode get mode => controller.mode;

  bool get isEditable => controller.isEditable;

  bool get isPresenting => mode == DashboardMode.presentation;

  /// Whether the words a widget holds can be typed into.
  ///
  /// Content is not configuration: a note is written where it is read, so only
  /// presentation makes it read-only.
  bool get isTypable => !isPresenting;

  DashboardStateValues get state => controller.state;

  DashboardDocument get document => controller.document;

  DashboardTone get tone => palette.toneFor(spec.accent);

  Color get strong => palette.strongFor(spec.accent);

  /// Bumped when something asked every widget to read its source again.
  int get refreshToken => controller.refreshToken;

  /// Change this widget. [transient] is for a change still in flight, so a
  /// drag or a slide does not fill the undo history.
  void update(
    DashboardWidgetSpec Function(DashboardWidgetSpec spec) change, {
    bool transient = false,
  }) =>
      controller.edit(
        (document) => document.withWidget(change(spec)),
        transient: transient,
      );

  void setSettings(Map<String, Object?> values) =>
      update((spec) => spec.withSettings(values));

  void setSource(DashboardDataSource source) =>
      update((spec) => spec.copyWith(source: source));

  /// Ask which thing this widget shows, right where it was pressed.
  ///
  /// A "choose…" affordance that opens the settings panel instead of the
  /// picker is a dead end, so an empty widget asks the question itself.
  Future<void> pickSource({
    required DashboardSourceKind kind,
    bool Function(ViewPB view)? filter,
  }) async {
    final chosen = await showInteractiveViewPicker(
      context,
      selectedViewId: spec.source.viewId.isEmpty ? null : spec.source.viewId,
      filter: filter,
    );
    if (chosen == null) {
      return;
    }
    setSource(
      spec.source.copyWith(kind: kind, viewId: chosen.id, name: chosen.name),
    );
  }

  /// The value of the variable bound to [setting], or null when the setting is
  /// not bound to anything.
  Object? boundValue(String setting) {
    final key = spec.bindings[setting];
    return key == null || key.isEmpty ? null : state[key];
  }

  /// The variable bound to [setting], if any.
  DashboardVariable? boundVariable(String setting) {
    final key = spec.bindings[setting];
    return key == null || key.isEmpty ? null : document.variableFor(key);
  }

  Future<void> run(DashboardAction action) =>
      runDashboardAction(context, controller: controller, action: action);
}

/// Where a widget is offered in the "Add" menu.
enum DashboardWidgetGroup {
  /// Words: headings, notes, callouts, dividers.
  text,

  /// Things from the workspace: pages, pictures, files, links, embeds.
  content,

  /// Books, albums, repositories — the workspace's own collections.
  collections,

  /// Anything that reads a source: databases, collections, charts, metrics.
  data,

  /// Clocks, calendars, countdowns, reminders.
  time,

  /// Controls that do something: buttons, selectors, inputs, toggles.
  controls,

  /// Everything else a dashboard can show — weather today, more tomorrow.
  info,
}

/// One kind of thing a dashboard can hold.
///
/// This is the extension point. A new widget is one of these plus a builder;
/// nothing in the canvas, the menus, the configuration panel or the persisted
/// document has to change for it to exist.
@immutable
class DashboardWidgetDefinition {
  const DashboardWidgetDefinition({
    required this.type,
    required this.label,
    required this.icon,
    required this.group,
    required this.builder,
    this.description,
    this.defaultColumnSpan = 4,
    this.defaultRowSpan = 4,
    this.minimumColumnSpan = 1,
    this.minimumRowSpan = 1,
    this.defaultSettings = const {},
    this.defaultSource = DashboardDataSource.none,
    this.defaultAccent = DashboardAccent.neutral,
    this.defaultTitle,
    this.showsTitleByDefault = true,
    this.paintsOwnSurface = false,
    this.padding,
    this.configure,
    this.keywords = const [],
    this.slashName,
  });

  final String type;

  /// Resolved lazily so a definition can be a constant while its name is
  /// translated.
  final String Function() label;
  final String Function()? description;
  final IconData icon;
  final DashboardWidgetGroup group;
  final Widget Function(DashboardWidgetContext context) builder;

  final int defaultColumnSpan;
  final int defaultRowSpan;
  final int minimumColumnSpan;
  final int minimumRowSpan;

  final Map<String, Object?> defaultSettings;
  final DashboardDataSource defaultSource;
  final DashboardAccent defaultAccent;
  final String Function()? defaultTitle;
  final bool showsTitleByDefault;

  /// True when the widget draws edge to edge and the card must not paint a
  /// surface, a title or padding around it — a divider, a picture, an embed.
  final bool paintsOwnSurface;

  /// Overrides the card's usual inset.
  final EdgeInsets? padding;

  final List<DashboardConfigField> Function(DashboardWidgetContext context)?
      configure;

  /// Extra words the "Add" search matches on.
  final List<String> keywords;

  /// The `/` command that inserts this widget, when it has one.
  final String? slashName;

  /// A fresh spec for this widget, ready to be dropped on the canvas.
  DashboardWidgetSpec create({DashboardPlacement? placement}) =>
      DashboardWidgetSpec(
        id: newDashboardId('w'),
        type: type,
        placement: placement ??
            DashboardPlacement(
              columnSpan: defaultColumnSpan,
              rowSpan: defaultRowSpan,
            ),
        title: defaultTitle?.call() ?? '',
        showTitle: showsTitleByDefault,
        accent: defaultAccent,
        source: defaultSource,
        settings: Map<String, Object?>.from(defaultSettings),
      );
}

/// Every widget a dashboard knows how to draw.
abstract final class DashboardWidgetRegistry {
  static final Map<String, DashboardWidgetDefinition> _definitions = {};
  static final List<String> _order = [];
  static bool _initialized = false;

  /// Called by the built-in registration, and by anything adding its own.
  static void register(DashboardWidgetDefinition definition) {
    if (!_definitions.containsKey(definition.type)) {
      _order.add(definition.type);
    }
    _definitions[definition.type] = definition;
  }

  static DashboardWidgetDefinition? definitionFor(String type) {
    _ensureInitialized();
    return _definitions[type];
  }

  static List<DashboardWidgetDefinition> all() {
    _ensureInitialized();
    return [
      for (final type in _order)
        if (_definitions[type] != null) _definitions[type]!,
    ];
  }

  static List<DashboardWidgetDefinition> inGroup(DashboardWidgetGroup group) =>
      [
        for (final definition in all())
          if (definition.group == group) definition,
      ];

  /// The definitions matching [query], best first.
  ///
  /// An exact name wins, then a name that starts with the query, then a
  /// keyword — the same ranking the workspace search uses, so the two feel
  /// like one thing.
  static List<DashboardWidgetDefinition> search(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return all();
    }
    final scored = <(int, DashboardWidgetDefinition)>[];
    for (final definition in all()) {
      final name = definition.label().toLowerCase();
      int? score;
      if (name == needle) {
        score = 0;
      } else if (name.startsWith(needle)) {
        score = 1;
      } else if (name.contains(needle)) {
        score = 2;
      } else if (definition.keywords
          .any((keyword) => keyword.toLowerCase().startsWith(needle))) {
        score = 3;
      } else if (definition.keywords
          .any((keyword) => keyword.toLowerCase().contains(needle))) {
        score = 4;
      }
      if (score != null) {
        scored.add((score, definition));
      }
    }
    scored.sort((a, b) {
      final byScore = a.$1.compareTo(b.$1);
      return byScore != 0
          ? byScore
          : a.$2.label().length.compareTo(b.$2.label().length);
    });
    return [for (final entry in scored) entry.$2];
  }

  @visibleForTesting
  static void reset() {
    _definitions.clear();
    _order.clear();
    _initialized = false;
  }

  static void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    // Set first: registration reaches back into the registry for the shared
    // helpers, and a second pass would double every definition.
    _initialized = true;
    registerBuiltInDashboardWidgets();
  }
}
