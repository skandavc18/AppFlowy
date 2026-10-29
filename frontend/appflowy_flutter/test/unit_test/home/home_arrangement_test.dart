import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/blank/home/home_arrangement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:flutter_test/flutter_test.dart';

const _note = DashboardWidgetSpec(
  id: 'w-note',
  type: 'text',
  title: 'Groceries',
  placement: DashboardPlacement(rowSpan: 3),
  settings: {'text': 'Remember the milk'},
);

void main() {
  group('HomeBlockPlacement', () {
    test('stays inside the grid', () {
      expect(
        const HomeBlockPlacement(column: 10, span: 6).clamped(),
        const HomeBlockPlacement(column: 6, span: 6),
      );
      expect(
        const HomeBlockPlacement(column: -3, span: 0, rows: 0).clamped(),
        const HomeBlockPlacement(span: 1, rows: 1),
      );
      expect(
        const HomeBlockPlacement(span: 40, rows: 900).clamped(),
        const HomeBlockPlacement(rows: homeMaximumRows),
      );
    });

    test('fits its content again once its height is cleared', () {
      const pinned = HomeBlockPlacement(column: 2, span: 5, rows: 7);
      expect(pinned.fitted(), const HomeBlockPlacement(column: 2, span: 5));
      expect(pinned.copyWith(span: 4).rows, 7);
    });

    test('is widened in place, moving only as far as the edge makes it', () {
      const narrow = HomeBlockPlacement(column: 2, span: 3, rows: 4);
      expect(narrow.widened(3), same(narrow));
      expect(narrow.widened(2), same(narrow));
      expect(
        narrow.widened(4),
        const HomeBlockPlacement(column: 2, span: 4, rows: 4),
      );
      expect(
        const HomeBlockPlacement(column: 9, span: 3).widened(4),
        const HomeBlockPlacement(column: 8, span: 4),
      );
      expect(
        const HomeBlockPlacement(column: 9, span: 3).widened(20),
        const HomeBlockPlacement(),
      );
    });

    test('is written compactly and read back', () {
      const pinned = HomeBlockPlacement(column: 2, span: 5, rows: 7);
      expect(pinned.toJson(), {'x': 2, 'w': 5, 'h': 7});
      expect(HomeBlockPlacement.fromJson(pinned.toJson()), pinned);
      expect(const HomeBlockPlacement(span: 6).toJson(), {'x': 0, 'w': 6});
      expect(
        HomeBlockPlacement.fromJson(const {'x': 'left', 'w': 13.5, 'h': -2}),
        const HomeBlockPlacement(rows: 1),
      );
    });
  });

  group('HomeArrangement', () {
    final defaults = HomeArrangement.defaults();
    final noteId = homeWidgetBlockId(_note.id);

    test('starts as Home always looked', () {
      expect(
        defaults.blocks,
        ['glance', 'jumpBackIn', 'calendar', 'events', 'reminders'],
      );
      expect(defaults.missingBlocks, isEmpty);
      expect(defaults.widgets.widgetCount, 0);
      // The pages worked on lately across the start, a rail beside them.
      expect(
        defaults.placementOf('jumpBackIn'),
        const HomeBlockPlacement(span: 8),
      );
      for (final id in ['glance', 'calendar', 'events', 'reminders']) {
        expect(
          defaults.placementOf(id),
          const HomeBlockPlacement(column: 8, span: 4),
        );
      }
    });

    test('places a part anywhere, at any size', () {
      const wide = HomeBlockPlacement(rows: 6);
      final placed = defaults.place('calendar', wide);
      expect(placed.placementOf('calendar'), wide);
      expect(placed.places, {'calendar': wide});
      // Out-of-range placements are kept inside the grid.
      expect(
        defaults
            .place('events', const HomeBlockPlacement(column: 11, span: 5))
            .placementOf('events'),
        const HomeBlockPlacement(column: 7, span: 5),
      );
      // Unknown blocks are not placed.
      expect(defaults.place('sparkles', wide), defaults);
      // Put back where it starts, a part keeps no place of its own.
      expect(
        placed
            .place('calendar', HomeBlock.calendar.defaultPlacement)
            .normalized(),
        defaults,
      );
    });

    test('reorders blocks and keeps the ones left out where they were', () {
      final swapped = defaults.arrange(['calendar', 'glance']);
      expect(
        swapped.blocks,
        ['calendar', 'jumpBackIn', 'glance', 'events', 'reminders'],
      );
      final moved = defaults.arrange(
        ['jumpBackIn', 'glance', 'calendar', 'events', 'reminders'],
        id: 'glance',
        placement: const HomeBlockPlacement(span: 8),
      );
      expect(moved.blocks.take(2), ['jumpBackIn', 'glance']);
      expect(moved.placementOf('glance'), const HomeBlockPlacement(span: 8));
      // Ids that are not on Home, and repeats, are ignored.
      expect(
        defaults.arrange(['sparkles', 'events', 'events', 'glance']).blocks,
        ['events', 'jumpBackIn', 'calendar', 'glance', 'reminders'],
      );
    });

    test('a part taken off can be put back; a widget goes with its spec', () {
      final without = defaults
          .place('reminders', const HomeBlockPlacement(rows: 4))
          .remove('reminders');
      expect(without.contains('reminders'), isFalse);
      expect(without.places, isEmpty);
      expect(without.missingBlocks, [HomeBlock.reminders]);
      expect(without.add('reminders'), defaults);
      expect(defaults.add('reminders'), defaults);
      expect(defaults.add('sparkles'), defaults);

      final withNote = defaults.addWidget(_note);
      expect(withNote.blocks.last, noteId);
      // A narrow widget goes to the end edge, beside the rail.
      expect(
        withNote.placementOf(noteId),
        const HomeBlockPlacement(column: 8, span: 4, rows: 3),
      );
      expect(withNote.widgetFor(noteId)?.settings, _note.settings);
      final removed = withNote.remove(noteId);
      expect(removed.widgets.widgetCount, 0);
      expect(removed.blocks, defaults.blocks);
    });

    test('a wide widget starts from the start edge', () {
      final table = _note.copyWith(
        id: 'w-table',
        placement: const DashboardPlacement(columnSpan: 8, rowSpan: 6),
      );
      expect(
        defaults.addWidget(table).placementOf(homeWidgetBlockId(table.id)),
        const HomeBlockPlacement(span: 8, rows: 6),
      );
    });

    test('a widget keeps its place in its own placement, with a height', () {
      final withNote = defaults.addWidget(_note);
      final placed = withNote.place(
        noteId,
        const HomeBlockPlacement(column: 2, span: 6, rows: 5),
      );
      final spec = placed.widgetFor(noteId)!;
      expect(spec.placement.column, 2);
      expect(spec.placement.columnSpan, 6);
      expect(spec.placement.rowSpan, 5);
      expect(placed.places, isEmpty);
      // A widget cannot fit its content: without a height it keeps its own.
      final moved = placed.place(noteId, const HomeBlockPlacement());
      expect(
        moved.placementOf(noteId),
        const HomeBlockPlacement(rows: 5),
      );
    });

    test('a widget deleted from its settings leaves Home too', () {
      final withNote = defaults.addWidget(_note);
      final adopted = withNote.withWidgets(
        withNote.widgets.withoutWidget(_note.id),
      );
      expect(adopted.blocks, defaults.blocks);
    });

    test('duplicates, unknown parts and orphaned widgets are dropped', () {
      final messy = HomeArrangement(
        blocks: const [
          'jumpBackIn',
          'glance',
          'sparkles',
          'widget:missing',
          'glance',
          'calendar',
        ],
        places: const {
          'calendar': HomeBlockPlacement(column: 8, span: 4),
          'events': HomeBlockPlacement(span: 6),
          'sparkles': HomeBlockPlacement(span: 6),
          'glance': HomeBlockPlacement(column: 20, span: 6),
        },
        widgets: const DashboardDocument().addWidget(_note),
      ).normalized();
      expect(messy.blocks, ['jumpBackIn', 'glance', 'calendar']);
      // Places of parts not on Home, or where a part starts, are dropped;
      // the rest are kept inside the grid.
      expect(messy.places, {
        'glance': const HomeBlockPlacement(column: 6, span: 6),
      });
      // Nothing places the note, so it is not kept.
      expect(messy.widgets.widgetCount, 0);
    });

    test('survives being written and read back', () {
      final arranged = defaults
          .arrange(['calendar', 'glance'])
          .place('calendar', const HomeBlockPlacement(span: 6, rows: 8))
          .remove('events')
          .addWidget(_note);
      final json = jsonDecode(jsonEncode(arranged.toJson()));
      final restored = HomeArrangement.fromJson(
        Map<String, Object?>.from(json as Map),
      );
      expect(restored, arranged);
      expect(restored.widgetFor(noteId), arranged.widgetFor(noteId));
      expect(
        HomeArrangement.fromJson(const {
          'blocks': ['glance', 3, '', 'sparkles'],
          'places': {'glance': 'left', 'calendar': 3},
        }),
        const HomeArrangement(blocks: ['glance']),
      );
    });

    test('still names a wide column and a rail for older builds', () {
      final json = defaults
          .place('calendar', const HomeBlockPlacement(span: 6))
          .place('events', const HomeBlockPlacement(column: 2, span: 4))
          .toJson();
      expect(json['version'], HomeArrangement.version);
      // Each block is on the side its middle is on.
      expect(json['main'], ['jumpBackIn', 'calendar', 'events']);
      expect(json['side'], ['glance', 'reminders']);
    });

    test('reads Home as it was kept in two columns', () {
      final legacy = HomeArrangement.fromJson({
        'main': ['jumpBackIn', 'calendar'],
        'side': ['glance', 'events', 'widget:${_note.id}', 'jumpBackIn'],
        'widgets': const DashboardDocument().addWidget(_note).toJson(),
      });
      // The glance card headed the rail, so it still leads.
      expect(legacy.blocks, [
        'glance',
        'jumpBackIn',
        'calendar',
        'events',
        noteId,
      ]);
      expect(
        legacy.placementOf('calendar'),
        const HomeBlockPlacement(span: 8),
      );
      expect(
        legacy.placementOf('events'),
        const HomeBlockPlacement(column: 8, span: 4),
      );
      // Listed in both columns, a part was kept in the wide one.
      expect(
        legacy.placementOf('jumpBackIn'),
        const HomeBlockPlacement(span: 8),
      );
      expect(
        legacy.placementOf(noteId),
        const HomeBlockPlacement(column: 8, span: 4, rows: 3),
      );
      expect(legacy.places.keys, ['calendar']);

      // A column on its own took the whole width.
      final single = HomeArrangement.fromJson(const {
        'main': [],
        'side': ['calendar', 'glance'],
      });
      expect(single.blocks, ['calendar', 'glance']);
      expect(single.placementOf('glance'), const HomeBlockPlacement());
      expect(
        HomeArrangement.fromJson(const {
          'main': 7,
          'side': ['glance', 3],
        }),
        const HomeArrangement(
          blocks: ['glance'],
          places: {'glance': HomeBlockPlacement()},
        ),
      );
    });
  });

  group('HomeArrangementStore', () {
    test('keeps each workspace its own arrangement on this device', () async {
      final storage = _MemoryStorage();
      final store = HomeArrangementStore(storage: storage);
      await store.load('first');
      expect(store.arrangement, HomeArrangement.defaults());
      expect(storage.values, isEmpty);

      final arranged = store.arrangement.remove('glance');
      store.update(arranged);
      expect(store.arrangement, arranged);
      await store.flush();
      expect(storage.values.keys, ['appflowy_home_layout_first']);

      // Another workspace starts from the defaults, and switching back
      // restores what was arranged there.
      await store.load('second');
      expect(store.arrangement, HomeArrangement.defaults());
      await store.load('first');
      expect(store.arrangement, arranged);
      final reopened = HomeArrangementStore(storage: storage);
      await reopened.load('first');
      expect(reopened.arrangement, arranged);
      store.dispose();
      reopened.dispose();
    });

    test('unsaved changes are written when the store goes away', () async {
      final storage = _MemoryStorage();
      final store = HomeArrangementStore(storage: storage);
      await store.load('workspace');
      store.update(store.arrangement.remove('events'));
      store.dispose();
      await Future<void>.delayed(Duration.zero);
      final saved =
          jsonDecode(storage.values['appflowy_home_layout_workspace']!);
      expect((saved as Map)['side'], ['glance', 'calendar', 'reminders']);
    });

    test('a stored arrangement that cannot be read falls back', () async {
      final storage = _MemoryStorage()
        ..values['appflowy_home_layout_broken'] = '{not json';
      final store = HomeArrangementStore(storage: storage);
      await store.load('broken');
      expect(store.arrangement, HomeArrangement.defaults());
      store.dispose();
    });

    test('without persistence nothing is read or written', () async {
      final storage = _MemoryStorage();
      final store = HomeArrangementStore(storage: storage, persist: false);
      await store.load('workspace');
      store.update(store.arrangement.remove('glance'));
      await store.flush();
      store.dispose();
      expect(storage.reads, 0);
      expect(storage.values, isEmpty);
    });
  });
}

class _MemoryStorage implements KeyValueStorage {
  final values = <String, String>{};
  int reads = 0;

  @override
  Future<String?> get(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> set(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> clear() async => values.clear();

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }
}
