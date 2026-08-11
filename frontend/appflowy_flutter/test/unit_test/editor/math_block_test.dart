import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_source_editor.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_symbols.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the symbol palette', () {
    testWidgets('renders every preview it offers', (tester) async {
      for (final group in kMathSymbolGroups) {
        for (final symbol in group.symbols) {
          if (symbol.label != null) {
            continue;
          }
          var failed = false;
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Math.tex(
                    symbol.preview,
                    mathStyle: MathStyle.text,
                    textStyle: const TextStyle(fontSize: 13.5),
                    onErrorFallback: (_) {
                      failed = true;
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
            ),
          );
          expect(
            failed,
            isFalse,
            reason: '${group.name}: ${symbol.preview} did not render',
          );
        }
      }
    });

    testWidgets('reaches the integrals in Calculus at the block width',
        (tester) async {
      var latex = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 420,
                child: MathSourceEditor(
                  latex: '',
                  showLabel: false,
                  autofocus: false,
                  onChanged: (value) => latex = value,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Calculus'));
      await tester.pumpAndSettle();

      // Every symbol in the group has to be reachable, outright or by
      // scrolling — a palette that hides its later rows is a palette that
      // loses them.
      final scroll = find.descendant(
        of: find.byType(Scrollbar),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scroll, findsOneWidget);

      final integral = find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip && (widget.message ?? '').startsWith(r'\int '),
      );
      expect(integral, findsWidgets);
      // A symbol must not claim a whole row, or the later ones fall below the
      // palette and cannot be reached at all.
      final chip = tester.getRect(integral.first);
      expect(chip.width, lessThan(80));
      expect(tester.getRect(scroll).contains(chip.center), isTrue);

      await tester.tap(integral.first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(latex, contains(r'\int'));
    });
  });

  group('the equation box', () {
    Widget wrap({
      double? height,
      ValueChanged<double>? onResize,
      ValueChanged<double>? onResizeHeight,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 900,
                child: ResizableMedia(
                  width: 420,
                  minWidth: 300,
                  height: height,
                  minHeight: 110,
                  onResize: onResize ?? (_) {},
                  onResizeHeight: onResizeHeight,
                  child: const SizedBox(height: 90),
                ),
              ),
            ),
          ),
        );

    testWidgets('takes the width it is given and can be dragged wider',
        (tester) async {
      double? resized;
      await tester.pumpWidget(wrap(onResize: (value) => resized = value));

      // The equation is a small object on the page, not a full-width banner.
      final box = find.byKey(const ValueKey('resizable_media'));
      expect(tester.getSize(box).width, 420);

      await tester.hover(box);
      await tester.pump();
      final handle = find.byKey(const ValueKey('resizable_media_right_handle'));
      expect(handle, findsOneWidget);

      await tester.drag(handle, const Offset(60, 0));
      await tester.pump();
      expect(resized, isNotNull);
      expect(resized, greaterThan(420));
    });

    testWidgets('offers corner grips that size both edges at once',
        (tester) async {
      double? width;
      double? height;
      await tester.pumpWidget(
        wrap(
          onResize: (value) => width = value,
          onResizeHeight: (value) => height = value,
        ),
      );

      final box = find.byKey(const ValueKey('resizable_media'));
      await tester.hover(box);
      await tester.pump();

      final corner = find.byKey(
        const ValueKey('resizable_media_bottom_right_handle'),
      );
      expect(corner, findsOneWidget);

      await tester.drag(corner, const Offset(50, 40));
      await tester.pump();
      expect(width, greaterThan(420));
      expect(height, greaterThan(90));
    });
  });
}

extension on WidgetTester {
  Future<void> hover(Finder finder) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await sendEventToBinding(pointer.hover(getCenter(finder)));
  }
}
