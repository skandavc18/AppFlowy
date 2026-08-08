import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/google_calendar_provider.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy_backend/log.dart';

/// Putting a reminder on somebody's Google calendar as well.
///
/// Entirely optional: nothing here is reached unless an account is connected
/// AND the person asked for it, so a reminder keeps working with no network
/// and no account at all.
abstract final class ReminderGoogleSync {
  /// The meta key that remembers the copy already sent, so a reminder saved
  /// twice does not become two events.
  static const remoteKey = 'af_google_event';

  /// Whether an account is connected that could take a reminder.
  static Future<bool> isAvailable({ProviderConnections? connections}) async {
    final store = connections ?? ProviderConnections.instance;
    await store.ensureLoaded();
    return store.all.any((c) => c.service == ProviderService.googleCalendar);
  }

  /// Whether that account may actually write.
  static Future<bool> canWrite({ProviderConnections? connections}) async {
    final store = connections ?? ProviderConnections.instance;
    await store.ensureLoaded();
    for (final connection in store.all) {
      if (connection.service != ProviderService.googleCalendar) {
        continue;
      }
      if (connection.scopes.any(
        (s) => s.endsWith('/auth/calendar') || s.endsWith('/calendar.events'),
      )) {
        return true;
      }
    }
    return false;
  }

  /// Send [reminder] to the first account that will take it.
  ///
  /// Returns the remote event id, or null when nothing could be written — a
  /// refusal is logged and never thrown at the interface, because a reminder
  /// that saved locally has still done its job.
  static Future<String?> push(
    AppReminder reminder, {
    ProviderConnections? connections,
  }) async {
    final store = connections ?? ProviderConnections.instance;
    await store.ensureLoaded();

    for (final connection in store.all) {
      if (connection.service != ProviderService.googleCalendar) {
        continue;
      }
      final provider = GoogleCalendarProvider(
        connection: connection,
        selectedCalendarIds: const <String>{},
      );
      try {
        await provider.refresh();
        final target = _writableCalendar(provider);
        if (target == null) {
          continue;
        }
        final event = await provider.createEvent(
          CalendarEventDraft(
            title: reminder.title.isEmpty ? reminder.message : reminder.title,
            start: reminder.includeTime
                ? ZonedDateTime.local(reminder.scheduledAt)
                : ZonedDateTime.allDay(reminder.scheduledAt),
            end: reminder.includeTime
                ? ZonedDateTime.local(
                    reminder.scheduledAt.add(const Duration(minutes: 30)),
                  )
                : null,
            calendarId: target.id,
            description: reminder.message,
            recurrence: reminder.recurrence,
            kind: CalendarEventKind.reminder,
          ),
        );
        if (event != null) {
          return event.remoteId;
        }
      } catch (error) {
        Log.warn('A reminder could not be sent to Google Calendar: $error');
      } finally {
        provider.dispose();
      }
    }
    return null;
  }

  static CalendarInfo? _writableCalendar(GoogleCalendarProvider provider) {
    if (!provider.capabilities.canCreate) {
      return null;
    }
    CalendarInfo? fallback;
    for (final calendar in provider.calendars) {
      if (calendar.isReadOnly) {
        continue;
      }
      if (calendar.isPrimary) {
        return calendar;
      }
      fallback ??= calendar;
    }
    return fallback;
  }
}
