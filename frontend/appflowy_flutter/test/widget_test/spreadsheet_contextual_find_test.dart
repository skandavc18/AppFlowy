import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_toolbar.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _outside = ValueKey('outside-sheet-find');
late Map<String, dynamic> _translations;

void main() {
  late bool previousFontFetching;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _translations = await const TestBundleAssetLoader()
        .load('assets/translations', const Locale('en', 'US'));
    previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  tearDownAll(
    () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
  );

  test('native search uses displayed values, all visible rows and no mutations',
      () {
    final controller = SpreadsheetController(data: _data());
    addTearDown(controller.dispose);
    final before = controller.toJson();
    final evaluator = controller.evaluator;
    controller.setSearch('ALPHA');
    expect(controller.searchMatches, const [
      CellRef(0, 0),
      CellRef(1, 0),
      CellRef(2, 0),
      CellRef(65, 5),
    ]);
    expect(controller.active, const CellRef(0, 0));
    controller.stepSearch(-1);
    expect(controller.active, const CellRef(65, 5));
    controller.stepSearch(1);
    expect(controller.active, const CellRef(0, 0));
    controller.setSearch('20');
    expect(controller.searchMatches, const [CellRef(0, 2)]);
    expect(controller.active, const CellRef(0, 2));
    expect(controller.displayTextAt(controller.active), '20');
    controller.setSearch('SUM');
    expect(controller.searchMatches, isEmpty);
    controller.setSearch('25%');
    expect(controller.searchMatches, const [CellRef(0, 4)]);
    controller.setSearch('0.25');
    expect(controller.searchMatches, isEmpty);
    controller.setSearch('a.b');
    expect(controller.searchMatches, const [CellRef(4, 0)]);
    controller.setSearch('');
    expect(controller.searchMatches, isEmpty);
    expect(controller.searchMatchIndex, -1);
    expect(controller.toJson(), before);
    expect(controller.evaluator, same(evaluator));
    expect(controller.canUndo, isFalse);
  });

  test('native search retains current filtered/hidden-cell semantics', () {
    final data = _data()
      ..setRowSpec(1, const SheetRow(hidden: true))
      ..setColumn(5, const SheetColumn(hidden: true));
    data.filters = const [SheetFilter(column: 0, query: 'alpha')];
    final controller = SpreadsheetController(data: data);
    addTearDown(controller.dispose);
    final before = controller.toJson();
    controller.setSearch('alpha');
    expect(controller.searchMatches, const [CellRef(0, 0), CellRef(2, 0)]);
    expect(controller.toJson(), before);
    expect(controller.canUndo, isFalse);
  });

  test('read-only replacement calls cannot write or create undo', () {
    final controller = SpreadsheetController(data: _data(), editable: false);
    addTearDown(controller.dispose);
    final before = controller.toJson();
    controller.setSearch('alpha');
    controller.replaceCurrent('changed');
    expect(controller.replaceAll('changed'), 0);
    expect(controller.toJson(), before);
    expect(controller.canUndo, isFalse);
  });

  for (final mode in ['light', 'dark', 'paper']) {
    _test('$mode: hovered sheet owns Ctrl+F despite a document caret',
        (tester) async {
      await _withSheet(
        tester,
        mode: mode,
        body: (fixture) async {
          final controller = _controller(tester);
          final gridState =
              tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid));
          final before = fixture.editor.document.toJson();
          final caret = Selection.single(
            path: fixture.paragraph.path,
            startOffset: 2,
            endOffset: 2,
          );
          fixture.editor.selection = caret;
          final pageFocus = _pageFocus(tester);
          pageFocus.requestFocus();
          await tester.pump();
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            // No activation click: an inactive sheet must still own hover find.
            // Keep the real page scroll/gesture gate in this integration fixture.
            await mouse.addPointer(
              location: tester.getCenter(find.byType(SpreadsheetGrid)),
            );
            await tester.pump();
            expect(pageFocus.hasPrimaryFocus, isTrue);
            expect(fixture.editor.selection, caret);
            expect(controller.isEditing, isFalse);
            await _chord(tester);
            expect(find.byType(SpreadsheetFindBar), findsOneWidget);
            expect(fixture.pageFinds, 0);
            expect(_findInput(tester).focusNode.hasPrimaryFocus, isTrue);
            expect(fixture.editor.selection, isNull);
            await tester.enterText(_findField(), 'ALPHA');
            await tester.pump();
            expect(controller.searchMatches, hasLength(4));
            expect(
              find.text(
                LocaleKeys.spreadsheet_find_results.tr(args: ['1', '4']),
              ),
              findsOneWidget,
            );
            final barState = tester.state(find.byType(SpreadsheetFindBar));
            await mouse.moveTo(const Offset(850, 700));
            await _chord(tester);
            expect(
              tester.state(find.byType(SpreadsheetFindBar)),
              same(barState),
            );
            expect(_findInput(tester).controller.text, 'ALPHA');
            expect(fixture.pageFinds, 0);
            await tester.tap(_barButton(Icons.close_rounded));
            await tester.pump();
            expect(find.byType(SpreadsheetFindBar), findsNothing);
            expect(
              tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid)),
              same(gridState),
            );
            expect(_controller(tester), same(controller));
            expect(fixture.editor.document.toJson(), before);
            expect(controller.canUndo, isFalse);
          } finally {
            await mouse.removePointer();
          }
        },
      );
    });

    _test('$mode: selected sheet owns Ctrl+F without hover', (tester) async {
      await _withSheet(
        tester,
        mode: mode,
        body: (fixture) async {
          final controller = _controller(tester);
          final gridState =
              tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid));
          final before = fixture.editor.document.toJson();
          final selection = Selection.single(
            path: fixture.sheet.path,
            startOffset: 0,
            endOffset: 1,
          );
          fixture.editor.selection = selection;
          final pageFocus = _pageFocus(tester);
          pageFocus.requestFocus();
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            await mouse.addPointer(location: const Offset(950, 810));
            await tester.pump();
            expect(pageFocus.hasPrimaryFocus, isTrue);
            expect(fixture.editor.selection, selection);
            await _chord(tester);
            expect(find.byType(SpreadsheetFindBar), findsOneWidget);
            expect(_findInput(tester).focusNode.hasPrimaryFocus, isTrue);
            expect(fixture.editor.selection, isNull);
            expect(fixture.pageFinds, 0);
            expect(
              tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid)),
              same(gridState),
            );
            expect(_controller(tester), same(controller));
            expect(fixture.editor.document.toJson(), before);
            expect(controller.canUndo, isFalse);
          } finally {
            await mouse.removePointer();
          }
        },
      );
    });
  }

  for (final focusTitle in [false, true]) {
    _test('ordinary page field stays native (focused=$focusTitle)',
        (tester) async {
      await _withSheet(
        tester,
        body: (fixture) async {
          final before = fixture.editor.document.toJson();
          final titleFinder = find.descendant(
            of: find.byKey(_outside),
            matching: find.byType(EditableText),
          );
          final title = tester.widget<EditableText>(titleFinder);
          final titleState = tester.state<EditableTextState>(titleFinder);
          title.controller.text = 'Uncommitted page title';
          fixture.editor.selection = Selection.single(
            path: fixture.sheet.path,
            startOffset: 0,
            endOffset: 1,
          );
          final focus = focusTitle ? title.focusNode : _pageFocus(tester);
          focus.requestFocus();
          await tester.pump();
          expect(focus.hasPrimaryFocus, isTrue);
          expect(title.focusNode.hasFocus, focusTitle);
          expect(title.controller.text, 'Uncommitted page title');
          // Desktop single-line fields select all on focus. Establish the desired
          // selection and baseline AFTER that native behavior, before hover/Find.
          title.controller.selection =
              const TextSelection(baseOffset: 2, extentOffset: 8);
          await tester.pump();
          final draft = title.controller.value;
          expect(
            draft.selection,
            const TextSelection(baseOffset: 2, extentOffset: 8),
          );
          expect(
            tester
                .element(titleFinder)
                .findAncestorWidgetOfExactType<ContextualFindRegion>()!
                .findInEditable,
            isFalse,
          );
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            // Focused native fields block unrelated sheet hover; an unfocused
            // native field under the pointer blocks selected-sheet fallback too.
            await mouse.addPointer(
              location: tester.getCenter(
                focusTitle ? find.byType(SpreadsheetGrid) : titleFinder,
              ),
            );
            await tester.pump();
            await _chord(tester);
            expect(find.byType(SpreadsheetFindBar), findsNothing);
            expect(fixture.pageFinds, 0);
            expect(focus.hasPrimaryFocus, isTrue);
            expect(
              tester.state<EditableTextState>(titleFinder),
              same(titleState),
            );
            expect(
              tester.widget<EditableText>(titleFinder).controller,
              same(title.controller),
            );
            expect(title.controller.value, draft);
            expect(fixture.editor.document.toJson(), before);
            expect(_controller(tester).canUndo, isFalse);
          } finally {
            await mouse.removePointer();
          }
        },
      );
    });
  }

  _test(
      'native in-cell Ctrl+F opens the existing bar and searches formula values',
      (tester) async {
    await _withSheet(
      tester,
      body: (fixture) async {
        final controller = _controller(tester);
        final before = fixture.editor.document.toJson();
        await tester.tapAt(
          _cellPoint(tester, 0, 0),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        await tester.pump();
        expect(controller.editing, const CellRef(0, 0));
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'spreadsheet-editor',
        );
        await _chord(tester);
        expect(find.byType(SpreadsheetFindBar), findsOneWidget);
        expect(_findInput(tester).focusNode.hasPrimaryFocus, isTrue);
        await tester.enterText(_findField(), '20');
        await tester.pump();
        expect(controller.currentSearchMatch, const CellRef(0, 2));
        expect(controller.active, const CellRef(0, 2));
        await tester.enterText(_findField(), 'SUM');
        await tester.pump();
        expect(controller.searchMatches, isEmpty);
        expect(
          find.text(LocaleKeys.spreadsheet_find_noResults.tr()),
          findsOneWidget,
        );
        expect(fixture.editor.document.toJson(), before);
        expect(controller.canUndo, isFalse);
      },
    );
  });

  _test('find navigation reveals an offscreen cell and retains the grid',
      (tester) async {
    await _withSheet(
      tester,
      body: (fixture) async {
        final gridState =
            tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid));
        final controller = _controller(tester);
        gridState.focusGrid();
        await tester.pump();
        await _chord(tester);
        await tester.enterText(_findField(), 'alpha');
        await tester.pump();
        await tester.tap(_barButton(Icons.keyboard_arrow_up_rounded));
        await tester.pump();
        await tester.pump();
        expect(controller.searchMatchIndex, 3);
        expect(controller.active, const CellRef(65, 5));
        final scrollables = tester
            .stateList<ScrollableState>(
              find.descendant(
                of: find.byType(SpreadsheetGrid),
                matching: find.byType(Scrollable),
              ),
            )
            .toList();
        expect(
          scrollables
              .firstWhere((state) => state.position.axis == Axis.vertical)
              .position
              .pixels,
          greaterThan(0),
        );
        expect(
          scrollables
              .firstWhere((state) => state.position.axis == Axis.horizontal)
              .position
              .pixels,
          greaterThan(0),
        );
        expect(_findInput(tester).focusNode.hasPrimaryFocus, isTrue);
        await tester.tap(_barButton(Icons.keyboard_arrow_down_rounded));
        await tester.pump();
        await tester.pump();
        expect(controller.active, const CellRef(0, 0));
        expect(
          tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid)),
          same(gridState),
        );
        expect(controller.canUndo, isFalse);
      },
    );
  });

  for (final editable in [true, false]) {
    _test('outside click keeps the intended cell focus, editable=$editable',
        (tester) async {
      await _withSheet(
        tester,
        editable: editable,
        body: (fixture) async {
          final before = fixture.editor.document.toJson();
          final controller = _controller(tester);
          final gridState =
              tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid));
          gridState.focusGrid();
          await tester.pump();
          await _chord(tester);
          await tester.enterText(_findField(), 'alpha');
          await tester.pump();
          final gridRect = tester.getRect(find.byType(SpreadsheetGrid));
          final down = await tester.startGesture(
            _cellPoint(tester, 1, 2),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump(const Duration(milliseconds: 30));
          // Removing the strip on DOWN shifts the cell under this same gesture.
          expect(find.byType(SpreadsheetFindBar), findsOneWidget);
          expect(tester.getRect(find.byType(SpreadsheetGrid)), gridRect);
          await down.up();
          await down.removePointer();
          await tester.pump();
          await tester.pump();
          expect(find.byType(SpreadsheetFindBar), findsNothing);
          expect(controller.searchQuery, isEmpty);
          expect(controller.active, const CellRef(1, 2));
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            editable ? 'spreadsheet-editor' : 'spreadsheet-grid',
          );
          expect(
            tester.state<SpreadsheetGridState>(find.byType(SpreadsheetGrid)),
            same(gridState),
          );
          expect(_controller(tester), same(controller));
          expect(fixture.editor.document.toJson(), before);
          expect(controller.canUndo, isFalse);
        },
      );
    });
  }

  _test('outside field retains focus; cancelled outside press does not dismiss',
      (tester) async {
    await _withSheet(
      tester,
      body: (fixture) async {
        tester
            .state<SpreadsheetGridState>(find.byType(SpreadsheetGrid))
            .focusGrid();
        await tester.pump();
        await _chord(tester);
        final press = await tester.startGesture(
          _cellPoint(tester, 1, 2),
          kind: PointerDeviceKind.mouse,
        );
        await press.cancel();
        await press.removePointer();
        await tester.pump();
        expect(find.byType(SpreadsheetFindBar), findsOneWidget);
        await tester.tap(find.byKey(_outside), kind: PointerDeviceKind.mouse);
        await tester.pump();
        await tester.pump();
        expect(find.byType(SpreadsheetFindBar), findsNothing);
        expect(fixture.outsideFocus.hasPrimaryFocus, isTrue);
      },
    );
  });

  _test('removing a sheet before its requested focus frame is safe',
      (tester) async {
    await _withSheet(
      tester,
      body: (fixture) async {
        final regionFinder = find.descendant(
          of: find.byType(SpreadsheetBlockComponent),
          matching: find.byType(ContextualFindRegion),
        );
        expect(regionFinder, findsOneWidget);
        final region = tester.widget<ContextualFindRegion>(regionFinder);
        region.onFind();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
      },
    );
  });
}

SpreadsheetData _data() => SpreadsheetData(
      rowCount: 100,
      columnCount: 6,
      cells: {
        const CellRef(0, 0): const SheetCell(raw: 'alpha'),
        const CellRef(1, 0): const SheetCell(raw: 'ALPHA'),
        const CellRef(2, 0): const SheetCell(raw: 'alphabet'),
        const CellRef(65, 5): const SheetCell(raw: 'alpha distant'),
        const CellRef(0, 1): const SheetCell(raw: '10'),
        const CellRef(0, 2): const SheetCell(raw: '=B1*2'),
        const CellRef(3, 3): const SheetCell(raw: '=SUM(B1:B1)'),
        const CellRef(0, 4): const SheetCell(
          raw: '0.25',
          style: CellStyle(format: CellNumberFormat.percent, decimals: 0),
        ),
        const CellRef(4, 0): const SheetCell(raw: 'a.b'),
        const CellRef(5, 0): const SheetCell(raw: 'acb'),
      },
    );

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 20)),
    );

SpreadsheetController _controller(WidgetTester tester) =>
    tester.widget<SpreadsheetGrid>(find.byType(SpreadsheetGrid)).controller;
FocusNode _pageFocus(WidgetTester tester) => tester
    .state<KeyboardServiceWidgetState>(find.byType(KeyboardServiceWidget))
    .focusNode;
Finder _findField() => find.descendant(
      of: find.byType(SpreadsheetFindBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                LocaleKeys.spreadsheet_find_placeholder.tr(),
      ),
    );
EditableText _findInput(WidgetTester tester) => tester.widget<EditableText>(
      find.descendant(of: _findField(), matching: find.byType(EditableText)),
    );
Finder _barButton(IconData icon) => find.descendant(
      of: find.byType(SpreadsheetFindBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == icon,
      ),
    );
Offset _cellPoint(WidgetTester tester, int row, int column) =>
    tester.getTopLeft(find.byType(SpreadsheetGrid)) +
    Offset(
      SpreadsheetMetrics.gutterWidth +
          SheetColumn.defaultWidth * (column + 0.5),
      SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight * (row + 0.5),
    );

Future<void> _chord(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

Future<void> _withSheet(
  WidgetTester tester, {
  String mode = 'light',
  bool editable = true,
  required Future<void> Function(_SheetFixture fixture) body,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 840);
  final fixture = _SheetFixture(mode: mode, editable: editable);
  try {
    await tester.pumpWidget(fixture.build());
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(find.byType(SpreadsheetBlockComponent), findsOneWidget);
    expect(find.byType(KeyboardServiceWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
    await body(fixture);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.dispose();
    tester.view.reset();
  }
  expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
}

class _SheetFixture {
  _SheetFixture({required this.mode, required this.editable}) {
    sheet = spreadsheetNode(data: _data(), width: 620, height: 440);
    editor = EditorState(
      document: Document(root: pageNode(children: [sheet, paragraph])),
    )
      ..editable = editable
      ..disableSealTimer = true;
    scroll = EditorScrollController(editorState: editor, shrinkWrap: true);
  }
  final String mode;
  final bool editable;
  final paragraph =
      paragraphNode(text: 'Neighbouring paragraph retains its caret');
  final outsideFocus = FocusNode(debugLabel: 'outside-sheet-find');
  late final Node sheet;
  late final EditorState editor;
  late final EditorScrollController scroll;
  int pageFinds = 0;

  Widget build() => EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        saveLocale: false,
        assetLoader: const _PreloadedTranslations(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: const Locale('en', 'US'),
            localizationsDelegates: context.localizationDelegates,
            theme: ThemeData(
              platform: TargetPlatform.windows,
              brightness: mode == 'dark' ? Brightness.dark : Brightness.light,
              extensions: [PaperThemeExtension(enabled: mode == 'paper')],
            ),
            home: AppFlowyTheme(
              data: mode == 'dark'
                  ? AppFlowyDefaultTheme().dark()
                  : AppFlowyDefaultTheme().light(),
              child: FlowyOverlay(
                child: Scaffold(
                  body: ContextualFindRegion(
                    debugLabel: 'Page',
                    onFind: () => pageFinds++,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 260,
                          child: TextField(
                            key: _outside,
                            focusNode: outsideFocus,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: SizedBox(
                            width: 720,
                            height: 700,
                            child: AppFlowyEditor(
                              editorState: editor,
                              editable: editable,
                              editorScrollController: scroll,
                              editorStyle: EditorStyle.desktop(
                                padding: EdgeInsets.zero,
                                maxWidth: 720,
                              ),
                              blockComponentBuilders: {
                                ...standardBlockComponentBuilderMap,
                                PageBlockKeys.type:
                                    CustomPageBlockComponentBuilder(),
                                SpreadsheetBlockKeys.type:
                                    SpreadsheetBlockComponentBuilder(),
                              },
                              contextMenuItems: const [],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void dispose() {
    scroll.dispose();
    editor.dispose();
    outsideFocus.dispose();
  }
}

class _PreloadedTranslations extends AssetLoader {
  const _PreloadedTranslations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}
