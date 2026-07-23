import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/time/duration.dart';
import 'package:flowy_infra_ui/src/flowy_overlay/flowy_dialog.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flowy_infra_ui/widget/dialog/styled_dialogs.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop motion stays restrained and non-bouncy', () {
    expect(AppFlowyMotion.instant, const Duration(milliseconds: 90));
    expect(AppFlowyMotion.fast, const Duration(milliseconds: 140));
    expect(AppFlowyMotion.standard, const Duration(milliseconds: 160));
    expect(AppFlowyMotion.gentle, const Duration(milliseconds: 180));
    expect(AppFlowyMotion.deliberate, const Duration(milliseconds: 240));
    expect(FlowyDurations.fastest, AppFlowyMotion.fast);
    expect(FlowyDurations.fast, AppFlowyMotion.standard);
    expect(FlowyDurations.medium, AppFlowyMotion.gentle);
    expect(FlowyDurations.slow, AppFlowyMotion.deliberate);
  });

  test('legacy dialog route uses the refined transition duration', () {
    final route = StyledDialogRoute<void>(
      pageBuilder: (_, __, ___) => const SizedBox.shrink(),
      barrier: DialogBarrier(),
    );

    expect(route.transitionDuration, AppFlowyMotion.gentle);
  });

  testWidgets('AppFlowy buttons are low profile with animated hover',
      (tester) async {
    late AppFlowyThemeData appFlowyTheme;
    await tester.pumpWidget(
      _testApp(
        builder: (context, theme) {
          appFlowyTheme = theme;
          return Center(
            child: AFGhostButton.normal(
              onTap: () {},
              builder: (_, __, ___) => const SizedBox.square(dimension: 12),
            ),
          );
        },
      ),
    );

    final button = find.byType(AFGhostButton);
    expect(tester.getSize(button).height, lessThanOrEqualTo(32));
    final containers = tester
        .widgetList<AnimatedContainer>(
          find.descendant(of: button, matching: find.byType(AnimatedContainer)),
        )
        .toList();
    expect(containers, hasLength(2));
    expect(
      containers
          .every((container) => container.duration == AppFlowyMotion.fast),
      isTrue,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(button));
    await tester.pump(AppFlowyMotion.fast);

    final hoveredContainers = tester
        .widgetList<AnimatedContainer>(
          find.descendant(of: button, matching: find.byType(AnimatedContainer)),
        )
        .toList();
    final innerDecoration = hoveredContainers.last.decoration! as BoxDecoration;
    expect(innerDecoration.color, appFlowyTheme.fillColorScheme.contentHover);
    expect(innerDecoration.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('AppFlowy fields own precise local styling', (tester) async {
    late AppFlowyThemeData appFlowyTheme;
    await tester.pumpWidget(
      _testApp(
        builder: (context, theme) {
          appFlowyTheme = theme;
          return const Center(
            child: SizedBox(width: 240, child: AFTextField()),
          );
        },
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final decoration = field.decoration!;
    final border = decoration.enabledBorder! as OutlineInputBorder;
    final focusedBorder = decoration.focusedBorder! as OutlineInputBorder;
    expect(decoration.filled, isTrue);
    expect(decoration.fillColor, appFlowyTheme.surfaceColorScheme.layer01);
    expect(border.borderRadius, BorderRadius.circular(10));
    expect(border.borderSide.width, 0.6);
    expect(focusedBorder.borderSide.width, 1);
  });

  testWidgets('legacy hover and tooltip geometry is compact', (tester) async {
    await tester.pumpWidget(
      _testApp(
        builder: (_, __) => const Center(
          child: FlowyTooltip(
            message: 'Compact tooltip',
            child: FlowyHover(child: SizedBox.square(dimension: 24)),
          ),
        ),
      ),
    );

    final hoverContainer = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(FlowyHover),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final hoverDecoration = hoverContainer.decoration! as BoxDecoration;
    expect(hoverContainer.duration, AppFlowyMotion.fast);
    expect(hoverDecoration.borderRadius, BorderRadius.circular(8));

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    final tooltipDecoration = tooltip.decoration! as BoxDecoration;
    expect(
      tooltip.padding,
      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
    expect(tooltipDecoration.borderRadius, BorderRadius.circular(8));
    expect(tooltip.textStyle?.fontSize, 12);
  });

  testWidgets('FlowyDialog bypasses Material elevation', (tester) async {
    await tester.pumpWidget(
      _testApp(
        builder: (_, __) => const FlowyDialog(
          width: 400,
          expandHeight: false,
          child: SizedBox(height: 120),
        ),
      ),
    );

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.elevation, 0);
    expect(dialog.backgroundColor, Colors.transparent);
    expect(dialog.surfaceTintColor, Colors.transparent);
  });
}

Widget _testApp({
  required Widget Function(BuildContext context, AppFlowyThemeData theme)
      builder,
}) {
  final materialTheme = DesktopAppearance().getThemeData(
    AppTheme.fallback,
    Brightness.light,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final palette = materialTheme.extension<PremiumThemeExtension>()!;
  final appFlowyTheme = PremiumTheme.appFlowyTheme(
    base: AppFlowyDefaultTheme().light(),
    palette: palette,
    brightness: Brightness.light,
  );

  return MaterialApp(
    theme: materialTheme,
    home: AppFlowyTheme(
      data: appFlowyTheme,
      child: Scaffold(
        body: Builder(
          builder: (context) => builder(context, appFlowyTheme),
        ),
      ),
    ),
  );
}
