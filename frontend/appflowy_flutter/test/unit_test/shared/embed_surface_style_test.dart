import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _EmbedStyle = ({
  Color border,
  List<BoxShadow> rest,
  List<BoxShadow> raised
});

Future<_EmbedStyle> _resolve(
  WidgetTester tester, {
  required AppTheme appTheme,
  required Brightness brightness,
}) async {
  late _EmbedStyle style;
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: DesktopAppearance().getThemeData(
        appTheme,
        brightness,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: Builder(
        builder: (context) {
          style = (
            border: EditorSurfaceStyle.embedBorder(context),
            rest: EditorSurfaceStyle.embedShadow(context),
            raised: EditorSurfaceStyle.embedShadow(context, raised: true),
          );
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return style;
}

void main() {
  final paperTheme = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );

  test('embedded blocks share one generously rounded geometry', () {
    expect(EditorSurfaceStyle.embedCornerRadius, 20);
    expect(
      EditorSurfaceStyle.embedBorderRadius,
      BorderRadius.circular(EditorSurfaceStyle.embedCornerRadius),
    );
    // Code blocks are framed exactly like every other embedded document.
    expect(codeBlockCornerRadius, EditorSurfaceStyle.embedCornerRadius);
  });

  testWidgets('depth is soft and lifted, never a hard edge', (tester) async {
    final light = await _resolve(
      tester,
      appTheme: AppTheme.fallback,
      brightness: Brightness.light,
    );

    // Ambient height plus a tight contact shadow — the page preview card
    // recipe, with no outline anywhere in it.
    expect(light.rest, hasLength(2));
    final shadow = light.rest.first;
    expect(shadow.blurRadius, greaterThanOrEqualTo(20));
    expect(shadow.offset.dy, greaterThan(0));
    expect(shadow.spreadRadius, lessThan(0));
    expect(shadow.color.a, lessThan(0.15));

    final contact = light.rest.last;
    expect(contact.blurRadius, lessThan(shadow.blurRadius));
    expect(contact.color.a, lessThan(shadow.color.a));

    // Hovering deepens rather than changes character.
    expect(light.raised.first.blurRadius, greaterThan(shadow.blurRadius));
    expect(light.raised.first.offset.dy, greaterThan(shadow.offset.dy));
    expect(light.raised.first.color.a, greaterThan(shadow.color.a));
  });

  testWidgets('borders recede so the shadow defines the card', (tester) async {
    final light = await _resolve(
      tester,
      appTheme: AppTheme.fallback,
      brightness: Brightness.light,
    );
    final dark = await _resolve(
      tester,
      appTheme: AppTheme.fallback,
      brightness: Brightness.dark,
    );

    expect(light.border.a, closeTo(0.38, 0.001));
    expect(dark.border.a, closeTo(0.38, 0.001));
    // Dark surfaces need a touch more shadow to read as lifted.
    expect(dark.rest.first.color.a, greaterThan(light.rest.first.color.a));
    // A black contact shadow would vanish on a dark canvas, so the card is
    // edged by a whisper of light instead.
    final darkRim = dark.rest.last;
    expect(darkRim.color.r, 1);
    expect(darkRim.color.a, lessThan(0.12));
    expect(darkRim.spreadRadius, greaterThan(0));
    expect(dark.raised.last.color.a, greaterThan(darkRim.color.a));
  });

  testWidgets('paper keeps its warm shadow', (tester) async {
    final paper = await _resolve(
      tester,
      appTheme: paperTheme,
      brightness: Brightness.light,
    );

    expect(paper.rest.first.color.r, greaterThan(paper.rest.first.color.b));
    expect(paper.border.r, greaterThan(paper.border.b));
    expect(paper.rest.first.color, isNot(const Color(0xFF000000)));
    // Derived from the shared paper stationery tone.
    expect(paper.rest.first.color.r, closeTo(PaperTheme.shadow.r, 0.001));
  });

  group('ViewerCard', () {
    BoxDecoration decorationOf(WidgetTester tester) {
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(ViewerCard),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return container.decoration! as BoxDecoration;
    }

    for (final appearance in [
      (label: 'light', theme: AppTheme.fallback, brightness: Brightness.light),
      (label: 'dark', theme: AppTheme.fallback, brightness: Brightness.dark),
      (label: 'paper', theme: paperTheme, brightness: Brightness.light),
    ]) {
      testWidgets('is borderless and softly rounded in ${appearance.label}', (
        tester,
      ) async {
        await tester.pumpWidget(
          _cardApp(
            appTheme: appearance.theme,
            brightness: appearance.brightness,
            card: const ViewerCard(child: SizedBox(width: 200, height: 120)),
          ),
        );

        final decoration = decorationOf(tester);
        expect(decoration.border, isNull);
        expect(decoration.borderRadius, EditorSurfaceStyle.embedBorderRadius);
        expect(decoration.boxShadow, isNotEmpty);
      });
    }

    testWidgets('lifts a little further under the pointer', (tester) async {
      await tester.pumpWidget(
        _cardApp(
          appTheme: AppTheme.fallback,
          brightness: Brightness.light,
          card: const ViewerCard(child: SizedBox(width: 200, height: 120)),
        ),
      );

      final resting = decorationOf(tester).boxShadow!.first;

      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer();
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(find.byType(ViewerCard)));
      await tester.pumpAndSettle();

      final hovered = decorationOf(tester).boxShadow!.first;
      expect(hovered.blurRadius, greaterThan(resting.blurRadius));
      expect(hovered.color.a, greaterThan(resting.color.a));
      expect(decorationOf(tester).border, isNull);
    });

    testWidgets('a flush card carries no depth of its own', (tester) async {
      await tester.pumpWidget(
        _cardApp(
          appTheme: AppTheme.fallback,
          brightness: Brightness.light,
          card: const ViewerCard(
            elevation: ViewerCardElevation.flush,
            child: SizedBox(width: 200, height: 120),
          ),
        ),
      );

      expect(decorationOf(tester).boxShadow, isEmpty);
    });
  });
}

Widget _cardApp({
  required AppTheme appTheme,
  required Brightness brightness,
  required Widget card,
}) {
  return MaterialApp(
    themeAnimationDuration: Duration.zero,
    theme: DesktopAppearance().getThemeData(
      appTheme,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    ),
    home: Scaffold(body: Center(child: card)),
  );
}
