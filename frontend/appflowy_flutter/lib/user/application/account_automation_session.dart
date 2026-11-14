import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/extensions/application/extension_manager.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/sync/server_settings_sync.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/sync/synced_automation_files.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/code.pbenum.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:path/path.dart' as p;

/// Quiesces account automation before logout, without turning its local
/// removal into a synced deletion. Rejected logouts retain the local data.
class AccountAutomationSession {
  AccountAutomationSession({
    Future<String> Function()? dataPath,
    Future<void> Function()? stop,
    Future<void> Function()? reset,
    Future<void> Function()? resume,
    KeyValueStorage? storage,
  })  : _dataPath =
            dataPath ?? (() => getIt<ApplicationDataStorage>().getPath()),
        _stop = stop ?? _stopAutomation,
        _reset = reset ?? _resetAutomation,
        _resume = resume ?? _resumeAutomation,
        _storage = storage;

  static final AccountAutomationSession instance = AccountAutomationSession();

  final Future<String> Function() _dataPath;
  final Future<void> Function() _stop;
  final Future<void> Function() _reset;
  final Future<void> Function() _resume;
  final KeyValueStorage? _storage;
  Future<FlowyResult<void, FlowyError>>? _signingOut;

  Future<FlowyResult<void, FlowyError>> signOut(
    Future<FlowyResult<void, FlowyError>> Function() backendSignOut,
  ) {
    final running = _signingOut;
    if (running != null) return running;
    final next =
        _signOut(backendSignOut).whenComplete(() => _signingOut = null);
    _signingOut = next;
    return next;
  }

  Future<FlowyResult<void, FlowyError>> _signOut(
    Future<FlowyResult<void, FlowyError>> Function() backendSignOut,
  ) async {
    var signedOut = false;
    try {
      await _stop();
      final root = await _dataPath();
      if (root.isEmpty || p.dirname(p.absolute(root)) == p.absolute(root)) {
        throw StateError('The account data directory is invalid.');
      }
      final result = await backendSignOut();
      signedOut = result.fold((_) => true, (_) => false);
      if (signedOut) {
        try {
          for (final folder in automationDataFolders) {
            final path = p.join(root, folder);
            switch (await FileSystemEntity.type(path, followLinks: false)) {
              case FileSystemEntityType.directory:
                await Directory(path).delete(recursive: true);
              case FileSystemEntityType.link:
                await Link(path).delete();
              case FileSystemEntityType.file:
                await File(path).delete();
              case FileSystemEntityType.notFound:
                break;
              default:
                throw FileSystemException(
                  'Account automation data could not be removed.',
                  path,
                );
            }
          }
          final storage = _storage ?? getIt<KeyValueStorage>();
          for (final key in [
            ExtensionStore.enabledKey,
            DartExtensionHost.disabledKey,
            DartExtensionHost.themeKey,
          ]) {
            await storage.remove(key);
          }
        } finally {
          await _reset();
        }
      }
      return result;
    } on FileSystemException catch (error) {
      return _failure(error);
    } on StateError catch (error) {
      return _failure(error);
    } finally {
      if (!signedOut) await _resume();
    }
  }

  FlowyResult<void, FlowyError> _failure(Object error) {
    Log.error('Account automation cleanup failed (${error.runtimeType}).');
    return FlowyResult.failure(
      FlowyError(
        code: ErrorCode.Internal,
        msg: LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
      ),
    );
  }

  static Future<void> _stopAutomation() async {
    await Future.wait([
      WorkflowManager.instance.stop(),
      ExtensionManager.instance.stop(),
    ]);
    await Future.wait([
      WorkspaceSyncEngine.instance.suspendForSignOut(),
      ServerSettingsSync.instance.suspendForSignOut(),
    ]);
  }

  static Future<void> _resetAutomation() async {
    await Future.wait([
      WorkspaceSyncEngine.instance.forgetAccount(),
      ServerSettingsSync.instance.forgetAccount(),
      WorkflowManager.instance.resetAccount(),
      ExtensionManager.instance.resetAccount(),
    ]);
  }

  static Future<void> _resumeAutomation() async {
    await Future.wait([
      WorkflowManager.instance.resumeAfterSignOutFailure(),
      ExtensionManager.instance.start(),
    ]);
    WorkspaceSyncEngine.instance.resumeAfterSignOutFailure();
    await ServerSettingsSync.instance.resumeAfterSignOutFailure();
  }
}
