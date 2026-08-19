import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/presentation/encryption/encryption_dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

/// Sealing one block, and putting it back.
///
/// This is the whole of "encrypt this block": the node is serialised, sealed
/// with the workspace key and written back as a block that holds nothing but
/// ciphertext. Because the payload is the node's own JSON, an embed, a picture,
/// a table or a paragraph with links in it all come back exactly as they went.
Future<void> applyBlockEncryption({
  required BuildContext context,
  required EditorState editorState,
  required Node node,
  required bool seal,
}) async {
  // Revealing is the one direction that needs the passphrase said out loud;
  // sealing only needs the key that is already here.
  final gate = seal ? ensureWorkspaceUnlocked : confirmWorkspaceKey;
  if (!await gate(context)) {
    return;
  }
  if (!context.mounted) {
    return;
  }

  final replacement = seal ? sealBlock(node) : openBlock(node);
  if (replacement == null) {
    reportEncryptionOutcome(
      context: context,
      succeeded: false,
      succeededMessage: '',
      failedMessage: seal
          ? LocaleKeys.encryption_blockCouldNotSeal.tr()
          : LocaleKeys.encryption_blockCouldNotOpen.tr(),
    );
    return;
  }

  // Insert before deleting. An empty document grows a stray paragraph the
  // moment its last child goes, so the replacement has to be in place first.
  final transaction = editorState.transaction
    ..insertNode(node.path, replacement)
    ..deleteNode(node);
  await editorState.apply(transaction);

  if (context.mounted) {
    reportEncryptionOutcome(
      context: context,
      succeeded: true,
      succeededMessage: seal
          ? LocaleKeys.encryption_blockSealed.tr()
          : LocaleKeys.encryption_blockOpened.tr(),
    );
  }
}
