import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_theme.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final appearance in [
    (name: 'light', brightness: Brightness.light, paper: false),
    (name: 'dark', brightness: Brightness.dark, paper: false),
    (name: 'paper', brightness: Brightness.light, paper: true),
  ]) {
    group('${appearance.name} spreadsheet pixels', () {
      Future<void> withPainter(
        WidgetTester tester,
        Future<void> Function(_PainterFixture fixture) body,
      ) async {
        late _PainterFixture fixture;
        await tester.pumpWidget(
          MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: ThemeData(
              brightness: appearance.brightness,
              extensions: [PaperThemeExtension(enabled: appearance.paper)],
            ),
            home: Builder(
              builder: (context) {
                final palette = SpreadsheetPalette.of(context);
                fixture = _PainterFixture(
                  palette,
                  SpreadsheetTypography.of(context, palette),
                );
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        try {
          await body(fixture);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      }

      testWidgets('every unformatted resting row has the exact same surface',
          (tester) async {
        await withPainter(tester, (fixture) async {
          final pixels = await _paint(tester, fixture.painter());
          for (var row = 0; row < 7; row++) {
            for (var column = 0; column < 4; column++) {
              _expectColor(pixels.cell(row, column), fixture.palette.surface);
            }
          }
          expect(fixture.palette.bandedSurface, fixture.palette.surface);
          expect(fixture.palette.headerSurface, fixture.palette.surface);
          expect(fixture.palette.gutterSurface, fixture.palette.surface);
          if (appearance.paper) {
            expect(fixture.palette.surface, PaperTheme.editorBackground);
            expect(
              fixture.palette.surface.r,
              greaterThan(fixture.palette.surface.b),
            );
          }
        });
      });

      testWidgets('a gutter row hover cannot shade the body', (tester) async {
        await withPainter(tester, (fixture) async {
          fixture.controller.setHoveredRow(2);
          final pixels = await _paint(tester, fixture.painter());
          for (var row = 1; row <= 3; row++) {
            for (var column = 0; column < 4; column++) {
              _expectColor(pixels.cell(row, column), fixture.palette.surface);
            }
          }
        });
      });

      testWidgets('hover blends once in one cell, never across its row',
          (tester) async {
        await withPainter(tester, (fixture) async {
          fixture.controller.setHoveredRow(2);
          final pixels = await _paint(
            tester,
            fixture.painter(hoveredCell: const CellRef(2, 1)),
          );
          final hovered =
              Color.alphaBlend(fixture.palette.hover, fixture.palette.surface);
          _expectColor(pixels.cell(2, 1), hovered);
          for (final (row, column) in [
            (2, 0),
            (2, 2),
            (2, 3),
            (1, 1),
            (3, 1),
          ]) {
            _expectColor(pixels.cell(row, column), fixture.palette.surface);
          }
          expect(pixels.cell(2, 1), isNot(pixels.cell(2, 2)));
        });
      });

      testWidgets(
          'explicit opaque and translucent fills survive paint and JSON',
          (tester) async {
        await withPainter(tester, (fixture) async {
          const opaque = Color(0xFFF3DFB9);
          const translucent = Color(0x996D8792);
          // A saved whole-row fill can resemble a stripe. It is intentional
          // document formatting, unlike the old pointer-wide row wash.
          for (var column = 0; column < 4; column++) {
            fixture.controller.data.setStyle(
              CellRef(1, column),
              const CellStyle(backgroundColor: 0xFFF3DFB9),
            );
          }
          fixture.controller.data.setStyle(
            const CellRef(3, 2),
            const CellStyle(backgroundColor: 0x996D8792),
          );
          final stored = fixture.controller.toJson();
          final pixels = await _paint(tester, fixture.painter());
          for (var column = 0; column < 4; column++) {
            _expectColor(pixels.cell(1, column), opaque);
            _expectColor(pixels.cell(2, column), fixture.palette.surface);
          }
          _expectColor(
            pixels.cell(3, 2),
            Color.alphaBlend(translucent, fixture.palette.surface),
          );
          final hovered = await _paint(
            tester,
            fixture.painter(hoveredCell: const CellRef(1, 2)),
          );
          _expectColor(
            hovered.cell(1, 2),
            Color.alphaBlend(fixture.palette.hover, opaque),
          );
          _expectColor(hovered.cell(1, 1), opaque);
          expect(fixture.controller.toJson(), stored);
          final restored = SpreadsheetData.fromJson(stored);
          expect(
            restored.styleAt(const CellRef(1, 2)).backgroundColor,
            0xFFF3DFB9,
          );
          expect(
            restored.styleAt(const CellRef(3, 2)).backgroundColor,
            0x996D8792,
          );
          expect(restored.styleAt(const CellRef(2, 2)).backgroundColor, isNull);
        });
      });

      testWidgets('the hover fade touches only its old and new cells',
          (tester) async {
        await withPainter(tester, (fixture) async {
          for (final progress in [0.0, 0.5, 1.0]) {
            final pixels = await _paint(
              tester,
              fixture.painter(
                hoveredCell: const CellRef(3, 1),
                previousHoveredCell: const CellRef(1, 2),
                previousHoverOpacity: 0.6,
                hover: progress,
              ),
            );
            final eased = Curves.easeOutCubic.transform(progress);
            Color wash(double opacity) => Color.alphaBlend(
                  fixture.palette.hover
                      .withValues(alpha: fixture.palette.hover.a * opacity),
                  fixture.palette.surface,
                );
            _expectColor(pixels.cell(3, 1), wash(eased));
            _expectColor(pixels.cell(1, 2), wash((1 - eased) * 0.6));
            for (final (row, column) in [
              (1, 0),
              (1, 1),
              (2, 1),
              (3, 0),
              (3, 2),
            ]) {
              _expectColor(pixels.cell(row, column), fixture.palette.surface);
            }
          }
        });
      });

      testWidgets('focus fades without a halo, inset fill or moving geometry',
          (tester) async {
        await withPainter(tester, (fixture) async {
          fixture.controller.selectCell(const CellRef(2, 1));
          for (final progress in [0.0, 0.5, 1.0]) {
            final pixels =
                await _paint(tester, fixture.painter(selection: progress));
            _expectColor(pixels.cell(2, 1), fixture.palette.surface);
            // The previous expanding halo leaked two pixels into this cell.
            _expectColor(
              pixels.at(SheetColumn.defaultWidth - 2, 85),
              fixture.palette.surface,
            );
            _expectColor(
              pixels.at(SheetColumn.defaultWidth + 3, 85),
              fixture.palette.surface,
            );
            final eased = Curves.easeOutCubic.transform(progress);
            final stroke = fixture.palette.focusRing.withValues(
              alpha: fixture.palette.focusRing.a * (0.65 + 0.35 * eased),
            );
            _expectColor(
              pixels.at(SheetColumn.defaultWidth, 85),
              Color.alphaBlend(stroke, fixture.palette.surface),
            );
          }
        });
      });

      testWidgets(
          'the New row separator has the same weight as an internal rule',
          (tester) async {
        await withPainter(tester, (fixture) async {
          final pixels = await _paint(tester, fixture.painter());
          expect(
            pixels.at(66, SheetRow.defaultHeight * 2 - 1),
            pixels.at(66, SheetRow.defaultHeight * 8 - 1),
          );
          expect(SpreadsheetMetrics.gridStrokeWidth, lessThan(1));
        });
      });

      testWidgets(
          'selection and search remain visible without changing saved fills',
          (tester) async {
        await withPainter(tester, (fixture) async {
          fixture.controller.data
            ..setRaw(const CellRef(2, 1), 'find')
            ..setStyle(
              const CellRef(2, 1),
              const CellStyle(backgroundColor: 0xFFF3DFB9),
            );
          fixture.controller
            ..selectRange(const CellRef(2, 1), const CellRef(3, 1))
            ..setSearch('find');
          final stored = fixture.controller.toJson();
          final pixels = await _paint(tester, fixture.painter());
          final selected = Color.alphaBlend(
            fixture.palette.selection,
            const Color(0xFFF3DFB9),
          );
          final found = Color.alphaBlend(
            fixture.palette.accent.withValues(alpha: 0.30),
            selected,
          );
          // Sample below the text, not on a glyph or the range outline.
          _expectColor(pixels.at(150, SheetRow.defaultHeight * 3 - 6), found);
          expect(fixture.controller.toJson(), stored);
        });
      });

      testWidgets('hover and focus repaints reuse laid-out cell text',
          (tester) async {
        await withPainter(tester, (fixture) async {
          const ref = CellRef(1, 0);
          fixture.controller.data.setRaw(ref, 'Stable');
          await _paint(tester, fixture.painter());
          TextPainter cached() => fixture.cache.painterFor(
                ref: ref,
                text: 'Stable',
                style: cellTextStyle(
                  base: fixture.typography.cell,
                  style: CellStyle.empty,
                  palette: fixture.palette,
                  isError: false,
                ),
                maxWidth: SheetColumn.defaultWidth -
                    SpreadsheetMetrics.cellPaddingHorizontal * 2,
                align: TextAlign.left,
              );
          final original = cached();
          fixture.controller.selectCell(ref);
          for (final progress in [0.0, 0.25, 0.5, 1.0]) {
            await _paint(
              tester,
              fixture.painter(
                hoveredCell: ref,
                hover: progress,
                selection: progress,
              ),
            );
            expect(cached(), same(original));
          }
          expect(fixture.controller.revision, 0);
        });
      });
    });
  }
}

class _PainterFixture {
  _PainterFixture(this.palette, this.typography) {
    controller.selectCell(const CellRef(7, 3));
  }

  final SpreadsheetPalette palette;
  final SpreadsheetTypography typography;
  final controller =
      SpreadsheetController(data: SpreadsheetData.empty(rows: 8));
  final horizontal = ScrollController();
  final vertical = ScrollController();
  final cache = SheetTextCache();

  SheetBodyPainter painter({
    CellRef? hoveredCell,
    CellRef? previousHoveredCell,
    double previousHoverOpacity = 1,
    double hover = 1,
    double selection = 1,
  }) =>
      SheetBodyPainter(
        controller: controller,
        geometry: SheetGeometry.from(controller),
        palette: palette,
        typography: typography,
        textCache: cache,
        horizontal: horizontal,
        vertical: vertical,
        fillPreview: null,
        hoveredCell: hoveredCell,
        previousHoveredCell: previousHoveredCell,
        previousHoverOpacity: previousHoverOpacity,
        hoverSettle: AlwaysStoppedAnimation<double>(hover),
        selectionSettle: AlwaysStoppedAnimation<double>(selection),
        placeholder: null,
        addRowLabel: 'New row',
        addRowHovered: false,
        repaint: controller,
      );

  void dispose() {
    controller.dispose();
    horizontal.dispose();
    vertical.dispose();
  }
}

Future<_Pixels> _paint(WidgetTester tester, SheetBodyPainter painter) async {
  final size =
      Size(painter.geometry.contentWidth, painter.geometry.contentHeight);
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  try {
    final pixels = await tester.runAsync(() async {
      final image =
          await picture.toImage(size.width.ceil(), size.height.ceil());
      try {
        return _Pixels(
          image.width,
          (await image.toByteData())!,
        );
      } finally {
        image.dispose();
      }
    });
    return pixels!;
  } finally {
    picture.dispose();
  }
}

class _Pixels {
  const _Pixels(this.width, this.bytes);
  final int width;
  final ByteData bytes;

  Color at(double x, double y) {
    final offset = (y.floor() * width + x.floor()) * 4;
    return Color.fromARGB(
      bytes.getUint8(offset + 3),
      bytes.getUint8(offset),
      bytes.getUint8(offset + 1),
      bytes.getUint8(offset + 2),
    );
  }

  Color cell(int row, int column) => at(
        (column + 0.75) * SheetColumn.defaultWidth,
        (row + 0.5) * SheetRow.defaultHeight,
      );
}

void _expectColor(Color actual, Color expected) {
  // Canvas alpha blending is quantized to 8-bit channels in these captures.
  expect(actual.a, closeTo(expected.a, 1 / 255));
  expect(actual.r, closeTo(expected.r, 1 / 255));
  expect(actual.g, closeTo(expected.g, 1 / 255));
  expect(actual.b, closeTo(expected.b, 1 / 255));
}
