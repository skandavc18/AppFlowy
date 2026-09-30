import 'package:appflowy/plugins/blank/home/home_agenda.dart';
import 'package:appflowy/plugins/blank/home/home_search.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_query.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 30, 10, 30);

ViewGalleryEntry _entry(
  String id, {
  String? name,
  DateTime? at,
  String type = 'Page',
  String location = '',
  bool pinned = false,
  int edited = 0,
}) =>
    ViewGalleryEntry(
      view: ViewPB(
        id: id,
        name: name ?? id,
        parentViewId: location,
        lastEdited: Int64(edited),
        extra: type,
      ),
      at: at,
      pinned: pinned,
    );

String _valueOf(ViewGalleryEntry entry, String column) => switch (column) {
      ViewGalleryColumns.name => entry.view.name,
      ViewGalleryColumns.kind => entry.view.extra,
      ViewGalleryColumns.location => entry.view.parentViewId,
      ViewGalleryColumns.pinned => entry.pinned ? 'Pinned' : '',
      ViewGalleryColumns.when =>
        entry.at == null ? '' : viewGalleryPeriodOf(entry.at!, _now).name,
      _ => '',
    };

DateTime? _timeOf(ViewGalleryEntry entry, String column) =>
    column == ViewGalleryColumns.when ? entry.at : null;

List<String> _ids(Iterable<ViewGalleryEntry> entries) =>
    entries.map((entry) => entry.id).toList();

void main() {
  group('library periods', () {
    test('calendar days, not 24 hour steps', () {
      expect(
        viewGalleryPeriodOf(DateTime(2026, 9, 30, 0, 1), _now),
        ViewGalleryPeriod.today,
      );
      expect(
        viewGalleryPeriodOf(DateTime(2026, 9, 29, 23, 59), _now),
        ViewGalleryPeriod.yesterday,
      );
      expect(
        viewGalleryPeriodOf(DateTime(2026, 9, 24), _now),
        ViewGalleryPeriod.thisWeek,
      );
      expect(
        viewGalleryPeriodOf(DateTime(2026, 9, 23), _now),
        ViewGalleryPeriod.thisMonth,
      );
      expect(
        viewGalleryPeriodOf(DateTime(2026, 8, 31), _now),
        ViewGalleryPeriod.earlier,
      );
      // Early in a month, "this week" wins over the month boundary.
      expect(
        viewGalleryPeriodOf(DateTime(2026, 9, 28), DateTime(2026, 10, 2)),
        ViewGalleryPeriod.thisWeek,
      );
    });

    test('seconds and legacy milliseconds both read as instants', () {
      final instant = DateTime(2026, 9, 30, 9);
      final seconds = Int64(instant.millisecondsSinceEpoch ~/ 1000);
      expect(viewGalleryTime(seconds), instant);
      expect(
        viewGalleryTime(Int64(instant.millisecondsSinceEpoch)),
        instant,
      );
      expect(viewGalleryTime(Int64()), isNull);
    });
  });

  group('library query', () {
    final entries = [
      _entry('b', name: 'Beta plan', at: _now, location: 'Work'),
      _entry(
        'a',
        name: 'alpha notes',
        at: DateTime(2026, 9, 29, 8),
        type: 'Table',
        location: 'Home',
      ),
      _entry('c', name: 'Gamma', type: 'Board', location: 'Work'),
      _entry('d', name: 'Delta', at: DateTime(2026, 8), pinned: true),
    ];

    test('search hides what does not match and keeps the order', () {
      final result = applyViewGalleryQuery(
        entries,
        const TableQuery(search: '  WORK '),
        valueOf: _valueOf,
        timeOf: _timeOf,
      );
      expect(_ids(result), ['b', 'c']);
      expect(
        _ids(
          applyViewGalleryQuery(
            entries,
            const TableQuery(search: 'table'),
            valueOf: _valueOf,
            timeOf: _timeOf,
          ),
        ),
        ['a'],
      );
    });

    test('filter by value or by having any value', () {
      expect(
        _ids(
          applyViewGalleryQuery(
            entries,
            const TableQuery(filterColumn: 'location', filterValue: 'work'),
            valueOf: _valueOf,
            timeOf: _timeOf,
          ),
        ),
        ['b', 'c'],
      );
      expect(
        _ids(
          applyViewGalleryQuery(
            entries,
            const TableQuery(filterColumn: 'pinned'),
            valueOf: _valueOf,
            timeOf: _timeOf,
          ),
        ),
        ['d'],
      );
    });

    test('sorts names case-insensitively and times with empties last', () {
      expect(
        _ids(
          applyViewGalleryQuery(
            entries,
            const TableQuery(sortColumn: 'name'),
            valueOf: _valueOf,
            timeOf: _timeOf,
          ),
        ),
        ['a', 'b', 'd', 'c'],
      );
      for (final direction in TableSortDirection.values) {
        final sorted = _ids(
          applyViewGalleryQuery(
            entries,
            TableQuery(sortColumn: 'when', direction: direction),
            valueOf: _valueOf,
            timeOf: _timeOf,
          ),
        );
        expect(sorted.last, 'c');
        expect(
          sorted.take(3),
          direction == TableSortDirection.ascending
              ? ['d', 'a', 'b']
              : ['b', 'a', 'd'],
        );
      }
    });

    test('equal values keep the library order (stable)', () {
      final same = [
        for (final id in ['3', '1', '2', '5', '4'])
          _entry(id, name: 'Same', at: _now),
      ];
      expect(
        _ids(
          applyViewGalleryQuery(
            same,
            const TableQuery(sortColumn: 'name'),
            valueOf: _valueOf,
            timeOf: _timeOf,
          ),
        ),
        ['3', '1', '2', '5', '4'],
      );
    });

    test('time groups run newest first; others alphabetically', () {
      final byName = applyViewGalleryQuery(
        entries,
        const TableQuery(sortColumn: 'name'),
        valueOf: _valueOf,
        timeOf: _timeOf,
      );
      final byTime = groupViewGallery(
        byName,
        'when',
        valueOf: _valueOf,
        timeOf: _timeOf,
        ungrouped: 'None',
      );
      expect(
        byTime.map((group) => group.label),
        ['today', 'yesterday', 'earlier', 'None'],
      );
      final byLocation = groupViewGallery(
        entries,
        'location',
        valueOf: _valueOf,
        timeOf: _timeOf,
        ungrouped: 'None',
      );
      expect(byLocation.map((group) => group.label), ['Home', 'Work', 'None']);
      expect(_ids(byLocation[1].entries), ['b', 'c']);
      expect(
        groupViewGallery(
          entries,
          '',
          valueOf: _valueOf,
          timeOf: _timeOf,
          ungrouped: 'None',
        ).single.entries,
        entries,
      );
    });

    test('filter values are distinct, and time values newest first', () {
      expect(
        viewGalleryValuesOf(
          entries,
          'location',
          valueOf: _valueOf,
          timeOf: _timeOf,
        ),
        ['Home', 'Work'],
      );
      expect(
        viewGalleryValuesOf(
          entries,
          'when',
          valueOf: _valueOf,
          timeOf: _timeOf,
        ),
        ['today', 'yesterday', 'earlier'],
      );
    });
  });

  group('library spec', () {
    test('round-trips everything but the search box', () {
      const spec = ViewGallerySpec(
        scale: GalleryCardScale.large,
        face: GalleryCardFace.portrait,
        layout: ViewGalleryLayout.list,
        showCoverPlaceholder: false,
        sortColumn: 'when',
        direction: TableSortDirection.descending,
        filterColumn: 'type',
        filterValue: 'Page',
        groupColumn: 'location',
      );
      expect(ViewGallerySpec.fromJson(spec.toJson()), spec);
      expect(const ViewGallerySpec().toJson(), isEmpty);
      expect(
        ViewGallerySpec.fromJson(const {'layout': 7}),
        const ViewGallerySpec(),
      );
      final query = spec.query(search: 'x');
      expect(query.search, 'x');
      expect(spec.withQuery(query.copyWith(groupColumn: '')).groupColumn, '');
    });
  });

  group('home search placement', () {
    test('centres on the bar and stays on screen', () {
      final rect = homeSearchPanelRect(
        anchor: const Rect.fromLTWH(300, 400, 700, 54),
        viewport: const Size(1400, 1000),
      );
      expect(rect.center.dx, closeTo(650, 0.01));
      expect(rect.top, 376);
      expect(rect.height, 600);
      final narrow = homeSearchPanelRect(
        anchor: const Rect.fromLTWH(10, 100, 300, 54),
        viewport: const Size(400, 800),
      );
      expect(narrow.left, 16);
      expect(narrow.right, 384);
    });

    test('moves up when the bar is near the bottom', () {
      final rect = homeSearchPanelRect(
        anchor: const Rect.fromLTWH(100, 700, 600, 54),
        viewport: const Size(1000, 800),
      );
      expect(rect.height, 360);
      expect(rect.bottom, 784);
      final tiny = homeSearchPanelRect(
        anchor: const Rect.fromLTWH(0, 10, 100, 54),
        viewport: const Size(200, 20),
      );
      expect(tiny.height, greaterThanOrEqualTo(0));
    });
  });

  group('home agenda', () {
    AppReminder reminder(
      String id,
      DateTime at, {
      ReminderPriority priority = ReminderPriority.none,
      bool done = false,
    }) =>
        AppReminder(
          id: id,
          title: 'Reminder $id',
          message: '',
          scheduledAt: at,
          priority: priority,
          isDone: done,
        );

    CalendarEvent event(String id, DateTime start, {DateTime? end}) =>
        CalendarEvent(
          id: id,
          calendarId: 'cal',
          title: 'Event $id',
          start: ZonedDateTime.local(start),
          end: end == null ? null : ZonedDateTime.local(end),
        );

    test('next commitment, priority, overdue, today and coming up', () {
      final agenda = HomeAgenda.compute(
        now: _now,
        events: [
          event(
            'past',
            DateTime(2026, 9, 30, 8),
            end: DateTime(2026, 9, 30, 9),
          ),
          event(
            'ongoing',
            DateTime(2026, 9, 30, 10),
            end: DateTime(2026, 9, 30, 11),
          ),
          event('later', DateTime(2026, 9, 30, 15)),
          event('tomorrow', DateTime(2026, 10, 1, 9)),
          event('far', DateTime(2026, 11, 1, 9)),
          // A reminder's own calendar copy is not listed twice.
          reminder('r1', DateTime(2026, 9, 30, 17)).toCalendarEvent(),
        ],
        reminders: [
          reminder('r1', DateTime(2026, 9, 30, 17)),
          reminder(
            'late',
            DateTime(2026, 9, 28, 9),
            priority: ReminderPriority.low,
          ),
          reminder(
            'loud',
            DateTime(2026, 10, 2, 9),
            priority: ReminderPriority.high,
          ),
          reminder('done', DateTime(2026, 9, 30, 12), done: true),
        ],
        colorOf: (_) => Colors.blue,
      );
      expect(agenda.next?.id, 'ongoing');
      expect(agenda.priority?.id, 'reminder:late');
      expect(agenda.overdue.map((item) => item.id), ['reminder:late']);
      expect(
        agenda.today.map((item) => item.id),
        ['past', 'ongoing', 'later', 'reminder:r1'],
      );
      expect(
        agenda.upcoming.map((item) => item.id),
        ['tomorrow', 'reminder:loud'],
      );
    });

    test('without events, the next reminder that is not the priority', () {
      final agenda = HomeAgenda.compute(
        now: _now,
        events: const [],
        reminders: [
          reminder(
            'first',
            DateTime(2026, 9, 30, 12),
            priority: ReminderPriority.high,
          ),
          reminder('second', DateTime(2026, 9, 30, 14)),
        ],
        colorOf: (_) => Colors.blue,
      );
      expect(agenda.priority?.id, 'reminder:first');
      expect(agenda.next?.id, 'reminder:second');
      expect(
        HomeAgenda.compute(
          now: _now,
          events: const [],
          reminders: const [],
          colorOf: (_) => Colors.blue,
        ).next,
        isNull,
      );
    });
  });
}
