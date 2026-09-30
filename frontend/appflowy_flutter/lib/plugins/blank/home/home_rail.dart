import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/blank/home/home_agenda.dart';
import 'package:appflowy/plugins/blank/home/home_sections.dart';
import 'package:appflowy/plugins/blank/home/home_weather.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/weather/weather_reading.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A card on Home's side rail: a small heading, then its content.
class HomeRailCard extends StatelessWidget {
  const HomeRailCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return WorkspaceSurface(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              WorkspaceGlyph(icon, size: 16, color: palette.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: title),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          TextSpan(
                            text: '  $subtitle',
                            style: WorkspaceTypography.style(
                              context,
                              WorkspaceTextRole.metadata,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.section,
                    ).copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: WorkspaceTokens.space2),
          child,
        ],
      ),
    );
  }
}

/// The time, the weather and the page to pick back up, in one place.
class HomeGlanceCard extends StatelessWidget {
  const HomeGlanceCard({
    super.key,
    required this.now,
    required this.formatTime,
    required this.weather,
    required this.resume,
  });

  final DateTime now;
  final String Function(DateTime time) formatTime;
  final Widget weather;
  final Widget resume;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final clock = HomeClock(
      now: now,
      formatTime: formatTime,
      alignment: CrossAxisAlignment.start,
    );
    return WorkspaceSurface(
      key: const ValueKey('home-glance'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >=
                    MediaQuery.textScalerOf(context).scale(270)
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: clock),
                      const SizedBox(width: WorkspaceTokens.space2),
                      weather,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      clock,
                      const SizedBox(height: WorkspaceTokens.space2),
                      weather,
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: WorkspaceTokens.space4,
            ),
            child: Divider(height: 1, thickness: 1, color: palette.border),
          ),
          resume,
        ],
      ),
    );
  }
}

String _degrees(double value) => '${value.round()}°';

/// The weather where somebody chose, or a way to choose somewhere.
class HomeWeatherTile extends StatelessWidget {
  const HomeWeatherTile({
    super.key,
    required this.source,
    required this.onChoosePlace,
  });

  final HomeWeatherSource source;
  final VoidCallback onChoosePlace;

  Future<void> _showMenu(BuildContext context) async {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    await showAppMenu<void>(
      context: context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      placement: AppMenuPlacement.belowEnd,
      entries: [
        AppMenuHeader(LocaleKeys.landing_weatherSource.tr()),
        AppMenuItem(
          label: LocaleKeys.landing_weatherRefresh.tr(),
          icon: Icons.refresh_rounded,
          onSelected: () => unawaited(source.refresh()),
        ),
        AppMenuItem(
          label: LocaleKeys.landing_weatherChangePlace.tr(),
          icon: Icons.edit_location_alt_rounded,
          onSelected: onChoosePlace,
        ),
        AppMenuItem(
          label: source.fahrenheit
              ? LocaleKeys.landing_weatherCelsius.tr()
              : LocaleKeys.landing_weatherFahrenheit.tr(),
          icon: Icons.swap_horiz_rounded,
          onSelected: () => unawaited(source.setFahrenheit(!source.fahrenheit)),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.landing_weatherHide.tr(),
          icon: Icons.visibility_off_rounded,
          onSelected: () => unawaited(source.clear()),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final place = source.place;
    if (place == null) {
      return TextButton.icon(
        key: const ValueKey('home-weather-add'),
        onPressed: onChoosePlace,
        style: TextButton.styleFrom(
          foregroundColor: palette.secondaryText,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: const StadiumBorder(),
          textStyle: WorkspaceTypography.style(
            context,
            WorkspaceTextRole.metadata,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
        icon: WorkspaceGlyph(
          Icons.wb_sunny_rounded,
          size: 16,
          color: palette.secondaryText,
        ),
        label: Text(LocaleKeys.landing_weatherAdd.tr()),
      );
    }
    final reading = source.reading;
    final metadata = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.metadata,
    );
    final status = reading != null
        ? LocaleKeys.landing_weatherHighLow.tr(
            args: [_degrees(reading.high), _degrees(reading.low)],
          )
        : source.isLoading
            ? LocaleKeys.landing_weatherReading.tr()
            : LocaleKeys.landing_weatherUnavailable.tr();
    return Builder(
      builder: (context) => Semantics(
        button: true,
        label: reading == null
            ? '${place.name}, $status'
            : LocaleKeys.landing_weatherLabel.tr(
                args: [place.name, _degrees(reading.temperature), status],
              ),
        child: ExcludeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('home-weather'),
              borderRadius: BorderRadius.circular(WorkspaceTokens.inputRadius),
              onTap: () => unawaited(_showMenu(context)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          WorkspaceGlyph(
                            reading != null
                                ? weatherIconFor(reading.code)
                                : source.isLoading
                                    ? Icons.cloud_queue_rounded
                                    : Icons.cloud_off_rounded,
                            size: 22,
                            color: palette.accent,
                          ),
                          if (reading != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              _degrees(reading.temperature),
                              style: homeSerif(
                                WorkspaceTypography.style(
                                  context,
                                  WorkspaceTextRole.pageTitle,
                                ),
                              ).copyWith(
                                fontSize: 28,
                                fontWeight: FontWeight.w400,
                                height: 1.1,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        place.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metadata.copyWith(
                          color: palette.primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metadata,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A month at a glance. Days with events carry a round mark, days with a
/// reminder a square one; choosing a day shows its events.
class HomeCalendarCard extends StatelessWidget {
  const HomeCalendarCard({
    super.key,
    required this.month,
    required this.today,
    required this.selected,
    required this.eventDays,
    required this.reminderDays,
    required this.onMonthChanged,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final Set<DateTime> eventDays;
  final Set<DateTime> reminderDays;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final localizations = MaterialLocalizations.of(context);
    // Material counts from Sunday (0); DateTime counts Sunday as 7.
    final firstDay = localizations.firstDayOfWeekIndex == 0
        ? DateTime.sunday
        : localizations.firstDayOfWeekIndex;
    final days = monthGridDays(month, firstDayOfWeek: firstDay);
    final showingToday = month.year == today.year && month.month == today.month;
    final metadata = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.metadata,
    );
    Widget arrow(IconData icon, String tooltip, int offset, String key) =>
        IconButton(
          key: ValueKey(key),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          onPressed: () => onMonthChanged(calendarMonthOffset(month, offset)),
          icon: WorkspaceGlyph(icon, color: palette.secondaryText),
        );
    return HomeRailCard(
      key: const ValueKey('home-calendar'),
      title: DateFormat.yMMMM().format(month),
      icon: Icons.calendar_month_rounded,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!showingToday)
            TextButton(
              key: const ValueKey('home-calendar-today'),
              onPressed: () {
                onMonthChanged(DateTime(today.year, today.month));
                onSelect(today);
              },
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: const StadiumBorder(),
              ),
              child: Text(LocaleKeys.landing_today.tr()),
            ),
          arrow(
            Icons.chevron_left_rounded,
            LocaleKeys.landing_previousMonth.tr(),
            -1,
            'home-calendar-previous',
          ),
          arrow(
            Icons.chevron_right_rounded,
            LocaleKeys.landing_nextMonth.tr(),
            1,
            'home-calendar-next',
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (final weekday in weekdayOrder(firstDay))
                  Expanded(
                    child: Center(
                      child: Text(
                        localizations.narrowWeekdays[weekday % 7],
                        style: metadata.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              // Large text grows the marks, never past their column.
              final size = math.max(
                0.0,
                math.min(
                  MediaQuery.textScalerOf(context)
                      .scale(28)
                      .clamp(28.0, 44.0)
                      .toDouble(),
                  constraints.maxWidth / 7 - 2,
                ),
              );
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var week = 0; week < days.length ~/ 7; week++)
                    Row(
                      children: [
                        for (final day in days.skip(week * 7).take(7))
                          Expanded(
                            child: _HomeCalendarDay(
                              day: day,
                              size: size,
                              inMonth: day.month == month.month,
                              isToday: isSameDay(day, today),
                              isSelected: isSameDay(day, selected),
                              hasEvents: eventDays.contains(day),
                              hasReminders: reminderDays.contains(day),
                              onTap: () => onSelect(day),
                            ),
                          ),
                      ],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeCalendarDay extends StatelessWidget {
  const _HomeCalendarDay({
    required this.day,
    required this.size,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.hasEvents,
    required this.hasReminders,
    required this.onTap,
  });

  final DateTime day;
  final double size;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final bool hasEvents;
  final bool hasReminders;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final onAccent = Theme.of(context).colorScheme.onPrimary;
    final mark = isSelected ? onAccent : palette.accent;
    Widget dot(bool square, Color color) => Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: color,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
          ),
        );
    return Semantics(
      button: true,
      selected: isSelected,
      label: DateFormat.yMMMMEEEEd().format(day),
      child: ExcludeSemantics(
        child: InkResponse(
          key: ValueKey(
            'home-calendar-day-${DateFormat('yyyy-MM-dd').format(day)}',
          ),
          onTap: onTap,
          radius: size / 2 + 4,
          child: SizedBox(
            height: size + 8,
            child: Center(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? palette.accent
                      : isToday
                          ? palette.accent.withValues(alpha: 0.12)
                          : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.metadata,
                        color: isSelected
                            ? onAccent
                            : isToday
                                ? palette.accent
                                : inMonth
                                    ? palette.primaryText
                                    : palette.mutedText,
                      ).copyWith(
                        fontWeight: isToday || isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (hasEvents || hasReminders)
                      Positioned(
                        bottom: 3,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasEvents) dot(false, mark),
                            if (hasReminders)
                              dot(
                                true,
                                isSelected ? onAccent : palette.success,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _timeOf(
  HomeAgendaItem item,
  String Function(DateTime time) formatTime,
) {
  if (item.allDay) return LocaleKeys.landing_allDay.tr();
  final end = item.end;
  final range = end == null || !end.isAfter(item.start)
      ? formatTime(item.start)
      : '${formatTime(item.start)} – ${formatTime(end)}';
  return item.location.isEmpty ? range : '$range · ${item.location}';
}

class _RailEmpty extends StatelessWidget {
  const _RailEmpty({
    super.key,
    required this.title,
    required this.detail,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.body,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
              ),
            ),
          ],
        ),
      );
}

/// The chosen day's calendar events; for today, the next few days as well.
class HomeEventsCard extends StatelessWidget {
  const HomeEventsCard({
    super.key,
    required this.day,
    required this.today,
    required this.events,
    required this.upcoming,
    required this.formatTime,
    required this.onOpen,
    this.onToday,
  });

  final DateTime day;
  final DateTime today;
  final List<HomeAgendaItem> events;
  final List<HomeAgendaItem> upcoming;
  final String Function(DateTime time) formatTime;
  final ValueChanged<HomeAgendaItem> onOpen;
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final isToday = isSameDay(day, today);
    return HomeRailCard(
      key: const ValueKey('home-events'),
      title: LocaleKeys.landing_events.tr(),
      subtitle: isToday
          ? LocaleKeys.landing_today.tr()
          : DateFormat.MMMEd().format(day),
      icon: Icons.event_rounded,
      trailing: isToday || onToday == null
          ? null
          : TextButton(
              key: const ValueKey('home-events-today'),
              onPressed: onToday,
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                shape: const StadiumBorder(),
              ),
              child: Text(LocaleKeys.landing_today.tr()),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (events.isEmpty)
            _RailEmpty(
              key: const ValueKey('home-events-empty'),
              title: LocaleKeys.landing_noEvents.tr(),
              detail: LocaleKeys.landing_noEventsDetail.tr(),
            )
          else
            for (final item in events)
              HomeAgendaRow(
                item: item,
                subtitle: _timeOf(item, formatTime),
                onOpen: () => onOpen(item),
              ),
          if (upcoming.isNotEmpty) ...[
            const SizedBox(height: WorkspaceTokens.space2),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: HomeEyebrow(label: LocaleKeys.landing_comingUp.tr()),
            ),
            for (final item in upcoming)
              HomeAgendaRow(
                item: item,
                subtitle: '${DateFormat.MMMEd().format(item.start)} · '
                    '${_timeOf(item, formatTime)}',
                onOpen: () => onOpen(item),
              ),
          ],
        ],
      ),
    );
  }
}

/// Reminders still waiting to be done: overdue first, then soonest.
class HomeRemindersCard extends StatelessWidget {
  const HomeRemindersCard({
    super.key,
    required this.reminders,
    required this.now,
    required this.formatTime,
    required this.onOpen,
    required this.onComplete,
    this.onAdd,
    this.limit = 6,
  });

  final List<HomeAgendaItem> reminders;
  final DateTime now;
  final String Function(DateTime time) formatTime;
  final ValueChanged<HomeAgendaItem> onOpen;
  final ValueChanged<HomeAgendaItem> onComplete;
  final VoidCallback? onAdd;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final today = startOfDay(now);
    String when(HomeAgendaItem item) {
      if (item.start.isBefore(today)) {
        return '${LocaleKeys.landing_overdue.tr()} · '
            '${DateFormat.MMMd().format(item.start)}';
      }
      final time =
          item.allDay ? LocaleKeys.landing_allDay.tr() : formatTime(item.start);
      return isSameDay(item.start, today)
          ? '${LocaleKeys.landing_today.tr()} · $time'
          : '${DateFormat.MMMEd().format(item.start)} · $time';
    }

    final shown = reminders.take(limit).toList();
    return HomeRailCard(
      key: const ValueKey('home-reminders'),
      title: LocaleKeys.landing_reminders.tr(),
      icon: Icons.notifications_active_rounded,
      trailing: onAdd == null
          ? null
          : Tooltip(
              message: LocaleKeys.landing_addReminderTooltip.tr(),
              child: TextButton.icon(
                key: const ValueKey('home-reminders-add'),
                onPressed: onAdd,
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: const StadiumBorder(),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(LocaleKeys.landing_addReminder.tr()),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shown.isEmpty)
            _RailEmpty(
              key: const ValueKey('home-reminders-empty'),
              title: LocaleKeys.landing_noReminders.tr(),
              detail: LocaleKeys.landing_noRemindersDetail.tr(),
            )
          else
            for (final item in shown)
              HomeAgendaRow(
                item: item,
                subtitle: when(item),
                overdue: item.start.isBefore(today),
                onOpen: () => onOpen(item),
                onComplete: () => onComplete(item),
              ),
          if (reminders.length > shown.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Text(
                LocaleKeys.landing_moreReminders
                    .tr(args: ['${reminders.length - shown.length}']),
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
