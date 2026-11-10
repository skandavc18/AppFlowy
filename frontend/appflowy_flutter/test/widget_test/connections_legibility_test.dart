import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/settings/pages/connections/connections_chrome.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// GitHub's brand accent is almost black, so its "Connect a GitHub account"
/// button disappeared on the dark settings page. Every family's button and
/// glyph has to read in every theme, measured on the rendered pixels.
void main() {
  final paper = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );

  for (final mode in const ['light', 'dark', 'paper']) {
    testWidgets('connection buttons and glyphs read in $mode', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.binding.setSurfaceSize(const Size(640, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final theme = DesktopAppearance().getThemeData(
        mode == 'paper' ? paper : AppTheme.fallback,
        mode == 'dark' ? Brightness.dark : Brightness.light,
        'Ahem',
        builtInCodeFontFamily,
      );
      late FolderExplorerPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Builder(
            builder: (context) {
              palette = FolderExplorerPalette.of(context);
              return ColoredBox(
                color: palette.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final family in ProviderAccountFamily.values)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            ConnectionGlyph(
                              icon: family.icon,
                              accent: family.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ConnectionAddButton(
                                palette: palette,
                                label: 'Connect ${family.label}',
                                accent: family.accent,
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(textContrastGuideline));

      final glyphs = find.byType(ConnectionGlyph);
      expect(glyphs, findsNWidgets(ProviderAccountFamily.values.length));
      for (final glyph in glyphs.evaluate()) {
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byWidget(glyph.widget),
            matching: find.byType(Icon),
          ),
        );
        final tile = tester.widget<Container>(
          find.descendant(
            of: find.byWidget(glyph.widget),
            matching: find.byType(Container),
          ),
        );
        final fill = Color.alphaBlend(
          (tile.decoration! as BoxDecoration).color!,
          palette.surface,
        );
        expect(
          LegibleColor.contrast(icon.color!, fill),
          greaterThanOrEqualTo(LegibleColor.text),
          reason: '${(glyph.widget as ConnectionGlyph).icon} in $mode',
        );
      }
      semantics.dispose();
    });
  }
}
