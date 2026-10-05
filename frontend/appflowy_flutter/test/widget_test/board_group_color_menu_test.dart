import 'package:appflowy/plugins/database/board/application/board_group_colors.dart';
import 'package:appflowy/plugins/database/board/presentation/board_style.dart';
import 'package:appflowy/plugins/database/board/presentation/widgets/board_group_menu.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/extension.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Without easy_localization started, every label reads as its key.
const _color = 'board.column.color';
const _default = 'board.column.defaultColor';
const _none = 'board.column.noColor';

ThemeData _theme(String appearance) => DesktopAppearance().getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

/// Opens the column menu, then its colour submenu.
Future<void> _openColors(
  WidgetTester tester, {
  required String appearance,
  required BoardColumnColor? color,
  required SelectOptionColorPB? optionColor,
  bool canRename = true,
  bool canDelete = true,
  ValueChanged<BoardColumnColor?>? onColorChanged,
  List<String>? ran,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(appearance),
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppMenu<void>(
                context: context,
                globalPosition: const Offset(80, 80),
                entries: boardGroupMenuEntries(
                  context,
                  canRename: canRename,
                  canDelete: canDelete,
                  color: color,
                  optionColor: optionColor,
                  onRename: () => ran?.add('rename'),
                  onHide: () => ran?.add('hide'),
                  onDelete: () => ran?.add('delete'),
                  onColorChanged: onColorChanged ?? (_) {},
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_color));
  await tester.pumpAndSettle();
}

Finder _row(String label) => find.ancestor(
      of: find.text(label),
      matching: find.byType(AppMenuRow),
    );

bool _selected(WidgetTester tester, String label) =>
    tester.widget<AppMenuRow>(_row(label)).selected;

/// The swatch beside [label], painted in [color].
Finder _swatch(String label, Color color) => find.descendant(
      of: _row(label),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration! as BoxDecoration).color == color,
      ),
    );

void main() {
  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance: a column offers every colour, its own one ticked first',
        (tester) async {
      final chosen = <BoardColumnColor?>[];
      await _openColors(
        tester,
        appearance: appearance,
        color: null,
        optionColor: SelectOptionColorPB.Purple,
        onColorChanged: chosen.add,
      );
      final context = tester.element(find.text('open'));

      expect(find.text(_default), findsOneWidget);
      expect(find.text(_none), findsOneWidget);
      for (final tint in SelectOptionColorPB.values) {
        expect(find.text(tint.colorName()), findsOneWidget);
        expect(
          _swatch(tint.colorName(), tint.toColor(context)),
          findsOneWidget,
        );
        expect(_selected(tester, tint.colorName()), isFalse);
      }
      // "Default" is the option's own colour, and it is the current choice.
      expect(
        _swatch(_default, SelectOptionColorPB.Purple.toColor(context)),
        findsOneWidget,
      );
      expect(_selected(tester, _default), isTrue);
      expect(_selected(tester, _none), isFalse);
      expect(
        _swatch(_none, boardColumnWellColor(boardPaletteOf(context))),
        findsOneWidget,
      );

      await tester.tap(find.text(SelectOptionColorPB.Blue.colorName()));
      await tester.pumpAndSettle();

      expect(chosen, [const BoardColumnColor.tint(SelectOptionColorPB.Blue)]);
      expect(find.byType(AppMenuSurface), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a column turned plain can go back to its group', (tester) async {
    final chosen = <BoardColumnColor?>[];
    await _openColors(
      tester,
      appearance: 'light',
      color: BoardColumnColor.plain,
      optionColor: SelectOptionColorPB.Green,
      onColorChanged: chosen.add,
    );

    expect(_selected(tester, _none), isTrue);
    expect(_selected(tester, _default), isFalse);

    await tester.tap(find.text(_default));
    await tester.pumpAndSettle();

    expect(chosen, [null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a chosen colour is ticked in place of the default',
      (tester) async {
    await _openColors(
      tester,
      appearance: 'dark',
      color: const BoardColumnColor.tint(SelectOptionColorPB.Aqua),
      optionColor: SelectOptionColorPB.Green,
    );

    expect(_selected(tester, SelectOptionColorPB.Aqua.colorName()), isTrue);
    expect(_selected(tester, _default), isFalse);
    expect(_selected(tester, _none), isFalse);
  });

  testWidgets(
      'a column with no colour of its own has nothing to turn off, and the '
      '"No …" column cannot be renamed or deleted', (tester) async {
    final ran = <String>[];
    await _openColors(
      tester,
      appearance: 'paper',
      color: null,
      optionColor: null,
      canRename: false,
      canDelete: false,
      ran: ran,
    );
    final context = tester.element(find.text('open'));

    expect(find.text(_none), findsNothing);
    expect(
      _swatch(_default, boardColumnWellColor(boardPaletteOf(context))),
      findsOneWidget,
    );
    expect(find.text('board.column.renameColumn'), findsNothing);
    expect(find.text('board.column.deleteColumn'), findsNothing);

    await tester.tap(find.text('board.column.hideColumn'));
    await tester.pumpAndSettle();
    expect(ran, ['hide']);
  });

  testWidgets('rename and delete run from the column menu', (tester) async {
    final ran = <String>[];
    await _openColors(
      tester,
      appearance: 'light',
      color: null,
      optionColor: SelectOptionColorPB.Pink,
      ran: ran,
    );
    // Back out of the colour submenu to the column's own rows.
    await tester.tap(find.text('board.column.renameColumn'));
    await tester.pumpAndSettle();
    expect(ran, ['rename']);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('board.column.deleteColumn'));
    await tester.pumpAndSettle();
    expect(ran, ['rename', 'delete']);
    expect(tester.takeException(), isNull);
  });
}
