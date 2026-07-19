import 'package:appflowy/plugins/database/grid/presentation/widgets/header/desktop_field_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/desktop_grid_text_cell.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary grid page titles use stronger typography', (
    tester,
  ) async {
    late TextStyle primaryStyle;
    late TextStyle regularStyle;
    late TextStyle themedBodyStyle;

    await tester.pumpWidget(
      MaterialApp(
        theme: DesktopAppearance().getThemeData(
          AppTheme.fallback,
          Brightness.light,
          preferredFontFamily,
          builtInCodeFontFamily,
        ),
        home: Builder(
          builder: (context) {
            themedBodyStyle = Theme.of(context).textTheme.bodyMedium!;
            primaryStyle = DesktopGridTextCellStyle.resolve(
              context,
              isPrimary: true,
            );
            regularStyle = DesktopGridTextCellStyle.resolve(
              context,
              isPrimary: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    expect(primaryStyle.fontSize, 16);
    expect(primaryStyle.fontWeight, FontWeight.w600);
    expect(primaryStyle.color, Colors.black);
    expect(
      primaryStyle.fontVariations,
      const [FontVariation.weight(600)],
    );
    expect(regularStyle, themedBodyStyle);
  });

  testWidgets('grid column names use larger high-contrast typography', (
    tester,
  ) async {
    late Color color;
    late Color strongColor;

    await tester.pumpWidget(
      MaterialApp(
        theme: DesktopAppearance().getThemeData(
          AppTheme.fallback,
          Brightness.light,
          preferredFontFamily,
          builtInCodeFontFamily,
        ),
        home: Builder(
          builder: (context) {
            color = DesktopGridHeaderStyle.fieldNameColor(context);
            strongColor = AFThemeExtension.of(context).strongText;
            return const SizedBox();
          },
        ),
      ),
    );

    expect(DesktopGridHeaderStyle.fieldNameFontSize, 15);
    expect(DesktopGridHeaderStyle.fieldNameFontWeight, FontWeight.w600);
    expect(color, strongColor);
  });
}
