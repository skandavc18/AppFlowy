import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/presentation/encryption/encryption_dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Sealing every cell of a column, and writing them back in the clear.
///
/// Unlike a block, a column is not one value: the whole table has to be read
/// and every cell written back one at a time, which is slow enough to be worth
/// showing. The dialog also says plainly what will happen before it happens,
/// because a table is somebody's data and this rewrites all of it.
Future<void> applyColumnEncryption({
  required BuildContext context,
  required String viewId,
  required String fieldId,
  required bool seal,
}) async {
  // The row that asks for this lives in a menu that closes on the way out, so
  // the menu's own context is gone by the time the first dialog would open.
  // Everything here is application-modal anyway, so it is hosted at the root.
  BuildContext? host() => AppGlobals.rootNavKey.currentContext;

  final opening = host();
  if (opening == null || !opening.mounted) {
    return;
  }

  final gate = seal ? ensureWorkspaceUnlocked : confirmWorkspaceKey;
  if (!await gate(opening)) {
    return;
  }

  final asking = host();
  if (asking == null || !asking.mounted) {
    return;
  }

  final confirmed = await showDialog<bool>(
        context: asking,
        builder: (_) => _ConfirmColumnEncryption(seal: seal),
      ) ??
      false;
  if (!confirmed) {
    return;
  }
  final working = host();
  if (working == null || !working.mounted) {
    return;
  }

  final progress = showDialog<void>(
    context: working,
    barrierDismissible: false,
    builder: (_) => const _Working(),
  );

  final registry = EncryptedColumnRegistry.instance;
  final result = seal
      ? await registry.encryptColumn(viewId: viewId, fieldId: fieldId)
      : await registry.decryptColumn(viewId: viewId, fieldId: fieldId);

  final closing = host();
  if (closing != null && closing.mounted) {
    Navigator.of(closing, rootNavigator: true).pop();
  }
  await progress;

  final telling = host();
  if (telling == null || !telling.mounted) {
    return;
  }

  reportEncryptionOutcome(
    context: telling,
    succeeded: result.succeeded,
    succeededMessage: seal
        ? LocaleKeys.encryption_columnSealed.tr(args: ['${result.cells}'])
        : LocaleKeys.encryption_columnOpened.tr(args: ['${result.cells}']),
    failedMessage: _reasonFor(result.failure),
  );
}

String _reasonFor(String? failure) => switch (failure) {
      'locked' => LocaleKeys.encryption_needsUnlocking.tr(),
      'unsupported' => LocaleKeys.encryption_columnTextOnly.tr(),
      'wrongKey' => LocaleKeys.encryption_columnWrongKey.tr(),
      'incomplete' => LocaleKeys.encryption_columnIncomplete.tr(),
      'missing' || 'read' => LocaleKeys.encryption_columnCouldNotRead.tr(),
      _ => LocaleKeys.encryption_couldNotChange.tr(),
    };

class _ConfirmColumnEncryption extends StatelessWidget {
  const _ConfirmColumnEncryption({required this.seal});

  final bool seal;

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        seal
            ? LocaleKeys.encryption_columnEncrypt.tr()
            : LocaleKeys.encryption_columnDecrypt.tr(),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: premium.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Text(
          seal
              ? LocaleKeys.encryption_columnEncryptBody.tr()
              : LocaleKeys.encryption_columnDecryptBody.tr(),
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: premium.textSecondary,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            seal
                ? LocaleKeys.encryption_columnEncrypt.tr()
                : LocaleKeys.encryption_columnDecrypt.tr(),
          ),
        ),
      ],
    );
  }
}

class _Working extends StatelessWidget {
  const _Working();

  @override
  Widget build(BuildContext context) {
    final premium = PremiumThemeExtension.of(context);
    return AlertDialog(
      backgroundColor: premium.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: SizedBox(
        width: 260,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                LocaleKeys.encryption_columnWorking.tr(),
                style: TextStyle(fontSize: 13, color: premium.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
