import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_block/custom_page_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_theme.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _appearances = [
  (name: 'light', brightness: Brightness.light, paper: false),
  (name: 'dark', brightness: Brightness.dark, paper: false),
  (name: 'paper', brightness: Brightness.light, paper: true),
];

void main() {
  for (final appearance in _appearances) {
    group('mouse editing in ${appearance.name}', () {
      testWidgets('a held press does not edit; accepted UP edits immediately',
          (tester) async {
        await _withGrid(
          tester,
          (fixture) async {
            final sheet = fixture.controller;
            final mouse = await tester.startGesture(
              _cellPoint(tester, const CellRef(1, 1)),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump(const Duration(milliseconds: 120));
            expect(sheet.isEditing, isFalse);
            expect(sheet.active, const CellRef(0, 0));
            expect(find.byType(TextField), findsNothing);
            await mouse.up();
            // No double-click timeout and no second click.
            await tester.pump();
            await tester.pump();
            expect(sheet.editing, const CellRef(1, 1));
            expect(_field(tester).focusNode!.hasFocus, isTrue);
            expect(_field(tester).controller!.text, '5');
            expect(sheet.canUndo, isFalse);
            await mouse.removePointer();
          },
          brightness: appearance.brightness,
          paper: appearance.paper,
        );
      });

      testWidgets('click, formula, Tab, typing, ShiftTab, Enter and Escape',
          (tester) async {
        await _withGrid(
          tester,
          (fixture) async {
            final sheet = fixture.controller;
            await _click(tester, _cellPoint(tester, const CellRef(1, 1)));
            await tester.enterText(find.byType(TextField), '=A1+B1');
            await _key(tester, LogicalKeyboardKey.tab);
            expect(sheet.data.rawAt(const CellRef(1, 1)), '=A1+B1');
            expect(sheet.valueAt(const CellRef(1, 1)).asNumber, 3);
            expect(sheet.active, const CellRef(1, 2));
            expect(sheet.isEditing, isFalse);

            await _key(tester, LogicalKeyboardKey.keyX);
            expect(sheet.editingText, 'x');
            expect(sheet.editingFromKeystroke, isTrue);
            await tester.enterText(find.byType(TextField), 'next value');
            await _key(tester, LogicalKeyboardKey.tab, shift: true);
            expect(sheet.data.rawAt(const CellRef(1, 2)), 'next value');
            expect(sheet.active, const CellRef(1, 1));

            await _key(tester, LogicalKeyboardKey.enter);
            expect(sheet.editingText, '=A1+B1');
            await tester.enterText(find.byType(TextField), 'cancel this');
            await _key(tester, LogicalKeyboardKey.escape);
            expect(sheet.isEditing, isFalse);
            expect(sheet.data.rawAt(const CellRef(1, 1)), '=A1+B1');

            await _key(tester, LogicalKeyboardKey.f2);
            expect(sheet.editingFromKeystroke, isFalse);
            await tester.enterText(find.byType(TextField), '=A1*B1');
            await _key(tester, LogicalKeyboardKey.enter);
            expect(sheet.active, const CellRef(2, 1));
            expect(sheet.valueAt(const CellRef(1, 1)).asNumber, 2);
            await _key(tester, LogicalKeyboardKey.enter);
            await tester.enterText(find.byType(TextField), '12');
            await _key(tester, LogicalKeyboardKey.enter, shift: true);
            expect(sheet.active, const CellRef(1, 1));
            expect(sheet.data.rawAt(const CellRef(2, 1)), '12');
          },
          brightness: appearance.brightness,
          paper: appearance.paper,
        );
      });

      testWidgets('clicking another cell commits once without eating its tap',
          (tester) async {
        await _withGrid(
          tester,
          (fixture) async {
            final sheet = fixture.controller;
            await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
            await tester.enterText(find.byType(TextField), 'saved once');
            final editingFocus = _field(tester).focusNode!;
            final focusChanges = <String>[];
            void recordFocus() {
              focusChanges.add(
                'focused=${editingFocus.hasFocus}, editing=${sheet.editing}',
              );
            }

            editingFocus.addListener(recordFocus);
            final next = await tester.startGesture(
              _cellPoint(tester, const CellRef(1, 1)),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump(const Duration(milliseconds: 120));
            expect(sheet.editing, const CellRef(0, 0));
            expect(sheet.data.rawAt(const CellRef(0, 0)), '1');
            await next.up();
            await tester.pump();
            await tester.pump();
            editingFocus.removeListener(recordFocus);
            expect(sheet.data.rawAt(const CellRef(0, 0)), 'saved once');
            expect(
              sheet.editing,
              const CellRef(1, 1),
              reason: 'Focus transitions while switching cells: $focusChanges',
            );
            expect(_field(tester).controller!.text, '5');
            expect(_field(tester).focusNode!.hasFocus, isTrue);
            expect(_field(tester).focusNode, same(editingFocus));
            expect(
              focusChanges,
              isEmpty,
              reason: 'The retained cell editor must not lose focus',
            );
            await next.removePointer();
            await _key(tester, LogicalKeyboardKey.escape);
            sheet.undo();
            await tester.pump();
            expect(sheet.data.rawAt(const CellRef(0, 0)), '1');
            expect(sheet.canUndo, isFalse, reason: 'one cell commit, one undo');
            sheet.redo();
            await tester.pump();
            expect(sheet.data.rawAt(const CellRef(0, 0)), 'saved once');
          },
          brightness: appearance.brightness,
          paper: appearance.paper,
        );
      });

      testWidgets('same-cell clicks place the caret without committing',
          (tester) async {
        await _withGrid(
          tester,
          (fixture) async {
            final sheet = fixture.controller;
            await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
            await tester.enterText(find.byType(TextField), 'alpha beta gamma');
            final state =
                tester.state<EditableTextState>(find.byType(EditableText));
            await tester.pump(kDoubleTapTimeout);
            await _click(tester, _caretPoint(tester, 3));
            expect(
              tester.state<EditableTextState>(find.byType(EditableText)),
              same(state),
            );
            expect(
              _field(tester).controller!.selection,
              const TextSelection.collapsed(offset: 3),
            );
            expect(sheet.editingText, 'alpha beta gamma');
            expect(sheet.data.rawAt(const CellRef(0, 0)), '1');
            expect(sheet.canUndo, isFalse);
            await _key(tester, LogicalKeyboardKey.arrowRight, shift: true);
            expect(
              _field(tester).controller!.selection,
              const TextSelection(baseOffset: 3, extentOffset: 4),
            );
            await _key(tester, LogicalKeyboardKey.backspace);
            expect(sheet.editingText, 'alpa beta gamma');
            expect(sheet.isEditing, isTrue);
          },
          data: _sample()..setColumn(0, const SheetColumn(width: 360)),
          brightness: appearance.brightness,
          paper: appearance.paper,
        );
      });

      testWidgets(
          'native text dragging survives frames and does not select cells',
          (tester) async {
        await _withGrid(
          tester,
          (fixture) async {
            final sheet = fixture.controller;
            await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
            await tester.enterText(find.byType(TextField), 'alpha beta gamma');
            await tester.pump(kDoubleTapTimeout);
            final text = _field(tester).controller!;
            final state =
                tester.state<EditableTextState>(find.byType(EditableText));
            final from = _caretPoint(tester, 1);
            final middle = _caretPoint(tester, 5);
            final to = _caretPoint(tester, 9);
            final drag =
                await tester.startGesture(from, kind: PointerDeviceKind.mouse);
            await tester.pump();
            await drag.moveTo(middle);
            await tester.pump();
            expect(sheet.isEditing, isTrue);
            await drag.moveTo(to);
            await tester.pump();
            await drag.up();
            await tester.pump();
            expect(
              tester.state<EditableTextState>(find.byType(EditableText)),
              same(state),
            );
            expect(text.selection.isCollapsed, isFalse);
            expect(text.selection.textInside(text.text), 'lpha bet');
            expect(sheet.selection, CellRange.single(const CellRef(0, 0)));
            expect(sheet.canUndo, isFalse);
            await drag.removePointer();
          },
          data: _sample()..setColumn(0, const SheetColumn(width: 360)),
          brightness: appearance.brightness,
          paper: appearance.paper,
        );
      });
    });
  }

  testWidgets('a cancelled pointer cannot start an edit', (tester) async {
    await _withGrid(tester, (fixture) async {
      final pointer = await tester.startGesture(
        _cellPoint(tester, const CellRef(1, 1)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 120));
      await pointer.cancel();
      await tester.pump();
      expect(fixture.controller.isEditing, isFalse);
      expect(fixture.controller.active, const CellRef(0, 0));
      expect(fixture.controller.canUndo, isFalse);
      await pointer.removePointer();
    });
  });

  for (final align in CellAlign.values) {
    testWidgets('painted and editable glyph positions agree: ${align.name}',
        (tester) async {
      final data = _sample()
        ..setRaw(const CellRef(0, 0), 'Stable')
        ..setStyle(const CellRef(0, 0), CellStyle(align: align));
      await _withGrid(
        tester,
        (fixture) async {
          const ref = CellRef(0, 0);
          final body = _bodyPainter(tester);
          final style = cellTextStyle(
            base: body.typography.cell,
            style: data.styleAt(ref),
            palette: body.palette,
            isError: false,
          );
          final textAlign =
              resolveAlign(data.styleAt(ref), fixture.controller.valueAt(ref));
          final painted = body.textCache.painterFor(
            ref: ref,
            text: 'Stable',
            style: style,
            maxWidth: SheetColumn.defaultWidth -
                SpreadsheetMetrics.cellPaddingHorizontal * 2,
            align: textAlign,
          );
          final x = switch (textAlign) {
            TextAlign.right => SheetColumn.defaultWidth -
                SpreadsheetMetrics.cellPaddingHorizontal -
                painted.width,
            TextAlign.center => (SheetColumn.defaultWidth - painted.width) / 2,
            _ => SpreadsheetMetrics.cellPaddingHorizontal,
          };
          const selection = TextSelection(baseOffset: 0, extentOffset: 6);
          final expected = _bodyOrigin(tester) +
              Offset(x, (SheetRow.defaultHeight - painted.height) / 2) +
              painted.getBoxesForSelection(selection).first.toRect().topLeft;
          await _click(tester, _cellPoint(tester, ref));
          final render =
              tester.state<EditableTextState>(_editable()).renderEditable;
          final actual = render.localToGlobal(
            render.getBoxesForSelection(selection).first.toRect().topLeft,
          );
          expect(actual.dx, closeTo(expected.dx, 0.01));
          expect(actual.dy, closeTo(expected.dy, 0.01));
          final container = tester.widget<Container>(
            find.ancestor(
              of: _editorField(),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.foregroundDecoration is BoxDecoration,
              ),
            ),
          );
          expect((container.decoration! as BoxDecoration).boxShadow, isNull);
          expect(
            (container.foregroundDecoration! as BoxDecoration).boxShadow,
            isNull,
          );
          expect(_field(tester).style, style);
          await _key(tester, LogicalKeyboardKey.escape);
          expect(fixture.controller.canUndo, isFalse);
        },
        data: data,
      );
    });
  }

  for (final appearance in _appearances) {
    testWidgets(
        'editing preserves explicit fill and text style: ${appearance.name}',
        (tester) async {
      const stored = CellStyle(
        backgroundColor: 0xFFF3DFB9,
        textColor: 0xFF423326,
        italic: true,
        underline: true,
        align: CellAlign.center,
      );
      final data = _sample()..setStyle(const CellRef(0, 0), stored);
      await _withGrid(
        tester,
        (fixture) async {
          await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
          final container = tester.widget<Container>(
            find.ancestor(
              of: _editorField(),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.foregroundDecoration is BoxDecoration,
              ),
            ),
          );
          expect(
            (container.decoration! as BoxDecoration).color,
            const Color(0xFFF3DFB9),
          );
          expect(_field(tester).style!.color, const Color(0xFF423326));
          expect(_field(tester).style!.fontStyle, FontStyle.italic);
          expect(_field(tester).style!.decoration, TextDecoration.underline);
          expect(_field(tester).textAlign, TextAlign.center);
          await tester.enterText(_editorField(), 'saved');
          await _key(tester, LogicalKeyboardKey.tab);
          expect(fixture.controller.data.styleAt(const CellRef(0, 0)), stored);
          fixture.controller.undo();
          expect(fixture.controller.data.styleAt(const CellRef(0, 0)), stored);
          expect(fixture.controller.data.rawAt(const CellRef(0, 0)), '1');
        },
        data: data,
        brightness: appearance.brightness,
        paper: appearance.paper,
      );
    });
  }

  testWidgets('an inert outside press commits only after an accepted release',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
      await tester.enterText(_editorField(), 'outside commit');
      final outside = await tester.startGesture(
        const Offset(780, 560),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(fixture.controller.isEditing, isTrue);
      expect(fixture.controller.data.rawAt(const CellRef(0, 0)), '1');
      await outside.up();
      await tester.pump();
      await tester.pump();
      expect(fixture.controller.isEditing, isFalse);
      expect(
        fixture.controller.data.rawAt(const CellRef(0, 0)),
        'outside commit',
      );
      fixture.controller.undo();
      expect(fixture.controller.canUndo, isFalse);
      await outside.removePointer();
    });
  });

  testWidgets('an outside drag does not dismiss the draft', (tester) async {
    await _withGrid(tester, (fixture) async {
      await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
      await tester.enterText(_editorField(), 'still a draft');
      final outside = await tester.startGesture(
        const Offset(750, 500),
        kind: PointerDeviceKind.mouse,
      );
      await outside.moveBy(const Offset(20, 20));
      await tester.pump();
      await outside.moveBy(const Offset(20, 20));
      await tester.pump();
      await outside.up();
      await tester.pump();
      expect(fixture.controller.editingText, 'still a draft');
      expect(fixture.controller.isEditing, isTrue);
      expect(fixture.controller.canUndo, isFalse);
      await outside.removePointer();
    });
  });

  testWidgets(
      'an old outside tap cannot commit a reopened edit at the same cell',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
      await tester.enterText(_editorField(), 'first draft');
      final outside = await tester.startGesture(
        const Offset(750, 500),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.escape);
      await _key(tester, LogicalKeyboardKey.f2);
      await tester.enterText(_editorField(), 'second draft');
      await outside.up();
      await tester.pump();
      expect(fixture.controller.isEditing, isTrue);
      expect(fixture.controller.editingText, 'second draft');
      expect(fixture.controller.data.rawAt(const CellRef(0, 0)), '1');
      expect(fixture.controller.canUndo, isFalse);
      await outside.removePointer();
    });
  });

  testWidgets('clicking another field commits without stealing its focus',
      (tester) async {
    final outside = TextEditingController();
    final focus = FocusNode();
    const outsideKey = ValueKey('outside-field');
    try {
      await _withGrid(tester, (fixture) async {
        await tester.pumpWidget(
          fixture.app(
            trailing: TextField(
              key: outsideKey,
              controller: outside,
              focusNode: focus,
            ),
          ),
        );
        await tester.pump();
        await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
        await tester.enterText(_editorField(), 'cell draft');
        await _click(tester, tester.getCenter(find.byKey(outsideKey)));
        await tester.pump();
        expect(
          fixture.controller.data.rawAt(const CellRef(0, 0)),
          'cell draft',
        );
        expect(fixture.controller.isEditing, isFalse);
        expect(focus.hasFocus, isTrue);
        await tester.enterText(find.byKey(outsideKey), 'outside draft');
        expect(outside.text, 'outside draft');
        expect(
          fixture.controller.data.rawAt(const CellRef(0, 0)),
          'cell draft',
        );
      });
    } finally {
      outside.dispose();
      focus.dispose();
    }
  });

  testWidgets('native double click selects a word in the existing field',
      (tester) async {
    await _withGrid(
      tester,
      (fixture) async {
        await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
        await tester.enterText(find.byType(TextField), 'alpha beta gamma');
        await tester.pump(kDoubleTapTimeout);
        final point = _caretPoint(tester, 8);
        await _click(tester, point);
        await tester.pump(const Duration(milliseconds: 50));
        await _click(tester, point);
        final text = _field(tester).controller!;
        expect(text.selection.textInside(text.text), 'beta');
        expect(fixture.controller.isEditing, isTrue);
        expect(fixture.controller.canUndo, isFalse);
      },
      data: _sample()..setColumn(0, const SheetColumn(width: 360)),
    );
  });

  testWidgets('F2 changes a typed draft to caret editing without reloading it',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final sheet = fixture.controller;
      await _key(tester, LogicalKeyboardKey.keyX);
      await tester.enterText(find.byType(TextField), 'draft');
      await _key(tester, LogicalKeyboardKey.f2);
      expect(sheet.editingText, 'draft');
      expect(sheet.editingFromKeystroke, isFalse);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(_field(tester).controller!.selection.extentOffset, 4);
      await _key(tester, LogicalKeyboardKey.numpadEnter);
      expect(sheet.data.rawAt(const CellRef(0, 0)), 'draft');
      expect(sheet.active, const CellRef(1, 0));
    });
  });

  testWidgets(
    'text selection, copy, cut, paste and undo stay in the field',
    (tester) async {
      var clipboard = '';
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        switch (call.method) {
          case 'Clipboard.setData':
            clipboard = (call.arguments as Map)['text'] as String;
            return null;
          case 'Clipboard.getData':
            return {'text': clipboard};
          case 'Clipboard.hasStrings':
            return {'value': clipboard.isNotEmpty};
        }
        return null;
      });
      try {
        await _withGrid(tester, (fixture) async {
          final sheet = fixture.controller;
          await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
          await tester.enterText(find.byType(TextField), 'alpha beta');
          await tester.pump(const Duration(milliseconds: 600));
          await _key(tester, LogicalKeyboardKey.keyA, control: true);
          expect(
            _field(tester).controller!.selection,
            const TextSelection(baseOffset: 0, extentOffset: 10),
          );
          expect(sheet.selection.isSingle, isTrue);
          await _key(tester, LogicalKeyboardKey.keyC, control: true);
          expect(clipboard, 'alpha beta');
          await _key(tester, LogicalKeyboardKey.keyX, control: true);
          expect(sheet.editingText, '');
          expect(sheet.data.rawAt(const CellRef(0, 0)), '1');
          await tester.pump(const Duration(milliseconds: 600));
          await _key(tester, LogicalKeyboardKey.keyV, control: true);
          expect(sheet.editingText, 'alpha beta');
          await tester.pump(const Duration(milliseconds: 600));
          await _key(tester, LogicalKeyboardKey.keyZ, control: true);
          expect(sheet.editingText, '');
          expect(sheet.isEditing, isTrue);
          expect(sheet.canUndo, isFalse);
          expect(sheet.data.rawAt(const CellRef(0, 1)), '2');
        });
      } finally {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('Shift click commits the old draft and extends without editing',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final sheet = fixture.controller;
      await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
      await tester.enterText(find.byType(TextField), 'kept');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      try {
        await _click(tester, _cellPoint(tester, const CellRef(2, 1)));
      } finally {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      expect(
        sheet.selection,
        const CellRange.raw(top: 0, left: 0, bottom: 2, right: 1),
      );
      expect(sheet.isEditing, isFalse);
      expect(sheet.data.rawAt(const CellRef(0, 0)), 'kept');
      sheet.undo();
      expect(sheet.canUndo, isFalse);
    });
  });

  for (final modifier in [
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.metaLeft,
  ]) {
    testWidgets('${modifier.keyLabel} click selects without starting an edit',
        (tester) async {
      await _withGrid(tester, (fixture) async {
        await tester.sendKeyDownEvent(modifier);
        try {
          await _click(tester, _cellPoint(tester, const CellRef(1, 1)));
        } finally {
          await tester.sendKeyUpEvent(modifier);
        }
        expect(fixture.controller.active, const CellRef(1, 1));
        expect(fixture.controller.isEditing, isFalse);
      });
    });
  }

  for (final shift in [false, true]) {
    testWidgets(
        'drag range selection survives intermediate frames: shift=$shift',
        (tester) async {
      await _withGrid(tester, (fixture) async {
        final sheet = fixture.controller;
        final original = sheet.toJson();
        if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        final drag = await tester.startGesture(
          _cellPoint(tester, const CellRef(1, 0)),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(sheet.isEditing, isFalse);
        await drag.moveTo(_cellPoint(tester, const CellRef(2, 1)));
        await tester.pump();
        expect(sheet.isEditing, isFalse);
        expect(sheet.selection.rowCount, greaterThan(1));
        await drag.moveTo(_cellPoint(tester, const CellRef(3, 2)));
        await tester.pump();
        await drag.up();
        if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(sheet.anchor, CellRef(shift ? 0 : 1, 0));
        expect(sheet.active, const CellRef(3, 2));
        expect(sheet.isEditing, isFalse);
        expect(sheet.toJson(), original);
        await drag.removePointer();
      });
    });
  }

  testWidgets('dragging from another cell commits without opening a new field',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final sheet = fixture.controller;
      await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
      await tester.enterText(find.byType(TextField), 'draft');
      final drag = await tester.startGesture(
        _cellPoint(tester, const CellRef(1, 1)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(sheet.editing, const CellRef(0, 0));
      await drag.moveTo(_cellPoint(tester, const CellRef(2, 1)));
      await tester.pump();
      await drag.moveTo(_cellPoint(tester, const CellRef(3, 2)));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(sheet.isEditing, isFalse);
      expect(sheet.data.rawAt(const CellRef(0, 0)), 'draft');
      expect(
        sheet.selection,
        const CellRange.raw(top: 1, left: 1, bottom: 3, right: 2),
      );
      await drag.removePointer();
    });
  });

  testWidgets('fill handle press never edits or collapses the source range',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final sheet = fixture.controller;
      sheet.selectRange(const CellRef(0, 0), const CellRef(1, 0));
      await tester.pump();
      final source = sheet.selection;
      final handle = _bodyOrigin(tester) +
          const Offset(SheetColumn.defaultWidth, SheetRow.defaultHeight * 2);
      final drag =
          await tester.startGesture(handle, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 120));
      expect(sheet.selection, source);
      expect(sheet.isEditing, isFalse);
      await drag.moveBy(const Offset(0, 20));
      await tester.pump();
      expect(sheet.selection, source);
      expect(_bodyPainter(tester).fillPreview, isNotNull);
      await drag.moveBy(const Offset(0, 44));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(sheet.data.rawAt(const CellRef(2, 0)), '7');
      expect(sheet.data.rawAt(const CellRef(3, 0)), '10');
      expect(sheet.isEditing, isFalse);
      sheet.undo();
      expect(sheet.data.rawAt(const CellRef(2, 0)), '7');
      expect(sheet.data.rawAt(const CellRef(3, 0)), '');
      expect(sheet.canUndo, isFalse);
      await drag.removePointer();
    });
  });

  testWidgets('a cancelled fill leaves data and the source selection untouched',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final sheet = fixture.controller;
      final stored = sheet.toJson();
      sheet.selectRange(const CellRef(0, 0), const CellRef(1, 0));
      await tester.pump();
      final source = sheet.selection;
      final drag = await tester.startGesture(
        _bodyOrigin(tester) +
            const Offset(SheetColumn.defaultWidth, SheetRow.defaultHeight * 2),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(0, 20));
      await tester.pump();
      await drag.moveBy(const Offset(0, 44));
      await tester.pump();
      expect(_bodyPainter(tester).fillPreview, isNotNull);
      await drag.cancel();
      await tester.pump();
      expect(_bodyPainter(tester).fillPreview, isNull);
      expect(sheet.selection, source);
      expect(sheet.toJson(), stored);
      expect(sheet.canUndo, isFalse);
      expect(sheet.isEditing, isFalse);
      await drag.removePointer();
    });
  });

  testWidgets(
      'right click and row/column/corner selection do not start editing',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final sheet = fixture.controller;
      final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
      await _click(
        tester,
        origin + const Offset(SpreadsheetMetrics.gutterWidth + 20, 17),
      );
      expect(sheet.selectedColumnHeader, 0);
      expect(sheet.isEditing, isFalse);
      await _click(
        tester,
        origin + const Offset(20, SpreadsheetMetrics.headerHeight + 51),
      );
      expect(sheet.selection.columnCount, sheet.data.columnCount);
      expect(sheet.selection.rowCount, 1);
      expect(sheet.isEditing, isFalse);
      await _click(tester, origin + const Offset(20, 17));
      expect(
        sheet.selection.cellCount,
        sheet.data.rowCount * sheet.data.columnCount,
      );
      expect(sheet.isEditing, isFalse);
      final selection = sheet.selection;
      await _click(
        tester,
        _cellPoint(tester, const CellRef(1, 1)),
        buttons: kSecondaryMouseButton,
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(sheet.selection, selection);
      expect(sheet.isEditing, isFalse);
      expect(find.byType(TextField), findsNothing);
      await _key(tester, LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 200));
    });
  });

  for (final column in [true, false]) {
    testWidgets(
        '${column ? 'column' : 'row'} resize retains draft and has one undo',
        (tester) async {
      await _withGrid(tester, (fixture) async {
        final sheet = fixture.controller;
        await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
        await tester.enterText(find.byType(TextField), 'resize draft');
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'resize draft',
            selection: TextSelection(baseOffset: 2, extentOffset: 5),
          ),
        );
        await tester.pump();
        final before = _field(tester).controller!.value;
        final state =
            tester.state<EditableTextState>(find.byType(EditableText));
        final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
        final point = origin +
            (column
                ? const Offset(
                    SpreadsheetMetrics.gutterWidth + SheetColumn.defaultWidth,
                    17,
                  )
                : const Offset(
                    20,
                    SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight,
                  ));
        final drag =
            await tester.startGesture(point, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 120));
        expect(sheet.editingText, before.text);
        for (var step = 0; step < 2; step++) {
          await drag.moveBy(column ? const Offset(20, 0) : const Offset(0, 12));
          await tester.pump();
          expect(
            tester.state<EditableTextState>(find.byType(EditableText)),
            same(state),
          );
          expect(_field(tester).controller!.value, before);
          expect(sheet.data.rawAt(const CellRef(0, 0)), '1');
        }
        await drag.up();
        await tester.pump();
        expect(_field(tester).controller!.value, before);
        expect(
          column ? sheet.data.columnWidth(0) : sheet.data.rowHeight(0),
          column ? SheetColumn.defaultWidth + 40 : SheetRow.defaultHeight + 24,
        );
        await drag.removePointer();
        await _key(tester, LogicalKeyboardKey.escape);
        sheet.undo();
        await tester.pump();
        expect(sheet.data.columnWidth(0), SheetColumn.defaultWidth);
        expect(sheet.data.rowHeight(0), SheetRow.defaultHeight);
        expect(sheet.canUndo, isFalse);
      });
    });
  }

  for (final column in [true, false]) {
    testWidgets(
        'cancelled ${column ? 'column' : 'row'} resize restores geometry without recording an edit',
        (tester) async {
      await _withGrid(tester, (fixture) async {
        final stored = fixture.controller.toJson();
        final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
        final point = origin +
            (column
                ? const Offset(
                    SpreadsheetMetrics.gutterWidth + SheetColumn.defaultWidth,
                    17,
                  )
                : const Offset(
                    20,
                    SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight,
                  ));
        final delta = column ? const Offset(20, 0) : const Offset(0, 12);
        final drag =
            await tester.startGesture(point, kind: PointerDeviceKind.mouse);
        await drag.moveBy(delta);
        await tester.pump();
        await drag.moveBy(delta);
        await tester.pump();
        expect(
          column
              ? fixture.controller.data.columnWidth(0)
              : fixture.controller.data.rowHeight(0),
          column ? SheetColumn.defaultWidth + 40 : SheetRow.defaultHeight + 24,
        );
        await drag.cancel();
        await tester.pump();
        expect(
          fixture.controller.data.columnWidth(0),
          SheetColumn.defaultWidth,
        );
        expect(fixture.controller.data.rowHeight(0), SheetRow.defaultHeight);
        expect(
          _bodyPainter(tester).geometry.columnWidth(0),
          SheetColumn.defaultWidth,
        );
        expect(
          _bodyPainter(tester).geometry.rowHeight(0),
          SheetRow.defaultHeight,
        );
        expect(fixture.controller.toJson(), stored);
        expect(fixture.controller.canUndo, isFalse);
        await drag.removePointer();
      });
    });
  }

  testWidgets('a cancelled column reorder keeps data and history unchanged',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final stored = fixture.controller.toJson();
      final origin = tester.getTopLeft(find.byType(SpreadsheetGrid)) +
          const Offset(SpreadsheetMetrics.gutterWidth, 0);
      final drag = await tester.startGesture(
        origin + const Offset(40, 17),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(150, 0));
      await tester.pump();
      await drag.moveBy(const Offset(180, 0));
      await tester.pump();
      expect(fixture.controller.toJson(), stored);
      await drag.cancel();
      await tester.pump();
      expect(fixture.controller.toJson(), stored);
      expect(fixture.controller.canUndo, isFalse);
      expect(fixture.controller.isEditing, isFalse);
      await drag.removePointer();
    });
  });

  testWidgets('column reordering remains a single undoable mouse drag',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final origin = tester.getTopLeft(find.byType(SpreadsheetGrid)) +
          const Offset(SpreadsheetMetrics.gutterWidth, 0);
      final drag = await tester.startGesture(
        origin + const Offset(40, 17),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(fixture.controller.isEditing, isFalse);
      await drag.moveBy(const Offset(150, 0));
      await tester.pump();
      await drag.moveBy(const Offset(180, 0));
      await tester.pump();
      await drag.up();
      await tester.pump();
      expect(fixture.controller.data.toRows().first, ['2', '3', '1']);
      expect(fixture.controller.isEditing, isFalse);
      fixture.controller.undo();
      expect(fixture.controller.data.toRows().first, ['1', '2', '3']);
      expect(fixture.controller.canUndo, isFalse);
      await drag.removePointer();
    });
  });

  testWidgets('header rename uses the same draft, Tab and Escape lifecycle',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
      final point =
          origin + const Offset(SpreadsheetMetrics.gutterWidth + 30, 17);
      await _click(tester, point);
      await tester.pump(const Duration(milliseconds: 50));
      await _click(tester, point);
      expect(fixture.controller.editingHeader, 0);
      expect(_field(tester).controller!.text, 'First');
      await tester.enterText(find.byType(TextField), 'Renamed');
      await _key(tester, LogicalKeyboardKey.tab);
      expect(fixture.controller.data.columnTitle(0), 'Renamed');
      expect(fixture.controller.data.rawAt(const CellRef(0, 0)), '1');
      final rows = fixture.controller.data.rowCount;
      fixture.controller.startEditingHeader(1);
      await tester.pump();
      await tester.pump();
      await tester.enterText(_editorField(), 'New title');
      await _key(tester, LogicalKeyboardKey.enter);
      expect(fixture.controller.data.columnTitle(1), 'New title');
      expect(fixture.controller.data.rowCount, rows);
      fixture.controller.startEditingHeader(0);
      await tester.pump();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Discard');
      await _key(tester, LogicalKeyboardKey.escape);
      expect(fixture.controller.data.columnTitle(0), 'Renamed');
      fixture.controller.undo();
      expect(fixture.controller.data.columnTitle(1), 'Second');
      fixture.controller.undo();
      expect(fixture.controller.data.columnTitle(0), 'First');
      expect(fixture.controller.canUndo, isFalse);
    });
  });

  testWidgets('a header draft switches directly into a focused body editor',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      final sheet = fixture.controller;
      sheet.startEditingHeader(0);
      await tester.pump();
      await tester.pump();
      await tester.enterText(_editorField(), 'Renamed once');
      final focus = _field(tester).focusNode;
      await _click(tester, _cellPoint(tester, const CellRef(1, 1)));
      expect(sheet.data.columnTitle(0), 'Renamed once');
      expect(sheet.editingHeader, isNull);
      expect(sheet.editing, const CellRef(1, 1));
      expect(_field(tester).controller!.text, '5');
      expect(_field(tester).focusNode, same(focus));
      expect(focus!.hasFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.escape);
      sheet.undo();
      expect(sheet.data.columnTitle(0), 'First');
      expect(sheet.canUndo, isFalse);
    });
  });

  testWidgets('header and gutter retain semantic tap and axis drag actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await _withGrid(tester, (fixture) async {
        for (final (type, actions) in [
          (
            SheetHorizontalDragGestureRecognizer,
            [ui.SemanticsAction.scrollLeft, ui.SemanticsAction.scrollRight],
          ),
          (
            SheetVerticalDragGestureRecognizer,
            [ui.SemanticsAction.scrollUp, ui.SemanticsAction.scrollDown],
          ),
        ]) {
          final detector = find.byWidgetPredicate(
            (widget) =>
                widget is RawGestureDetector &&
                widget.gestures.containsKey(type),
          );
          final data = tester.getSemantics(detector).getSemanticsData();
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          for (final action in actions) {
            expect(data.hasAction(action), isTrue, reason: '$type: $action');
          }
        }
      });
    } finally {
      semantics.dispose();
    }
  });

  for (final readOnly in [
    (widget: false, controller: true),
    (widget: true, controller: false),
    (widget: false, controller: false),
  ]) {
    testWidgets(
        'readonly at either boundary blocks editing and mutations: $readOnly',
        (tester) async {
      await _withGrid(
        tester,
        (fixture) async {
          final sheet = fixture.controller;
          final original = sheet.toJson();
          await _click(tester, _cellPoint(tester, const CellRef(1, 1)));
          expect(sheet.active, const CellRef(1, 1));
          expect(sheet.isEditing, isFalse);
          for (final key in [
            LogicalKeyboardKey.f2,
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.keyX,
            LogicalKeyboardKey.delete,
          ]) {
            await _key(tester, key);
          }
          for (final key in [
            LogicalKeyboardKey.keyB,
            LogicalKeyboardKey.keyI,
            LogicalKeyboardKey.keyU,
            LogicalKeyboardKey.keyV,
            LogicalKeyboardKey.keyZ,
          ]) {
            await _key(tester, key, control: true);
          }
          final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
          for (final column in [true, false]) {
            final point = origin +
                (column
                    ? const Offset(
                        SpreadsheetMetrics.gutterWidth +
                            SheetColumn.defaultWidth,
                        17,
                      )
                    : const Offset(
                        20,
                        SpreadsheetMetrics.headerHeight +
                            SheetRow.defaultHeight,
                      ));
            final drag =
                await tester.startGesture(point, kind: PointerDeviceKind.mouse);
            await drag
                .moveBy(column ? const Offset(20, 0) : const Offset(0, 20));
            await tester.pump();
            await drag
                .moveBy(column ? const Offset(40, 0) : const Offset(0, 40));
            await tester.pump();
            await drag.up();
            await tester.pump();
            await drag.removePointer();
          }
          sheet.selectRange(const CellRef(0, 0), const CellRef(1, 0));
          await tester.pump();
          final fill = await tester.startGesture(
            _bodyOrigin(tester) +
                const Offset(
                  SheetColumn.defaultWidth,
                  SheetRow.defaultHeight * 2,
                ),
            kind: PointerDeviceKind.mouse,
          );
          await fill.moveBy(const Offset(0, 20));
          await tester.pump();
          await fill.moveBy(const Offset(0, 44));
          await tester.pump();
          await fill.up();
          await tester.pump();
          await fill.removePointer();
          expect(sheet.toJson(), original);
          expect(sheet.isEditing, isFalse);
          expect(_bodyPainter(tester).geometry.showAddAffordances, isFalse);
          expect(find.byType(TextField), findsNothing);
        },
        editable: readOnly.widget,
        controllerEditable: readOnly.controller,
      );
    });
  }

  for (final commit in [false, true]) {
    testWidgets(
        'source rebind and viewport resize retain the draft: commit=$commit',
        (tester) async {
      await _withGrid(tester, (fixture) async {
        await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
        const value = TextEditingValue(
          text: 'local draft',
          selection: TextSelection(baseOffset: 2, extentOffset: 6),
          composing: TextRange(start: 0, end: 6),
        );
        tester.testTextInput.updateEditingValue(value);
        await tester.pump();
        final state =
            tester.state<EditableTextState>(find.byType(EditableText));
        final textController = _field(tester).controller;
        final incoming = fixture.controller.data.clone()
          ..setRaw(const CellRef(0, 0), 'remote value')
          ..setRaw(const CellRef(2, 1), 'remote neighbour');
        // Match the real block's order: it disposes the old controller BEFORE
        // the retained grid receives its replacement.
        fixture.controller.dispose();
        fixture.controller = SpreadsheetController(data: incoming);
        await tester.pumpWidget(fixture.app(width: 520, height: 270));
        await tester.pump();
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(state),
        );
        expect(_field(tester).controller, same(textController));
        expect(_field(tester).controller!.value, value);
        expect(_field(tester).focusNode!.hasFocus, isTrue);
        expect(fixture.controller.editingText, value.text);
        expect(
          fixture.controller.data.rawAt(const CellRef(2, 1)),
          'remote neighbour',
        );
        await _key(
          tester,
          commit ? LogicalKeyboardKey.tab : LogicalKeyboardKey.escape,
        );
        expect(
          fixture.controller.data.rawAt(const CellRef(0, 0)),
          commit ? value.text : 'remote value',
        );
        expect(fixture.controller.canUndo, commit);
        if (commit) {
          fixture.controller.undo();
          expect(
            fixture.controller.data.rawAt(const CellRef(0, 0)),
            'remote value',
          );
          expect(
            fixture.controller.data.rawAt(const CellRef(2, 1)),
            'remote neighbour',
          );
          expect(fixture.controller.canUndo, isFalse);
        }
      });
    });
  }

  testWidgets('scroll offsets move the editor without replacing its draft',
      (tester) async {
    await _withGrid(
      tester,
      (fixture) async {
        await _click(tester, _cellPoint(tester, const CellRef(2, 1)));
        await tester.enterText(find.byType(TextField), 'scroll draft');
        final state =
            tester.state<EditableTextState>(find.byType(EditableText));
        final before = tester.getTopLeft(find.byType(TextField));
        _bodyPainter(tester).vertical.jumpTo(20);
        _bodyPainter(tester).horizontal.jumpTo(30);
        await tester.pump();
        expect(
          tester.getTopLeft(find.byType(TextField)),
          before - const Offset(30, 20),
        );
        expect(
          tester.state<EditableTextState>(find.byType(EditableText)),
          same(state),
        );
        expect(fixture.controller.editingText, 'scroll draft');
      },
      data: SpreadsheetData.empty(rows: 30, columns: 12),
    );
  });

  testWidgets('trackpad scrolling stays scrolling, not selection or editing',
      (tester) async {
    await _withGrid(
      tester,
      (fixture) async {
        final point = _cellPoint(tester, const CellRef(2, 1));
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(
            pointer: 81,
            device: 81,
            position: point,
          ),
        );
        for (var step = 1; step <= 3; step++) {
          await tester.sendEventToBinding(
            PointerPanZoomUpdateEvent(
              pointer: 81,
              device: 81,
              position: point,
              pan: Offset(0, -24.0 * step),
              panDelta: const Offset(0, -24),
              timeStamp: Duration(milliseconds: step * 20),
            ),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            pointer: 81,
            device: 81,
            position: point,
            pan: const Offset(0, -72),
            timeStamp: const Duration(milliseconds: 200),
          ),
        );
        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(
            pointer: 81,
            device: 81,
            position: point,
            timeStamp: const Duration(milliseconds: 201),
          ),
        );
        await tester.pumpAndSettle();
        expect(_bodyPainter(tester).vertical.offset, greaterThan(0));
        expect(fixture.controller.active, const CellRef(0, 0));
        expect(fixture.controller.isEditing, isFalse);
        expect(fixture.controller.canUndo, isFalse);
      },
      data: SpreadsheetData.empty(rows: 30, columns: 12),
    );
  });

  for (final motion in [
    (disabled: false, accessible: false),
    (disabled: true, accessible: false),
    (disabled: false, accessible: true),
  ]) {
    testWidgets('interaction-only canvas fades respect media flags: $motion',
        (tester) async {
      await _withGrid(
        tester,
        (fixture) async {
          final reduced = motion.disabled || motion.accessible;
          expect(_bodyPainter(tester).selectionSettle.value, 1);
          expect(tester.binding.transientCallbackCount, 0);
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(780, 580));
          await mouse.moveTo(_cellPoint(tester, const CellRef(1, 1)));
          await tester.pump();
          final hovered = _bodyPainter(tester);
          expect(hovered.hoveredCell, const CellRef(1, 1));
          expect(hovered.hoverSettle.value, reduced ? 1 : lessThan(1));
          await tester.pump(const Duration(milliseconds: 40));
          expect(
            _bodyPainter(tester),
            same(hovered),
            reason: 'ticks must not rebuild the sheet',
          );
          if (!reduced) {
            expect(hovered.hoverSettle.value, inExclusiveRange(0, 1));
          }
          await tester.pump(AppFlowyMotion.fast);
          expect(hovered.hoverSettle.value, 1);
          fixture.controller.selectCell(const CellRef(2, 1));
          await tester.pump();
          final selected = _bodyPainter(tester);
          expect(selected.selectionSettle.value, reduced ? 1 : lessThan(1));
          await tester.pump(const Duration(milliseconds: 40));
          expect(_bodyPainter(tester), same(selected));
          await tester.pump(AppFlowyMotion.fast);
          await mouse.moveTo(const Offset(780, 580));
          await tester.pump();
          await tester.pump(AppFlowyMotion.fast);
          expect(_bodyPainter(tester).hoveredCell, isNull);
          expect(_bodyPainter(tester).hoverSettle.value, 1);
          if (!reduced) {
            // Flutter 3.27's interpolation has reached its endpoint, but only
            // finishes when elapsed time is strictly greater than the duration.
            await tester.pump(const Duration(microseconds: 1));
          }
          expect(
            _bodyPainter(tester).hoverSettle.status,
            AnimationStatus.completed,
          );
          expect(
            tester.binding.transientCallbackCount,
            0,
            reason: 'hover=${_bodyPainter(tester).hoverSettle.status}, '
                'selection=${_bodyPainter(tester).selectionSettle.status}',
          );
          await mouse.removePointer();
        },
        disableAnimations: motion.disabled,
        accessibleNavigation: motion.accessible,
      );
    });
  }

  testWidgets('enabling reduced motion finishes an in-flight interaction',
      (tester) async {
    await _withGrid(tester, (fixture) async {
      fixture.controller.selectCell(const CellRef(2, 1));
      await tester.pump();
      expect(_bodyPainter(tester).selectionSettle.value, lessThan(1));
      fixture.disableAnimations = true;
      await tester.pumpWidget(fixture.app());
      expect(_bodyPainter(tester).selectionSettle.value, 1);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });

  testWidgets(
    'real editor keeps text shortcuts, frame resize and source updates local',
    (tester) async {
      final node = spreadsheetNode(data: _sample(), width: 620, height: 360);
      final paragraph = paragraphNode(text: 'Do not edit this paragraph');
      final editor = EditorState(
        document: Document(root: pageNode(children: [node, paragraph])),
      );
      final scroll =
          EditorScrollController(editorState: editor, shrinkWrap: true);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: FlowyOverlay(
              child: Scaffold(
                body: AppFlowyEditor(
                  editorState: editor,
                  editorScrollController: scroll,
                  editorStyle:
                      const EditorStyle.desktop(padding: EdgeInsets.all(24)),
                  blockComponentBuilders: {
                    ...standardBlockComponentBuilderMap,
                    PageBlockKeys.type: CustomPageBlockComponentBuilder(),
                    SpreadsheetBlockKeys.type:
                        SpreadsheetBlockComponentBuilder(),
                  },
                  contextMenuItems: const [],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final grid = find.byType(SpreadsheetGrid);
        for (final type in <Type>[
          KeyboardServiceWidget,
          SelectionServiceWidget,
          SpreadsheetBlockComponent,
          ResizableMedia,
        ]) {
          expect(
            find.ancestor(of: grid, matching: find.byType(type)),
            findsOneWidget,
          );
        }
        editor.selection =
            Selection.single(path: node.path, startOffset: 0, endOffset: 1);
        await tester.pump();
        await _click(tester, _cellPoint(tester, const CellRef(0, 0)));
        await tester.enterText(find.byType(TextField), 'local draft');
        await _key(tester, LogicalKeyboardKey.keyA, control: true);
        await _key(tester, LogicalKeyboardKey.backspace);
        expect(_field(tester).controller!.text, '');
        expect(
          editor.document.root.children.map((child) => child.type),
          [SpreadsheetBlockKeys.type, ParagraphBlockKeys.type],
        );
        expect(paragraph.delta!.toPlainText(), 'Do not edit this paragraph');
        expect(editor.selection, isNull);
        await tester.enterText(find.byType(TextField), 'retained draft');
        final state =
            tester.state<EditableTextState>(find.byType(EditableText));
        final before = _field(tester).controller!.value;
        final resize = await tester.startGesture(
          tester.getCenter(
            find.byKey(const ValueKey('resizable_media_bottom_right_handle')),
          ),
          kind: PointerDeviceKind.mouse,
        );
        for (var step = 0; step < 2; step++) {
          await resize.moveBy(const Offset(-20, 20));
          await tester.pump();
          expect(
            tester.state<EditableTextState>(find.byType(EditableText)),
            same(state),
          );
          expect(_field(tester).controller!.value, before);
        }
        await resize.up();
        await tester.pump();
        await resize.removePointer();
        final previous = tester.widget<SpreadsheetGrid>(grid).controller;
        final incoming = previous.data.clone()
          ..setRaw(const CellRef(2, 1), 'remote');
        await editor.apply(
          editor.transaction
            ..updateNode(node, {
              SpreadsheetBlockKeys.data: incoming.toJson(),
            }),
        );
        await tester.pump();
        await tester.pump();
        final rebound = tester.widget<SpreadsheetGrid>(grid).controller;
        expect(rebound, isNot(same(previous)));
        expect(_field(tester).controller!.value, before);
        expect(rebound.editingText, before.text);
        expect(rebound.data.rawAt(const CellRef(2, 1)), 'remote');
        await _key(tester, LogicalKeyboardKey.tab);
        expect(rebound.data.rawAt(const CellRef(0, 0)), 'retained draft');
        expect(rebound.active, const CellRef(0, 1));
        await tester.pump(SpreadsheetController.persistDebounce);
        await tester.pump();
        expect(editor.document.root.children.length, 2);
        expect(paragraph.delta!.toPlainText(), 'Do not edit this paragraph');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        scroll.dispose();
        editor.dispose();
        semantics.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

SpreadsheetData _sample() => SpreadsheetData.fromRows(
      [
        ['First', 'Second', 'Third'],
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9'],
      ],
      minRows: 6,
    );

class _GridFixture {
  _GridFixture({
    required SpreadsheetData data,
    required this.editable,
    required bool controllerEditable,
    required this.brightness,
    required this.paper,
    required this.disableAnimations,
    required this.accessibleNavigation,
  }) : controller =
            SpreadsheetController(data: data, editable: controllerEditable);

  SpreadsheetController controller;
  final bool editable;
  final Brightness brightness;
  final bool paper;
  bool disableAnimations;
  final bool accessibleNavigation;
  final key = GlobalKey<SpreadsheetGridState>();

  Widget app({double width = 700, double height = 320, Widget? trailing}) =>
      MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: ThemeData(
          brightness: brightness,
          platform: TargetPlatform.windows,
          extensions: [PaperThemeExtension(enabled: paper)],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: SpreadsheetGrid(
                    key: key,
                    controller: controller,
                    editable: editable,
                    autofocus: true,
                    addRowLabel: 'New row',
                  ),
                ),
              ),
              if (trailing != null) SizedBox(height: 56, child: trailing),
            ],
          ),
        ),
      );
}

Future<void> _withGrid(
  WidgetTester tester,
  Future<void> Function(_GridFixture fixture) body, {
  SpreadsheetData? data,
  bool editable = true,
  bool controllerEditable = true,
  Brightness brightness = Brightness.light,
  bool paper = false,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  final fixture = _GridFixture(
    data: data ?? _sample(),
    editable: editable,
    controllerEditable: controllerEditable,
    brightness: brightness,
    paper: paper,
    disableAnimations: disableAnimations,
    accessibleNavigation: accessibleNavigation,
  );
  try {
    await tester.pumpWidget(fixture.app());
    await tester.pump();
    await tester.pump();
    await body(fixture);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.controller.dispose();
  }
}

Finder _bodyPaint() => find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is SheetBodyPainter,
    );

SheetBodyPainter _bodyPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_bodyPaint()).painter! as SheetBodyPainter;

Offset _bodyOrigin(WidgetTester tester) => tester.getTopLeft(_bodyPaint());

Offset _cellPoint(WidgetTester tester, CellRef ref) {
  final painter = _bodyPainter(tester);
  final geometry = painter.geometry;
  final row = geometry.bodyIndexOf(ref.row);
  final box = tester.renderObject<RenderBox>(_bodyPaint());
  return box.localToGlobal(
    Offset(
      geometry.columnLeft(ref.column) +
          geometry.columnWidth(ref.column) / 2 -
          (painter.horizontal.hasClients ? painter.horizontal.offset : 0),
      geometry.rowTop(row) +
          geometry.rowHeight(row) / 2 -
          (painter.vertical.hasClients ? painter.vertical.offset : 0),
    ),
  );
}

Finder _editorField() => find.descendant(
      of: find.byType(SpreadsheetGrid),
      matching: find.byType(TextField),
    );

Finder _editable() => find.descendant(
      of: find.byType(SpreadsheetGrid),
      matching: find.byType(EditableText),
    );

TextField _field(WidgetTester tester) =>
    tester.widget<TextField>(_editorField());

Offset _caretPoint(WidgetTester tester, int offset) {
  final render = tester.state<EditableTextState>(_editable()).renderEditable;
  final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
  return render.localToGlobal(Offset(caret.left + 0.2, caret.center.dy));
}

Future<void> _click(
  WidgetTester tester,
  Offset point, {
  int buttons = kPrimaryMouseButton,
}) async {
  final gesture = await tester.startGesture(
    point,
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump();
  await gesture.removePointer();
  await tester.pump();
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.pump();
  await tester.pump();
}
