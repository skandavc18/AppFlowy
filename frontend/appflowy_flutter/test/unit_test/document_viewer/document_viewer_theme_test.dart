import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _sample = DocumentViewerTheme(
  mode: DocumentViewerMode.light,
  canvas: Color(0xFFF4F4F6),
  canvasEdge: Color(0xFFEDEDF0),
  page: Color(0xFFFDFDFE),
  pageBorder: Color(0x0F0F172A),
  chrome: Color(0xF5FCFCFD),
  chromeBorder: Color(0x140F172A),
  control: Color(0x080F172A),
  controlHover: Color(0x0F0F172A),
  controlPressed: Color(0x1A0F172A),
  controlSelected: Color(0x1F0F172A),
  hairline: Color(0x0F0F172A),
  divider: Color(0x160F172A),
  textPrimary: Color(0xFF15181D),
  textSecondary: Color(0xFF585F6B),
  textMuted: Color(0xFF8A919C),
  icon: Color(0xFF4E5561),
  iconMuted: Color(0xFF9AA0AA),
  accent: Color(0xFF2C6BD6),
  accentSoft: Color(0x1F2C6BD6),
  onAccent: Color(0xFFFFFFFF),
  codeSurface: Color(0xFFF6F6F8),
  codeBorder: Color(0x120F172A),
  quoteBar: Color(0x1F0F172A),
  selection: Color(0x332C6BD6),
  scrollThumb: Color(0x520F172A),
  pageShadow: [],
  floatShadow: [],
  shellShadow: [],
  scrim: Color(0x8A1D2230),
);

Future<DocumentViewerTheme> _resolve(
  WidgetTester tester, {
  required AppTheme appTheme,
  required Brightness brightness,
}) async {
  late DocumentViewerTheme resolved;
  await tester.pumpWidget(
    MaterialApp(
      // Resolve the requested appearance immediately instead of animating.
      themeAnimationDuration: Duration.zero,
      theme: DesktopAppearance().getThemeData(
        appTheme,
        brightness,
        defaultFontFamily,
        builtInCodeFontFamily,
      ),
      home: Builder(
        builder: (context) {
          resolved = DocumentViewerTheme.resolve(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return resolved;
}

void main() {
  // Typography must resolve from bundled faces; never reach the network.
  GoogleFonts.config.allowRuntimeFetching = false;

  final paperTheme = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );

  group('DocumentViewerTheme', () {
    testWidgets('resolves an intentional palette per appearance',
        (tester) async {
      final dark = await _resolve(
        tester,
        appTheme: AppTheme.fallback,
        brightness: Brightness.dark,
      );
      final light = await _resolve(
        tester,
        appTheme: AppTheme.fallback,
        brightness: Brightness.light,
      );
      final paper = await _resolve(
        tester,
        appTheme: paperTheme,
        brightness: Brightness.light,
      );

      expect(dark.mode, DocumentViewerMode.dark);
      expect(light.mode, DocumentViewerMode.light);
      expect(paper.mode, DocumentViewerMode.paper);

      // Three distinct canvases: no appearance reuses another's surfaces.
      expect(dark.canvas, isNot(light.canvas));
      expect(light.canvas, isNot(paper.canvas));
      expect(dark.page, isNot(light.page));
      expect(light.page, isNot(paper.page));
    });

    testWidgets('paper keeps warm stationery surfaces', (tester) async {
      final paper = await _resolve(
        tester,
        appTheme: paperTheme,
        brightness: Brightness.light,
      );

      expect(paper.isPaper, isTrue);
      expect(paper.canvas, PaperTheme.editorBackground);
      expect(paper.accent, PaperTheme.accent);
      // Warm means red >= green >= blue, and never a cold pure white.
      for (final surface in [paper.canvas, paper.page, paper.chrome]) {
        expect(surface.r, greaterThanOrEqualTo(surface.g));
        expect(surface.g, greaterThanOrEqualTo(surface.b));
        expect(surface, isNot(const Color(0xFFFFFFFF)));
      }
    });

    testWidgets('dark stays a deep neutral with a lifted page', (tester) async {
      final dark = await _resolve(
        tester,
        appTheme: AppTheme.fallback,
        brightness: Brightness.dark,
      );

      expect(dark.isDark, isTrue);
      expect(dark.brightness, Brightness.dark);
      // The reading page sits above the canvas, as in Arc and Cursor.
      expect(dark.page.r, greaterThan(dark.canvas.r));
      expect(dark.pageShadow, isNotEmpty);
    });

    testWidgets('light reads as Apple Preview: quiet canvas, crisp page',
        (tester) async {
      final light = await _resolve(
        tester,
        appTheme: AppTheme.fallback,
        brightness: Brightness.light,
      );

      expect(light.page.r, greaterThan(light.canvas.r));
      // Borders are hairlines, never structural lines.
      expect(light.hairline.a, lessThan(0.2));
      expect(light.pageBorder.a, lessThan(0.2));
    });

    testWidgets('an installed scope wins over the ambient appearance',
        (tester) async {
      late DocumentViewerTheme resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: DesktopAppearance().getThemeData(
            AppTheme.fallback,
            Brightness.light,
            defaultFontFamily,
            builtInCodeFontFamily,
          ),
          home: DocumentViewerThemeScope(
            theme: _sample.copyWith(canvas: const Color(0xFF123456)),
            child: Builder(
              builder: (context) {
                resolved = DocumentViewerTheme.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(resolved.canvas, const Color(0xFF123456));
    });

    test('lerp keeps a valid palette at both ends', () {
      final other = _sample.copyWith(canvas: const Color(0xFF000000));

      expect(_sample.lerp(other, 0).canvas, _sample.canvas);
      expect(_sample.lerp(other, 1).canvas, other.canvas);
      expect(_sample.lerp(null, 0.5), same(_sample));
    });
  });

  group('DocumentTypography', () {
    // The bundled code face keeps the scale resolvable without a network.
    DocumentTypography resolve({double scale = 1}) =>
        DocumentTypography.resolve(
          _sample,
          scale: scale,
          monoFamily: builtInCodeFontFamily,
        );

    test('builds a reading-first scale that grows with zoom', () {
      final base = resolve();
      final zoomed = resolve(scale: 1.5);

      // Generous, comfortable measure for long-form reading.
      expect(base.body.height, greaterThanOrEqualTo(1.6));
      expect(base.body.fontSize, 16);
      expect(zoomed.body.fontSize, 24);
      expect(zoomed.code.fontSize, base.code.fontSize! * 1.5);

      // Headings never grow as the level increases.
      final sizes = [
        for (var level = 1; level <= 6; level++)
          base.headingFor(level).fontSize!,
      ];
      for (var index = 1; index < sizes.length; index++) {
        expect(sizes[index], lessThanOrEqualTo(sizes[index - 1]));
      }
      expect(sizes.first, greaterThan(base.body.fontSize!));
    });

    test('gives headings room above and beneath', () {
      final typography = resolve();
      for (var level = 2; level <= 6; level++) {
        expect(typography.spaceAboveHeading(level), greaterThan(0));
        expect(typography.spaceBelowHeading(level), greaterThan(0));
      }
      // A section break breathes more than a minor heading.
      expect(
        typography.spaceAboveHeading(2),
        greaterThan(typography.spaceAboveHeading(5)),
      );
    });
  });

  group('document geometry', () {
    test('reading measure and chrome stay desktop-first', () {
      expect(DocumentViewerTheme.readingWidth, 720);
      expect(
        DocumentViewerTheme.wideReadingWidth,
        greaterThan(DocumentViewerTheme.readingWidth),
      );
      expect(DocumentViewerTheme.readingPadding.left, greaterThan(32));
      expect(DocumentViewerTheme.chromeHeight, lessThanOrEqualTo(48));
      expect(DocumentViewerTheme.controlSize, 28);
    });
  });
}
