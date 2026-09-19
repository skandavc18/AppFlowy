import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// The domain a sealed cell belongs to, so a sealed block cannot be pasted into
/// a cell and opened there.
const String encryptedCellContext = 'cell';

/// Which columns of a table hold sealed values.
///
/// A column belongs to the DATABASE, not to one view of it, so the mark is
/// written on the database's first view exactly as the property styles are —
/// otherwise a grid and a board of the same table would disagree about which
/// column is readable.
@immutable
class EncryptedColumns {
  const EncryptedColumns({this.fieldIds = const <String>{}});

  static const envelopeKey = 'appflowy_encrypted_columns';
  static const currentVersion = 1;

  final Set<String> fieldIds;

  bool contains(String fieldId) => fieldIds.contains(fieldId);

  bool get isEmpty => fieldIds.isEmpty;

  static EncryptedColumns fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return const EncryptedColumns();
    }
    final values = Map<String, Object?>.from(envelope);
    final version = values['version'];
    if (version is! int || version < 1 || version > currentVersion) {
      return const EncryptedColumns();
    }
    final fields = values['fields'];
    if (fields is! List) {
      return const EncryptedColumns();
    }
    return EncryptedColumns(
      fieldIds: fields.whereType<String>().toSet(),
    );
  }

  /// A writer must not interpret malformed or future protection metadata as
  /// permission to store plaintext. UI-only legacy reads remain tolerant.
  static EncryptedColumns? forWriting(String extra) {
    if (extra.isEmpty) return const EncryptedColumns();
    try {
      final values = jsonDecode(extra);
      if (values is! Map) return null;
      if (!values.containsKey(envelopeKey)) return const EncryptedColumns();
      final mark = values[envelopeKey];
      if (mark is! Map || mark['version'] != currentVersion) return null;
      final fields = mark['fields'];
      if (fields is! List || fields.any((field) => field is! String))
        return null;
      return EncryptedColumns(fieldIds: fields.cast<String>().toSet());
    } on Object {
      return null;
    }
  }

  EncryptedColumns with_(String fieldId, {required bool sealed}) {
    final next = Set<String>.from(fieldIds);
    if (sealed) {
      next.add(fieldId);
    } else {
      next.remove(fieldId);
    }
    return EncryptedColumns(fieldIds: next);
  }

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    if (fieldIds.isEmpty) {
      values.remove(envelopeKey);
    } else {
      values[envelopeKey] = {
        'version': currentVersion,
        'fields': fieldIds.toList()..sort(),
      };
    }
    return values.isEmpty ? '' : jsonEncode(values);
  }
}

/// What happened when a column was sealed or opened.
class ColumnEncryptionResult {
  const ColumnEncryptionResult({
    required this.changed,
    this.cells = 0,
    this.failure,
  });

  const ColumnEncryptionResult.failed(String reason)
      : changed = false,
        cells = 0,
        failure = reason;

  final bool changed;
  final int cells;
  final String? failure;

  bool get succeeded => failure == null;
}

/// Preflight ALL values before the first write. The private key copy cannot
/// become zeroes if the vault locks while a backend write is in flight.
/// Rollback covers only this operation's attempted writes and preserves the
/// original ciphertext/plaintext verbatim. No secret is included in failures.
Future<ColumnEncryptionResult> rewriteColumnEncryption({
  required Uint8List key,
  required Map<String, String> values,
  required bool encrypt,
  required Future<bool> Function(String rowId, String value) write,
  required Future<bool> Function() mark,
}) async {
  final ownedKey = Uint8List.fromList(key);
  final replacements = <String, String>{};
  final attempted = <String>[];
  try {
    try {
      for (final entry in values.entries) {
        final value = entry.value;
        if (value.isEmpty) continue;
        if (looksSealed(value)) {
          final plaintext = openText(
            key: ownedKey,
            value: value,
            context: encryptedCellContext,
          );
          if (!encrypt) replacements[entry.key] = plaintext;
        } else if (encrypt) {
          replacements[entry.key] = sealText(
            key: ownedKey,
            plaintext: value,
            context: encryptedCellContext,
          );
        }
      }
    } on Object {
      return const ColumnEncryptionResult.failed('wrongKey');
    }
    try {
      for (final entry in replacements.entries) {
        attempted.add(entry.key);
        if (!await write(entry.key, entry.value)) throw StateError('write');
      }
      if (!await mark()) throw StateError('mark');
      return ColumnEncryptionResult(changed: true, cells: replacements.length);
    } on Object {
      var rolledBack = true;
      for (final rowId in attempted.reversed) {
        try {
          if (!await write(rowId, values[rowId]!)) rolledBack = false;
        } on Object {
          rolledBack = false;
        }
      }
      return ColumnEncryptionResult.failed(rolledBack ? 'write' : 'incomplete');
    }
  } finally {
    ownedKey.fillRange(0, ownedKey.length, 0);
  }
}

/// Remembers which columns are sealed, and does the sealing.
///
/// The type picker, the heading menu and every cell need the same answer and
/// must agree the moment any of them changes it, so it is fetched once and
/// shared — the same shape as the property style and location registries.
class EncryptedColumnRegistry {
  EncryptedColumnRegistry._();

  static final EncryptedColumnRegistry instance = EncryptedColumnRegistry._();

  final Map<String, ValueNotifier<EncryptedColumns>> _views = {};
  final Map<String, String> _hosts = {};
  final Map<String, Future<String>> _resolving = {};
  final Map<String, Future<EncryptedColumns?>> _reading = {};
  final Set<String> _rewriting = {};

  /// Bumped whenever anything changes, for surfaces that are not the view the
  /// column was sealed in.
  final ValueNotifier<int> revision = ValueNotifier(0);

  ValueNotifier<EncryptedColumns> listenable(String viewId) {
    final notifier = _views.putIfAbsent(
      viewId,
      () => ValueNotifier(const EncryptedColumns()),
    );
    unawaited(refresh(viewId));
    return notifier;
  }

  /// Whether this column holds sealed values. Answers from what has already
  /// been read, so it is safe to call while building.
  bool isEncrypted(String viewId, String fieldId) =>
      _views[viewId]?.value.contains(fieldId) ?? false;

  Set<String> encryptedFields(String viewId) =>
      _views[viewId]?.value.fieldIds ?? const <String>{};

  /// Only a plain text column can be sealed.
  ///
  /// Writing ciphertext into a date, a number or a select column would not
  /// round trip — the backend parses what it is given — so the offer is simply
  /// not made rather than made and then corrupting the table.
  static bool canEncrypt(FieldType fieldType) =>
      fieldType == FieldType.RichText;

  Future<void> refresh(String viewId) async {
    await readColumns(viewId);
  }

  /// An authoritative read for writers. Null means unknown, NOT unencrypted.
  /// Concurrent readers await the same operation instead of racing an empty
  /// cache during startup.
  Future<EncryptedColumns?> readColumns(String viewId) {
    final pending = _reading[viewId];
    if (pending != null) {
      return pending;
    }
    final future = _readColumns(viewId);
    _reading[viewId] = future;
    return future.whenComplete(() {
      _reading.removeWhere((id, _) => id == viewId);
    });
  }

  Future<EncryptedColumns?> _readColumns(String viewId) async {
    try {
      final host = await _hostFor(viewId);
      final result = await ViewBackendService.getView(host);
      final view = result.fold((found) => found, (_) => null);
      if (view == null) {
        return null;
      }
      final columns = EncryptedColumns.forWriting(view.extra);
      if (columns == null) return null;
      _views.putIfAbsent(
        viewId,
        () => ValueNotifier(const EncryptedColumns()),
      );
      _adopt(host, columns);
      return columns;
    } on Object {
      return null;
    }
  }

  void _adopt(String host, EncryptedColumns columns) {
    var changed = false;
    for (final entry in _views.entries) {
      if (entry.key != host && _hosts[entry.key] != host) {
        continue;
      }
      if (setEquals(entry.value.value.fieldIds, columns.fieldIds)) {
        continue;
      }
      entry.value.value = columns;
      changed = true;
    }
    if (changed) {
      revision.value++;
    }
  }

  Future<String> _hostFor(String viewId) async {
    final known = _hosts[viewId];
    if (known != null) {
      return known;
    }
    final pending = _resolving[viewId];
    if (pending != null) {
      return pending;
    }
    final future = _resolveHost(viewId);
    _resolving[viewId] = future;
    try {
      final host = await future;
      _hosts[viewId] = host;
      return host;
    } finally {
      _resolving.removeWhere((key, _) => key == viewId);
    }
  }

  Future<String> _resolveHost(String viewId) async {
    final databaseId = await DatabaseViewBackendService(viewId: viewId)
        .getDatabaseId()
        .fold((id) => id, (_) => null);
    if (databaseId == null) {
      throw StateError('Could not resolve the encrypted column owner.');
    }
    final host = await DatabaseEventGetDatabases().send().fold(
          (databases) => databases.items
              .firstWhereOrNull((meta) => meta.databaseId == databaseId)
              ?.viewId,
          (_) => null,
        );
    if (host == null || host.isEmpty) {
      throw StateError('Could not resolve the encrypted column owner.');
    }
    return host;
  }

  /// Seals every cell of [fieldId], then marks the column.
  ///
  /// The cells are written first on purpose. Marking a column whose cells are
  /// still in the clear would tell the interface to hide words that are not
  /// actually hidden.
  Future<ColumnEncryptionResult> encryptColumn({
    required String viewId,
    required String fieldId,
  }) =>
      _transformColumn(viewId: viewId, fieldId: fieldId, encrypt: true);

  /// Writes every cell of [fieldId] back in the clear, then clears the mark.
  Future<ColumnEncryptionResult> decryptColumn({
    required String viewId,
    required String fieldId,
  }) =>
      _transformColumn(viewId: viewId, fieldId: fieldId, encrypt: false);

  Future<ColumnEncryptionResult> _transformColumn({
    required String viewId,
    required String fieldId,
    required bool encrypt,
  }) async {
    String? operation;
    try {
      final host = await _hostFor(viewId);
      final id = '$host|$fieldId';
      if (!_rewriting.add(id))
        return const ColumnEncryptionResult.failed('busy');
      operation = id;
      if (await readColumns(viewId) == null) {
        return const ColumnEncryptionResult.failed('read');
      }
      final field = await _field(viewId, fieldId);
      if (field == null) return const ColumnEncryptionResult.failed('missing');
      if (!canEncrypt(field.fieldType)) {
        return const ColumnEncryptionResult.failed('unsupported');
      }
      final values = await _columnValues(viewId, fieldId);
      if (values == null) return const ColumnEncryptionResult.failed('read');
      final vault = EncryptionVault.instance;
      await vault.ensureLoaded();
      final key = vault.keyForBulkWork;
      if (key == null) return const ColumnEncryptionResult.failed('locked');
      return await rewriteColumnEncryption(
        key: key,
        values: values,
        encrypt: encrypt,
        write: (rowId, value) async => (await CellBackendService.updateCell(
          viewId: viewId,
          cellContext: CellContext(fieldId: fieldId, rowId: rowId),
          data: value,
        ))
            .fold((_) => true, (_) => false),
        mark: () => _mark(viewId, fieldId, sealed: encrypt),
      );
    } on Object {
      return const ColumnEncryptionResult.failed('read');
    } finally {
      if (operation != null) _rewriting.remove(operation);
    }
  }

  Future<Map<String, String>?> _columnValues(
      String viewId, String fieldId) async {
    final rows = await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB()..value = viewId,
    ).send().fold<RepeatedRowTextPB?>((rows) => rows, (_) => null);
    if (rows == null) return null;
    final column = rows.fieldIds.indexOf(fieldId);
    if (column < 0) return null;
    return {
      for (final row in rows.rows)
        row.rowId: column < row.cells.length ? row.cells[column] : '',
    };
  }

  /// Every sealed cell of [fieldId], by row id.
  ///
  /// For re-keying: a passphrase change has to find each sealed value before it
  /// can write any of them back.
  Future<Map<String, String>> sealedCells({
    required String viewId,
    required String fieldId,
  }) async {
    final rows = await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB()..value = viewId,
    ).send().fold<RepeatedRowTextPB?>((rows) => rows, (failure) {
      Log.warn('Could not read $viewId to find its sealed cells: $failure');
      return null;
    });
    if (rows == null) {
      return const <String, String>{};
    }

    final column = rows.fieldIds.indexOf(fieldId);
    if (column < 0) {
      return const <String, String>{};
    }

    return {
      for (final row in rows.rows)
        if (column < row.cells.length && looksSealed(row.cells[column]))
          row.rowId: row.cells[column],
    };
  }

  /// Writes one already-sealed value into a cell.
  Future<bool> writeSealedCell({
    required String viewId,
    required String fieldId,
    required String rowId,
    required String value,
  }) async {
    final result = await CellBackendService.updateCell(
      viewId: viewId,
      cellContext: CellContext(fieldId: fieldId, rowId: rowId),
      data: value,
    );
    return result.fold((_) => true, (error) {
      Log.warn('A sealed cell of $fieldId could not be written: $error');
      return false;
    });
  }

  Future<FieldPB?> _field(String viewId, String fieldId) async {
    final fields = await FieldBackendService.getFields(viewId: viewId)
        .fold((fields) => fields, (_) => const <FieldPB>[]);
    return fields.firstWhereOrNull((field) => field.id == fieldId);
  }

  Future<bool> _mark(
    String viewId,
    String fieldId, {
    required bool sealed,
  }) async {
    final host = await _hostFor(viewId);
    // Re-read: the extra carries every other mark, and a stale copy would write
    // them away.
    final current = await ViewBackendService.getView(host);
    final view = current.fold((found) => found, (_) => null);
    if (view == null) {
      return false;
    }

    final currentColumns = EncryptedColumns.forWriting(view.extra);
    if (currentColumns == null) return false;
    final next = currentColumns.with_(fieldId, sealed: sealed);

    final result = await ViewBackendService.updateView(
      viewId: host,
      extra: next.mergeIntoExtra(view.extra),
    );
    return result.fold(
      (_) {
        _adopt(host, next);
        revision.value++;
        return true;
      },
      (_) => false,
    );
  }

  @visibleForTesting
  void seedForTest(String viewId, EncryptedColumns columns) {
    _hosts[viewId] = viewId;
    _views
        .putIfAbsent(viewId, () => ValueNotifier(const EncryptedColumns()))
        .value = columns;
  }
}
