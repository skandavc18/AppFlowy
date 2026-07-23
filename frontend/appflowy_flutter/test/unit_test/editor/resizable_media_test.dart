import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clamps media to its available width and resizes from the edge',
      (tester) async {
    double? resizedWidth;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 500,
            child: ResizableMedia(
              width: defaultVisualMediaWidth,
              onResize: (width) => resizedWidth = width,
              child: const AspectRatio(
                aspectRatio: 16 / 9,
                child: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('resizable_media'))).width,
      500,
    );

    await tester.drag(
      find.byKey(const ValueKey('resizable_media_right_handle')),
      const Offset(-100, 0),
    );
    await tester.pump();

    expect(resizedWidth, lessThan(500));
    expect(
      tester.getSize(find.byKey(const ValueKey('resizable_media'))).width,
      resizedWidth,
    );
  });

  testWidgets('resizes intrinsic height from an in-frame bottom handle', (
    tester,
  ) async {
    double? resizedHeight;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 500,
            child: ResizableMedia(
              width: 420,
              onResize: (_) {},
              onResizeHeight: (height) => resizedHeight = height,
              child: const SizedBox(
                height: 220,
                child: ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );

    final media = find.byKey(const ValueKey('resizable_media'));
    final bottomHandle =
        find.byKey(const ValueKey('resizable_media_bottom_handle'));
    expect(tester.getSize(media).height, 220);
    expect(
      tester.getRect(media).contains(tester.getCenter(bottomHandle)),
      isTrue,
    );

    await tester.drag(bottomHandle, const Offset(0, 80));
    await tester.pump();

    expect(resizedHeight, greaterThan(220));
    expect(tester.getSize(media).height, resizedHeight);
  });

  testWidgets('shrinks height upward despite a competing vertical drag', (
    tester,
  ) async {
    var height = 420.0;
    var ancestorDragUpdates = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (_) => ancestorDragUpdates++,
          child: Center(
            child: SizedBox(
              width: 520,
              child: StatefulBuilder(
                builder: (context, setState) => ResizableMedia(
                  width: 460,
                  height: height,
                  minHeight: 140,
                  onResize: (_) {},
                  onResizeHeight: (value) => setState(() => height = value),
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final media = find.byKey(const ValueKey('resizable_media'));
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('resizable_media_bottom_handle')),
      ),
    );
    await gesture.moveBy(const Offset(0, -120));
    await gesture.up();
    await tester.pump();

    expect(height, closeTo(300, 1));
    expect(tester.getSize(media).height, closeTo(300, 1));
    expect(ancestorDragUpdates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizes width and height from the bottom-right corner', (
    tester,
  ) async {
    var width = 460.0;
    var height = 380.0;
    var ancestorPanUpdates = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (_) => ancestorPanUpdates++,
          child: Center(
            child: SizedBox(
              width: 600,
              child: StatefulBuilder(
                builder: (context, setState) => ResizableMedia(
                  width: width,
                  height: height,
                  minWidth: 320,
                  minHeight: 140,
                  onResize: (value) => setState(() => width = value),
                  onResizeHeight: (value) => setState(() => height = value),
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final media = find.byKey(const ValueKey('resizable_media'));
    await tester.drag(
      find.byKey(const ValueKey('resizable_media_bottom_right_handle')),
      const Offset(-60, -90),
    );
    await tester.pump();

    expect(width, closeTo(340, 1));
    expect(height, closeTo(290, 1));
    expect(tester.getSize(media), const Size(340, 290));
    expect(ancestorPanUpdates, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active height tightly constrains the resized child', (
    tester,
  ) async {
    BoxConstraints? childConstraints;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ResizableMedia(
            width: 460,
            height: 180,
            minHeight: 140,
            onResize: (_) {},
            onResizeHeight: (_) {},
            child: LayoutBuilder(
              builder: (context, constraints) {
                childConstraints = constraints;
                return const SizedBox(height: 640);
              },
            ),
          ),
        ),
      ),
    );

    expect(childConstraints?.hasTightHeight, isTrue);
    expect(childConstraints?.maxHeight, 180);
    expect(
      tester.getSize(find.byKey(const ValueKey('resizable_media'))).height,
      180,
    );
    expect(tester.takeException(), isNull);
  });
}
