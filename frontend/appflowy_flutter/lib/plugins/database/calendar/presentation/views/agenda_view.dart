import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_chip.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// What the agenda calls each day: TODAY, TOMORROW, or the date itself.
typedef AgendaDayLabel = String Function(
  DateTime day, {
  required bool relative,
});

/// A chronological list — the reading that works on a narrow window.
///
/// One column of time down the left, one of content on the right, and a
/// section heading per day. No boxes at all: the time column is the structure.
class CalendarAgendaView extends StatelessWidget {
  const CalendarAgendaView({
    super.key,
    required this.from,
    required this.to,
    required this.events,
    required this.delegate,
    required this.labelFor,
    required this.allDayLabel,
    this.emptyState,
  });

  final DateTime from;
  final DateTime to;
  final List<CalendarEvent> events;
  final CalendarViewDelegate delegate;
  final AgendaDayLabel labelFor;
  final String allDayLabel;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    final sections = groupAgenda(events, from: from, to: to);
    if (sections.isEmpty) {
      return emptyState ?? const SizedBox.shrink();
    }

    final today = startOfDay(DateTime.now());

    return CalendarScrollScope(
      child: ListView.builder(
        primary: calendarDrivesPageScroll(context) ? true : null,
        padding: const EdgeInsets.fromLTRB(
          CalendarMetrics.space4,
          CalendarMetrics.space2,
          CalendarMetrics.space4,
          CalendarMetrics.space6,
        ),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final section = sections[index];
          final isToday = isSameDay(section.day, today);
          return Padding(
            padding: EdgeInsets.only(
              top: index == 0 ? 0 : CalendarMetrics.space5,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionHeading(
                  day: section.day,
                  label: labelFor(section.day, relative: true),
                  emphasised: isToday,
                ),
                const SizedBox(height: CalendarMetrics.space2),
                for (final event in section.events)
                  _AgendaRow(
                    event: event,
                    day: section.day,
                    delegate: delegate,
                    allDayLabel: allDayLabel,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.day,
    required this.label,
    required this.emphasised,
  });

  final DateTime day;
  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Row(
      children: [
        CalendarSectionLabel(text: label.toUpperCase(), emphasised: emphasised),
        const SizedBox(width: CalendarMetrics.space2),
        Text(
          DateFormat.MMMd().format(day),
          style: TextStyle(
            fontSize: 11,
            height: 1,
            color: palette.textMuted.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: CalendarMetrics.space3),
        Expanded(
          child: Container(
            height: 0.7,
            color: palette.gridLine,
          ),
        ),
      ],
    );
  }
}

class _AgendaRow extends StatelessWidget {
  const _AgendaRow({
    required this.event,
    required this.day,
    required this.delegate,
    required this.allDayLabel,
  });

  final CalendarEvent event;
  final DateTime day;
  final CalendarViewDelegate delegate;
  final String allDayLabel;

  @override
  Widget build(BuildContext context) {
    final palette = calendarPaletteOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: CalendarMetrics.agendaTimeColumnWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 10, right: 12),
              child: Text(
                _time(),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1,
                  color: palette.textSecondary,
                  fontVariations: const [FontVariation.weight(580)],
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: CalendarEventChip(
              event: event,
              color: delegate.colorOf(event),
              density: CalendarChipDensity.comfortable,
              onTap: delegate.onOpenEvent == null
                  ? null
                  : () => delegate.onOpenEvent!(event),
              onSecondaryTap: delegate.onEventMenu == null
                  ? null
                  : (position) => delegate.onEventMenu!(event, position),
              onToggleComplete: delegate.onToggleComplete == null ||
                      event.kind == CalendarEventKind.event
                  ? null
                  : () => delegate.onToggleComplete!(event),
            ),
          ),
        ],
      ),
    );
  }

  String _time() {
    if (event.isAllDay) {
      return allDayLabel;
    }
    // A day in the middle of a long event has no start of its own to show.
    if (event.startDay.isBefore(day)) {
      return '→';
    }
    return calendarShortTime(event.start.local);
  }
}
