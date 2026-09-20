import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_theme.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

const _reference = ValueKey('spreadsheet-reference');
const _modes = ['light', 'dark', 'paper'];

// The main agent generates/reviews these three new baselines separately.
// These are real grids in reference hosts, not a replica of the block chrome.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late bool fontFetching;
  final families = <String>{};
  setUpAll(() async {
    fontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final mode in _modes) {
      final text = _theme(mode).textTheme;
      families
          .addAll([text.bodyMedium!.fontFamily!, text.bodySmall!.fontFamily!]);
    }
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final mode in _modes) {
    testWidgets(
      '$mode: uniform idle rows, local hover and flush editing',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controllers =
            List.generate(3, (_) => SpreadsheetController(data: _data()));
        final keys = List.generate(3, (index) => ValueKey('sheet-$index'));
        TestGesture? mouse;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: _theme(mode),
              themeAnimationDuration: Duration.zero,
              home: Builder(
                builder: (context) {
                  final palette = SpreadsheetPalette.of(context);
                  final text = Theme.of(context).textTheme;
                  return RepaintBoundary(
                    key: _reference,
                    child: Material(
                      color: palette.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Spreadsheet / ${mode.toUpperCase()}',
                              style: text.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'One surface · saved fills stay intact · native text editing',
                              style: text.bodySmall!
                                  .copyWith(color: palette.textSecondary),
                            ),
                            const SizedBox(height: 24),
                            for (var index = 0; index < 3; index++) ...[
                              Text(
                                [
                                  'Resting',
                                  'Hover — one cell only',
                                  'Editing — no inset box',
                                ][index],
                                style: text.bodySmall!
                                    .copyWith(color: palette.textMuted),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 244,
                                child: SpreadsheetGrid(
                                  key: keys[index],
                                  controller: controllers[index],
                                  baseTextStyle: text.bodyMedium,
                                  addRowLabel: 'New row',
                                ),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          await tester.pump();
          final editingGrid = find.byKey(keys[2]);
          final point = tester.getTopLeft(editingGrid) +
              const Offset(
                SpreadsheetMetrics.gutterWidth + 70,
                SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight / 2,
              );
          final click =
              await tester.startGesture(point, kind: PointerDeviceKind.mouse);
          await click.up();
          await tester.pump();
          await tester.pump();
          await click.removePointer();
          final field = find.descendant(
            of: editingGrid,
            matching: find.byType(TextField),
          );
          await tester.enterText(field, 'Draft stays inline');

          final hoverPoint = tester.getTopLeft(find.byKey(keys[1])) +
              const Offset(
                SpreadsheetMetrics.gutterWidth + 270 + 50,
                SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight * 1.5,
              );
          mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(890, 1010));
          await mouse.moveTo(hoverPoint);
          await tester.pump();
          await tester
              .pump(AppFlowyMotion.fast + const Duration(milliseconds: 1));
          final context = tester.element(find.byKey(_reference));
          expect(PaperTheme.isEnabled(context), mode == 'paper');
          expect(controllers[2].editing, const CellRef(0, 0));
          expect(controllers[2].editingText, 'Draft stays inline');
          expect(controllers[2].data.rawAt(const CellRef(0, 0)), 'Research');
          final bodyPaints = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((paint) => paint.painter)
              .whereType<SheetBodyPainter>()
              .toList();
          expect(bodyPaints, hasLength(3));
          expect(bodyPaints[1].hoveredCell, const CellRef(1, 1));
          expect(bodyPaints[1].hoverSettle.value, 1);
          for (final painter in bodyPaints) {
            expect(families, contains(painter.typography.cell.fontFamily));
            expect(painter.palette.bandedSurface, painter.palette.surface);
          }
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(_reference),
            matchesGoldenFile('goldens/spreadsheet_$mode.png'),
          );
        } finally {
          await mouse?.removePointer();
          await tester.pumpWidget(const SizedBox.shrink());
          for (final controller in controllers) {
            controller.dispose();
          }
        }
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

SpreadsheetData _data() => SpreadsheetData.fromRows(
      [
        ['Task', 'Budget', 'Status', 'Progress'],
        ['Research', '240', 'Done', '1'],
        ['Prototype', '580', 'Review', '0.75'],
        ['Refine', '160', 'In progress', '0.35'],
        ['Ship', '90', 'Planned', '0'],
      ],
      minRows: 5,
      minColumns: 4,
    )
      ..setColumn(0, const SheetColumn(title: 'Task', width: 270))
      ..setColumn(1, const SheetColumn(title: 'Budget', width: 150))
      ..setColumn(2, const SheetColumn(title: 'Status', width: 180))
      ..setColumn(3, const SheetColumn(title: 'Progress', width: 130))
      ..setStyle(
        const CellRef(1, 2),
        const CellStyle(backgroundColor: 0xFFF3DFB9),
      )
      ..setStyle(
        const CellRef(0, 3),
        const CellStyle(format: CellNumberFormat.percent),
      )
      ..setStyle(
        const CellRef(1, 3),
        const CellStyle(format: CellNumberFormat.percent),
      )
      ..setStyle(
        const CellRef(2, 3),
        const CellStyle(format: CellNumberFormat.percent),
      )
      ..setStyle(
        const CellRef(3, 3),
        const CellStyle(format: CellNumberFormat.percent),
      );
