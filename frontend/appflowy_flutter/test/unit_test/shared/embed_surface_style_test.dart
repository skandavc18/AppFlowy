import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
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

    // A single, wide, downward shadow — the page preview card recipe.
    expect(light.rest, hasLength(1));
    final shadow = light.rest.single;
    expect(shadow.blurRadius, greaterThanOrEqualTo(20));
    expect(shadow.offset.dy, greaterThan(0));
    expect(shadow.spreadRadius, lessThan(0));
    expect(shadow.color.a, lessThan(0.15));

    // Hovering deepens rather than changes character.
    expect(light.raised.single.blurRadius, greaterThan(shadow.blurRadius));
    expect(light.raised.single.offset.dy, greaterThan(shadow.offset.dy));
    expect(light.raised.single.color.a, greaterThan(shadow.color.a));
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
    expect(dark.rest.single.color.a, greaterThan(light.rest.single.color.a));
  });

  testWidgets('paper keeps its warm shadow', (tester) async {
    final paper = await _resolve(
      tester,
      appTheme: paperTheme,
      brightness: Brightness.light,
    );

    expect(paper.rest.single.color.r, greaterThan(paper.rest.single.color.b));
    expect(paper.border.r, greaterThan(paper.border.b));
    expect(paper.rest.single.color, isNot(const Color(0xFF000000)));
    // Derived from the shared paper stationery tone.
    expect(paper.rest.single.color.r, closeTo(PaperTheme.shadow.r, 0.001));
  });
}
