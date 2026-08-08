import 'dart:async';

import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:universal_platform/universal_platform.dart';

/// What somebody can do straight from a notification.
enum ReminderNotificationAction { done, snooze, open }

/// What the scheduler needs from the rest of the application.
///
/// Passing this in rather than reaching for a bloc is what makes the whole
/// firing rule testable without a widget tree or a running backend.
abstract class ReminderNotificationDelegate {
  /// Everything that might still need to speak.
  List<AppReminder> get reminders;

  /// Remember that the operating system has been told, so a restart does not
  /// repeat every notification of the day.
  Future<void> markNotified(AppReminder reminder);

  Future<void> complete(AppReminder reminder);

  Future<void> snooze(AppReminder reminder, SnoozeOption option);

  /// Bring the thing the reminder is about to the front.
  Future<void> open(AppReminder reminder);
}

/// How a notification should read, kept out of the firing rule so the words
/// can be translated without touching the timing.
typedef ReminderNotificationCopy = ({
  String title,
  String body,
  String done,
  String snooze,
  String open,
});

/// Turns due reminders into operating-system notifications.
///
/// The rule itself is [dueReminders], which is pure. Everything else is the
/// plumbing that shows one and remembers it was shown.
class ReminderNotificationScheduler {
  ReminderNotificationScheduler({
    Duration tick = const Duration(seconds: 20),
    @visibleForTesting bool? supportsNotifications,
  })  : _tick = tick,
        _supported = supportsNotifications ??
            (UniversalPlatform.isWindows ||
                UniversalPlatform.isMacOS ||
                UniversalPlatform.isLinux);

  static final ReminderNotificationScheduler instance =
      ReminderNotificationScheduler();

  /// A notification older than this is not worth interrupting somebody for —
  /// it belongs in the panel, not on top of whatever they are doing.
  static const staleAfter = Duration(hours: 12);

  final Duration _tick;
  final bool _supported;

  ReminderNotificationDelegate? _delegate;
  ReminderNotificationCopy Function(AppReminder)? _copy;
  Timer? _timer;

  /// Shown where the operating system has no notification centre this build
  /// can reach — currently iOS and Android. Set once, at startup.
  void Function(AppReminder, ReminderNotificationCopy)? fallbackPresenter;

  /// Notifications held so the plugin's listener keeps working; the plugin
  /// only dispatches callbacks to objects it still has a reference to.
  final Map<String, LocalNotification> _live = <String, LocalNotification>{};

  bool get isRunning => _timer != null;

  void start({
    required ReminderNotificationDelegate delegate,
    required ReminderNotificationCopy Function(AppReminder) copy,
  }) {
    _delegate = delegate;
    _copy = copy;
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => unawaited(sweep()));
    unawaited(sweep());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _delegate = null;
    _copy = null;
  }

  /// Fire everything that has come due since the last look.
  Future<void> sweep({DateTime? now}) async {
    final delegate = _delegate;
    final copy = _copy;
    if (delegate == null || copy == null) {
      return;
    }
    final due = dueReminders(delegate.reminders, now: now ?? DateTime.now());
    for (final reminder in due) {
      await _present(reminder, delegate, copy);
    }
  }

  Future<void> _present(
    AppReminder reminder,
    ReminderNotificationDelegate delegate,
    ReminderNotificationCopy Function(AppReminder) copy,
  ) async {
    // Record it first: a notification that failed to show is far better than
    // one that shows again on every tick.
    await delegate.markNotified(reminder);

    final words = copy(reminder);

    if (!_supported) {
      fallbackPresenter?.call(reminder, words);
      return;
    }

    try {
      final notification = LocalNotification(
        identifier: 'appflowy-reminder-${reminder.id}',
        title: words.title,
        body: words.body,
        silent: !reminder.playsSound,
        actions: [
          LocalNotificationAction(text: words.done),
          LocalNotificationAction(text: words.snooze),
          LocalNotificationAction(text: words.open),
        ],
      );
      notification.onClick = () => unawaited(delegate.open(reminder));
      notification.onClickAction = (index) {
        final action =
            index >= 0 && index < ReminderNotificationAction.values.length
                ? ReminderNotificationAction.values[index]
                : ReminderNotificationAction.open;
        final work = switch (action) {
          ReminderNotificationAction.done => delegate.complete(reminder),
          ReminderNotificationAction.snooze =>
            delegate.snooze(reminder, SnoozeOption.tenMinutes),
          ReminderNotificationAction.open => delegate.open(reminder),
        };
        unawaited(work);
        _live.remove(reminder.id);
      };
      notification.onClose = (_) => _live.remove(reminder.id);

      _live[reminder.id] = notification;
      await notification.show();
    } catch (error) {
      Log.warn('A reminder could not be shown by the system: $error');
    }
  }

  @visibleForTesting
  void forgetLiveNotifications() => _live.clear();
}

/// Which reminders the operating system still owes somebody, right now.
///
/// Pure on purpose: this is the part that must never be wrong, and it can be
/// checked without a notification centre, a backend or a clock.
List<AppReminder> dueReminders(
  Iterable<AppReminder> reminders, {
  required DateTime now,
  Duration staleAfter = ReminderNotificationScheduler.staleAfter,
}) {
  final due = <AppReminder>[];
  for (final reminder in reminders) {
    if (reminder.isDone || reminder.isArchived) {
      continue;
    }
    final fires = reminder.firesAt;
    if (fires.isAfter(now)) {
      continue;
    }
    // Already announced this occurrence.
    final notified = reminder.notifiedAt;
    if (notified != null && !notified.isBefore(fires)) {
      continue;
    }
    // Long past: it is history, not an interruption.
    if (now.difference(fires) > staleAfter) {
      continue;
    }
    due.add(reminder);
  }
  due.sort((a, b) => a.firesAt.compareTo(b.firesAt));
  return due;
}
