import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('popover captures inherited themes from its trigger',
      (tester) async {
    final controller = PopoverController();
    const popupKey = ValueKey('themed-popup');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: const ColorScheme.light(primary: Colors.blue),
        ),
        home: Scaffold(
          body: Theme(
            data: ThemeData(
              colorScheme: const ColorScheme.light(primary: Colors.red),
            ),
            child: Popover(
              controller: controller,
              animationDuration: Duration.zero,
              direction: PopoverDirection.bottomWithLeftAligned,
              popupBuilder: (context) => ColoredBox(
                key: popupKey,
                color: Theme.of(context).colorScheme.primary,
                child: const SizedBox.square(dimension: 20),
              ),
              child: const SizedBox.square(dimension: 20),
            ),
          ),
        ),
      ),
    );

    controller.show();
    await tester.pump();

    final popup = tester.widget<ColoredBox>(find.byKey(popupKey));
    expect(popup.color, Colors.red);

    controller.close();
    await tester.pump();
  });
}
