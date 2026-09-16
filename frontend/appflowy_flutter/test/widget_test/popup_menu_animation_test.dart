import 'package:appflowy/shared/popup_menu/appflowy_popup_menu.dart' as popup;
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final appearance in ['light', 'dark', 'paper']) {
    for (final style in <String, AnimationStyle?>{
      'default': null,
      'undershoot': AnimationStyle(
        curve: Curves.easeInBack,
        reverseCurve: Curves.easeInBack,
      ),
      'overshoot': AnimationStyle(
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeOutBack,
      ),
      'no animation': AnimationStyle.noAnimation,
    }.entries) {
      testWidgets('$appearance ${style.key}: every popup frame is bounded',
          (tester) async {
        int? selected;
        await tester.pumpWidget(
          _app(
            appearance,
            popup.PopupMenuButton<int>(
              popUpAnimationStyle: style.value,
              onSelected: (value) => selected = value,
              itemBuilder: (_) => const [
                popup.PopupMenuItem(value: 1, child: Text('First item')),
                popup.PopupMenuItem(value: 2, child: Text('Second item')),
              ],
              child: const Text('Open menu'),
            ),
          ),
        );
        await tester.tap(find.text('Open menu'));
        await tester.pump();
        await _checkFrames(tester);
        expect(find.text('Second item').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Second item'));
        await tester.pump();
        await _checkFrames(tester);
        expect(selected, 2);
        expect(find.text('Second item'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.binding.transientCallbackCount, 0);
      });
    }
  }
}

Future<void> _checkFrames(WidgetTester tester) async {
  // pumpAndSettle's default 100ms step skips the invalid first frames that
  // a real high-refresh Windows engine encounters.
  for (var frame = 0; frame < 24; frame++) {
    await tester.pump(const Duration(milliseconds: 8));
    expect(tester.takeException(), isNull);
    for (final fade in tester.widgetList<FadeTransition>(
      find.byType(FadeTransition, skipOffstage: false),
    )) {
      expect(fade.opacity.value, inInclusiveRange(0, 1));
    }
  }
}

Widget _app(String appearance, Widget child) => MaterialApp(
      theme: DesktopAppearance().getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        appearance == 'dark' ? Brightness.dark : Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(body: Center(child: child)),
    );
