import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the grid a dashboard is laid out on', () {
    test('a canvas offers fewer columns as it narrows', () {
      expect(dashboardColumnsFor(1400), 12);
      expect(dashboardColumnsFor(1000), 8);
      expect(dashboardColumnsFor(700), 6);
      expect(dashboardColumnsFor(500), 4);
      expect(dashboardColumnsFor(320), 2);
    });

    test('a widget that filled the row still fills a narrower one', () {
      const full = DashboardPlacement(columnSpan: 12);
      expect(
        scaleDashboardPlacement(full, from: 12, to: 4).columnSpan,
        4,
        reason: 'a full-width widget must stay full width',
      );
      const half = DashboardPlacement(column: 6, columnSpan: 6);
      final scaled = scaleDashboardPlacement(half, from: 12, to: 4);
      expect(scaled.columnSpan, 2);
      expect(scaled.column, 2);
    });

    test('a widget is never scaled outside the canvas', () {
      const edge = DashboardPlacement(column: 10, columnSpan: 2);
      final scaled = scaleDashboardPlacement(edge, from: 12, to: 2);
      expect(scaled.column + scaled.columnSpan, lessThanOrEqualTo(2));
    });

    test('overlapping widgets are pushed down, not on top of each other', () {
      final settled = resolveDashboardLayout(
        const [
          DashboardSlot(
            id: 'a',
            placement: DashboardPlacement(columnSpan: 6, rowSpan: 3),
          ),
          DashboardSlot(
            id: 'b',
            placement: DashboardPlacement(columnSpan: 6, rowSpan: 3),
          ),
        ],
        columns: 12,
      );
      final a = settled.firstWhere((slot) => slot.id == 'a').placement;
      final b = settled.firstWhere((slot) => slot.id == 'b').placement;
      expect(a.overlaps(b), isFalse);
      expect(b.row, a.endRow);
    });

    test('widgets side by side stay side by side', () {
      final settled = resolveDashboardLayout(
        const [
          DashboardSlot(
            id: 'a',
            placement: DashboardPlacement(columnSpan: 6, rowSpan: 3),
          ),
          DashboardSlot(
            id: 'b',
            placement: DashboardPlacement(column: 6, columnSpan: 6, rowSpan: 3),
          ),
        ],
        columns: 12,
      );
      expect(settled.every((slot) => slot.placement.row == 0), isTrue);
    });

    test('a gap above a widget is closed', () {
      final settled = resolveDashboardLayout(
        const [
          DashboardSlot(id: 'a', placement: DashboardPlacement(row: 9)),
        ],
        columns: 12,
      );
      expect(settled.single.placement.row, 0);
    });

    test('a free section leaves a widget where it was dropped', () {
      final settled = resolveDashboardLayout(
        const [
          DashboardSlot(id: 'a', placement: DashboardPlacement(row: 9)),
        ],
        columns: 12,
        compact: false,
      );
      expect(settled.single.placement.row, 9);
    });

    test('a free section still refuses to let two widgets overlap', () {
      final settled = resolveDashboardLayout(
        const [
          DashboardSlot(
            id: 'a',
            placement: DashboardPlacement(row: 4, columnSpan: 6, rowSpan: 3),
          ),
          DashboardSlot(
            id: 'b',
            placement: DashboardPlacement(row: 4, columnSpan: 6, rowSpan: 3),
          ),
        ],
        columns: 12,
        compact: false,
      );
      final a = settled.firstWhere((slot) => slot.id == 'a').placement;
      final b = settled.firstWhere((slot) => slot.id == 'b').placement;
      expect(a.row, 4, reason: 'the first one keeps its place');
      expect(a.overlaps(b), isFalse);
    });

    test('the widget being dragged keeps exactly where it was put', () {
      final settled = resolveDashboardLayout(
        const [
          DashboardSlot(
            id: 'a',
            placement: DashboardPlacement(columnSpan: 6, rowSpan: 3),
          ),
          DashboardSlot(
            id: 'dragged',
            placement: DashboardPlacement(row: 4, columnSpan: 6, rowSpan: 3),
          ),
        ],
        columns: 12,
        floating: 'dragged',
      );
      expect(
        settled.firstWhere((slot) => slot.id == 'dragged').placement.row,
        4,
      );
    });

    test('the pixel geometry answers where a pointer is', () {
      final metrics = dashboardGridMetrics(
        width: 1200,
        columns: 12,
        gap: 10,
        rowHeight: 40,
      );
      // 12 columns of x plus 11 gaps of 10 must come to 1200.
      expect(metrics.columnWidth * 12 + 110, closeTo(1200, 0.001));
      expect(metrics.leftOf(0), 0);
      expect(metrics.columnAt(metrics.leftOf(3)), 3);
      expect(metrics.rowAt(metrics.topOf(5)), 5);
      expect(metrics.spanForWidth(metrics.widthOf(4)), 4);
      expect(metrics.spanForHeight(metrics.heightOf(3)), 3);
    });
  });

  group('arranging a section', () {
    test('a two column arrangement fills a row before starting the next', () {
      final widgets = [
        for (var index = 0; index < 4; index++)
          DashboardWidgetSpec(
            id: '$index',
            type: 'text',
            placement: DashboardPlacement(row: index),
          ),
      ];
      final arranged =
          applySectionLayout(widgets, DashboardSectionLayout.twoColumn);
      expect(arranged[0].placement.column, 0);
      expect(arranged[0].placement.columnSpan, 6);
      expect(arranged[1].placement.column, 6);
      expect(arranged[1].placement.row, arranged[0].placement.row);
      expect(arranged[2].placement.row, greaterThan(arranged[0].placement.row));
    });

    test('a sidebar is a narrow column and a wide one', () {
      final widgets = [
        const DashboardWidgetSpec(id: 'a', type: 'list'),
        const DashboardWidgetSpec(id: 'b', type: 'database'),
      ];
      final arranged =
          applySectionLayout(widgets, DashboardSectionLayout.sidebarLeft);
      expect(arranged[0].placement.columnSpan, 3);
      expect(arranged[1].placement.columnSpan, 9);
    });

    test('the free arrangement leaves everything where it is', () {
      final widgets = [
        const DashboardWidgetSpec(
          id: 'a',
          type: 'text',
          placement: DashboardPlacement(column: 5, row: 2),
        ),
      ];
      expect(
        applySectionLayout(widgets, DashboardSectionLayout.free),
        widgets,
      );
    });
  });

  group('what a dashboard remembers', () {
    test('a whole dashboard survives a round trip', () {
      final document = DashboardDocument(
        sections: [
          DashboardSection(
            id: 'section',
            title: 'Overview',
            layout: DashboardSectionLayout.twoColumn,
            widgets: [
              DashboardWidgetSpec(
                id: 'w1',
                type: 'metric',
                title: 'Open tasks',
                accent: DashboardAccent.purple,
                placement: const DashboardPlacement(columnSpan: 3, rowSpan: 3),
                source: const DashboardDataSource(
                  kind: DashboardSourceKind.database,
                  viewId: 'db',
                  name: 'Tasks',
                  field: 'Points',
                ),
                settings: const {'aggregate': 'sum'},
                bindings: const {'filter': 'project'},
                actions: const [
                  DashboardAction(
                    kind: DashboardActionKind.openPage,
                    target: 'page',
                    targetName: 'Tasks',
                  ),
                ],
                visibleWhen: 'project=alpha',
              ),
            ],
          ),
        ],
        variables: const [
          DashboardVariable(
            key: 'project',
            label: 'Project',
            options: [DashboardOption(id: 'alpha', label: 'Alpha')],
          ),
        ],
        settings: const DashboardSettings(
          density: DashboardDensity.compact,
          columns: 8,
        ),
        subtitle: 'Everything at a glance',
      );

      final restored = DashboardDocument.fromJson(document.toJson());
      expect(restored, document);
    });

    test('the envelope rides on a view without erasing what is there', () {
      const existing = '{"cover":{"type":"colour"}}';
      final extra = DashboardMetadata(document: DashboardDocument.blank())
          .mergeIntoExtra(existing);
      expect(extra, contains('cover'));
      expect(DashboardMetadata.fromExtra(extra), isNotNull);

      final removed = DashboardMetadata.removeFromExtra(extra);
      expect(DashboardMetadata.fromExtra(removed), isNull);
      expect(removed, contains('cover'));
    });

    test('an envelope from a newer version is ignored, not half read', () {
      const extra = '{"appflowy_dashboard":{"version":99,"spec":{}}}';
      expect(DashboardMetadata.fromExtra(extra), isNull);
    });

    test('an unknown widget type is kept rather than dropped', () {
      final document = DashboardDocument.fromJson({
        'sections': [
          {
            'id': 's',
            'widgets': [
              {'id': 'w', 'type': 'something_new'},
            ],
          },
        ],
      });
      expect(document.widgetById('w')?.type, 'something_new');
      expect(
        DashboardDocument.fromJson(document.toJson()).widgetById('w'),
        isNotNull,
      );
    });

    test('removing a variable also removes what was bound to it', () {
      var document = DashboardDocument(
        sections: [
          const DashboardSection(
            id: 's',
            widgets: [
              DashboardWidgetSpec(
                id: 'w',
                type: 'chart',
                bindings: {'filter': 'project', 'period': 'period'},
              ),
            ],
          ),
        ],
        variables: const [
          DashboardVariable(key: 'project', label: 'Project'),
          DashboardVariable(key: 'period', label: 'Period'),
        ],
      );
      document = document.withoutVariable('project');
      expect(document.widgetById('w')?.bindings, {'period': 'period'});
      expect(document.variables.length, 1);
    });

    test('a widget can be moved between sections', () {
      var document = DashboardDocument(
        sections: [
          const DashboardSection(
            id: 'a',
            widgets: [DashboardWidgetSpec(id: 'w', type: 'text')],
          ),
          const DashboardSection(id: 'b'),
        ],
      );
      document = document.moveWidget('w', 'b');
      expect(document.sectionById('a')!.widgets, isEmpty);
      expect(document.sectionById('b')!.widgets.single.id, 'w');
    });
  });

  group('the state a dashboard keeps', () {
    test('a variable starts at the value it declares', () {
      const variables = [
        DashboardVariable(
          key: 'search',
          label: 'Search',
          kind: DashboardVariableKind.text,
        ),
        DashboardVariable(
          key: 'live',
          label: 'Live',
          kind: DashboardVariableKind.toggle,
        ),
        DashboardVariable(
          key: 'when',
          label: 'When',
          kind: DashboardVariableKind.period,
        ),
      ];
      final state = DashboardStateValues.initial(variables);
      expect(state.text('search'), '');
      expect(state.flag('live'), isFalse);
      expect(state['when'], DashboardPeriod.thisWeek.name);
    });

    test('an option variable that offers everything starts with nothing set',
        () {
      const variable = DashboardVariable(
        key: 'project',
        label: 'Project',
        options: [DashboardOption(id: 'a', label: 'Alpha')],
      );
      expect(variable.initialValue, isNull);
      expect(
        variable.copyWith(includeAll: false).initialValue,
        'a',
        reason: 'without an "everything" choice something must be chosen',
      );
    });

    test('a visibility rule reads the state', () {
      const state = DashboardStateValues({'live': true, 'project': 'alpha'});
      expect(dashboardVisibilityHolds('', state), isTrue);
      expect(dashboardVisibilityHolds('live', state), isTrue);
      expect(dashboardVisibilityHolds('!live', state), isFalse);
      expect(dashboardVisibilityHolds('project=alpha', state), isTrue);
      expect(dashboardVisibilityHolds('project=beta', state), isFalse);
      expect(dashboardVisibilityHolds('missing', state), isFalse);
    });

    test('an empty choice does not count as chosen', () {
      const state = DashboardStateValues({'tags': <String>[], 'name': ''});
      expect(dashboardVisibilityHolds('tags', state), isFalse);
      expect(dashboardVisibilityHolds('name', state), isFalse);
    });

    test('a rule can match one of several chosen values', () {
      const state = DashboardStateValues({
        'tags': ['a', 'b'],
      });
      expect(dashboardVisibilityHolds('tags=b', state), isTrue);
      expect(dashboardVisibilityHolds('tags=c', state), isFalse);
    });

    test('a period is resolved against now, not stored as dates', () {
      final now = DateTime(2026, 8, 12, 15);
      final week = DashboardPeriod.thisWeek.rangeFrom(now);
      expect(week.start, DateTime(2026, 8, 10));
      expect(week.end, DateTime(2026, 8, 17));

      final today = DashboardPeriod.today.rangeFrom(now);
      expect(today.start, DateTime(2026, 8, 12));

      final quarter = DashboardPeriod.thisQuarter.rangeFrom(now);
      expect(quarter.start, DateTime(2026, 7));
      expect(quarter.end, DateTime(2026, 10));

      expect(DashboardPeriod.allTime.rangeFrom(now).start, isNull);
    });
  });

  group('a dashboard needs no data source at all', () {
    test('a widget with nothing bound reports itself unbound', () {
      const source = DashboardDataSource();
      expect(source.isBound, isFalse);
      expect(source.kind, DashboardSourceKind.none);
    });

    test('a database source is only bound once a view is named', () {
      const source = DashboardDataSource(kind: DashboardSourceKind.database);
      expect(source.isBound, isFalse);
      expect(source.copyWith(viewId: 'db').isBound, isTrue);
    });

    test('a source that needs no view is bound as soon as it is chosen', () {
      const source = DashboardDataSource(kind: DashboardSourceKind.reminders);
      expect(source.isBound, isTrue);
    });

    test('a dashboard of buttons and notes is a complete dashboard', () {
      final document = DashboardDocument(
        sections: [
          DashboardSection(
            id: 's',
            widgets: [
              const DashboardWidgetSpec(id: 'b', type: 'button'),
              const DashboardWidgetSpec(id: 'n', type: 'sticky_note'),
            ],
          ),
        ],
      );
      expect(document.isEmpty, isFalse);
      expect(document.widgetCount, 2);
      expect(
        document.allWidgets.every((widget) => !widget.source.isBound),
        isTrue,
      );
    });
  });
}
