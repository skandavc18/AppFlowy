import 'dart:async';
import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_birth_form.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_chart_panel.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_chart_selector.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vedic_chart_view.dart';
import 'package:appflowy/extensions/dart/built_in/astrology_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/templates/presentation/template_preview.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _epsilon = 0.01;
const _openKey = ValueKey('open-astrology-preview');

const _cardTypes = {
  'Birth details': astrologyInputWidgetType,
  'Saved horoscopes': astrologyLibraryWidgetType,
  'Lagna · D-1': astrologyChartWidgetType,
  'Navamsha · D-9': astrologyChartWidgetType,
  'Panchanga': astrologyPanchangaWidgetType,
  'Transit · D-1': astrologyChartWidgetType,
  'Planetary & special lagnas': astrologyPlacementsWidgetType,
  'Shadbala': astrologyShadbalaWidgetType,
  'Vimshottari dasha': astrologyDashaWidgetType,
  'Ashtakavarga': astrologyAshtakavargaWidgetType,
  'Life events': astrologyEventsWidgetType,
};

const _readingViews = {
  astrologyChartWidgetType: AstrologyView.chart,
  astrologyDashaWidgetType: AstrologyView.dasha,
  astrologyShadbalaWidgetType: AstrologyView.shadbala,
  astrologyAshtakavargaWidgetType: AstrologyView.ashtakavarga,
  astrologyPlacementsWidgetType: AstrologyView.placements,
  astrologyPanchangaWidgetType: AstrologyView.panchanga,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GeolocatorPlatform previousGeolocator;
  late _NoDeviceLocation location;
  setUp(() {
    _resetAstrology();
    previousGeolocator = GeolocatorPlatform.instance;
    location = _NoDeviceLocation();
    GeolocatorPlatform.instance = location;
  });
  tearDown(() {
    GeolocatorPlatform.instance = previousGeolocator;
    // Widgets must already be unmounted: never dispose the shared notifier.
    _resetAstrology();
  });

  group('the real, whole Astrology template preview', () {
    for (final appearance in const [
      (name: 'light', brightness: Brightness.light, paper: false),
      (name: 'dark', brightness: Brightness.dark, paper: false),
      (name: 'paper', brightness: Brightness.light, paper: true),
    ]) {
      // Window width is NOT grid width. The dialog caps at 1120, keeps
      // 48px outside each edge, and insets its dashboard by another 20px.
      for (final viewport in const [
        (width: 1600.0, bodyWidth: 1080.0, columns: 8),
        (width: 1200.0, bodyWidth: 1064.0, columns: 8),
        (width: 800.0, bodyWidth: 664.0, columns: 6),
      ]) {
        testWidgets(
          '${appearance.name} at ${viewport.width.toInt()}x900 starts at '
          'birth details and keeps the paired layout without overflow',
          (tester) async {
            _setViewport(tester, viewport.width);
            final context = await _activateAstrology();
            try {
              final result = await _openPreview(
                tester,
                theme: _theme(
                  brightness: appearance.brightness,
                  paper: appearance.paper,
                ),
              );

              // FIRST, before ensureVisible, jumpTo, focus changes or taps in
              // the dialog. Finding an off-screen form is not enough.
              _expectInitialBirthForm(tester);
              _expectTheme(
                tester,
                brightness: appearance.brightness,
                paper: appearance.paper,
              );
              final controller = _expectRealPreview(tester);
              final before = jsonEncode(controller.document.toJson());
              final canvasWidth =
                  tester.getSize(find.byType(DashboardCanvas)).width;
              expect(canvasWidth, closeTo(viewport.bodyWidth, _epsilon));
              expect(dashboardColumnsFor(canvasWidth), viewport.columns);
              expect(dashboardColumnsFor(canvasWidth).isEven, isTrue);

              final dialog = tester.widget<Dialog>(find.byType(Dialog));
              final dialogSize = tester.getSize(find.byWidget(dialog.child!));
              expect(
                dialogSize.width,
                closeTo(viewport.bodyWidth + 40, _epsilon),
              );
              expect(dialogSize.height, closeTo(760, _epsilon));

              final initialRects = _cardRects(tester);
              final gap = controller.document.settings.density.gap;
              _expectLayout(initialRects, width: canvasWidth, gap: gap);
              expect(location.calls, isEmpty);

              // A later live-transit tick must not acquire location, start
              // the native engine, or pull the preview away from the form.
              await tester.pump(const Duration(minutes: 2));
              await tester.pumpAndSettle();
              _expectInitialBirthForm(tester);
              _expectRealPreview(tester);
              expect(location.calls, isEmpty);

              final outer = _outerPosition(tester);
              final birthTop = tester.getRect(_card('Birth details')).top;
              expect(outer.maxScrollExtent, greaterThan(0));
              for (final fraction in const [0.5, 1.0]) {
                outer.jumpTo(outer.maxScrollExtent * fraction);
                await tester.pumpAndSettle();
                expect(outer.pixels, greaterThan(0));
                expect(
                  tester.getRect(_card('Birth details')).top,
                  closeTo(birthTop - outer.pixels, _epsilon),
                );
                final scrolledRects = _cardRects(tester);
                _expectLayout(scrolledRects, width: canvasWidth, gap: gap);
                for (final title in _cardTypes.keys) {
                  expect(
                    scrolledRects[title],
                    rectMoreOrLessEquals(
                      initialRects[title]!,
                      epsilon: _epsilon,
                    ),
                    reason: '$title must not reflow when the preview scrolls.',
                  );
                }
                _expectRealPreview(tester);
              }

              expect(jsonEncode(controller.document.toJson()), before);
              expect(location.calls, isEmpty);
              expect(result.isCompleted, isFalse, reason: 'Never confirm use.');
            } finally {
              // The real dialog owns/disposes its controller. Detach every
              // listener before the extension unregisters its contributions.
              await _unmount(tester);
              context.scope.close();
            }
          },
          variant: TargetPlatformVariant.only(TargetPlatform.windows),
        );
      }
    }

    testWidgets(
      'cancelling returns false without creating backend-bound content',
      (tester) async {
        _setViewport(tester, 1200);
        final context = await _activateAstrology();
        try {
          final result = await _openPreview(tester, theme: _theme());
          _expectInitialBirthForm(tester);
          final controller = _expectRealPreview(tester);
          final before = jsonEncode(controller.document.toJson());
          expect(result.isCompleted, isFalse);
          expect(find.text('Use this template'), findsOneWidget);

          final close = find.descendant(
            of: find.byType(Dialog),
            matching: find.widgetWithIcon(IconButton, Icons.close_rounded),
          );
          expect(close.hitTestable(), findsOneWidget);
          await tester.tap(close);
          await tester.pumpAndSettle();

          expect(result.isCompleted, isTrue);
          expect(await result.future, isFalse);
          expect(find.byType(Dialog), findsNothing);
          expect(find.byType(DashboardCard), findsNothing);
          expect(find.byKey(_openKey).hitTestable(), findsOneWidget);
          expect(controller.viewId, isEmpty);
          expect(controller.canUndo, isFalse);
          expect(jsonEncode(controller.document.toJson()), before);

          // There is no backend bootstrap, repository, real position or
          // ephemeris fixture in this harness, including after dismissal.
          await tester.pump(const Duration(minutes: 2));
          await tester.pumpAndSettle();
          expect(location.calls, isEmpty);
          expect(find.byType(DatabaseTabBarView), findsNothing);
          expect(find.byType(VedicChartView), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
          context.scope.close();
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  });
}

// Keep these lifecycle/theme helpers aligned with astrology_integration_test.
void _resetAstrology() {
  AstrologyRuntime.active.value = false;
  ExtensionBlockRegistry.unregisterAll('astrology');
  DashboardWidgetRegistry.unregisterAll('astrology');
}

Future<DartExtensionContext> _activateAstrology() async {
  final extension = AstrologyExtension();
  final context = DartExtensionContext(info: extension.info);
  await extension.activate(context);
  return context;
}

ThemeData _theme({
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
    DesktopAppearance().getThemeData(
      paper
          ? AppTheme.builtins.firstWhere(
              (theme) => theme.themeName == BuiltInTheme.paper,
            )
          : AppTheme.fallback,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

/// Only the launching page is a harness; the dialog, controller, canvas and
/// all eleven cards are production widgets. Do not call a blueprint builder
/// here or replace the registered builders with individually sized previews.
Widget barePageWidget({
  required ThemeData theme,
  required WorkspaceTemplate template,
  required ValueChanged<bool> onClosed,
}) =>
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              key: _openKey,
              onPressed: () => unawaited(
                showTemplatePreview(
                  context,
                  template,
                  confirmLabel: 'Use this template',
                ).then<void>(onClosed),
              ),
              child: const Text('Open Astrology preview'),
            ),
          ),
        ),
      ),
    );

void _setViewport(WidgetTester tester, double width) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = Size(width, 900);
  addTearDown(tester.view.reset);
}

Future<Completer<bool>> _openPreview(
  WidgetTester tester, {
  required ThemeData theme,
}) async {
  final result = Completer<bool>();
  await tester.pumpWidget(
    barePageWidget(
      theme: theme,
      template: astrologyDashboardTemplate(),
      onClosed: result.complete,
    ),
  );
  await tester.tap(find.byKey(_openKey));
  await tester.pumpAndSettle();
  return result;
}

ScrollPosition _outerPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(DashboardBoard),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void _expectInitialBirthForm(WidgetTester tester) {
  expect(
    find.byKey(const ValueKey('astrology-name')).hitTestable(),
    findsOneWidget,
    reason: 'Opening the whole preview must show the top birth form, '
        'not automatically scroll down to Saved horoscopes.',
  );
  expect(
    _outerPosition(tester).pixels,
    0.0,
    reason: 'Check the OUTER first scroll position, not a card-local scroller.',
  );
}

void _expectTheme(
  WidgetTester tester, {
  required Brightness brightness,
  required bool paper,
}) {
  final context = tester.element(find.byType(Dialog));
  expect(Theme.of(context).brightness, brightness);
  expect(PaperTheme.isEnabled(context), paper);
  expect(
    tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
    DashboardPalette.of(context).surface,
  );
  if (paper) {
    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey('astrology-birth-surface')),
          )
          .color,
      PaperTheme.editorPreviewBackground,
    );
  }
}

Finder _card(String title) => find.byWidgetPredicate(
      (widget) => widget is DashboardCard && widget.spec.title == title,
      description: 'DashboardCard titled "$title"',
    );

DashboardController _expectRealPreview(WidgetTester tester) {
  expect(AstrologyRuntime.active.value, isTrue);
  expect(find.byType(DashboardBoard), findsOneWidget);
  expect(find.byType(DashboardSectionView), findsOneWidget);
  expect(find.byType(DashboardCanvas), findsOneWidget);
  expect(find.byType(DashboardCard), findsNWidgets(11));
  expect(
    DashboardWidgetRegistry.all()
        .where((definition) => definition.extensionId == 'astrology')
        .map((definition) => definition.type),
    unorderedEquals(_cardTypes.values.toSet()),
  );
  expect(_cardTypes.values.toSet(), hasLength(9));

  final controller =
      tester.widget<DashboardCanvas>(find.byType(DashboardCanvas)).controller;
  expect(controller.viewId, isEmpty);
  expect(controller.mode, DashboardMode.presentation);
  expect(controller.isEditable, isFalse);
  expect(controller.document.widgetCount, 11);
  expect(controller.document.settings.columns, 0);
  expect(controller.state[astrologyDraftKey], isNull);
  expect(controller.canUndo, isFalse);
  expect(controller.canRedo, isFalse);
  expect(astrologyEventsViewId(controller.document), isEmpty);

  for (final entry in _cardTypes.entries) {
    final finder = _card(entry.key);
    expect(finder, findsOneWidget);
    final card = tester.widget<DashboardCard>(finder);
    expect(card.controller, same(controller));
    expect(card.spec.type, entry.value, reason: entry.key);
    expect(card.spec.source.isBound, isFalse, reason: entry.key);
    final panels = find.descendant(
      of: finder,
      matching: find.byType(AstrologyChartPanel),
    );
    final view = _readingViews[entry.value];
    if (view == null) {
      expect(panels, findsNothing);
      continue;
    }
    expect(panels, findsOneWidget);
    final panel = tester.widget<AstrologyChartPanel>(panels);
    expect(panel.preview, isTrue, reason: entry.key);
    expect(panel.view, view);
    expect(panel.division, card.spec.integer('division', fallback: 1));
    expect(panel.onConfigure, isNull);
    expect(panel.calculator, isNull, reason: 'No fake chart calculation.');
    expect(panel.locationService, isNull);
    expect(panel.input.utc, isNull);
    expect(panel.input.place, isNull);
    expect(
      find.descendant(
        of: finder,
        matching: find.text(
          'Live ${view.label.toLowerCase()} appear after you use this template. '
          'No location is requested in a preview.',
        ),
      ),
      findsOneWidget,
    );
  }
  expect(find.byType(AstrologyChartPanel), findsNWidgets(8));

  final form =
      tester.widget<AstrologyBirthForm>(find.byType(AstrologyBirthForm));
  expect(form.enabled, isFalse);
  expect(form.locationService, isNull);
  expect(form.input.toJson(), const AstrologyInput().toJson());
  for (final id in const [
    'astrology-name',
    'astrology-date',
    'astrology-time',
    'astrology-place',
  ]) {
    final field = tester.widget<TextField>(find.byKey(ValueKey(id)));
    expect(field.enabled, isFalse, reason: id);
    expect(field.autofocus, isFalse, reason: id);
    expect(field.controller!.text, isEmpty, reason: id);
  }
  expect(
    tester
        .widget<Switch>(find.byKey(const ValueKey('astrology-now')))
        .onChanged,
    isNull,
  );
  for (final id in const [
    'astrology-current-location',
    'astrology-search',
    'astrology-advanced',
    'astrology-generate',
    'astrology-save',
  ]) {
    expect(
      tester.widget<TextButton>(find.byKey(ValueKey(id))).onPressed,
      isNull,
      reason: id,
    );
  }
  expect(find.byType(DropdownButton<int>), findsNothing);
  expect(find.byType(AstrologyChartSelector), findsNWidgets(3));
  for (final selector in tester.widgetList<AstrologyChartSelector>(
    find.byType(AstrologyChartSelector),
  )) {
    expect(selector.onChanged, isNull);
    final card = tester.getRect(
      find.ancestor(
          of: find.byWidget(selector), matching: find.byType(DashboardCard)),
    );
    final control = tester.getRect(find.byWidget(selector));
    expect(control.center.dx, greaterThan(card.center.dx));
    expect(control.top, greaterThanOrEqualTo(card.top));
    expect(control.bottom, lessThanOrEqualTo(card.top + 40));
  }
  expect(
    find.text('Preview only · location lookup is disabled.'),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: _card('Saved horoscopes'),
      matching: find.textContaining(
        'Each person appears here and as a subpage.',
      ),
    ),
    findsOneWidget,
  );
  expect(
    find.descendant(
      of: _card('Life events'),
      matching: find.textContaining('Save a named horoscope above'),
    ),
    findsOneWidget,
  );
  expect(find.byType(ActionChip), findsNothing);
  expect(
    tester
        .widget<TextButton>(
          find.descendant(
            of: _card('Saved horoscopes'),
            matching: find.byWidgetPredicate((widget) => widget is TextButton),
          ),
        )
        .onPressed,
    isNull,
  );
  expect(find.byType(DatabaseTabBarView), findsNothing);
  expect(find.byType(VedicChartView), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.byType(ErrorWidget), findsNothing);
  expect(
    tester.takeException(),
    isNull,
    reason: 'No layout/overflow or IO error.',
  );
  return controller;
}

/// Measure real DashboardCards, including those below the viewport. Subtract
/// the canvas origin so a scroll moves the screen, not the expected layout.
Map<String, Rect> _cardRects(WidgetTester tester) {
  final origin = tester.getTopLeft(find.byType(DashboardCanvas));
  return {
    for (final title in _cardTypes.keys)
      title: tester.getRect(_card(title)).shift(-origin),
  };
}

void _expectLayout(
  Map<String, Rect> rects, {
  required double width,
  required double gap,
}) {
  // These are visual requirements, not expected values obtained from the
  // production layout resolver. Six-plus-six scales exactly to 4+4 and 3+3;
  // the former three four-column cards collide on an eight-column preview.
  const rows = [
    ['Birth details'],
    ['Saved horoscopes'],
    ['Lagna · D-1', 'Navamsha · D-9'],
    ['Panchanga', 'Transit · D-1'],
    ['Planetary & special lagnas'],
    ['Shadbala', 'Vimshottari dasha'],
    ['Ashtakavarga'],
    ['Life events'],
  ];
  var nextTop = 0.0;
  for (final row in rows) {
    final left = rects[row.first]!;
    expect(left.top, closeTo(nextTop, _epsilon), reason: row.first);
    expect(left.left, closeTo(0, _epsilon), reason: row.first);
    if (row.length == 1) {
      expect(left.width, closeTo(width, _epsilon), reason: row.first);
    } else {
      final right = rects[row.last]!;
      final reason = '${row.first} and ${row.last} must remain equal peers.';
      expect(right.top, closeTo(left.top, _epsilon), reason: reason);
      expect(right.height, closeTo(left.height, _epsilon), reason: reason);
      expect(right.width, closeTo(left.width, _epsilon), reason: reason);
      expect(left.width, closeTo((width - gap) / 2, _epsilon), reason: reason);
      expect(right.left - left.right, closeTo(gap, _epsilon), reason: reason);
      expect(right.right, closeTo(width, _epsilon), reason: reason);
      expect(left.overlaps(right), isFalse, reason: reason);
    }
    nextTop = left.bottom + gap;
  }

  final entries = rects.entries.toList();
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    expect(entry.value.width, greaterThan(0), reason: entry.key);
    expect(entry.value.height, greaterThan(0), reason: entry.key);
    expect(
      entry.value.left,
      greaterThanOrEqualTo(-_epsilon),
      reason: entry.key,
    );
    expect(
      entry.value.right,
      lessThanOrEqualTo(width + _epsilon),
      reason: entry.key,
    );
    for (var j = i + 1; j < entries.length; j++) {
      expect(
        entry.value.overlaps(entries[j].value),
        isFalse,
        reason: '${entry.key} overlaps ${entries[j].key}.',
      );
    }
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Intercept only the platform boundary, never the real card builders or
/// panels. Record even a caught plugin error; supply no position that could
/// let an accidental request proceed into the native ephemeris engine.
class _NoDeviceLocation extends Fake
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError(
      'Unexpected preview geolocator call: ${invocation.memberName}',
    );
  }
}
