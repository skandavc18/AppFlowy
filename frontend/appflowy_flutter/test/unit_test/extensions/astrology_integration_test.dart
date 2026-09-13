import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_birth_form.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_block.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_chart_panel.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_location.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vedic_chart_view.dart';
import 'package:appflowy/extensions/dart/built_in/astrology_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/extensions/presentation/island_slash_items.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _blockCases = {
  astrologyBlockType: ('Astrology', AstrologyView.chart, 1),
  'extension_astrology_navamsha': (
    'Astrology · Navamsha D-9',
    AstrologyView.chart,
    9,
  ),
  'extension_astrology_dasha': (
    'Astrology · Dasha table',
    AstrologyView.dasha,
    1,
  ),
  'extension_astrology_shadbala': (
    'Astrology · Shadbala',
    AstrologyView.shadbala,
    1,
  ),
  'extension_astrology_ashtakavarga': (
    'Astrology · Ashtakavarga',
    AstrologyView.ashtakavarga,
    1,
  ),
  'extension_astrology_placements': (
    'Astrology · Planetary & special lagnas',
    AstrologyView.placements,
    1,
  ),
  'extension_astrology_panchanga': (
    'Astrology · Panchanga & key info',
    AstrologyView.panchanga,
    1,
  ),
};

const _readingViews = {
  astrologyChartWidgetType: AstrologyView.chart,
  astrologyDashaWidgetType: AstrologyView.dasha,
  astrologyShadbalaWidgetType: AstrologyView.shadbala,
  astrologyAshtakavargaWidgetType: AstrologyView.ashtakavarga,
  astrologyPlacementsWidgetType: AstrologyView.placements,
  astrologyPanchangaWidgetType: AstrologyView.panchanga,
};

const _widgetTypes = {
  astrologyInputWidgetType,
  astrologyChartWidgetType,
  astrologyDashaWidgetType,
  astrologyShadbalaWidgetType,
  astrologyAshtakavargaWidgetType,
  astrologyPlacementsWidgetType,
  astrologyPanchangaWidgetType,
  astrologyLibraryWidgetType,
  astrologyEventsWidgetType,
};

const _place = AstrologyPlace(
  name: 'Test device place',
  latitude: 12.9715987123,
  longitude: 77.594566789,
  timeZone: 'Asia/Kolkata',
  isDeviceLocation: true,
);

AstrologyInput _input({
  String name = 'Test "profile"\nजन्म',
  IndianChartStyle style = IndianChartStyle.south,
  AstrologyAyanamsa ayanamsa = AstrologyAyanamsa.trueChitra,
}) =>
    AstrologyInput(
      name: name,
      utc: DateTime.utc(1990, 5, 15, 9, 20, 31, 123, 456),
      place: _place,
      utcOffsetMinutes: 345,
      style: style,
      ayanamsa: ayanamsa,
      ayanamsaOffsetArcseconds: -3723.125,
      trueNode: true,
      dashaYearDays: 360,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_resetAstrology);
  // Never dispose the shared ValueNotifier. Every widget test unmounts its
  // listeners in its body BEFORE this reset (and before controller disposal).
  tearDown(_resetAstrology);

  group('real Astrology extension registration', () {
    test('activation supplies seven slash items, builders, parsers and nodes',
        () async {
      final context = await _activateAstrology();
      try {
        expect(context.info.id, 'astrology');
        expect(AstrologyRuntime.active.value, isTrue);
        final blocks = ExtensionBlockRegistry.all()
            .where((block) => block.extensionId == context.info.id)
            .toList();
        expect(blocks, hasLength(7));
        expect(blocks.map((block) => block.type), _blockCases.keys);

        const configuration = BlockComponentConfiguration();
        final builders = ExtensionBlockRegistry.builders(configuration);
        final parsers = ExtensionBlockRegistry.parsers();
        final allItems = islandSlashMenuItems();
        final descriptions = islandSlashMenuDescriptions(allItems);
        final names = _blockCases.values.map((value) => value.$1).toSet();
        final items =
            allItems.where((item) => names.contains(item.name)).toList();
        expect(items, hasLength(7));
        expect(items.map((item) => item.name), unorderedEquals(names));
        expect(builders.keys, containsAll(_blockCases.keys));
        expect(parsers.keys, containsAll(_blockCases.keys));
        expect(
          ExtensionBlockRegistry.alignableTypes(),
          containsAll(_blockCases.keys),
        );

        for (final entry in _blockCases.entries) {
          final block = ExtensionBlockRegistry.definitionFor(entry.key)!;
          final item = items.singleWhere((item) => item.name == entry.value.$1);
          expect(block.hasSlashEntry, isTrue);
          expect(block.alignable, isTrue);
          expect(block.slashName, entry.value.$1);
          expect(item.keywords, containsAll(['astrology', 'vedic', 'kundali']));
          expect(item.keywords, contains(entry.value.$2.name));
          expect(descriptions[item], block.slashDescription);
          expect(descriptions[item], contains(entry.value.$2.label));
          expect(builders[entry.key], isA<AstrologyBlockBuilder>());
          expect(builders[entry.key]!.configuration, same(configuration));
          expect(parsers[entry.key], isA<AstrologyNodeParser>());
          expect(parsers[entry.key], same(block.parser));
          expect(parsers[entry.key]!.id, entry.key);

          final node = block.newNode!();
          expect(node.type, entry.key);
          expect(node.children, isEmpty);
          expect(node.attributes['view'], entry.value.$2.name);
          expect(node.attributes['division'], entry.value.$3);
          expect(node.attributes['profile'], const AstrologyInput().toJson());
          expect(block.newNode!(), isNot(same(node)));
          expect(builders[entry.key]!.validate(node), isTrue);
          expect(
            builders[entry.key]!.validate(
              Node(type: entry.key, children: [paragraphNode()]),
            ),
            isFalse,
          );
        }
      } finally {
        context.scope.close();
      }
    });

    test(
        'the catalogue template requires Astrology and every card is registered',
        () async {
      final template = TemplateRegistry.forId('vedic_astrology')!;
      expect(AstrologyRuntime.active.value, isFalse);
      expect(template.requires, {'astrology'});
      expect(template.extensionId, isEmpty);
      expect(template.kind, TemplateKind.dashboard);
      expect(template.parts, hasLength(1));
      final blueprint = template.parts.single.blueprint as TemplateDashboard;
      final document = blueprint.build(const {});
      final context = await _activateAstrology();
      try {
        final definitions = DashboardWidgetRegistry.all()
            .where((definition) => definition.extensionId == 'astrology');
        expect(
          definitions.map((definition) => definition.type).toSet(),
          _widgetTypes,
        );

        // The actual template has ELEVEN cards on a twelve-column grid,
        // including three instances of the same chart widget definition.
        expect(document.widgetCount, 11);
        expect(document.allWidgets.map((spec) => spec.type), [
          astrologyInputWidgetType,
          astrologyLibraryWidgetType,
          astrologyChartWidgetType,
          astrologyChartWidgetType,
          astrologyPanchangaWidgetType,
          astrologyChartWidgetType,
          astrologyPlacementsWidgetType,
          astrologyShadbalaWidgetType,
          astrologyDashaWidgetType,
          astrologyAshtakavargaWidgetType,
          astrologyEventsWidgetType,
        ]);
        expect(
            document.allWidgets.map((spec) => spec.type).toSet(), _widgetTypes);
        expect(
            document.allWidgets.map((spec) => spec.id).toSet(), hasLength(11));
        expect(document.allWidgets.first.placement.columnSpan, 12);
        expect(document.variableFor(astrologyDraftKey), isNotNull);
        expect(document.variableFor(astrologyDraftKey)!.initialValue, isNull);
        expect(isAstrologyLibrary(document), isTrue);
        expect(astrologyEventsViewId(document), isEmpty);
        for (final spec in document.allWidgets) {
          final definition = DashboardWidgetRegistry.definitionFor(spec.type);
          expect(definition, isNotNull, reason: spec.type);
          expect(template.requires, contains(definition!.extensionId));
          expect(spec.source.isBound, isFalse);
          expect(spec.placement.endColumn, lessThanOrEqualTo(12));
        }
      } finally {
        context.scope.close();
      }
      expect(TemplateRegistry.forId(template.id), same(template));
      expect(template.requires, {'astrology'});
    });

    test('closing the real scope unregisters contributions, not saved specs',
        () async {
      final previousBlocks = ExtensionBlockRegistry.all();
      final previousWidgets = DashboardWidgetRegistry.all();
      final document = buildAstrologyDashboard(input: _input());
      final before = jsonEncode(document.toJson());
      final context = await _activateAstrology();
      try {
        expect(AstrologyRuntime.active.value, isTrue);
        context.scope.close();
        expect(context.scope.isClosed, isTrue);
        expect(AstrologyRuntime.active.value, isFalse);
        expect(ExtensionBlockRegistry.all(), previousBlocks);
        expect(DashboardWidgetRegistry.all(), previousWidgets);
        for (final type in _blockCases.keys) {
          expect(ExtensionBlockRegistry.definitionFor(type), isNull);
          expect(ExtensionBlockRegistry.parsers(), isNot(contains(type)));
          expect(
            ExtensionBlockRegistry.builders(
                const BlockComponentConfiguration()),
            isNot(contains(type)),
          );
          expect(
              ExtensionBlockRegistry.alignableTypes(), isNot(contains(type)));
        }
        for (final type in _widgetTypes) {
          expect(DashboardWidgetRegistry.definitionFor(type), isNull);
        }
        final names = _blockCases.values.map((value) => value.$1).toSet();
        expect(
          islandSlashMenuItems().where((item) => names.contains(item.name)),
          isEmpty,
        );
        expect(jsonEncode(document.toJson()), before);
        expect(TemplateRegistry.forId('vedic_astrology'), isNotNull);
        final revision = ExtensionBlockRegistry.revision.value;
        context.scope.close();
        expect(ExtensionBlockRegistry.revision.value, revision);

        final reopened = await _activateAstrology();
        try {
          for (final spec in document.allWidgets) {
            expect(DashboardWidgetRegistry.definitionFor(spec.type), isNotNull);
          }
          expect(jsonEncode(document.toJson()), before);
        } finally {
          reopened.scope.close();
        }
      } finally {
        context.scope.close();
      }
    });
  });

  group('block persistence and Markdown export', () {
    test('real Node JSON and registered JSON fences preserve all input options',
        () async {
      final context = await _activateAstrology();
      try {
        final inputs = [
          const AstrologyInput(),
          for (final style in IndianChartStyle.values)
            for (final ayanamsa in AstrologyAyanamsa.values)
              _input(style: style, ayanamsa: ayanamsa),
        ];
        for (final entry in _blockCases.entries) {
          for (final input in inputs) {
            final node = astrologyNode(
              type: entry.key,
              input: input,
              view: entry.value.$2,
              division: entry.value.$3,
            )..updateAttributes({
                'width': 678.25,
                'height': 432.5,
                'align': 'right',
                'future_option': {
                  'text': 'Keep "quotes", \\slashes and\nnewlines',
                  'values': [1, true, null],
                },
              });
            final before = jsonEncode(node.toJson());
            final restored = Node.fromJson(
              Map<String, Object>.from(jsonDecode(before) as Map),
            );
            expect(restored.type, node.type);
            expect(restored.toJson(), node.toJson());
            expect(restored.children, isEmpty);
            final restoredInput = AstrologyInput.fromJson(
              astrologyMap(restored.attributes['profile']),
            );
            expect(restoredInput.toJson(), input.toJson());
            expect(restoredInput.fingerprint, input.fingerprint);
            expect(restoredInput.utc, input.utc);
            expect(restoredInput.isTransit, input.isTransit);
            expect(
              restoredInput.place?.isDeviceLocation,
              input.place?.isDeviceLocation,
            );

            final parser = ExtensionBlockRegistry.parsers()[entry.key]!;
            final markdown = parser.transform(restored, null);
            final fence = RegExp(r'^\n```astrology\n([^\n]+)\n```\n$')
                .firstMatch(markdown);
            expect(fence, isNotNull, reason: '${entry.key}: $markdown');
            final exported = astrologyMap(jsonDecode(fence!.group(1)!));
            expect(exported, node.attributes);
            expect(
              AstrologyInput.fromJson(astrologyMap(exported['profile']))
                  .toJson(),
              input.toJson(),
            );
            expect(exported['view'], entry.value.$2.name);
            expect(exported['division'], entry.value.$3);
            expect(exported['width'], 678.25);
            expect(exported['height'], 432.5);
            expect(exported['align'], 'right');
            expect(jsonEncode(node.toJson()), before,
                reason: 'Export is read-only.');
          }
        }
      } finally {
        context.scope.close();
      }
    });
  });

  group('registered dashboard card previews', () {
    for (final appearance in const [
      (name: 'light', brightness: Brightness.light, paper: false),
      (name: 'dark', brightness: Brightness.dark, paper: false),
      (name: 'paper', brightness: Brightness.light, paper: true),
    ]) {
      testWidgets(
          'every ${appearance.name} builder is safe at 280px and 1360px',
          (tester) async {
        await tester.binding.setSurfaceSize(const Size(1440, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final context = await _activateAstrology();
        final theme = _theme(
          brightness: appearance.brightness,
          paper: appearance.paper,
        );
        try {
          for (final library in [true, false]) {
            final input = library ? const AstrologyInput() : _input();
            final document = buildAstrologyDashboard(
              input: input,
              library: library,
              libraryId: 'preview-library-must-not-be-read',
              eventsViewId: library ? '' : 'preview-grid-must-not-be-opened',
            );
            final controller =
                DashboardController(viewId: '', document: document);
            final before = jsonEncode(document.toJson());
            try {
              expect(document.widgetCount, library ? 11 : 10);
              for (final spec in document.allWidgets) {
                for (final size in const [Size(280, 300), Size(1360, 300)]) {
                  await tester.pumpWidget(
                    _app(
                      _dashboardCard(controller, spec),
                      size: size,
                      theme: theme,
                    ),
                  );
                  await tester.pump();
                  _expectPreviewCard(tester, spec, input);
                  expect(
                    tester.getSize(find.byKey(ValueKey('preview-${spec.id}'))),
                    size,
                  );
                  expect(
                    tester.takeException(),
                    isNull,
                    reason: '${appearance.name}, ${spec.type}, $size',
                  );
                  if (appearance.paper &&
                      spec.type == astrologyInputWidgetType) {
                    expect(
                      tester
                          .widget<Material>(
                            find.byKey(
                                const ValueKey('astrology-birth-surface')),
                          )
                          .color,
                      PaperTheme.editorPreviewBackground,
                    );
                  }
                  // A preview must not acquire a minute clock on a later tick.
                  await tester.pump(const Duration(minutes: 2));
                  _expectPreviewCard(tester, spec, input);
                  expect(tester.takeException(), isNull);
                  await _unmount(tester);
                }
              }
              expect(jsonEncode(controller.document.toJson()), before);
              expect(controller.state[astrologyDraftKey], isNull);
            } finally {
              await _unmount(tester);
              // In the test body, not addTearDown: pending timers are checked
              // before ordinary teardown callbacks run.
              controller.dispose();
            }
          }
        } finally {
          await _unmount(tester);
          context.scope.close();
        }
      });
    }

    testWidgets('sibling cards observe the same unsaved controller draft',
        (tester) async {
      final context = await _activateAstrology();
      final document = buildAstrologyDashboard(input: _input());
      final controller = DashboardController(viewId: '', document: document);
      final inputSpec = document.allWidgets.first;
      final chartSpec = document.allWidgets.firstWhere(
        (spec) => spec.type == astrologyChartWidgetType,
      );
      try {
        await tester.pumpWidget(
          _app(
            Row(
              children: [
                Expanded(child: _dashboardCard(controller, inputSpec)),
                Expanded(child: _dashboardCard(controller, chartSpec)),
              ],
            ),
          ),
        );
        await tester.pump();
        final draft = _input(name: 'Unsaved sibling draft')
            .copyWith(style: IndianChartStyle.north, useCurrentTime: true);
        controller.setValue(astrologyDraftKey, draft);
        await tester.pump();
        expect(
          tester
              .widget<AstrologyBirthForm>(find.byType(AstrologyBirthForm))
              .input,
          same(draft),
        );
        final panel = tester
            .widget<AstrologyChartPanel>(find.byType(AstrologyChartPanel));
        expect(panel.input, same(draft));
        expect(panel.preview, isTrue);
        expect(astrologyInputFromDashboard(controller.document).name,
            _input().name);
        expect(controller.document, same(document));
        expect(find.byType(VedicChartView), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        controller.dispose();
        context.scope.close();
      }
    });
  });

  group('chart panel IO and asynchronous lifecycle', () {
    testWidgets('nonfinite ayanamsha input reports an error and recovers',
        (tester) async {
      final received = <AstrologyInput>[];
      final input = _input();
      Widget panel(AstrologyInput value) => _app(
            AstrologyChartPanel(
              key: const ValueKey('recoverable-ayanamsa-panel'),
              input: value,
              calculator: (resolved) async {
                received.add(resolved);
                return _chart(resolved);
              },
            ),
          );
      try {
        await tester.pumpWidget(panel(input));
        await tester.pump();
        final state = tester.state(find.byType(AstrologyChartPanel));
        for (final invalid in [double.nan, double.infinity, -double.infinity]) {
          final before = received.length;
          await tester.pumpWidget(
            panel(input.copyWith(ayanamsaOffsetArcseconds: invalid)),
          );
          await tester.pump();
          expect(received, hasLength(before));
          expect(find.textContaining('ayanamsha adjustment'), findsOneWidget);
          expect(find.byType(VedicChartView), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(panel(input));
          await tester.pump();
          expect(tester.state(find.byType(AstrologyChartPanel)), same(state));
          expect(received, hasLength(before + 1));
          expect(find.byType(VedicChartView), findsOneWidget);
          expect(find.textContaining(input.ayanamsaLabel), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await _unmount(tester);
      }
    });

    testWidgets(
        'preview overrides an active runtime and both injected IO seams',
        (tester) async {
      final location = _FakeLocationService();
      final calculated = <AstrologyInput>[];
      var configured = 0;
      try {
        for (final active in [false, true]) {
          AstrologyRuntime.active.value = active;
          for (final view in AstrologyView.values) {
            await tester.pumpWidget(
              _app(
                AstrologyChartPanel(
                  input: const AstrologyInput(),
                  view: view,
                  preview: true,
                  calculator: (input) async {
                    calculated.add(input);
                    return _chart(input);
                  },
                  locationService: location,
                  onConfigure: () => configured++,
                ),
                size: const Size(280, 300),
              ),
            );
            await tester.pump(const Duration(minutes: 2));
            expect(find.text(_previewMessage(view)), findsOneWidget);
            expect(find.text('Birth details / location'), findsNothing);
            expect(find.byType(VedicChartView), findsNothing);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(location.currentForces, isEmpty);
            expect(location.queries, isEmpty);
            expect(calculated, isEmpty);
            expect(configured, 0);
            expect(tester.takeException(), isNull);
          }
        }
      } finally {
        await _unmount(tester);
      }
    });

    for (final staleFails in [false, true]) {
      testWidgets(
          'a late ${staleFails ? 'failure' : 'chart'} cannot replace newer input',
          (tester) async {
        final first = Completer<AstrologyChart>();
        final second = Completer<AstrologyChart>();
        final oldInput = _input(name: 'Old input');
        final newInput = _input(name: 'New input')
            .copyWith(utc: DateTime.utc(2001, 8, 9, 10, 11));
        final oldChart = _chart(oldInput, ascendant: 15);
        final newChart = _chart(newInput, ascendant: 75);
        final location = _FakeLocationService();
        final received = <AstrologyInput>[];
        Future<AstrologyChart> calculate(AstrologyInput input) {
          received.add(input);
          return received.length == 1 ? first.future : second.future;
        }

        Widget panel(AstrologyInput input) => _app(
              AstrologyChartPanel(
                key: const ValueKey('same-panel-state'),
                input: input,
                calculator: calculate,
                locationService: location,
              ),
            );
        try {
          await tester.pumpWidget(panel(oldInput));
          final state = tester.state(find.byType(AstrologyChartPanel));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          await tester.pumpWidget(panel(newInput));
          expect(tester.state(find.byType(AstrologyChartPanel)), same(state));
          expect(
            received.map((input) => input.fingerprint),
            [oldInput.fingerprint, newInput.fingerprint],
          );
          second.complete(newChart);
          await tester.pump();
          _expectChart(tester, newChart);
          if (staleFails) {
            first.completeError(
                const FormatException('Stale calculation failed'));
          } else {
            first.complete(oldChart);
          }
          await tester.pump();
          _expectChart(tester, newChart);
          expect(find.textContaining('Stale calculation failed'), findsNothing);
          expect(find.text('Retry'), findsNothing);
          expect(location.currentForces, isEmpty);
          expect(location.queries, isEmpty);
          // Fixed horoscopes never acquire the live minute timer.
          await tester.pump(const Duration(minutes: 3));
          expect(received, hasLength(2));
          expect(tester.takeException(), isNull);
        } finally {
          await _unmount(tester);
          if (!first.isCompleted) first.complete(oldChart);
          if (!second.isCompleted) second.complete(newChart);
          await tester.pump();
        }
      });
    }

    testWidgets(
        'failed location exposes Retry and retries current with force true',
        (tester) async {
      final location = _FakeLocationService(
        onCurrent: (force) async {
          if (!force)
            throw const FormatException('Test location permission denied');
          return _place;
        },
      );
      final received = <AstrologyInput>[];
      final input = _input().copyWith(useCurrentLocation: true);
      try {
        await tester.pumpWidget(
          _app(
            AstrologyChartPanel(
              input: input,
              locationService: location,
              calculator: (resolved) async {
                received.add(resolved);
                return _chart(resolved);
              },
            ),
          ),
        );
        await tester.pump();
        expect(location.currentForces, [false]);
        expect(received, isEmpty);
        expect(find.text('Test location permission denied'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Retry'));
        await tester.pump();
        await tester.pump();
        expect(location.currentForces, [false, true]);
        expect(location.queries, isEmpty);
        expect(
            received.single.toJson(), input.copyWith(place: _place).toJson());
        expect(input.place, isNull,
            reason: 'Resolved location is not persisted.');
        expect(find.text('Retry'), findsNothing);
        expect(find.byType(VedicChartView), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
      }
    });

    testWidgets(
        'live calculation ticks by minute, pauses, resumes and stops on unmount',
        (tester) async {
      AstrologyRuntime.active.value = true;
      final received = <AstrologyInput>[];
      final location = _FakeLocationService();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      try {
        await tester.pumpWidget(
          _app(
            AstrologyChartPanel(
              input: const AstrologyInput(place: _place),
              locationService: location,
              calculator: (input) async {
                received.add(input);
                return _chart(input);
              },
            ),
          ),
        );
        await tester.pump();
        expect(received, hasLength(1));
        expect(received.single.utc!.isUtc, isTrue);
        expect(received.single.utc!.second, 0);
        expect(received.single.utc!.millisecond, 0);
        expect(received.single.utc!.microsecond, 0);
        expect(find.textContaining('Live transit · '), findsOneWidget);
        await tester.pump(const Duration(seconds: 59));
        expect(received, hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        expect(received, hasLength(2));

        // A supplied calculator bypasses Runtime.active. This test covers the
        // app lifecycle; the next test checks actual extension disablement.
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump(const Duration(minutes: 2));
        expect(received, hasLength(2));
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(received, hasLength(3));
        await tester.pump(const Duration(minutes: 1));
        expect(received, hasLength(4));
        expect(location.currentForces, isEmpty);
        expect(location.queries, isEmpty);
        await _unmount(tester);
        await tester.pump(const Duration(minutes: 3));
        expect(received, hasLength(4));
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    });

    testWidgets(
        'real runtime disablement cancels the minute timer without a calculator',
        (tester) async {
      // Always fail BEFORE the native engine is reachable. Supplying a fake
      // calculator here would make the runtime-disabled assertion meaningless.
      final location = _FakeLocationService(
        onCurrent: (_) async =>
            throw const FormatException('Test device unavailable'),
      );
      DartExtensionContext? context;
      try {
        await tester.pumpWidget(
          _app(
            AstrologyChartPanel(
              input: const AstrologyInput(),
              locationService: location,
            ),
          ),
        );
        expect(
            find.text('Enable Vedic astrology in Extensions.'), findsOneWidget);
        await tester.pump(const Duration(minutes: 2));
        expect(location.currentForces, isEmpty);

        context = await _activateAstrology();
        await tester.pump();
        expect(location.currentForces, [false]);
        expect(find.text('Test device unavailable'), findsOneWidget);
        await tester.pump(const Duration(seconds: 59));
        expect(location.currentForces, hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        expect(location.currentForces, [false, false]);

        context.scope.close();
        await tester.pump();
        expect(AstrologyRuntime.active.value, isFalse);
        expect(
            find.text('Enable Vedic astrology in Extensions.'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        await tester.pump(const Duration(minutes: 3));
        expect(location.currentForces, hasLength(2));

        context = await _activateAstrology();
        await tester.pump();
        expect(location.currentForces, hasLength(3));
        await _unmount(tester);
        context.scope.close();
        await tester.pump(const Duration(minutes: 3));
        expect(location.currentForces, hasLength(3));
        expect(location.queries, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        context?.scope.close();
      }
    });

    testWidgets(
        'a pending live calculation is not duplicated and may finish after disposal',
        (tester) async {
      final first = Completer<AstrologyChart>();
      final second = Completer<AstrologyChart>();
      final received = <AstrologyInput>[];
      try {
        await tester.pumpWidget(
          _app(
            AstrologyChartPanel(
              input: const AstrologyInput(place: _place),
              calculator: (input) {
                received.add(input);
                return received.length == 1 ? first.future : second.future;
              },
            ),
          ),
        );
        await tester.pump(const Duration(minutes: 3));
        expect(received, hasLength(1));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        first.complete(_chart(received.first));
        await tester.pump();
        expect(find.byType(VedicChartView), findsOneWidget);
        await tester.pump(const Duration(minutes: 1));
        expect(received, hasLength(2));
        await _unmount(tester);
        second.complete(_chart(received.last));
        await tester.pump(const Duration(minutes: 3));
        expect(received, hasLength(2));
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester);
        if (!first.isCompleted) first.complete(_chart(_input()));
        if (!second.isCompleted) second.complete(_chart(_input()));
        await tester.pump();
      }
    });
  });

  testWidgets(
      'all seven read-only document blocks mount placeholders, not charts',
      (tester) async {
    final context = await _activateAstrology();
    try {
      for (final entry in _blockCases.entries) {
        final node = ExtensionBlockRegistry.definitionFor(entry.key)!.newNode!()
          ..updateAttributes({'width': 280.0, 'height': 300.0});
        final editor = EditorState(
          document: Document(root: pageNode(children: [node])),
        )
          ..editable = false
          ..editorStyle = EditorStyle.desktop();
        final before = jsonEncode(editor.document.toJson());
        var writes = 0;
        final subscription = editor.transactionStream.listen((_) => writes++);
        try {
          expect(node.parent, same(editor.document.root));
          await tester.pumpWidget(
            _app(
              Provider<EditorState>.value(
                value: editor,
                child: AstrologyBlock(
                  key: node.key,
                  node: node,
                  configuration: BlockComponentConfiguration(
                    padding: (_) => EdgeInsets.zero,
                  ),
                ),
              ),
              size: const Size(280, 300),
            ),
          );
          await tester.pump(const Duration(minutes: 2));
          expect(AstrologyRuntime.active.value, isTrue);
          final panel = tester
              .widget<AstrologyChartPanel>(find.byType(AstrologyChartPanel));
          expect(panel.preview, isTrue);
          expect(panel.view, entry.value.$2);
          expect(panel.division, entry.value.$3);
          expect(panel.input.utc, isNull);
          expect(panel.input.place, isNull);
          expect(panel.onConfigure, isNull);
          expect(find.text(_previewMessage(entry.value.$2)), findsOneWidget);
          expect(find.byType(VedicChartView), findsNothing);
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(find.byType(AstrologyBirthForm), findsNothing);
          expect(find.text('Birth details'), findsNothing);
          expect(
            tester.widget<ResizableMedia>(find.byType(ResizableMedia)).editable,
            isFalse,
          );
          expect(
            tester.getSize(find.byKey(const ValueKey('resizable_media'))),
            const Size(280, 300),
          );
          expect(
            tester
                .widget<DropdownButton<AstrologyView>>(
                  find.byType(DropdownButton<AstrologyView>),
                )
                .onChanged,
            isNull,
          );
          for (final chip
              in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
            expect(chip.onSelected, isNull);
          }
          expect(writes, 0);
          expect(jsonEncode(editor.document.toJson()), before);
          expect(tester.takeException(), isNull, reason: entry.key);
        } finally {
          await _unmount(tester);
          // The broadcast listener detaches synchronously. Dispose its owner
          // and pump cleanup rather than awaiting it across fake-clock tests.
          unawaited(subscription.cancel());
          editor.dispose();
          await tester.pump();
        }
      }
    } finally {
      await _unmount(tester);
      context.scope.close();
    }
  });

  testWidgets(
      'an individually added chart declares its draft before later layout edits',
      (tester) async {
    final context = await _activateAstrology();
    final spec =
        DashboardWidgetRegistry.definitionFor(astrologyChartWidgetType)!
            .create();
    final controller = DashboardController(
      viewId: '',
      document: const DashboardDocument().addWidget(spec),
      persistDebounce: const Duration(days: 1),
    );
    try {
      expect(controller.document.variableFor(astrologyDraftKey), isNull);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => DashboardCard(
              controller: controller,
              spec: spec,
              palette: DashboardPalette.of(context),
              selected: false,
              dragging: false,
            ),
          ),
        ),
      );
      await tester.pump();
      // This real UI path calls _setDraft without the native engine needed by
      // BirthForm.onGenerate. A standalone chart has no template variables.
      await tester.tap(find.byTooltip('Switch to South Indian'));
      await tester.pump();
      final draft = controller.state[astrologyDraftKey] as AstrologyInput;
      expect(draft.style, IndianChartStyle.south);
      expect(controller.document.variableFor(astrologyDraftKey), isNotNull);
      expect(controller.document.variableFor(astrologyDraftKey)!.initialValue,
          isNull);
      controller
          .edit((document) => document.copyWith(subtitle: 'Later layout edit'));
      await tester.pump();
      expect(controller.state[astrologyDraftKey], same(draft));
      controller.undo();
      controller.redo();
      await tester.pump();
      expect(controller.state[astrologyDraftKey], same(draft));
      expect(
        tester
            .widget<AstrologyChartPanel>(find.byType(AstrologyChartPanel))
            .input,
        same(draft),
      );
      expect(controller.document.allWidgets.single.settings,
          isNot(contains('profile')));
      expect(find.byType(VedicChartView), findsNothing);
      expect(tester.takeException(), isNull);
      await controller.flush(); // An empty preview id performs no backend IO.
    } finally {
      await _unmount(tester);
      controller.dispose();
      context.scope.close();
    }
  });

  group('native-only dashboard callback regressions (source inspection)', () {
    test(
        'Save merges input into the latest controller document, not a stale view echo',
        () {
      // _BirthCard._save intentionally requires a real native calculation and
      // backend persistence. Do not fake those plugins just to invoke it here.
      final source = _dashboardSourceSection(
        'Future<void> _save(',
        '@override',
      );
      final saveAt = source
          .indexOf('await AstrologyDashboardService.instance.savePerson(');
      final merge = RegExp(
        r'controller\.edit\(\s*\(document\)\s*=>\s*'
        r'withAstrologyInput\(\s*document\s*,\s*input\s*,?\s*\)\s*,?\s*\)',
      ).firstMatch(source);
      expect(saveAt, greaterThanOrEqualTo(0));
      expect(merge, isNotNull);
      expect(merge!.start, greaterThan(saveAt));
      expect(
        RegExp(r'\badoptFromView\s*\(\s*saved\s*\)').hasMatch(source),
        isFalse,
      );
      final afterMerge = source.substring(merge.end);
      expect(
          afterMerge, contains('controller.setValue(astrologyDraftKey, null)'));
      expect(afterMerge, contains('await controller.flush()'));
    });

    test(
        'Generate uses the shared draft declaration path for individually added cards',
        () {
      final declaration =
          _dashboardSourceSection('void _setDraft(', 'class _BirthCard');
      expect(
        RegExp(r'variableFor\(\s*astrologyDraftKey\s*\)\s*==\s*null')
            .hasMatch(declaration),
        isTrue,
      );
      expect(declaration, contains('controller.edit('));
      expect(declaration, contains('document.withVariable('));
      final variable = RegExp(r'DashboardVariable\(\s*key:\s*astrologyDraftKey')
          .firstMatch(declaration);
      expect(variable, isNotNull);
      expect(
        declaration.indexOf('controller.setValue(astrologyDraftKey, input)'),
        greaterThan(variable!.end),
      );
      final generate = _dashboardSourceSection(
          'onGenerate: (input) async {', 'onSave: _save');
      expect(generate, contains('_setDraft(controller, input)'));
      expect(
          generate, isNot(contains('controller.setValue(astrologyDraftKey')));
    });
  });
}

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

ThemeData _theme(
        {Brightness brightness = Brightness.light, bool paper = false}) =>
    DesktopAppearance().getThemeData(
      paper
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

Widget _app(Widget child,
        {Size size = const Size(760, 540), ThemeData? theme}) =>
    MaterialApp(
      theme: theme ?? _theme(),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
          body: Center(child: SizedBox.fromSize(size: size, child: child))),
    );

Widget _dashboardCard(
        DashboardController controller, DashboardWidgetSpec spec) =>
    Builder(
      builder: (context) {
        final definition = DashboardWidgetRegistry.definitionFor(spec.type)!;
        return SizedBox.expand(
          key: ValueKey('preview-${spec.id}'),
          child: definition.builder(
            DashboardWidgetContext(
              context: context,
              controller: controller,
              spec: spec,
              palette: DashboardPalette.of(context),
            ),
          ),
        );
      },
    );

String _previewMessage(AstrologyView view) =>
    'Live ${view.label.toLowerCase()} appear after you use this template. '
    'No location is requested in a preview.';

void _expectPreviewCard(
  WidgetTester tester,
  DashboardWidgetSpec spec,
  AstrologyInput input,
) {
  expect(find.byType(VedicChartView), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  final view = _readingViews[spec.type];
  if (view != null) {
    final panel =
        tester.widget<AstrologyChartPanel>(find.byType(AstrologyChartPanel));
    expect(panel.preview, isTrue);
    expect(panel.view, view);
    expect(panel.division, spec.integer('division', fallback: 1));
    expect(find.text(_previewMessage(view)), findsOneWidget);
    if (spec.flag('transit')) {
      expect(panel.input.utc, isNull);
      expect(panel.input.place, isNull);
      expect(panel.input.utcOffsetMinutes, isNull);
      expect(panel.input.style, input.style);
      expect(panel.input.ayanamsa, input.ayanamsa);
      expect(
          panel.input.ayanamsaOffsetArcseconds, input.ayanamsaOffsetArcseconds);
      expect(panel.input.trueNode, input.trueNode);
      expect(panel.input.dashaYearDays, input.dashaYearDays);
    } else {
      expect(panel.input.toJson(), input.toJson());
    }
  } else {
    expect(find.byType(AstrologyChartPanel), findsNothing);
    switch (spec.type) {
      case astrologyInputWidgetType:
        final form =
            tester.widget<AstrologyBirthForm>(find.byType(AstrologyBirthForm));
        expect(form.enabled, isFalse);
        expect(form.input.toJson(), input.toJson());
        expect(find.text('Preview only · location lookup is disabled.'),
            findsOneWidget);
        for (final id in [
          'astrology-current-location',
          'astrology-search',
          'astrology-generate',
          'astrology-save',
        ]) {
          expect(tester.widget<TextButton>(find.byKey(ValueKey(id))).onPressed,
              isNull);
        }
      case astrologyLibraryWidgetType:
        expect(
            find.textContaining('Each person appears here and as a subpage.'),
            findsOneWidget);
        expect(find.byType(ActionChip), findsNothing);
      case astrologyEventsWidgetType:
        expect(find.textContaining('Save a named horoscope above'),
            findsOneWidget);
      default:
        fail('An untested astrology preview type was added: ${spec.type}');
    }
  }
}

void _expectChart(WidgetTester tester, AstrologyChart chart) {
  final view = tester.widget<VedicChartView>(find.byType(VedicChartView));
  expect(view.placements, same(chart.planets));
  expect(view.ascendant, chart.ascendant);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Synthetic UI fixtures ONLY, not reference ephemeris positions. All seven
/// classical planets and both nodes are supplied; no native engine is called.
AstrologyChart _chart(AstrologyInput input, {double ascendant = 33}) {
  final utc = input.utc!;
  const longitudes = [
    10.0,
    20.0,
    96.0,
    151.0,
    215.0,
    278.0,
    305.0,
    345.0,
    165.0
  ];
  return AstrologyChart(
    input: input,
    utc: utc,
    julianDay:
        2440587.5 + utc.millisecondsSinceEpoch / Duration.millisecondsPerDay,
    ayanamsaDegrees: 23.85675,
    ascendant: ascendant,
    midheaven: 301,
    planets: [
      for (final body in VedicBody.values)
        VedicPlacement(
          body: body,
          name: body.label,
          shortName: body.shortName,
          longitude: longitudes[body.index],
          speed: body == VedicBody.mercury ? -0.5 : 1,
        ),
    ],
    specialLagnas: const [],
    sunrise: utc.subtract(const Duration(hours: 6)),
    sunset: utc.add(const Duration(hours: 6)),
    nextSunrise: utc.add(const Duration(hours: 18)),
    weekday: utc.weekday % 7,
    localMeanHours: 12,
    ephemerisVersion: 'synthetic-test-fixture',
  );
}

class _FakeLocationService extends AstrologyLocationService {
  _FakeLocationService({this.onCurrent})
      : super(geocoder: const _NoNetworkGeocoder());

  final Future<AstrologyPlace> Function(bool force)? onCurrent;
  final currentForces = <bool>[];
  final queries = <String>[];

  @override
  Future<AstrologyPlace> current({bool force = false}) async {
    currentForces.add(force);
    final handler = onCurrent;
    return handler == null ? _place : await handler(force);
  }

  @override
  Future<List<AstrologyPlace>> search(String query) async {
    queries.add(query);
    return const [];
  }
}

class _NoNetworkGeocoder implements MapGeocoder {
  const _NoNetworkGeocoder();

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) => throw StateError(
      'Unexpected geocoder access in an astrology integration test.');

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) =>
      throw StateError(
          'Unexpected geocoder access in an astrology integration test.');
}

String _dashboardSourceSection(String start, String end) {
  final source = File(
    'lib/extensions/dart/built_in/astrology/astrology_dashboard_widgets.dart',
  ).readAsStringSync();
  final from = source.indexOf(start);
  expect(from, greaterThanOrEqualTo(0),
      reason: 'Missing source section: $start');
  final to = source.indexOf(end, from + start.length);
  expect(to, greaterThan(from), reason: 'Missing section end: $end');
  return source.substring(from, to);
}
