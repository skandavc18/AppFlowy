import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:flutter/widgets.dart';

import 'database_find_navigation.dart';

/// The calendar renderer is also used by non-database dashboards. Only its
/// own table provider may register database row/title anchors.
class DatabaseFindCalendarScope extends InheritedWidget {
  const DatabaseFindCalendarScope({
    super.key,
    required this.viewId,
    required this.calendarId,
    required this.primaryFieldId,
    required super.child,
  });

  final String viewId;
  final String calendarId;
  final String? primaryFieldId;

  @override
  bool updateShouldNotify(DatabaseFindCalendarScope oldWidget) =>
      viewId != oldWidget.viewId ||
      calendarId != oldWidget.calendarId ||
      primaryFieldId != oldWidget.primaryFieldId;
}

class DatabaseFindCalendarEvent extends StatelessWidget {
  const DatabaseFindCalendarEvent({
    super.key,
    required this.event,
    required this.child,
  });

  final CalendarEvent event;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<DatabaseFindCalendarScope>();
    final enabled = scope != null &&
        scope.calendarId == event.calendarId &&
        event.rowId.isNotEmpty;
    return DatabaseFindAnchor(
      target: DatabaseFindTarget.row(scope?.viewId ?? '', event.rowId),
      enabled: enabled,
      child: DatabaseFindAnchor(
        target: DatabaseFindTarget.cell(
          scope?.viewId ?? '',
          event.rowId,
          scope?.primaryFieldId,
        ),
        enabled: enabled && scope.primaryFieldId != null,
        child: child,
      ),
    );
  }
}
