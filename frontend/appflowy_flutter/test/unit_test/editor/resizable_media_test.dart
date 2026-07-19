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
}
