import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/presentation/encryption/encryption_dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/button.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

/// Putting the page in front of you behind the workspace key, from its own
/// options.
///
/// The same row the sidebar offers, reachable without hunting for the page in
/// the tree — which is where somebody actually is when they decide a page is
/// private.
class EncryptPageAction extends StatelessWidget {
  const EncryptPageAction({
    super.key,
    required this.view,
    this.onDone,
  });

  final ViewPB view;

  /// Lets the host close the menu the row was chosen from.
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final protected = view.isProtected;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: FlowyIconTextButton(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        onTap: () => unawaited(_toggle(protected)),
        leftIconBuilder: (_) => Icon(
          protected ? Icons.shield_rounded : Icons.shield_outlined,
          size: 16,
        ),
        iconPadding: 10.0,
        textBuilder: (_) => FlowyText(
          protected
              ? LocaleKeys.encryption_unprotectItem.tr()
              : LocaleKeys.encryption_protectItem.tr(),
          figmaLineHeight: 18.0,
        ),
      ),
    );
  }

  Future<void> _toggle(bool protected) async {
    // The menu is closed first, so the dialog is opened from the root
    // navigator rather than from a popover that is about to be unmounted.
    onDone?.call();

    final host = AppGlobals.rootNavKey.currentContext;
    if (host == null || !await ensureWorkspaceUnlocked(host)) {
      return;
    }

    final covered = protected
        ? await EncryptionMarkService.unprotect(view)
        : await EncryptionMarkService.protect(view);

    // Newly protected means newly shut; unprotecting has nothing left to hide.
    if (covered > 0) {
      protected
          ? EncryptionVault.instance.reveal(view.id)
          : lockProtectedItem(view.id);
    }

    final report = AppGlobals.rootNavKey.currentContext;
    if (report == null || !report.mounted) {
      return;
    }
    final inside = covered - 1;
    reportEncryptionOutcome(
      context: report,
      succeeded: covered > 0,
      succeededMessage: switch ((protected, inside > 0)) {
        (false, false) => LocaleKeys.encryption_itemProtectedLocked.tr(),
        (false, true) => LocaleKeys.encryption_itemProtectedLockedWithChildren
            .tr(args: ['$inside']),
        (true, false) => LocaleKeys.encryption_itemUnprotected.tr(),
        (true, true) => LocaleKeys.encryption_itemUnprotectedWithChildren
            .tr(args: ['$inside']),
      },
    );
  }
}
