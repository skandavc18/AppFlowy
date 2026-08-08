import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/notification_scheduler.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:easy_localization/easy_localization.dart';

/// Give reminders a voice outside the application window.
///
/// The words are resolved lazily, when a notification actually fires, so this
/// can be started before the translations have finished loading.
void startReminderNotifications() {
  final store = ReminderStore.instance;

  store.onOpenRequested = (reminder) async {
    if (!getIt.isRegistered<ReminderBloc>()) {
      return;
    }
    getIt<ReminderBloc>().add(
      ReminderEvent.pressReminder(reminderId: reminder.id),
    );
  };

  ReminderNotificationScheduler.instance
    ..fallbackPresenter = _presentInApp
    ..start(delegate: store, copy: _copyFor);
  store.start();
  Log.info('Reminder notifications are running.');
}

/// iOS and Android have no notification centre this build can reach, so a due
/// reminder is announced inside the application instead of silently passing.
void _presentInApp(AppReminder reminder, ReminderNotificationCopy words) {
  showToastNotification(
    message: words.title,
    description: words.body,
    type: ToastificationType.info,
  );
}

void stopReminderNotifications() {
  ReminderNotificationScheduler.instance.stop();
  ReminderStore.instance.stopPolling();
}

ReminderNotificationCopy _copyFor(AppReminder reminder) =>
    reminderNotificationCopy(
      reminder,
      heading: LocaleKeys.reminders_title.tr(),
      done: LocaleKeys.reminders_done.tr(),
      snooze: LocaleKeys.reminders_snooze.tr(),
      open: LocaleKeys.reminders_open.tr(),
      formatWhen: (when) => DateFormat.MMMEd().add_jm().format(when),
    );
