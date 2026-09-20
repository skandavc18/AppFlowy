import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_theme.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_toolbar.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _appearances = ['light', 'dark', 'paper'];
const _outside = ValueKey('outside-spreadsheet');
const _fade = Duration(milliseconds: 141);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late bool previousFontFetching;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    // Use the desktop theme's actual bundled face, not Ahem: line-height and
    // clipping assertions must exercise the same metrics as the application.
    for (final family in _appearances
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await binding.handleSystemMessage({'type': 'fontsChange'});
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
  });

  for (final mode in _appearances) {
    _test('$mode: idle, hover, keyboard focus and menu-held header chrome',
        (tester) async {
      await _withSheet(tester, mode, (fixture) async {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: const Offset(2, 2));
          final toolbar = find.byType(PreviewToolbar);
          final gridState = tester.state(find.byType(SpreadsheetGrid));
          final blockState =
              tester.state(find.byType(SpreadsheetBlockComponent));
          final document = fixture.editor.document.toJson();
          final controller = _controller(tester);
          _expectToolbar(tester, false);
          expect(
            _headerButton(Icons.search_rounded).hitTestable(),
            findsNothing,
          );

          await mouse.moveTo(tester.getCenter(find.byType(SpreadsheetGrid)));
          await _motion(tester);
          _expectToolbar(tester, true);
          final ids = <int>[];
          for (final icon in [
            Icons.search_rounded,
            Icons.filter_list_rounded,
            Icons.add_rounded,
            Icons.more_horiz_rounded,
          ]) {
            final button = _headerButton(icon);
            final native = tester.widget<IconButton>(button);
            final node = tester.getSemantics(button);
            final semantics = node.getSemanticsData();
            expect(native.onPressed, isNotNull);
            expect(semantics.hasFlag(ui.SemanticsFlag.isButton), isTrue);
            expect(semantics.hasAction(ui.SemanticsAction.tap), isTrue);
            expect(semantics.tooltip, native.tooltip);
            ids.add(node.id);
          }

          await mouse.moveTo(const Offset(2, 2));
          await _motion(tester);
          _expectToolbar(tester, false);
          // Cached widget semantics may survive exclusion. Inspect the live
          // root tree rather than finding detached debugSemantics by label.
          expect(_liveSemanticsIds(tester).intersection(ids.toSet()), isEmpty);

          for (final icon in [
            Icons.filter_list_rounded,
            Icons.add_rounded,
            Icons.more_horiz_rounded,
          ]) {
            await _tabTo(tester, fixture, _headerButton(icon));
            _expectToolbar(tester, true);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.byType(AppMenuSurface), findsOneWidget);
            expect(_focusedInside(toolbar), isFalse);
            await mouse.moveTo(const Offset(3, 3));
            await _motion(tester);
            // Neither hover nor toolbar focus can account for visibility:
            // the real menu must hold the ResizableMedia region below State.
            _expectToolbar(tester, true);
            expect(tester.state(find.byType(SpreadsheetGrid)), same(gridState));
            expect(
              tester.state(find.byType(SpreadsheetBlockComponent)),
              same(blockState),
            );
            expect(_controller(tester), same(controller));
            expect(controller.canUndo, isFalse);
            expect(fixture.editor.document.toJson(), document);

            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byType(AppMenuSurface), findsNothing);
            fixture.outsideFocus.requestFocus();
            await _motion(tester);
            _expectToolbar(tester, false);
          }
        } finally {
          await mouse.removePointer();
        }
      });
    });

    _test(
        '$mode: hover and local-pane resizing retain the uncommitted cell draft',
        (tester) async {
      await _withSheet(
        tester,
        mode,
        (fixture) async {
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            await mouse.addPointer(location: const Offset(2, 2));
            final grid = find.byType(SpreadsheetGrid);
            final controller = _controller(tester);
            final document = fixture.editor.document.toJson();
            final editorState = tester.state(find.byType(AppFlowyEditor));
            final gridState = tester.state(grid);
            await tester.tapAt(
              tester.getTopLeft(grid) +
                  const Offset(
                    SpreadsheetMetrics.gutterWidth + 30,
                    SpreadsheetMetrics.headerHeight + 16,
                  ),
              kind: PointerDeviceKind.mouse,
            );
            await _motion(tester);
            final field =
                find.descendant(of: grid, matching: find.byType(TextField));
            await tester.enterText(field, 'uncommitted cell draft');
            const value = TextEditingValue(
              text: 'uncommitted cell draft',
              selection: TextSelection(baseOffset: 3, extentOffset: 8),
              composing: TextRange(start: 0, end: 11),
            );
            tester.testTextInput.updateEditingValue(value);
            await _motion(tester);
            final input = _editable(tester, field);
            final state =
                tester.state<EditableTextState>(_editableFinder(field));

            for (final width in [320.0, 719.0, 720.0, 760.0, 320.0]) {
              fixture.resize(width: width);
              await _motion(tester);
              await mouse.moveTo(
                tester.getCenter(_headerButton(Icons.search_rounded)),
              );
              await _motion(tester);
              _expectToolbar(tester, true);
              await mouse.moveTo(const Offset(2, 2));
              await _motion(tester);
              _expectToolbar(tester, false);
              expect(
                tester.state(find.byType(AppFlowyEditor)),
                same(editorState),
              );
              expect(tester.state(grid), same(gridState));
              expect(tester.state(_editableFinder(field)), same(state));
              expect(
                _editable(tester, field).controller,
                same(input.controller),
              );
              expect(input.controller.value, value);
              expect(input.focusNode.hasPrimaryFocus, isTrue);
              expect(_controller(tester), same(controller));
              expect(controller.editingText, value.text);
              expect(controller.data.rawAt(const CellRef(0, 0)), 'alpha');
              expect(controller.canUndo, isFalse);
              expect(fixture.editor.document.toJson(), document);
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _motion(tester);
            expect(controller.isEditing, isFalse);
            expect(fixture.editor.document.toJson(), document);
          } finally {
            await mouse.removePointer();
          }
        },
        width: 760,
      );
    });

    for (final editable in [true, false]) {
      _test('$mode: collapsed controls stay reachable, editable=$editable',
          (tester) async {
        await _withSheet(
          tester,
          mode,
          (fixture) async {
            final before = fixture.sheet.attributes[SpreadsheetBlockKeys.data];
            _expectToolbar(tester, true);
            expect(find.byType(SpreadsheetGrid), findsNothing);
            expect(
              _headerButton(Icons.add_rounded),
              editable ? findsOneWidget : findsNothing,
            );
            final buttons = find.descendant(
              of: find.byType(PreviewToolbar),
              matching: find.byType(IconButton),
            );
            expect(buttons, findsNWidgets(editable ? 4 : 3));
            final frame =
                tester.getRect(find.byKey(const ValueKey('resizable_media')));
            for (var index = 0; index < buttons.evaluate().length; index++) {
              final button = buttons.at(index);
              final bounds = tester.getRect(button);
              expect(bounds.left, greaterThanOrEqualTo(frame.left));
              expect(bounds.right, lessThanOrEqualTo(frame.right));
              expect(bounds.top, greaterThanOrEqualTo(frame.top));
              expect(bounds.bottom, lessThanOrEqualTo(frame.bottom));
              await _tabTo(tester, fixture, button);
              expect(_focusedInside(button), isTrue);
            }

            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.byType(AppMenuSurface), findsOneWidget);
            final expand =
                find.text(LocaleKeys.spreadsheet_toolbar_expand.tr());
            expect(expand.hitTestable(), findsOneWidget);
            if (editable) {
              await tester.tap(expand, kind: PointerDeviceKind.mouse);
              await tester.pumpAndSettle();
              expect(find.byType(SpreadsheetGrid), findsOneWidget);
              expect(
                fixture.sheet.attributes[SpreadsheetBlockKeys.collapsed],
                false,
              );
            } else {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(_headerButton(Icons.add_rounded), findsNothing);
              expect(find.byType(SpreadsheetFindBar), findsNothing);
            }
            expect(fixture.sheet.attributes[SpreadsheetBlockKeys.data], before);
          },
          editable: editable,
          collapsed: true,
        );
      });
    }

    for (final scale in [1.0, 2.0]) {
      _test('$mode: both find fields retain state across 720px × $scale',
          (tester) async {
        final threshold = 720 * scale;
        await _withSheet(
          tester,
          mode,
          (fixture) async {
            await _openFind(tester, fixture);
            final findField = _findField();
            final replaceField = _replaceField();
            await tester.enterText(findField, 'alpha');
            await tester.enterText(replaceField, 'replacement draft');
            final findInput = _editable(tester, findField);
            final replaceInput = _editable(tester, replaceField);
            const findValue = TextEditingValue(
              text: 'alpha',
              selection: TextSelection.collapsed(offset: 2),
            );
            const replaceValue = TextEditingValue(
              text: 'replacement draft',
              selection: TextSelection(baseOffset: 2, extentOffset: 7),
            );
            findInput.controller.value = findValue;
            replaceInput.controller.value = replaceValue;
            final findState = tester.state(_editableFinder(findField));
            final replaceState = tester.state(_editableFinder(replaceField));
            final barState = tester.state(find.byType(SpreadsheetFindBar));
            final gridState = tester.state(find.byType(SpreadsheetGrid));
            final controller = _controller(tester);
            final document = fixture.editor.document.toJson();

            for (final focused in [findInput, replaceInput]) {
              focused.focusNode.requestFocus();
              await _motion(tester);
              // Desktop TextField selects all when focus is newly requested.
              // Establish the user's caret AFTER that native focus transition;
              // only resizing must preserve it without another focus change.
              findInput.controller.value = findValue;
              replaceInput.controller.value = replaceValue;
              await _motion(tester);
              final focusLosses = <bool>[];
              void recordFocus() {
                if (!focused.focusNode.hasPrimaryFocus) focusLosses.add(true);
              }

              focused.focusNode.addListener(recordFocus);
              try {
                for (final width in [
                  threshold + 20,
                  threshold,
                  threshold - 1,
                  320.0,
                  threshold + 1,
                  threshold - 1,
                  threshold,
                ]) {
                  fixture.resize(width: width);
                  await _motion(tester);
                  expect(
                    tester.getSize(find.byType(SpreadsheetFindBar)).width,
                    width,
                  );
                  expect(
                    tester.state(_editableFinder(findField)),
                    same(findState),
                  );
                  expect(
                    tester.state(_editableFinder(replaceField)),
                    same(replaceState),
                  );
                  expect(
                    tester.state(find.byType(SpreadsheetFindBar)),
                    same(barState),
                  );
                  expect(
                    tester.state(find.byType(SpreadsheetGrid)),
                    same(gridState),
                  );
                  expect(
                    _editable(tester, findField).controller,
                    same(findInput.controller),
                  );
                  expect(
                    _editable(tester, replaceField).controller,
                    same(replaceInput.controller),
                  );
                  expect(
                    _editable(tester, findField).focusNode,
                    same(findInput.focusNode),
                  );
                  expect(
                    _editable(tester, replaceField).focusNode,
                    same(replaceInput.focusNode),
                  );
                  expect(findInput.controller.value, findValue);
                  expect(replaceInput.controller.value, replaceValue);
                  expect(focused.focusNode.hasPrimaryFocus, isTrue);
                  expect(focusLosses, isEmpty);
                  expect(_controller(tester), same(controller));
                  expect(controller.searchQuery, 'alpha');
                  expect(controller.searchMatches, hasLength(3));
                  expect(fixture.editor.document.toJson(), document);
                  _expectToolbar(tester, true);
                  final findBounds = tester.getRect(findField);
                  final replaceBounds = tester.getRect(replaceField);
                  if (width < threshold) {
                    expect(replaceBounds.top, greaterThan(findBounds.bottom));
                  } else {
                    expect(
                      replaceBounds.center.dy,
                      closeTo(findBounds.center.dy, 0.01),
                    );
                    expect(replaceBounds.left, greaterThan(findBounds.right));
                  }
                  _expectLineFits(tester, findField);
                  _expectLineFits(tester, replaceField);
                }
              } finally {
                focused.focusNode.removeListener(recordFocus);
              }
            }
          },
          width: threshold + 20,
          scale: scale,
        );
      });
    }

    _test('$mode: scaled find keeps Backspace and repeated Enter local',
        (tester) async {
      await _withSheet(tester, mode, (fixture) async {
        final document = fixture.editor.document.toJson();
        fixture.editor.selection = Selection.single(
          path: fixture.sheet.path,
          startOffset: 0,
          endOffset: 1,
        );
        await _openFind(tester, fixture);
        final controller = _controller(tester);
        final field = _findField();
        final replace = _replaceField();
        for (final input in [field, replace]) {
          expect(
            find.ancestor(of: input, matching: find.byType(TextEntryShortcuts)),
            findsOneWidget,
          );
          _expectLineFits(tester, input);
        }
        expect(fixture.editor.selection, isNull);
        await tester.enterText(field, 'alphaxx');
        await _motion(tester);
        final input = _editable(tester, field);
        final focus = input.focusNode;
        final focusLosses = <bool>[];
        void recordFocus() {
          if (!focus.hasPrimaryFocus) focusLosses.add(true);
        }

        focus.addListener(recordFocus);
        try {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
          await _motion(tester);
          expect(input.controller.text, 'alphax');
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.backspace);
          await _motion(tester);
          expect(input.controller.text, 'alpha');
          await tester.sendKeyUpEvent(LogicalKeyboardKey.backspace);
          await _motion(tester);
          expect(controller.searchQuery, 'alpha');
          expect(controller.searchMatches, hasLength(3));
          var expectedIndex = controller.searchMatchIndex;
          // Flutter 3.27's legacy Windows simulator has no numpad-Enter map.
          // Use a supported wire mapping for that key only; the widget/theme
          // stays Windows and the normal focus/event dispatcher remains intact.
          for (final (logical, physical) in [
            (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter),
            (LogicalKeyboardKey.numpadEnter, PhysicalKeyboardKey.numpadEnter),
          ]) {
            final platform = logical == LogicalKeyboardKey.numpadEnter
                ? 'android'
                : 'windows';
            await tester.sendKeyDownEvent(
              logical,
              physicalKey: physical,
              platform: platform,
            );
            await _motion(tester);
            expectedIndex = (expectedIndex + 1) % 3;
            expect(controller.searchMatchIndex, expectedIndex);
            expect(focus.hasPrimaryFocus, isTrue);
            await tester.sendKeyRepeatEvent(
              logical,
              physicalKey: physical,
              platform: platform,
            );
            await _motion(tester);
            expectedIndex = (expectedIndex + 1) % 3;
            expect(controller.searchMatchIndex, expectedIndex);
            await tester.sendKeyUpEvent(
              logical,
              physicalKey: physical,
              platform: platform,
            );
            await _motion(tester);
            expect(controller.searchMatchIndex, expectedIndex);
          }
          // The platform's text-input submit path must keep the same focus too.
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await _motion(tester);
          expect(controller.searchMatchIndex, (expectedIndex + 1) % 3);
          expect(focus.hasPrimaryFocus, isTrue);
          expect(focusLosses, isEmpty);
          expect(
            input.controller.selection,
            const TextSelection.collapsed(offset: 5),
          );
          expect(fixture.editor.document.toJson(), document);
        } finally {
          focus.removeListener(recordFocus);
        }
      });
    });

    _test('$mode: the visible scaled find close button accepts a pointer',
        (tester) async {
      await _withSheet(tester, mode, (fixture) async {
        final document = fixture.editor.document.toJson();
        await _openFind(tester, fixture);
        await tester.enterText(_findField(), 'alpha');
        await _motion(tester);
        final controller = _controller(tester);
        expect(controller.searchMatches, hasLength(3));
        final close = find.descendant(
          of: find.byType(SpreadsheetFindBar),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is IconButton &&
                widget.tooltip == LocaleKeys.button_close.tr(),
          ),
        );
        expect(close.hitTestable(), findsOneWidget);
        final click = await tester.startGesture(
          tester.getCenter(close),
          kind: PointerDeviceKind.mouse,
        );
        await click.up();
        await click.removePointer();
        await _motion(tester);
        expect(find.byType(SpreadsheetFindBar), findsNothing);
        expect(controller.searchQuery, isEmpty);
        expect(controller.searchMatches, isEmpty);
        expect(fixture.editor.document.toJson(), document);
        fixture.outsideFocus.requestFocus();
        await _motion(tester);
        _expectToolbar(tester, false);
      });
    });

    _test(
        '$mode: large formula aggregates stay on one horizontally scrollable row',
        (tester) async {
      await _withSheet(
        tester,
        mode,
        (fixture) async {
          final controller = _controller(tester);
          final document = fixture.editor.document.toJson();
          controller.selectRange(const CellRef(0, 0), const CellRef(1, 2));
          await _motion(tester);
          expect(
            controller.valueAt(const CellRef(1, 2)).asNumber,
            33000000000000,
          );
          expect(controller.selectionSummary.sum, 69000000000000);
          final footer = find.byType(SpreadsheetFooter);
          final scroll = find.descendant(
            of: footer,
            matching: find.byType(SingleChildScrollView),
          );
          expect(scroll, findsOneWidget);
          expect(
            tester.widget<SingleChildScrollView>(scroll).scrollDirection,
            Axis.horizontal,
          );
          final state = tester.state<ScrollableState>(
            find.descendant(of: scroll, matching: find.byType(Scrollable)),
          );
          expect(state.position.maxScrollExtent, greaterThan(0));
          final summaries = [
            LocaleKeys.spreadsheet_summaryCells.tr(args: ['6']),
            LocaleKeys.spreadsheet_summarySum.tr(args: ['69000000000000']),
            LocaleKeys.spreadsheet_summaryAverage.tr(args: ['11500000000000']),
            LocaleKeys.spreadsheet_summaryMin.tr(args: ['1000000000000']),
            LocaleKeys.spreadsheet_summaryMax.tr(args: ['33000000000000']),
          ];
          final rows = find.descendant(of: scroll, matching: find.byType(Row));
          expect(rows, findsOneWidget);
          final viewport = tester.getRect(scroll);
          final dimensions =
              find.descendant(of: footer, matching: find.text('2 × 3'));
          final dimensionsBefore = tester.getRect(dimensions);
          double? baseline;
          for (final text in summaries) {
            final label =
                find.descendant(of: scroll, matching: find.text(text));
            expect(label, findsOneWidget);
            final rect = tester.getRect(label);
            baseline ??= rect.center.dy;
            expect(rect.center.dy, closeTo(baseline, 0.01));
            expect(rect.height, lessThanOrEqualTo(viewport.height));
            final paragraph = tester.renderObject<RenderParagraph>(label);
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: 0, extentOffset: text.length),
            );
            expect(boxes.map((box) => box.top).toSet(), hasLength(1));
          }
          final scrollPoint = viewport.topCenter + const Offset(0, 4);
          // Real embeds intentionally pass wheel/drag to the page until an
          // accepted click activates them. Keep that production gate enabled.
          await tester.tapAt(scrollPoint, kind: PointerDeviceKind.mouse);
          await _motion(tester);
          expect(
            state.position.physics.shouldAcceptUserOffset(state.position),
            isTrue,
          );
          final hitPath = tester.hitTestOnBinding(scrollPoint).path.join('\n');
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: scrollPoint,
              scrollDelta: const Offset(10000, 0),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            state.position.pixels,
            state.position.maxScrollExtent,
            reason: 'Footer viewport=$viewport, frame='
                '${tester.getRect(find.byKey(const ValueKey('resizable_media')))}'
                '\nHit path: $hitPath',
          );
          final last = tester.getRect(find.text(summaries.last));
          // A single 2x summary can exceed the viewport too. Its suffix must
          // be reachable at the end, not forced to fit by wrapping/shrinking.
          expect(last.right, closeTo(viewport.right, 0.01));
          expect(last.overlaps(viewport), isTrue);
          expect(tester.getRect(dimensions), dimensionsBefore);
          expect(fixture.editor.document.toJson(), document);
          expect(controller.canUndo, isFalse);
        },
        data: _formulaData(),
      );
    });
  }
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

SpreadsheetData _sample() => SpreadsheetData.fromRows([
      ['Name', 'Value', 'Other'],
      ['alpha', '10', 'first'],
      ['alpha', '20', 'second'],
      ['alpha', '30', 'third'],
    ]);

SpreadsheetData _formulaData() => SpreadsheetData.fromRows(
      [
        ['A', 'B', 'Formula'],
        ['1000000000000', '2000000000000', '=A1+B1'],
        ['=A1*10', '=B1*10', '=SUM(A1:B2)'],
      ],
      minRows: 2,
    );

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

// No application startup, service locator, DocumentBloc or backend mocks:
// document transactions, selection/keyboard services and sheet chrome are real.
class _SheetFixture {
  _SheetFixture({
    required this.mode,
    required this.editable,
    required bool collapsed,
    required double width,
    required double scale,
    required SpreadsheetData data,
  }) : layout = ValueNotifier((width: width, scale: scale)) {
    sheet = spreadsheetNode(data: data, width: 1800, height: 560);
    if (collapsed) {
      sheet.updateAttributes({SpreadsheetBlockKeys.collapsed: true});
    }
    editor = EditorState(
      document: Document(root: pageNode(children: [sheet, paragraph])),
    )
      ..editable = editable
      ..disableSealTimer = true;
    scroll = EditorScrollController(editorState: editor, shrinkWrap: true);
  }

  final String mode;
  final bool editable;
  final ValueNotifier<({double width, double scale})> layout;
  final outsideFocus = FocusNode(debugLabel: 'outside-spreadsheet');
  final paragraph =
      paragraphNode(text: 'Neighbouring paragraph stays unchanged');
  late final Node sheet;
  late final EditorState editor;
  late final EditorScrollController scroll;

  void resize({required double width}) =>
      layout.value = (width: width, scale: layout.value.scale);

  Widget build() {
    final theme = _theme(mode);
    final defaults = AppFlowyDefaultTheme();
    return EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: theme,
          themeAnimationDuration: Duration.zero,
          builder: (context, navigator) => AppFlowyTheme(
            data: PremiumTheme.appFlowyTheme(
              base: mode == 'dark' ? defaults.dark() : defaults.light(),
              palette: theme.extension<PremiumThemeExtension>()!,
              brightness: theme.brightness,
            ),
            child: ValueListenableBuilder(
              valueListenable: layout,
              builder: (context, value, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(value.scale)),
                child: child!,
              ),
              child: TooltipVisibility(visible: false, child: navigator!),
            ),
          ),
          home: FlowyOverlay(
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton(
                    key: _outside,
                    focusNode: outsideFocus,
                    onPressed: () {},
                    child: const Text('Outside spreadsheet'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 24),
                    child: ValueListenableBuilder(
                      valueListenable: layout,
                      builder: (context, value, _) => SizedBox(
                        width: value.width,
                        height: 760,
                        child: AppFlowyEditor(
                          editorState: editor,
                          editable: editable,
                          editorScrollController: scroll,
                          editorStyle: EditorStyle.desktop(
                            padding: EdgeInsets.zero,
                            maxWidth: 1800,
                            textScaleFactor: value.scale,
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _withSheet(
  WidgetTester tester,
  String mode,
  Future<void> Function(_SheetFixture fixture) body, {
  double width = 320,
  double scale = 2,
  bool editable = true,
  bool collapsed = false,
  SpreadsheetData? data,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(2048, 1000);
  addTearDown(tester.view.reset);
  final semantics = tester.ensureSemantics();
  final fixture = _SheetFixture(
    mode: mode,
    editable: editable,
    collapsed: collapsed,
    width: width,
    scale: scale,
    data: data ?? _sample(),
  );
  try {
    await tester.pumpWidget(fixture.build());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final block = find.byType(SpreadsheetBlockComponent);
    expect(block, findsOneWidget);
    for (final type in [
      AppFlowyEditor,
      KeyboardServiceWidget,
      SelectionServiceWidget,
    ]) {
      expect(
        find.ancestor(of: block, matching: find.byType(type)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: block, matching: find.byType(ResizableMedia)),
      findsOneWidget,
    );
    final context = tester.element(block);
    expect(PaperTheme.isEnabled(context), mode == 'paper');
    expect(
      Theme.of(context).brightness,
      mode == 'dark' ? Brightness.dark : Brightness.light,
    );
    expect(MediaQuery.textScalerOf(context).scale(12), 12 * scale);
    expect(
      LocaleKeys.spreadsheet_toolbar_find.tr(),
      isNot(LocaleKeys.spreadsheet_toolbar_find),
    );
    await body(fixture);
    expect(
      fixture.paragraph.delta!.toPlainText(),
      'Neighbouring paragraph stays unchanged',
    );
    expect(fixture.editor.document.root.children, hasLength(2));
    expect(tester.takeException(), isNull);
  } finally {
    for (final state
        in tester.stateList<EditableTextState>(find.byType(EditableText))) {
      state.hideToolbar();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.scroll.dispose();
    fixture.editor.dispose();
    fixture.layout.dispose();
    fixture.outsideFocus.dispose();
    // Dispose within the test body, before the framework's leak verification.
    semantics.dispose();
  }
}

SpreadsheetController _controller(WidgetTester tester) =>
    tester.widget<SpreadsheetGrid>(find.byType(SpreadsheetGrid)).controller;

Finder _headerButton(IconData icon) => find.descendant(
      of: find.byType(PreviewToolbar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.icon is Icon &&
            (widget.icon as Icon).icon == icon,
      ),
    );

Finder _findField() =>
    _fieldWithHint(LocaleKeys.spreadsheet_find_placeholder.tr());
Finder _replaceField() =>
    _fieldWithHint(LocaleKeys.spreadsheet_find_replacePlaceholder.tr());

Finder _fieldWithHint(String hint) => find.descendant(
      of: find.byType(SpreadsheetFindBar),
      matching: find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.hintText == hint,
      ),
    );

Finder _editableFinder(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

EditableText _editable(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(_editableFinder(field));

void _expectLineFits(WidgetTester tester, Finder field) {
  final render =
      tester.state<EditableTextState>(_editableFinder(field)).renderEditable;
  expect(render.size.height, greaterThanOrEqualTo(render.preferredLineHeight));
  final caret = render.getLocalRectForCaret(const TextPosition(offset: 0));
  final globalCaret = caret.shift(render.localToGlobal(Offset.zero));
  final bounds = tester.getRect(field);
  expect(globalCaret.top, greaterThanOrEqualTo(bounds.top - 0.01));
  expect(globalCaret.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
}

void _expectToolbar(WidgetTester tester, bool visible) {
  final toolbar = find.byType(PreviewToolbar);
  expect(toolbar, findsOneWidget);
  expect(
    tester
        .widget<AnimatedOpacity>(
          find
              .descendant(of: toolbar, matching: find.byType(AnimatedOpacity))
              .first,
        )
        .opacity,
    visible ? 1 : 0,
  );
  expect(
    tester
        .widget<IgnorePointer>(
          find
              .descendant(of: toolbar, matching: find.byType(IgnorePointer))
              .first,
        )
        .ignoring,
    !visible,
  );
  expect(
    tester
        .widget<ExcludeSemantics>(
          find
              .descendant(of: toolbar, matching: find.byType(ExcludeSemantics))
              .first,
        )
        .excluding,
    !visible,
  );
}

Future<void> _openFind(WidgetTester tester, _SheetFixture fixture) async {
  await _tabTo(tester, fixture, _headerButton(Icons.search_rounded));
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await _motion(tester);
  expect(find.byType(SpreadsheetFindBar), findsOneWidget);
  expect(_editable(tester, _findField()).focusNode.hasPrimaryFocus, isTrue);
}

bool _focusedInside(Finder finder) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null || !context.mounted) return false;
  final target = finder.evaluate().single;
  var found = identical(context, target);
  context.visitAncestorElements((element) {
    if (identical(element, target)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _tabTo(
  WidgetTester tester,
  _SheetFixture fixture,
  Finder button,
) async {
  fixture.outsideFocus.requestFocus();
  await _motion(tester);
  // The real block deliberately skips traversal into its nested FocusScope.
  // Enter at its native first button, then exercise actual Tab traversal among
  // the controls rather than changing the editor's keyboard service for tests.
  final firstIcon = find.descendant(
    of: _headerButton(Icons.search_rounded),
    matching: find.byType(Icon),
  );
  Focus.of(tester.element(firstIcon)).requestFocus();
  await _motion(tester);
  expect(_focusedInside(_headerButton(Icons.search_rounded)), isTrue);
  for (var attempt = 0; attempt < 30 && !_focusedInside(button); attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
  }
  expect(
    _focusedInside(button),
    isTrue,
    reason: 'Native sheet controls must remain in the Tab order',
  );
  await _motion(tester);
}

Future<void> _motion(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_fade);
  expect(tester.takeException(), isNull);
}

Set<int> _liveSemanticsIds(WidgetTester tester) {
  final ids = <int>{};
  void visit(SemanticsNode node) {
    ids.add(node.id);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = tester
      .binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode;
  if (root != null) visit(root);
  return ids;
}
