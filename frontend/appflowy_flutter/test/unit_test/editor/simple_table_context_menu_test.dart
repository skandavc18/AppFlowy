import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table_context_menu_entries.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_test/flutter_test.dart';

/// A right click inside a cell has to reach the row and column operations, so
/// these check the contribution the table makes to the editor's context menu.
void main() {
  EditorState editorWithTable({int rows = 3, int columns = 3}) {
    final table = simpleTableBlockNode(
      children: [
        for (var row = 0; row < rows; row++)
          simpleTableRowBlockNode(
            children: [
              for (var column = 0; column < columns; column++)
                simpleTableCellBlockNode(
                  children: [paragraphNode(text: '$row.$column')],
                ),
            ],
          ),
      ],
    );
    return EditorState(
      document: Document(root: pageNode(children: [table])),
    );
  }

  /// The paragraph inside the cell at [row], [column].
  Path cellTextPath(int row, int column) => [0, row, column, 0];

  List<String> labelsFor(EditorState editorState) => [
        for (final group in simpleTableContextMenuGroups(editorState))
          for (final entry in group) entry.getName(),
      ];

  final deleteRow =
      LocaleKeys.document_plugins_simpleTable_moreActions_deleteRow.tr();
  final deleteColumn =
      LocaleKeys.document_plugins_simpleTable_moreActions_deleteColumn.tr();

  test('a selection outside a table contributes nothing', () {
    expect(simpleTableContextMenuGroups(EditorState.blank()), isEmpty);
  });

  test('a cell contributes insert, align and delete groups', () {
    final editorState = editorWithTable();
    editorState.selection =
        Selection.collapsed(Position(path: cellTextPath(1, 1)));

    expect(
      labelsFor(editorState),
      containsAll([
        LocaleKeys.document_plugins_simpleTable_moreActions_insertAbove.tr(),
        LocaleKeys.document_plugins_simpleTable_moreActions_insertBelow.tr(),
        LocaleKeys.document_plugins_simpleTable_moreActions_insertLeft.tr(),
        LocaleKeys.document_plugins_simpleTable_moreActions_insertRight.tr(),
        LocaleKeys.document_plugins_simpleTable_moreActions_clearContents.tr(),
        deleteRow,
        deleteColumn,
      ]),
    );
  });

  test('the last row and column cannot be deleted away', () {
    final editorState = editorWithTable(rows: 1, columns: 1);
    editorState.selection =
        Selection.collapsed(Position(path: cellTextPath(0, 0)));

    final labels = labelsFor(editorState);
    expect(labels, isNot(contains(deleteRow)));
    expect(labels, isNot(contains(deleteColumn)));
  });

  test('deleting a row through the menu entry removes it', () async {
    final editorState = editorWithTable();
    editorState.selection =
        Selection.collapsed(Position(path: cellTextPath(1, 0)));

    simpleTableContextMenuGroups(editorState)
        .expand((group) => group)
        .firstWhere((entry) => entry.getName() == deleteRow)
        .onPressed(editorState);
    await Future<void>.delayed(Duration.zero);

    expect(editorState.document.nodeAtPath([0])!.rowLength, 2);
  });

  test('deleting a column through the menu entry removes it', () async {
    final editorState = editorWithTable();
    editorState.selection =
        Selection.collapsed(Position(path: cellTextPath(0, 1)));

    simpleTableContextMenuGroups(editorState)
        .expand((group) => group)
        .firstWhere((entry) => entry.getName() == deleteColumn)
        .onPressed(editorState);
    await Future<void>.delayed(Duration.zero);

    expect(editorState.document.nodeAtPath([0])!.columnLength, 2);
  });
}
