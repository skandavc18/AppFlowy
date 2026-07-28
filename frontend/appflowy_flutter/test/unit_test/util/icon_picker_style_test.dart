import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    RecentIcons.enable = false;
    // the picker shows an endless spinner until a pack is in the cache, so
    // preload here rather than fighting `pumpAndSettle`
    for (final pack in kIconPacks) {
      await loadIconPack(pack);
    }
  });

  tearDownAll(() => RecentIcons.enable = true);

  Future<void> pumpPicker(
    WidgetTester tester, {
    required bool enableBackgroundColorSelection,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 420,
            child: FlowyIconPicker(
              onSelectedIcon: (_) {},
              enableBackgroundColorSelection: enableBackgroundColorSelection,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('icon picker styles', () {
    testWidgets('every style is offered, colorful ones included',
        (tester) async {
      for (final enableBackgroundColorSelection in [true, false]) {
        await pumpPicker(
          tester,
          enableBackgroundColorSelection: enableBackgroundColorSelection,
        );

        for (final pack in kIconPacks) {
          expect(
            find.text(pack.displayName),
            findsOneWidget,
            reason: '${pack.displayName} missing when '
                'enableBackgroundColorSelection is '
                '$enableBackgroundColorSelection',
          );
        }
      }
    });

    testWidgets('picking the color style shows untinted icons', (tester) async {
      await pumpPicker(tester, enableBackgroundColorSelection: true);

      final colorPack = kIconPacks.firstWhere((pack) => pack.isColorful);
      await tester.tap(find.text(colorPack.displayName));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final svgs = tester
          .widgetList<FlowySvg>(find.byType(FlowySvg))
          .where((svg) => svg.svgString != null)
          .toList();

      expect(svgs, isNotEmpty);
      // a blend mode is what would flatten the artwork to a single color
      expect(svgs.every((svg) => svg.blendMode == null), isTrue);
    });

    testWidgets('the style chips sit beside each other, not one per row',
        (tester) async {
      await pumpPicker(tester, enableBackgroundColorSelection: true);

      final rects = <double, List<Rect>>{};
      for (final pack in kIconPacks) {
        final rect = tester.getRect(find.text(pack.displayName));
        rects.putIfAbsent(rect.top, () => []).add(rect);
      }

      // a chip that fills its row would leave one label per line
      expect(rects.values.any((row) => row.length > 1), isTrue);
      expect(rects.length, lessThan(kIconPacks.length));
      // and the chips must not span the popover
      for (final row in rects.values) {
        for (final rect in row) {
          expect(rect.width, lessThan(180));
        }
      }
    });
  });
}
