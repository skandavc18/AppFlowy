import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/finance/finance_format.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:flutter/foundation.dart';

/// Something a column can mean to a finance widget, with the header words a
/// person is likely to have used for it.
///
/// A widget never insists on exact column names. A table someone built by
/// hand — "Ticker", "Shares", "Cost" — reads the same as the one a template
/// made, and a setting can still point a role at any column explicitly.
@immutable
class FinanceRole {
  const FinanceRole(this.key, this.words);

  /// The settings key that overrides which column this role reads.
  final String key;

  /// Header words, best first. Matched exactly, then as a prefix, then
  /// anywhere in the header.
  final List<String> words;

  static const name = FinanceRole('nameColumn', [
    'name',
    'company',
    'stock',
    'holding',
    'instrument',
    'asset',
    'item',
    'title',
    'scrip',
    'account',
  ]);
  static const symbol = FinanceRole('symbolColumn', [
    'symbol',
    'ticker',
    'scrip code',
    'nse code',
    'code',
  ]);
  static const sector = FinanceRole('sectorColumn', [
    'sector',
    'category',
    'industry',
    'asset class',
    'class',
    'group',
    'type',
  ]);
  static const quantity = FinanceRole('quantityColumn', [
    'qty',
    'quantity',
    'shares',
    'units',
    'lots',
  ]);
  static const averagePrice = FinanceRole('averageColumn', [
    'avg price',
    'average price',
    'avg cost',
    'average cost',
    'buy price',
    'cost price',
    'purchase price',
    'avg',
  ]);
  static const lastPrice = FinanceRole('priceColumn', [
    'ltp',
    'last price',
    'current price',
    'market price',
    'cmp',
    'price',
  ]);
  static const value = FinanceRole('valueColumn', [
    'value',
    'current value',
    'market value',
    'balance',
    'outstanding',
    'amount',
    'worth',
  ]);
  static const invested = FinanceRole('investedColumn', [
    'invested',
    'cost basis',
    'investment',
    'principal',
    'purchase value',
    'cost',
  ]);
  static const date = FinanceRole('dateColumn', [
    'date',
    'day',
    'month',
    'as of',
    'bought on',
    'bought',
    'opened',
    'updated',
  ]);
  static const notes = FinanceRole('notesColumn', ['notes', 'note', 'memo']);
}

/// Which columns of a table play which roles.
///
/// Roles are claimed in the order they are asked for, so once "Avg price" is
/// the average a later "price" cannot take it as the last price as well.
class FinanceColumns {
  FinanceColumns._(this._indexes);

  factory FinanceColumns.resolve(
    ChartTable table,
    List<FinanceRole> roles, {
    Map<String, Object?> settings = const {},
  }) {
    final claimed = <int>{};
    final indexes = <String, int>{};
    final headers = [
      for (final column in table.columns) column.trim().toLowerCase(),
    ];

    // Explicit choices win, and are claimed before any guessing starts.
    for (final role in roles) {
      final chosen = settings[role.key];
      if (chosen is String && chosen.isNotEmpty) {
        final index = table.indexOf(chosen);
        if (index >= 0) {
          indexes[role.key] = index;
          claimed.add(index);
        }
      }
    }

    for (final role in roles) {
      if (indexes.containsKey(role.key)) {
        continue;
      }
      final index = _match(headers, role.words, claimed);
      if (index >= 0) {
        indexes[role.key] = index;
        claimed.add(index);
      }
    }
    return FinanceColumns._(indexes);
  }

  final Map<String, int> _indexes;

  /// The column [role] reads, or -1 when the table has none.
  int operator [](FinanceRole role) => _indexes[role.key] ?? -1;

  bool has(FinanceRole role) => this[role] >= 0;
}

int _match(List<String> headers, List<String> words, Set<int> claimed) {
  for (final test in <bool Function(String, String)>[
    (header, word) => header == word,
    (header, word) => header.startsWith(word),
    (header, word) => header.contains(word),
  ]) {
    for (final word in words) {
      for (var index = 0; index < headers.length; index++) {
        if (!claimed.contains(index) && test(headers[index], word)) {
          return index;
        }
      }
    }
  }
  return -1;
}

/// Typed reads of a table's displayed cells.
class FinanceSheet {
  const FinanceSheet(this.table);

  final ChartTable table;

  int get length => table.rows.length;

  String text(int row, int column) {
    if (column < 0 || row < 0 || row >= table.rows.length) {
      return '';
    }
    final cells = table.rows[row];
    return column < cells.length ? cells[column].trim() : '';
  }

  double? number(int row, int column) => parseMoney(text(row, column));

  DateTime? date(int row, int column) {
    final value = text(row, column);
    return value.isEmpty ? null : parseTableDate(value);
  }

  bool flag(int row, int column) {
    final value = text(row, column).toLowerCase();
    return value == 'yes' ||
        value == 'true' ||
        value == 'checked' ||
        value == '1' ||
        value == '✓';
  }

  List<String> parts(int row, int column) => tablePartsOf(text(row, column));

  /// The database row behind [row], when the table came from a database.
  String? rowId(int row) =>
      row >= 0 && row < table.rowIds.length ? table.rowIds[row] : null;

  /// The field id of [column], for writing a cell back.
  String? fieldId(int column) => column >= 0 && column < table.columnIds.length
      ? table.columnIds[column]
      : null;
}
