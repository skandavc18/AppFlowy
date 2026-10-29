import 'package:appflowy/plugins/blank/home/home_arrangement.dart';
import 'package:appflowy/plugins/blank/home/home_grid.dart';
import 'package:flutter_test/flutter_test.dart';

HomeGridBox _box(int column, int span, double height) =>
    (column: column, span: span, height: height);

HomeGridSlot _slot(int column, int span, double top, double height) =>
    (column: column, span: span, top: top, height: height);

void main() {
  group('packHomeGrid', () {
    test('lays Home out as a wide column beside a rail by default', () {
      final slots = packHomeGrid(
        [
          _box(8, 4, 200), // glance
          _box(0, 8, 500), // jump back in
          _box(8, 4, 300), // calendar
          _box(8, 4, 150), // events
          _box(8, 4, 100), // reminders
        ],
        gap: 14,
      );
      expect([for (final slot in slots) slot.top], [0, 0, 214, 528, 692]);
      expect(slots[1].height, 500);
    });

    test('a section sits below the lowest earlier one sharing its columns', () {
      final slots = packHomeGrid(
        [_box(0, 6, 100), _box(6, 6, 300), _box(0, 12, 50)],
        gap: 10,
      );
      expect(slots[2].top, 310);
    });

    test('a later section rises to the top when no earlier one is above it',
        () {
      final slots = packHomeGrid(
        [_box(0, 6, 100), _box(0, 6, 100), _box(6, 6, 50)],
      );
      expect([for (final slot in slots) slot.top], [0, 100, 0]);
    });

    test('an empty grid packs nothing', () {
      expect(packHomeGrid(const []), isEmpty);
    });
  });

  group('homeGridInsertionIndex', () {
    final stacked = [
      _slot(0, 12, 0, 100),
      _slot(0, 12, 114, 100),
      _slot(0, 12, 228, 100),
    ];

    test('follows the middles of the sections sharing its columns', () {
      int at(double top) => homeGridInsertionIndex(
            stacked,
            column: 0,
            span: 12,
            top: top,
            origin: 0,
          );
      expect(at(-40), 0);
      expect(at(20), 0);
      expect(at(60), 1);
      expect(at(170), 2);
      expect(at(300), 3);
    });

    test('keeps the order nearest where it began when several fit', () {
      final sideBySide = [_slot(0, 6, 0, 100), _slot(6, 6, 0, 100)];
      int at(int origin) => homeGridInsertionIndex(
            sideBySide,
            column: 0,
            span: 6,
            top: 150,
            origin: origin,
          );
      // Below the first section, and the second never shares its columns.
      expect(at(0), 1);
      expect(at(2), 2);
    });
  });

  group('moving up and down', () {
    const placements = [
      HomeBlockPlacement(column: 8, span: 4),
      HomeBlockPlacement(span: 8),
      HomeBlockPlacement(column: 8, span: 4),
    ];

    test('trades places with the nearest section sharing its columns', () {
      expect(homeGridIndexAbove(placements, 2), 0);
      expect(homeGridIndexBelow(placements, 0), 2);
    });

    test('has nowhere to go when no section shares its columns', () {
      expect(homeGridIndexAbove(placements, 1), isNull);
      expect(homeGridIndexBelow(placements, 1), isNull);
      expect(homeGridIndexAbove(placements, 0), isNull);
      expect(homeGridIndexBelow(placements, 2), isNull);
    });
  });

  group('narrower windows', () {
    const placements = [
      HomeBlockPlacement(column: 8, span: 4),
      HomeBlockPlacement(span: 8),
      HomeBlockPlacement(column: 8, span: 4, rows: 6),
      HomeBlockPlacement(column: 8, span: 4),
      HomeBlockPlacement(column: 8, span: 4, rows: 5),
    ];

    test('pair narrow sections that follow each other', () {
      expect(homeGridPairs(placements), const [
        HomeBlockPlacement(),
        HomeBlockPlacement(),
        HomeBlockPlacement(span: 6, rows: 6),
        HomeBlockPlacement(column: 6, span: 6),
        HomeBlockPlacement(rows: 5),
      ]);
    });

    test('stack every section in one column, keeping heights', () {
      expect(
        homeGridShownPlacements(placements, HomeGridMode.single),
        const [
          HomeBlockPlacement(),
          HomeBlockPlacement(),
          HomeBlockPlacement(rows: 6),
          HomeBlockPlacement(),
          HomeBlockPlacement(rows: 5),
        ],
      );
    });

    test('a wide window shows sections where they are kept', () {
      expect(
        homeGridShownPlacements(placements, HomeGridMode.grid),
        placements,
      );
      expect(
        homeGridShownPlacements(placements, HomeGridMode.pairs),
        homeGridPairs(placements),
      );
    });

    test('a narrower grid takes more columns to keep sections readable', () {
      // 3 columns are 217 wide at 940, the narrowest the grid used to be.
      expect(homeGridReadableSpan(940), 3);
      expect(homeGridReadableSpan(1184), 3);
      // A medium window: 3 columns would be under 200.
      expect(homeGridReadableSpan(734), 4);
      // Exactly enough is enough: 4 columns are 200 wide at 648.
      expect(homeGridReadableSpan(648), 4);
      expect(homeGridReadableSpan(647), 5);
      expect(homeGridReadableSpan(300, readable: 400), 12);
      expect(homeGridReadableSpan(0), 12);
    });
  });

  group('height units', () {
    test('include the gaps between them', () {
      expect(homeGridRowsHeight(3, 46, 14), 3 * 46 + 2 * 14);
      expect(homeGridRowsHeight(1, 46, 14), 46);
      expect(homeGridRowsHeight(0, 46, 14), 0);
    });

    test('a height snaps to the nearest whole number of units', () {
      expect(homeGridRowsFor(166, 46, 14), 3);
      expect(homeGridRowsFor(170, 46, 14), 3);
      expect(homeGridRowsFor(200, 46, 14), 4);
    });

    test('never below the minimum, nor above the tallest allowed', () {
      expect(homeGridRowsFor(10, 46, 14, minimum: 3), 3);
      expect(homeGridRowsFor(-500, 46, 14), 1);
      expect(homeGridRowsFor(100000, 46, 14), homeMaximumRows);
    });

    test('round-trip a whole number of units', () {
      for (var rows = 1; rows <= homeMaximumRows; rows++) {
        expect(
          homeGridRowsFor(homeGridRowsHeight(rows, 40, 10), 40, 10),
          rows,
        );
      }
    });
  });
}
