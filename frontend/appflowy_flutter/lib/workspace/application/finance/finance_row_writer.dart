import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/plugins/database/domain/select_option_cell_service.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';

/// Writes what a dashboard collected back into the table it reads.
///
/// Columns are named the way a person sees them — "Symbol", "Qty" — or by
/// field id. Each value is written the way its column takes it: a number as
/// a number, a date as a date, a choice picked from the column's options
/// (or added to them when it is new).
class FinanceRowWriter {
  FinanceRowWriter(this.viewId);

  final String viewId;

  List<FieldPB>? _fields;

  Future<List<FieldPB>> _readFields() async {
    final cached = _fields;
    if (cached != null) {
      return cached;
    }
    final result = await DatabaseEventGetFields(
      GetFieldPayloadPB(viewId: viewId),
    ).send();
    final fields = result.fold((fields) => fields.items.toList(), (error) {
      Log.warn('Could not read the columns of $viewId: ${error.msg}');
      return <FieldPB>[];
    });
    _fields = fields;
    return fields;
  }

  FieldPB? _find(List<FieldPB> fields, String column) {
    final wanted = column.trim().toLowerCase();
    for (final field in fields) {
      if (field.id == column) {
        return field;
      }
    }
    for (final field in fields) {
      if (field.name.trim().toLowerCase() == wanted) {
        return field;
      }
    }
    return null;
  }

  /// The column names the table has, for a form to offer only what fits.
  Future<Set<String>> columnNames() async =>
      {for (final field in await _readFields()) field.name.toLowerCase()};

  /// The options a select [column] offers, in order.
  Future<List<String>> optionsOf(String column) async {
    final field = _find(await _readFields(), column);
    if (field == null ||
        (field.fieldType != FieldType.SingleSelect &&
            field.fieldType != FieldType.MultiSelect)) {
      return const [];
    }
    try {
      return SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData)
          .options
          .map((option) => option.name)
          .toList();
    } on Object catch (_) {
      return const [];
    }
  }

  /// Adds a row holding [values], keyed by column. Returns the new row's id,
  /// or null when the row could not be made.
  Future<String?> addRow(Map<String, String> values) async {
    final created = await RowBackendService.createRow(viewId: viewId);
    final rowId = created.fold<String?>((meta) => meta.id, (error) {
      Log.error(error);
      return null;
    });
    if (rowId == null) {
      return null;
    }
    for (final entry in values.entries) {
      if (entry.value.trim().isEmpty) {
        continue;
      }
      await write(rowId, entry.key, entry.value);
    }
    return rowId;
  }

  /// Writes one cell. Returns whether the column took the value.
  Future<bool> write(String rowId, String column, String value) async {
    final field = _find(await _readFields(), column);
    if (field == null) {
      return false;
    }
    switch (field.fieldType) {
      case FieldType.SingleSelect:
      case FieldType.MultiSelect:
        final service = SelectOptionCellBackendService(
          viewId: viewId,
          fieldId: field.id,
          rowId: rowId,
        );
        if (value.trim().isEmpty) {
          return (await service.select(optionIds: const [])).isSuccess;
        }
        final options = _optionIds(field);
        final ids = <String>[];
        for (final name in tablePartsOf(value)) {
          final id = options[name.toLowerCase()];
          if (id != null) {
            ids.add(id);
          } else {
            // A choice nobody has made before is kept rather than dropped.
            await service.create(name: name);
            _fields = null;
          }
        }
        if (ids.isEmpty) {
          return true;
        }
        return (await service.select(optionIds: ids)).isSuccess;
      case FieldType.Checkbox:
        return _update(
          rowId,
          field.id,
          const ['yes', 'true', '1', 'checked']
                  .contains(value.trim().toLowerCase())
              ? 'Yes'
              : 'No',
        );
      case FieldType.DateTime:
        final date = parseTableDate(value);
        if (date == null) {
          return false;
        }
        final result = await DateCellBackendService(
          viewId: viewId,
          fieldId: field.id,
          rowId: rowId,
        ).update(date: date);
        return result.isSuccess;
      case FieldType.Number:
        final number = parseMoney(value);
        return _update(
          rowId,
          field.id,
          number == null ? value : _plainNumber(number),
        );
      case FieldType.RichText:
      case FieldType.URL:
        return _update(rowId, field.id, value);
      default:
        return false;
    }
  }

  Map<String, String> _optionIds(FieldPB field) {
    try {
      return {
        for (final option
            in SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData)
                .options)
          option.name.toLowerCase(): option.id,
      };
    } on Object catch (_) {
      return const {};
    }
  }

  Future<bool> _update(String rowId, String fieldId, String data) async {
    final result = await CellBackendService.updateCell(
      viewId: viewId,
      cellContext: CellContext(fieldId: fieldId, rowId: rowId),
      data: data,
    );
    return result.fold((_) => true, (error) {
      Log.error(error);
      return false;
    });
  }
}

/// A number the way a Number column parses it: no grouping, no symbol.
String _plainNumber(double value) {
  if ((value - value.roundToDouble()).abs() < 1e-9) {
    return value.round().toString();
  }
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  return text;
}
