// Changing the AppFlowy password, and moving everything that follows it over.

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_settings.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/application/sync/server_settings_sync.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

@immutable
class AppPasswordChangeOutcome {
  const AppPasswordChangeOutcome({
    required this.changed,
    required this.message,
  });

  final bool changed;

  /// What to tell the person, whether it worked or not.
  final String message;
}

/// Changes the AppFlowy password from [current] to [next].
///
/// Protected pages go first, because they are the one thing that cannot be
/// left half done: when they cannot be moved to the new password, nothing
/// changes at all. Then the password itself and backups, and last what is
/// kept elsewhere — the sync folder and the server — which are sealed again
/// now, or as soon as they can be reached.
Future<AppPasswordChangeOutcome> changeAppPassword({
  required String current,
  required String next,
  void Function(String step)? onStep,
}) async {
  final passwords = AppPassword.instance;
  await passwords.ensureLoaded();
  if (!passwords.isSet || !await passwords.check(current)) {
    return AppPasswordChangeOutcome(
      changed: false,
      message: LocaleKeys.appPassword_wrong.tr(),
    );
  }
  if (current == next) {
    return AppPasswordChangeOutcome(
      changed: true,
      message: LocaleKeys.appPassword_changed.tr(),
    );
  }

  final vault = EncryptionVault.instance;
  await vault.ensureLoaded();
  if (vault.isConfigured && vault.policy.usesAppPassword) {
    onStep?.call(LocaleKeys.appPassword_stepProtected.tr());
    final moved = await vault.changePassphrase(
      current: current,
      next: next,
      reseal: resealWorkspace,
    );
    if (!moved) {
      return AppPasswordChangeOutcome(
        changed: false,
        message: LocaleKeys.appPassword_changeProtectedFailed.tr(),
      );
    }
  }

  await passwords.commitChange(next);

  onStep?.call(LocaleKeys.appPassword_stepBackup.tr());
  await BackupSettings.instance.useAppPassword(next);

  var later = false;
  final sync = WorkspaceSyncEngine.instance;
  if (sync.isBoundHere && sync.isSealed) {
    onStep?.call(LocaleKeys.appPassword_stepSync.tr());
    await sync.markResealPending();
    try {
      await sync.sealWithAppPassword();
    } on Object catch (error) {
      Log.warn('The sync folder was not sealed again yet: $error');
      later = true;
    }
  }

  final server = ServerSettingsSync.instance;
  if (server.phase != ServerSettingsPhase.off &&
      server.phase != ServerSettingsPhase.notSetUp) {
    onStep?.call(LocaleKeys.appPassword_stepServer.tr());
    try {
      await server.resealWithAppPassword();
    } on Object catch (error) {
      Log.warn('The settings on the server were not sealed again: $error');
      later = true;
    }
  }

  return AppPasswordChangeOutcome(
    changed: true,
    message: later
        ? LocaleKeys.appPassword_changedSyncLater.tr()
        : LocaleKeys.appPassword_changed.tr(),
  );
}
