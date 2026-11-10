import 'package:appflowy/plugins/document/presentation/editor_plugins/cover/cover_ink.dart';
import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Visibility fixes that hold in every theme without needing the backend.
void main() {
  group('FlowyTextButton', () {
    // The app theme gives every text button a see-through side, for its focus
    // ring. That replaced the border a button asked for, so the plan page's
    // outlined "Add" read as loose text on light and paper.
    testWidgets('keeps an explicit border under the app theme', (
      tester,
    ) async {
      const purple = Color(0xFF5C3699);
      await tester.pumpWidget(
        MaterialApp(
          theme: DesktopAppearance().getThemeData(
            AppTheme.fallback,
            Brightness.light,
            'Ahem',
            builtInCodeFontFamily,
          ),
          home: Scaffold(
            body: Center(
              child: FlowyTextButton(
                'Add',
                fillColor: Colors.transparent,
                borderColor: purple,
                fontColor: purple,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      final material = tester.widget<Material>(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(Material),
        ),
      );
      final shape = material.shape! as OutlinedBorder;
      expect(shape.side.color, purple);
      expect(shape.side.style, BorderStyle.solid);
    });
  });

  group('CoverInk', () {
    Future<BuildContext> contextIn(WidgetTester tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return captured;
    }

    testWidgets('leaves the theme ink alone without a cover', (tester) async {
      final context = await contextIn(tester);
      expect(CoverInk.over(context, const PageStyleCover.none()), isNull);
      expect(CoverInk.button(context, null), isNull);
    });

    testWidgets('sets white over a shade on photographs', (tester) async {
      final context = await contextIn(tester);
      for (final cover in const [
        PageStyleCover(type: PageStyleCoverImageType.builtInImage, value: 'n2'),
        PageStyleCover(
          type: PageStyleCoverImageType.unsplashImage,
          value: 'https://images.unsplash.com/photo',
        ),
      ]) {
        final button = CoverInk.button(context, cover)!;
        expect(button.ink, Colors.white);
        expect(button.disc.computeLuminance(), lessThan(0.05));
      }
    });

    testWidgets('keeps dark ink on the light abstract artwork', (tester) async {
      final context = await contextIn(tester);
      const cover = PageStyleCover(
        type: PageStyleCoverImageType.builtInImage,
        value: '3',
      );
      final button = CoverInk.button(context, cover)!;
      expect(button.ink, CoverInk.dark);
      expect(button.disc.computeLuminance(), greaterThan(0.9));
    });

    testWidgets('picks the ink that reads on a plain colour', (tester) async {
      final context = await contextIn(tester);
      for (final (fill, ink) in const [
        ('0xFF1F2937', Colors.white),
        ('0xFFF5EBD7', CoverInk.dark),
      ]) {
        final cover = PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: fill,
        );
        final chosen = CoverInk.over(context, cover)!;
        expect(chosen, ink);
        expect(
          LegibleColor.contrast(chosen, Color(int.parse(fill))),
          greaterThanOrEqualTo(LegibleColor.text),
        );
      }
    });
  });
}
