import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_embed_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database_find_test_support.dart';
import 'surface_find_test_support.dart';

void main() {
  surfaceFindTestEnvironment();

  for (final count in [10, 50, 100]) {
    testWidgets('closed real cards have no Find fanout N=$count',
        (tester) async {
      final lookups = ValueNotifier(0);
      final specs = List.generate(
          count,
          (i) =>
              DashboardWidgetSpec(id: 'card-$i', type: 'unsupported-fixture'));
      final document = _CountedDocument(lookups, sections: [
        DashboardSection(id: 's', widgets: specs),
      ]);
      final dashboard = DashboardController(viewId: '', document: document);
      final controller = DashboardFindController(dashboard, title: () => '');
      var notifications = 0;
      controller.addListener(() => notifications++);
      try {
        await tester.pumpWidget(surfaceFindTestApp(SurfaceFindHost(
          controller: controller,
          child: SingleChildScrollView(
              child: Column(children: [
            for (final spec in specs)
              SizedBox(
                  height: 200,
                  child: Builder(
                      builder: (context) => DashboardCard(
                            controller: dashboard,
                            spec: spec,
                            palette: DashboardPalette.of(context),
                            selected: false,
                            dragging: false,
                          ))),
          ])),
        )));
        await pumpSurfaceFind(tester);
        lookups.value = 0;
        notifications = 0;
        dashboard.refresh();
        await pumpSurfaceFind(tester);
        print(
            'SCROLL_SEARCH closed N=$count notifications=$notifications lookups=${lookups.value}');
        expect(notifications, 0);
        expect(lookups.value, 0);
        for (var i = 0; i < 120; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(notifications, 0);
        expect(lookups.value, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        dashboard.dispose();
        lookups.dispose();
      }
    });
  }

  for (final empty in [true, false]) {
    testWidgets(
        empty
            ? 'open empty Find performs no authorization'
            : 'open close unsubscribes provider and unrelated events do no work',
        (tester) async {
      final reads = DatabaseFindReads();
      const spec = DashboardWidgetSpec(
          id: 'embed',
          type: 'database',
          source: DashboardDataSource(
              kind: DashboardSourceKind.database, viewId: databaseFindViewId));
      final dashboard = DashboardController(
          viewId: '',
          document: const DashboardDocument(
            sections: [
              DashboardSection(id: 's', widgets: [spec])
            ],
          ));
      final controller = DashboardFindController(dashboard,
          title: () => '', readProvider: reads.provider());
      var notifications = 0;
      controller.addListener(() => notifications++);
      try {
        await tester.pumpWidget(surfaceFindTestApp(SurfaceFindHost(
          controller: controller,
          child: DashboardFindEmbed(
              dashboard: dashboard,
              spec: spec,
              child: const DatabaseFindAnchor(
                  target: DatabaseFindTarget.cell(databaseFindViewId,
                      databaseFindRowId, databaseFindFieldId),
                  child: Text('needle'))),
        )));
        await pumpSurfaceFind(tester);
        controller.open();
        if (!empty) controller.setQuery('needle');
        await pumpSurfaceFind(tester);
        await pumpSurfaceFind(tester);
        if (empty) {
          print('SCROLL_SEARCH open-empty reads=${reads.calls.length}');
          expect(reads.calls, isEmpty);
        } else {
          expect(controller.matches, hasLength(1));
          controller.close();
          await pumpSurfaceFind(tester);
          notifications = 0;
          reads.calls.clear();
          reads.changes.add('unrelated-id');
          reads.access.value++;
          await pumpSurfaceFind(tester);
          print(
              'SCROLL_SEARCH closed-event notifications=$notifications reads=${reads.calls.length} subscribed=${reads.changes.hasListener}');
          expect(notifications, 0);
          expect(reads.changes.hasListener, isFalse);
          expect(reads.calls, isEmpty);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        dashboard.dispose();
        reads.dispose();
      }
    });
  }

  testWidgets(
      'native incremental query retains client caret and element through navigation',
      (tester) async {
    const text = 'native documentation abcdefghijklmnopqrstuvwxyzabcdef';
    final controller = SurfaceFindController(
        search: (q, options) => searchSurfaceEntries(
            const [SurfaceFindEntry('a', text), SurfaceFindEntry('b', text)],
            q,
            options));
    try {
      await tester.pumpWidget(surfaceFindTestApp(SurfaceFindHost(
        controller: controller,
        child: const Stack(children: [
          Positioned(
              top: 16,
              right: 20,
              child: SurfaceFindTarget(id: 'a', child: Text(text))),
          Positioned(
              bottom: 16,
              right: 20,
              child: SurfaceFindTarget(id: 'b', child: Text(text))),
        ]),
      )));
      await pumpSurfaceFind(tester);
      await openSurfaceFind(tester);
      final field = find.byType(EditableText);
      final element = tester.element(field);
      final state = tester.state<EditableTextState>(field);
      final focus = state.widget.focusNode;
      for (final query in [
        'native documentation',
        'abcdefghijklmnopqrstuvwxyzabcdef'
      ]) {
        tester.testTextInput.updateEditingValue(const TextEditingValue(
            text: '', selection: TextSelection.collapsed(offset: 0)));
        await tester.pump();
        for (var i = 1; i <= query.length; i++) {
          expect(focus.hasPrimaryFocus, isTrue);
          expect(tester.testTextInput.hasAnyClients, isTrue);
          expect(controller.queryController.selection,
              TextSelection.collapsed(offset: i - 1));
          tester.testTextInput.updateEditingValue(TextEditingValue(
              text: query.substring(0, i),
              selection: TextSelection.collapsed(offset: i)));
          if (i == 3 || i == 4 || i == 10) controller.step(1);
          await pumpSurfaceFind(tester);
          expect(tester.element(field), same(element));
          expect(tester.state(field), same(state));
          expect(state.widget.focusNode, same(focus));
          expect(state.widget.controller, same(controller.queryController));
          expect(controller.query, query.substring(0, i));
          expect(controller.queryController.selection,
              TextSelection.collapsed(offset: i));
          expect(controller.queryController.value.composing, TextRange.empty);
        }
        expect(controller.matches, hasLength(2));
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}

class _CountedDocument extends DashboardDocument {
  const _CountedDocument(this.lookups, {required super.sections});
  final ValueNotifier<int> lookups;
  @override
  DashboardWidgetSpec? widgetById(String id) {
    lookups.value++;
    return super.widgetById(id);
  }

  @override
  DashboardSection? sectionOf(String widgetId) {
    lookups.value++;
    return super.sectionOf(widgetId);
  }
}
