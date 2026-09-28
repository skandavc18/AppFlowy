import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'database_find_grid_test_support.dart' show settleDatabaseFindNavigation;
import 'database_find_test_support.dart';

void main() {
  setUpDatabaseFindTests();

  testWidgets(
      'saved styled inline-widget words map to exact native database boxes',
      (tester) async {
    final page = DatabaseFindHarness();
    page.view.name = 'Table';
    page.reads.fields[databaseFindViewId] = [
      page.reads.fields[databaseFindViewId]!.first..name = 'Body'
    ];
    page.reads.setText(databaseFindViewId, 'first needle second needle');
    const target = DatabaseFindTarget.cell(
        databaseFindViewId, databaseFindRowId, databaseFindFieldId);
    page.content = const Align(
        alignment: Alignment.bottomLeft,
        child: DatabaseFindAnchor(
          target: target,
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: 'first ',
                semanticsLabel: 'spoken prefix longer than ink'),
            WidgetSpan(
                child: Text('needle', key: ValueKey('inline-cell-word'))),
            TextSpan(text: ' second '),
            TextSpan(
                text: 'needle', style: TextStyle(fontWeight: FontWeight.bold)),
          ])),
        ));
    try {
      await page.mount(tester);
      final before = page.reads.snapshot();
      final native = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.byKey(const ValueKey('inline-cell-word')),
        matching: find.byType(RichText),
      ));
      await page.open(tester, hover: false);
      await page.query(tester, 'needle');
      final navigation = tester
          .widget<DatabaseFindScope>(find.byType(DatabaseFindScope))
          .controller;
      await settleDatabaseFindNavigation(tester, navigation);
      expect(navigation.reveal, DatabaseFindReveal.exact,
          reason: navigation.message);
      final boxes = native
          .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: 6))
          .map((box) => MatrixUtils.transformRect(
              native.getTransformTo(null), box.toRect()))
          .toList();
      expect(boxes, isNotEmpty);
      expect(navigation.visibleMatchRects, boxes);
      final pane = tester.getRect(find.byType(DatabaseFindScope)).inflate(.1);
      for (final box in boxes) {
        expect(pane.contains(box.topLeft), isTrue);
        expect(pane.contains(box.bottomRight), isTrue);
      }
      navigation.navigate();
      await settleDatabaseFindNavigation(tester, navigation);
      expect(navigation.reveal, DatabaseFindReveal.exact);
      final anchor = tester.renderObject<RenderDatabaseFindAnchor>(
          find.byType(DatabaseFindAnchor));
      expect(
          navigation.visibleMatchRects,
          anchor
              .measure(databaseFindSession(tester).current!)
              .boxes
              .map((box) => box.globalRect)
              .toList());
      expect(page.reads.snapshot(), before);
    } finally {
      await page.dispose(tester);
    }
  });
}
