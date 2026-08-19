import 'dart:convert';

import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

/// A block whose content really has been replaced by ciphertext.
///
/// Unlike a protected page — which is gated, not scrambled — a sealed block
/// keeps nothing readable at all. The whole node, its text, its formatting, its
/// attributes and anything nested inside it, is serialised, sealed and written
/// back as one attribute. What is left in the document is a block that says
/// what shape it used to be and nothing else.
///
/// Because the sealed payload is the node's own JSON, opening it is exactly the
/// node that went in. Nothing is lossy: a picture, a table, an embedded page or
/// a paragraph with links in it all survive.
class EncryptedBlockKeys {
  const EncryptedBlockKeys._();

  static const String type = 'encrypted_block';

  /// The sealed node, as written by the workspace key.
  static const String sealed = 'sealed';

  /// The type the block used to be, so a locked page still reads as a shape
  /// rather than a wall of identical boxes.
  static const String kind = 'kind';

  /// When it was sealed, in milliseconds since the epoch.
  static const String sealedAt = 'sealed_at';
}

/// The domain a sealed value belongs to.
///
/// Deliberately coarse. Binding to a block id would break copying a sealed
/// block from one page to another — a thing people legitimately do — while
/// binding to the domain still stops a sealed block being pasted into a
/// database cell and opened there.
const String encryptedBlockContext = 'block';

Node encryptedBlockNode({
  required String sealed,
  required String kind,
  DateTime? sealedAt,
}) =>
    Node(
      type: EncryptedBlockKeys.type,
      attributes: {
        EncryptedBlockKeys.sealed: sealed,
        EncryptedBlockKeys.kind: kind,
        EncryptedBlockKeys.sealedAt:
            (sealedAt ?? DateTime.now()).millisecondsSinceEpoch,
      },
    );

extension EncryptedNodeExtension on Node {
  bool get isEncryptedBlock => type == EncryptedBlockKeys.type;

  /// The type this block used to be.
  String get encryptedBlockKind =>
      attributes[EncryptedBlockKeys.kind] as String? ?? '';

  String? get encryptedBlockPayload =>
      attributes[EncryptedBlockKeys.sealed] as String?;
}

/// Seals [node] into a block that holds only ciphertext.
///
/// Returns null when the workspace is locked, because sealing without the key
/// is not possible and pretending otherwise would destroy the block.
Node? sealBlock(Node node) {
  final vault = EncryptionVault.instance;
  if (!vault.isUnlocked || node.isEncryptedBlock) {
    return null;
  }
  return encryptedBlockNode(
    sealed: vault.seal(
      jsonEncode(node.toJson()),
      context: encryptedBlockContext,
    ),
    kind: node.type,
  );
}

/// Recovers the node a sealed block was made from.
///
/// Returns null when the workspace is locked or the payload does not open,
/// which the caller must treat as "leave it alone" — never as "replace it with
/// something empty".
Node? openBlock(Node node) {
  final payload = node.encryptedBlockPayload;
  if (payload == null || payload.isEmpty) {
    return null;
  }

  final vault = EncryptionVault.instance;
  if (!vault.isUnlocked) {
    return null;
  }

  try {
    final decoded = jsonDecode(
      vault.open(payload, context: encryptedBlockContext),
    );
    if (decoded is! Map) {
      return null;
    }
    return Node.fromJson(Map<String, Object>.from(decoded));
  } on Object {
    return null;
  }
}

/// Whether this block can be sealed at all.
///
/// The page root is the document itself and a block already sealed has nothing
/// left to hide.
bool canSealBlock(Node node) =>
    !node.isEncryptedBlock && node.type != PageBlockKeys.type;
