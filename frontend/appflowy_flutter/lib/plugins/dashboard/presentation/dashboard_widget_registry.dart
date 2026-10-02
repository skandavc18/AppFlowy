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
  bool get isTypable => !isPresenting && !controller.isReadOnly;

  DashboardStateValues get state => controller.state;

  DashboardDocument get document => controller.document;

  /// How this widget is painted: its surface, its colour and the inks that
  /// read on it.
  DashboardAppearance get appearance => dashboardAppearanceOf(spec, palette);

  /// The widget's colour, settled onto what it is actually painted on.
  DashboardTone get tone => appearance.tone;

  Color get strong => appearance.tone.strong;

  /// Whether the widget sits on a wash of colour, where small words should be
  /// written in that colour's own ink rather than in grey.
  bool get onColour => appearance.onColour;

  /// Bumped when something asked every widget to read its source again.
  int get refreshToken => controller.refreshToken;

  /// Change this widget. [transient] is for a change still in flight, so a
  /// drag or a slide does not fill the undo history.
  void update(
    DashboardWidgetSpec Function(DashboardWidgetSpec spec) change, {
    bool transient = false,
  }) {
    if (!isTypable) return;
    controller.edit(
      (document) {
        // A delayed field callback may predate a title/settings change or a
        // deletion. Merge into the current widget, never its captured copy.
        final current = document.widgetById(spec.id);
        if (current == null || current.type != spec.type) return document;
        return document.withWidget(change(current));
      },
      transient: transient,
    );
  }

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
    if (!isTypable) return;
    final chosen = await showInteractiveViewPicker(
      context,
      selectedViewId: spec.source.viewId.isEmpty ? null : spec.source.viewId,
      filter: filter,
    );
    if (chosen == null || !isTypable) {
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
    this.headerTrailing,
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
    this.requiresScrollActivation = false,
    this.surface = DashboardSurface.floating,
    this.identity = DashboardAccent.neutral,
    bool? reservesHeader,
    this.controlsAtStart = false,
    this.padding,
    this.configure,
    this.keywords = const [],
    this.slashName,
    this.pageBlock,
    this.offered = true,
    this.extensionId = '',
  }) : _reservesHeader = reservesHeader;

  final String type;

  /// The extension that supplied this widget, or empty for a built-in one.
  final String extensionId;

  /// Resolved lazily so a definition can be a constant while its name is
  /// translated.
  final String Function() label;
  final String Function()? description;
  final IconData icon;
  final DashboardWidgetGroup group;
  final Widget Function(DashboardWidgetContext context) builder;

  /// Optional compact controls at the right of the card's title row.
  /// Also shown when the title is hidden and in the enlarged widget view.
  /// The host bounds their width and reserves space for its own hover actions.
  final Widget Function(DashboardWidgetContext context)? headerTrailing;

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

  /// Native scrollable contents let the page scroll until the card is clicked
  /// or keyboard-focused. Enlarged views remain immediately scrollable.
  /// Custom renderers with independent gesture physics must handle this themselves.
  final bool requiresScrollActivation;

  /// How the widget meets the page when nobody has chosen otherwise.
  final DashboardSurface surface;

  /// The colour the widget is drawn in while its own colour is "automatic".
  /// A clock is lavender and a checklist's ticks are mint without anybody
  /// having to ask; a colour chosen for the widget always wins.
  final DashboardAccent identity;

  final bool? _reservesHeader;

  /// Whether the widget's management controls get a row of their own above
  /// the content, rather than floating over it on hover.
  ///
  /// Widgets with their own navigation along the top edge — a calendar, a
  /// table, an embedded page — need it; everything else keeps a clean top.
  bool get reservesHeader =>
      _reservesHeader ?? (requiresScrollActivation || headerTrailing != null);

  /// Float the hover controls over the top-left corner instead of the right,
  /// for widgets that keep their own menu in the right-hand corner.
  final bool controlsAtStart;

  /// Overrides the card's usual inset.
  final EdgeInsets? padding;

  final List<DashboardConfigField> Function(DashboardWidgetContext context)?
      configure;

  /// Extra words the "Add" search matches on.
  final List<String> keywords;

  /// The `/` command that inserts this widget, when it has one.
  final String? slashName;

  /// The page block that already is this widget, when a page has one.
  ///
  /// Pages, dashboards and canvases offer one shared set of things to place.
  /// A widget naming its page twin here is offered in `/` as that block, and
  /// the block is not offered back on a dashboard as a second copy of it.
  /// Without a twin — the default, and so for every widget added later — a
  /// page holds the widget itself: `/` inserts a block that hosts it.
  final String? pageBlock;

  /// Whether the widget is offered on its own: in a dashboard's "Add", in `/`
  /// and on a canvas. A widget that only exists to carry something else —
  /// a page block on a dashboard — is placed through what it carries.
  final bool offered;

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

  /// This widget set up in advance: [settings] laid over its defaults, and
  /// its own [label] and [title] when given.
  ///
  /// A page block offered on a dashboard is the one page-block widget,
  /// prefilled with whatever its `/` entry inserted.
  DashboardWidgetDefinition prefilled({
    Map<String, Object?> settings = const {},
    String Function()? label,
    String Function()? title,
  }) =>
      DashboardWidgetDefinition(
        type: type,
        label: label ?? this.label,
        icon: icon,
        group: group,
        builder: builder,
        headerTrailing: headerTrailing,
        description: description,
        defaultColumnSpan: defaultColumnSpan,
        defaultRowSpan: defaultRowSpan,
        minimumColumnSpan: minimumColumnSpan,
        minimumRowSpan: minimumRowSpan,
        defaultSettings: {...defaultSettings, ...settings},
        defaultSource: defaultSource,
        defaultAccent: defaultAccent,
        defaultTitle: title ?? defaultTitle,
        showsTitleByDefault: showsTitleByDefault,
        paintsOwnSurface: paintsOwnSurface,
        requiresScrollActivation: requiresScrollActivation,
        surface: surface,
        identity: identity,
        reservesHeader: _reservesHeader,
        controlsAtStart: controlsAtStart,
        padding: padding,
        configure: configure,
        keywords: keywords,
        slashName: slashName,
        pageBlock: pageBlock,
        offered: offered,
        extensionId: extensionId,
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

  /// Removes every widget an extension added.
  ///
  /// ⚠️ A widget already on a canvas is NOT deleted — its spec stays in the
  /// document and the canvas draws the "unknown widget" placeholder, so
  /// switching the extension back on restores it untouched.
  static void unregisterAll(String extensionId) {
    if (extensionId.isEmpty) {
      return;
    }
    final doomed = [
      for (final entry in _definitions.entries)
        if (entry.value.extensionId == extensionId) entry.key,
    ];
    for (final type in doomed) {
      _definitions.remove(type);
      _order.remove(type);
    }
  }

  static List<DashboardWidgetDefinition> all() {
    _ensureInitialized();
    return [
      for (final type in _order)
        if (_definitions[type] != null) _definitions[type]!,
    ];
  }

  /// The widgets somebody can place by name — everything but the carriers.
  static List<DashboardWidgetDefinition> offered() => [
        for (final definition in all())
          if (definition.offered) definition,
      ];

  static List<DashboardWidgetDefinition> inGroup(DashboardWidgetGroup group) =>
      [
        for (final definition in offered())
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
      return offered();
    }
    final scored = <(int, DashboardWidgetDefinition)>[];
    for (final definition in offered()) {
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

/// Where a widget's chosen surface is kept in its settings.
const dashboardSurfaceKey = 'card_surface';

/// The surface somebody chose for [spec], or automatic.
DashboardSurface dashboardChosenSurface(DashboardWidgetSpec spec) {
  final saved = spec.settings[dashboardSurfaceKey];
  for (final surface in DashboardSurface.values) {
    if (surface.name == saved) {
      return surface;
    }
  }
  return DashboardSurface.automatic;
}

/// How one widget is painted, settled.
@immutable
class DashboardAppearance {
  const DashboardAppearance({
    required this.surface,
    required this.accent,
    required this.tone,
    required this.media,
  });

  /// Never [DashboardSurface.automatic]: that has been decided by now.
  final DashboardSurface surface;

  /// The colour in effect: the chosen one, or the widget's own identity.
  final DashboardAccent accent;

  /// [accent] settled onto [surface]; `tone.surface` is what the content is
  /// actually painted on.
  final DashboardTone tone;

  /// The widget paints its own surface edge to edge — a picture, an embed.
  final bool media;

  bool get onColour =>
      !media &&
      (surface == DashboardSurface.tinted ||
          surface == DashboardSurface.gradient);
}

/// Decide how [spec] is painted.
///
/// A surface somebody chose always wins. Otherwise the widget's own design
/// does — except that a colour picked for a sheet or for type set on the page
/// has always meant "paint me in it", so it still tints the widget.
DashboardAppearance dashboardAppearanceOf(
  DashboardWidgetSpec spec,
  DashboardPalette palette,
) {
  final definition = DashboardWidgetRegistry.definitionFor(spec.type);
  final media = definition?.paintsOwnSurface ?? false;
  final chosenColour = spec.accent != DashboardAccent.neutral;
  if (media) {
    return DashboardAppearance(
      surface: DashboardSurface.plain,
      accent: spec.accent,
      tone: palette.toneFor(spec.accent),
      media: true,
    );
  }

  final chosen = dashboardChosenSurface(spec);
  var surface = chosen != DashboardSurface.automatic
      ? chosen
      : (definition?.surface ?? DashboardSurface.floating);
  if (surface == DashboardSurface.automatic) {
    surface = DashboardSurface.floating;
  }
  if (chosen == DashboardSurface.automatic &&
      chosenColour &&
      (surface == DashboardSurface.floating ||
          surface == DashboardSurface.plain)) {
    surface = DashboardSurface.tinted;
  }

  final accent = chosenColour
      ? spec.accent
      : (definition?.identity ?? DashboardAccent.neutral);
  final tone = palette.toneFor(accent);
  final paintedOn = switch (surface) {
    DashboardSurface.tinted => tone.tint,
    DashboardSurface.gradient =>
      tone.gradient.isEmpty ? tone.tint : tone.gradient.first,
    DashboardSurface.plain => palette.canvas,
    DashboardSurface.floating || DashboardSurface.automatic => palette.surface,
  };
  return DashboardAppearance(
    surface: surface,
    accent: accent,
    tone: tone.copyWith(surface: paintedOn),
    media: false,
  );
}
