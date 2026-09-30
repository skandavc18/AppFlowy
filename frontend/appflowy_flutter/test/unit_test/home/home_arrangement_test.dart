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
  group('HomeArrangement', () {
    final defaults = HomeArrangement.defaults();

    test('starts as Home always looked', () {
      expect(defaults.main, ['jumpBackIn']);
      expect(defaults.side, ['glance', 'calendar', 'events', 'reminders']);
      expect(defaults.missingBlocks, isEmpty);
      expect(defaults.widgets.widgetCount, 0);
    });

    test('moves a block up, down and into the other column', () {
      // Slots count the gaps of the column as it is now.
      final up = defaults.move('events', HomeColumn.side, 1);
      expect(up.side, ['glance', 'events', 'calendar', 'reminders']);
      final down = defaults.move('glance', HomeColumn.side, 2);
      expect(down.side, ['calendar', 'glance', 'events', 'reminders']);
      final last = defaults.move('glance', HomeColumn.side, 4);
      expect(last.side, ['calendar', 'events', 'reminders', 'glance']);
      final across = defaults.move('calendar', HomeColumn.main, 0);
      expect(across.main, ['calendar', 'jumpBackIn']);
      expect(across.side, ['glance', 'events', 'reminders']);
      // Dropping a block where it already is changes nothing.
      expect(defaults.move('calendar', HomeColumn.side, 1), defaults);
      expect(defaults.move('calendar', HomeColumn.side, 2), defaults);
    });

    test('a part taken off can be put back; a widget goes with its spec', () {
      final without = defaults.remove('reminders');
      expect(without.side, ['glance', 'calendar', 'events']);
      expect(without.missingBlocks, [HomeBlock.reminders]);
      final restored = without.add('reminders', HomeBlock.reminders.homeColumn);
      expect(restored, defaults);

      final withNote = defaults.addWidget(_note, HomeColumn.side);
      final id = homeWidgetBlockId(_note.id);
      expect(withNote.side.last, id);
      expect(withNote.widgetFor(id), _note);
      final removed = withNote.remove(id);
      expect(removed.widgets.widgetCount, 0);
      expect(removed.side, defaults.side);
    });

    test('a widget deleted from its settings leaves its column too', () {
      final withNote = defaults.addWidget(_note, HomeColumn.main);
      final adopted = withNote.withWidgets(
        withNote.widgets.withoutWidget(_note.id),
      );
      expect(adopted.main, ['jumpBackIn']);
    });

    test('duplicates, unknown parts and orphaned widgets are dropped', () {
      final messy = HomeArrangement(
        main: const ['jumpBackIn', 'glance', 'sparkles', 'widget:missing'],
        side: const ['glance', 'calendar'],
        widgets: const DashboardDocument().addWidget(_note),
      ).normalized();
      expect(messy.main, ['jumpBackIn', 'glance']);
      expect(messy.side, ['calendar']);
      // Nothing places the note, so it is not kept.
      expect(messy.widgets.widgetCount, 0);
    });

    test('survives being written and read back', () {
      final arranged = defaults
          .move('calendar', HomeColumn.main, 1)
          .remove('events')
          .addWidget(_note, HomeColumn.side);
      final json = jsonDecode(jsonEncode(arranged.toJson()));
      final restored = HomeArrangement.fromJson(
        Map<String, Object?>.from(json as Map),
      );
      expect(restored, arranged);
      expect(restored.widgetFor(homeWidgetBlockId(_note.id)), _note);
      expect(
        HomeArrangement.fromJson(const {
          'main': 7,
          'side': ['glance', 3],
        }),
        const HomeArrangement(main: [], side: ['glance']),
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
