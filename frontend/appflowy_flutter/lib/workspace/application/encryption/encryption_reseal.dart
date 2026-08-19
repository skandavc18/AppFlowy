// Re-keying everything that was sealed with the old passphrase.
//
// ⚠️⚠️ Without this, changing the workspace passphrase is destructive.
// `EncryptionVault.changePassphrase` derives a new key and its own doc comment
// says callers must re-seal what the old key wrote — but nothing did, so every
// sealed block and every sealed column was left encrypted under a key nobody
// could produce again.
//
// The order matters and is not negotiable: EVERY payload is proved to open
// with the old key before ANY of them is written back. A run that started
// writing and then met a payload it could not read would leave the workspace
// half under one key and half under another, which is worse than either.

import 'dart:convert';

import 'package:appflowy/ai/tools/document_toolkit.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/encryption/encrypted_block.dart';
import 'package:appflowy/workspace/application/encryption/encrypted_column.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// One sealed payload, and where it lives.
@immutable
class SealedPayload {
  const SealedPayload({
    required this.ownerId,
    required this.itemId,
    required this.value,
    required this.context,
    this.rowId = '',
  });

  /// The page or the database view it belongs to.
  final String ownerId;

  /// The block id, or the field id for a cell.
  final String itemId;

  /// The row, for a cell.
  final String rowId;

  /// The sealed text as it stands.
  final String value;

  /// The AAD the payload was sealed with — coarse by design.
  final String context;

  bool get isCell => context == encryptedCellContext;
}

/// What a read-only pass found.
@immutable
class ResealSurvey {
  const ResealSurvey({
    this.blocks = 0,
    this.cells = 0,
    this.documents = 0,
    this.columns = 0,
    this.unreadable = const <String>[],
  });

  final int blocks;
  final int cells;
  final int documents;
  final int columns;

  /// Payloads the old key would not open. Named rather than counted, because
  /// this is what somebody has to go and look at.
  final List<String> unreadable;

  int get total => blocks + cells;

  bool get isEmpty => total == 0;

  /// Whether re-keying may go ahead at all.
  bool get canProceed => unreadable.isEmpty;
}

/// What a re-keying actually did.
@immutable
class ResealOutcome {
  const ResealOutcome({
    this.blocks = 0,
    this.cells = 0,
    this.failures = const <String>[],
    this.rolledBack = false,
    this.refused,
  });

  const ResealOutcome.refusedBecause(String reason, {this.failures = const []})
      : blocks = 0,
        cells = 0,
        rolledBack = false,
        refused = reason;

  final int blocks;
  final int cells;

  /// Things the backend would not write.
  final List<String> failures;

  /// Whether what had already been written was put back the way it was.
  final bool rolledBack;

  /// Set when the run never started, and why.
  final String? refused;

  bool get succeeded => refused == null && failures.isEmpty;
}

typedef ResealProgress = void Function(int done, int total);

/// Finds everything sealed in this workspace, and re-keys it.
abstract final class EncryptionResealService {
  /// A passphrase change touches every sealed thing, so a workspace with more
  /// than this is refused rather than half done.
  static const int maximumPayloads = 20000;

  /// Reads every sealed payload and proves [key] opens it. Writes nothing.
  static Future<ResealSurvey> survey({
    required Uint8List key,
    ResealProgress? onProgress,
  }) async {
    final found = await _gather(onProgress: onProgress);
    final unreadable = <String>[];

    for (final payload in found.payloads) {
      if (!_opens(payload, key)) {
        unreadable.add(_describe(payload));
        if (unreadable.length >= 20) {
          break;
        }
      }
    }

    return ResealSurvey(
      blocks: found.payloads.where((p) => !p.isCell).length,
      cells: found.payloads.where((p) => p.isCell).length,
      documents: found.documents,
      columns: found.columns,
      unreadable: unreadable,
    );
  }

  /// Re-seals everything from [from] to [to].
  ///
  /// Surveys first and refuses outright unless every payload opens, so a run
  /// that begins is one that can finish. If a WRITE fails part way, whatever
  /// landed is put back under the old key before returning.
  static Future<ResealOutcome> reseal({
    required Uint8List from,
    required Uint8List to,
    ResealProgress? onProgress,
  }) async {
    final found = await _gather();
    if (found.payloads.length > maximumPayloads) {
      return const ResealOutcome.refusedBecause('tooMuch');
    }

    for (final payload in found.payloads) {
      if (!_opens(payload, from)) {
        return ResealOutcome.refusedBecause(
          'unreadable',
          failures: [_describe(payload)],
        );
      }
    }

    final written = <SealedPayload>[];
    final failures = <String>[];
    var done = 0;

    for (final payload in found.payloads) {
      final next = _reseal(payload, from: from, to: to);
      if (next == null) {
        failures.add(_describe(payload));
        break;
      }
      if (!await _write(payload, next)) {
        failures.add(_describe(payload));
        break;
      }
      written.add(payload);
      onProgress?.call(++done, found.payloads.length);
    }

    if (failures.isEmpty) {
      return ResealOutcome(
        blocks: written.where((p) => !p.isCell).length,
        cells: written.where((p) => p.isCell).length,
      );
    }

    // Put back what landed, so the old passphrase still opens everything.
    var restored = true;
    for (final payload in written) {
      final back = _reseal(payload, from: to, to: from);
      if (back == null || !await _write(payload, back)) {
        restored = false;
      }
    }
    return ResealOutcome(failures: failures, rolledBack: restored);
  }

  // --- Finding what is sealed -------------------------------------------------

  static Future<({List<SealedPayload> payloads, int documents, int columns})>
      _gather({ResealProgress? onProgress}) async {
    final payloads = <SealedPayload>[];
    var documents = 0;
    var columns = 0;

    final views = await const WorkspaceItemService().getAllViews().then(
          (result) => result.fold((found) => found, (_) => <ViewPB>[]),
        );

    var seen = 0;
    for (final view in views) {
      final sealedColumns = EncryptedColumns.fromExtra(view.extra);
      if (sealedColumns.fieldIds.isNotEmpty) {
        columns += sealedColumns.fieldIds.length;
        for (final fieldId in sealedColumns.fieldIds) {
          payloads.addAll(await _cellsOf(view.id, fieldId));
        }
      }

      if (view.layout == ViewLayoutPB.Document) {
        final blocks = await _blocksOf(view.id);
        if (blocks.isNotEmpty) {
          documents++;
          payloads.addAll(blocks);
        }
      }

      onProgress?.call(++seen, views.length);
    }

    return (payloads: payloads, documents: documents, columns: columns);
  }

  /// Reads a page WITHOUT opening it — a survey must not pull every document
  /// in the workspace into the backend's cache.
  static Future<List<SealedPayload>> _blocksOf(String pageId) async {
    final data = await DocumentService()
        .getDocument(documentId: pageId)
        .then((result) => result.fold((found) => found, (_) => null));
    if (data == null) {
      return const [];
    }

    final found = <SealedPayload>[];
    for (final block in data.blocks.values) {
      if (block.ty != EncryptedBlockKeys.type) {
        continue;
      }
      final sealed = _sealedAttribute(block.data);
      if (sealed == null || sealed.isEmpty) {
        continue;
      }
      found.add(
        SealedPayload(
          ownerId: pageId,
          itemId: block.id,
          value: sealed,
          context: encryptedBlockContext,
        ),
      );
    }
    return found;
  }

  static Future<List<SealedPayload>> _cellsOf(
    String viewId,
    String fieldId,
  ) async {
    final cells = await EncryptedColumnRegistry.instance.sealedCells(
      viewId: viewId,
      fieldId: fieldId,
    );
    return [
      for (final cell in cells.entries)
        SealedPayload(
          ownerId: viewId,
          itemId: fieldId,
          rowId: cell.key,
          value: cell.value,
          context: encryptedCellContext,
        ),
    ];
  }

  static String? _sealedAttribute(String data) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) {
        return null;
      }
      final sealed = decoded[EncryptedBlockKeys.sealed];
      return sealed is String ? sealed : null;
    } on FormatException {
      return null;
    }
  }

  // --- Turning one key into another ------------------------------------------

  static bool _opens(SealedPayload payload, Uint8List key) {
    try {
      openText(key: key, value: payload.value, context: payload.context);
      return true;
    } on Object {
      return false;
    }
  }

  static String? _reseal(
    SealedPayload payload, {
    required Uint8List from,
    required Uint8List to,
  }) {
    try {
      return sealText(
        key: to,
        plaintext:
            openText(key: from, value: payload.value, context: payload.context),
        context: payload.context,
      );
    } on Object {
      return null;
    }
  }

  static Future<bool> _write(SealedPayload payload, String value) async {
    if (payload.isCell) {
      return EncryptedColumnRegistry.instance.writeSealedCell(
        viewId: payload.ownerId,
        fieldId: payload.itemId,
        rowId: payload.rowId,
        value: value,
      );
    }

    final toolkit = DocumentToolkit();
    // ⚠️ A document must be OPENED before it can be written; a read-only copy
    // accepts no changes at all.
    final data = await toolkit.open(payload.ownerId);
    if (data == null) {
      return false;
    }
    return toolkit.update(
      pageId: payload.ownerId,
      data: data,
      blockId: payload.itemId,
      attributes: {EncryptedBlockKeys.sealed: value},
    );
  }

  static String _describe(SealedPayload payload) => payload.isCell
      ? 'cell ${payload.rowId} of column ${payload.itemId}'
      : 'block ${payload.itemId} on page ${payload.ownerId}';
}

/// Re-keys everything, for [EncryptionVault.changePassphrase] to call.
///
/// Returns false when nothing was written and the old passphrase still works,
/// which is exactly what the vault needs in order to abandon the change.
Future<bool> resealWorkspace(Uint8List from, Uint8List to) async {
  final outcome = await EncryptionResealService.reseal(from: from, to: to);
  if (outcome.succeeded) {
    return true;
  }
  Log.error(
    'The workspace passphrase was not changed: '
    '${outcome.refused ?? outcome.failures.join(', ')}'
    '${outcome.rolledBack ? ' (what was written has been put back)' : ''}',
  );
  return false;
}
