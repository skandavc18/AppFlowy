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
  final Set<String> _loading = {};

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
    if (!_loading.add(viewId)) {
      return;
    }
    try {
      final host = await _hostFor(viewId);
      final result = await ViewBackendService.getView(host);
      final view = result.fold((found) => found, (_) => null);
      if (view == null) {
        return;
      }
      _adopt(host, EncryptedColumns.fromExtra(view.extra));
    } finally {
      _loading.remove(viewId);
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
    final host = await future;
    _hosts[viewId] = host;
    _resolving.removeWhere((key, _) => key == viewId);
    return host;
  }

  Future<String> _resolveHost(String viewId) async {
    final databaseId = await DatabaseViewBackendService(viewId: viewId)
        .getDatabaseId()
        .fold((id) => id, (_) => null);
    if (databaseId == null) {
      return viewId;
    }
    final host = await DatabaseEventGetDatabases().send().fold(
          (databases) => databases.items
              .firstWhereOrNull((meta) => meta.databaseId == databaseId)
              ?.viewId,
          (_) => null,
        );
    return host == null || host.isEmpty ? viewId : host;
  }

  /// Seals every cell of [fieldId], then marks the column.
  ///
  /// The cells are written first on purpose. Marking a column whose cells are
  /// still in the clear would tell the interface to hide words that are not
  /// actually hidden.
  Future<ColumnEncryptionResult> encryptColumn({
    required String viewId,
    required String fieldId,
  }) async {
    final vault = EncryptionVault.instance;
    await vault.ensureLoaded();
    final key = vault.keyForBulkWork;
    if (key == null) {
      return const ColumnEncryptionResult.failed('locked');
    }

    final field = await _field(viewId, fieldId);
    if (field == null) {
      return const ColumnEncryptionResult.failed('missing');
    }
    if (!canEncrypt(field.fieldType)) {
      return const ColumnEncryptionResult.failed('unsupported');
    }

    final sealing = await _rewriteCells(
      viewId: viewId,
      fieldId: fieldId,
      transform: (value) {
        if (value.isEmpty || looksSealed(value)) {
          return null;
        }
        return sealText(
          key: key,
          plaintext: value,
          context: encryptedCellContext,
        );
      },
    );
    if (sealing.written < 0) {
      return const ColumnEncryptionResult.failed('read');
    }

    final marked = await _mark(viewId, fieldId, sealed: true);
    return ColumnEncryptionResult(changed: marked, cells: sealing.written);
  }

  /// Writes every cell of [fieldId] back in the clear, then clears the mark.
  Future<ColumnEncryptionResult> decryptColumn({
    required String viewId,
    required String fieldId,
  }) async {
    final vault = EncryptionVault.instance;
    await vault.ensureLoaded();
    final key = vault.keyForBulkWork;
    if (key == null) {
      return const ColumnEncryptionResult.failed('locked');
    }

    var refused = false;
    final opening = await _rewriteCells(
      viewId: viewId,
      fieldId: fieldId,
      transform: (value) {
        if (value.isEmpty || !looksSealed(value)) {
          return null;
        }
        try {
          return openText(
            key: key,
            value: value,
            context: encryptedCellContext,
          );
        } on Object {
          // A cell sealed with an older passphrase must not be quietly emptied.
          refused = true;
          return null;
        }
      },
    );
    if (opening.written < 0) {
      return const ColumnEncryptionResult.failed('read');
    }
    if (refused) {
      return const ColumnEncryptionResult.failed('wrongKey');
    }

    // The mark is what makes the interface stop hiding the column, so it must
    // not be cleared while a cell is still ciphertext: that cell would be shown
    // raw, which reads as the column having lost its contents.
    if (opening.failed > 0) {
      return const ColumnEncryptionResult.failed('incomplete');
    }

    final marked = await _mark(viewId, fieldId, sealed: false);
    return ColumnEncryptionResult(changed: marked, cells: opening.written);
  }

  /// Reads every row once and writes back only the cells [transform] changes.
  ///
  /// [written] is -1 when the table could not be read at all, which is not the
  /// same as "nothing needed changing". [failed] counts cells the backend
  /// refused, so the caller can decline to clear a mark that is still true.
  Future<({int written, int failed})> _rewriteCells({
    required String viewId,
    required String fieldId,
    required String? Function(String value) transform,
  }) async {
    final rows = await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB()..value = viewId,
    ).send().fold<RepeatedRowTextPB?>((rows) => rows, (failure) {
      Log.warn('Could not read $viewId to seal a column: $failure');
      return null;
    });
    if (rows == null) {
      return (written: -1, failed: 0);
    }

    final column = rows.fieldIds.indexOf(fieldId);
    if (column < 0) {
      return (written: 0, failed: 0);
    }

    var written = 0;
    var failed = 0;
    for (final row in rows.rows) {
      if (column >= row.cells.length) {
        continue;
      }
      final next = transform(row.cells[column]);
      if (next == null) {
        continue;
      }
      final result = await CellBackendService.updateCell(
        viewId: viewId,
        cellContext: CellContext(fieldId: fieldId, rowId: row.rowId),
        data: next,
      );
      result.fold(
        (_) => written++,
        (error) {
          failed++;
          Log.warn('A cell of $fieldId could not be written: $error');
        },
      );
    }
    return (written: written, failed: failed);
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

    final next =
        EncryptedColumns.fromExtra(view.extra).with_(fieldId, sealed: sealed);
    _adopt(host, next);
    revision.value++;

    final result = await ViewBackendService.updateView(
      viewId: host,
      extra: next.mergeIntoExtra(view.extra),
    );
    return result.fold((_) => true, (_) => false);
  }

  @visibleForTesting
  void seedForTest(String viewId, EncryptedColumns columns) {
    _hosts[viewId] = viewId;
    _views
        .putIfAbsent(viewId, () => ValueNotifier(const EncryptedColumns()))
        .value = columns;
  }
}
