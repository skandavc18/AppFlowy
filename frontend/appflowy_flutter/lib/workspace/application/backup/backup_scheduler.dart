// The clock that takes a copy without being asked.
//
// Deliberately modest: a timer that wakes up now and then and asks the pure
// [backupIsDue] whether anything should happen. A backup that fires while
// somebody is typing must not interrupt them, so a run that cannot go ahead is
// simply skipped and tried again at the next tick rather than queued up.

import 'dart:async';

import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/backup_service.dart';
import 'package:appflowy/workspace/application/backup/backup_settings.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';

class BackupScheduler {
  BackupScheduler._();

  static final BackupScheduler instance = BackupScheduler._();

  /// How often the clock is consulted. The shortest schedule is hourly, so
  /// looking every five minutes is enough to be punctual and cheap enough to
  /// be invisible.
  static const Duration tick = Duration(minutes: 5);

  /// How long after the application opens before the first look.
  ///
  /// Starting a copy while the workspace is still loading would make AppFlowy
  /// feel slow for the one thing nobody asked to watch.
  static const Duration settleDelay = Duration(minutes: 2);

  Timer? _timer;
  bool _running = false;

  bool get isStarted => _timer != null;

  void start({UserProfilePB? userProfile}) {
    if (userProfile != null) {
      BackupService.instance.userProfile = userProfile;
    }
    if (_timer != null) {
      return;
    }
    _timer = Timer(settleDelay, () {
      unawaited(_consider());
      _timer = Timer.periodic(tick, (_) => unawaited(_consider()));
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Runs the copy a schedule of "when AppFlowy closes" asks for.
  Future<void> runOnClose() async {
    final settings = BackupSettings.instance;
    await settings.ensureLoaded();
    final policy = settings.policy;
    if (!policy.enabled ||
        policy.schedule != BackupSchedule.onClose ||
        !policy.isReady) {
      return;
    }
    await _run();
  }

  Future<void> _consider() async {
    if (_running || BackupService.instance.isRunning) {
      return;
    }
    final settings = BackupSettings.instance;
    await settings.ensureLoaded();
    if (!backupIsDue(
      policy: settings.policy,
      now: DateTime.now(),
      lastRunAt: settings.lastRunAt,
    )) {
      return;
    }
    if (!settings.isUnlocked) {
      // A sealed backup cannot stop and ask for a passphrase. Saying so once
      // is better than failing quietly every hour.
      Log.info(
        'A scheduled backup is due, but the backup passphrase has not been '
        'entered on this computer.',
      );
      return;
    }
    await _run();
  }

  Future<void> _run() async {
    _running = true;
    try {
      await BackupService.instance.runNow(automatic: true);
    } on Object catch (error) {
      Log.warn('A scheduled backup could not start: $error');
    } finally {
      _running = false;
    }
  }
}
