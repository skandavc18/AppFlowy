import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_codec.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// Exports a spreadsheet block as a markdown table of its computed values.
class SpreadsheetNodeParser extends NodeParser {
  const SpreadsheetNodeParser();

  @override
  String get id => SpreadsheetBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) {
    final raw = node.attributes[SpreadsheetBlockKeys.data];
    if (raw is! Map) {
      return '';
    }
    final table = encodeMarkdownTable(SpreadsheetData.fromJson(raw));
    return table.isEmpty ? '' : '$table\n';
  }
}
