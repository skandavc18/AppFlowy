import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_style.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A quiet word about how the connected calendars are getting on.
///
/// It says nothing at all while everything is fine and nothing is connected —
/// a sync indicator that is always visible is just clutter.
class CalendarSyncIndicator extends StatelessWidget {
  const CalendarSyncIndicator({
    super.key,
    required this.workspace,
    this.onReconnect,
  });

  final CalendarWorkspace workspace;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    if (workspace.remoteProviders.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = calendarPaletteOf(context);
    final status = workspace.status;

    if (status.state == CalendarSyncState.synced && status.pendingWrites == 0) {
      // Settled and nothing owing: a dot is enough.
      return Tooltip(
        message: LocaleKeys.calendarView_sync_synced.tr(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: CalendarColorDot(
            color: palette.textMuted.withValues(alpha: 0.5),
            size: 6,
          ),
        ),
      );
    }

    final (icon, label, tint) = switch (status.state) {
      CalendarSyncState.syncing => (
          Icons.sync_rounded,
          LocaleKeys.calendarView_sync_syncing.tr(),
          palette.textSecondary,
        ),
      CalendarSyncState.offline => (
          Icons.cloud_off_rounded,
          LocaleKeys.calendarView_sync_offline.tr(),
          palette.textMuted,
        ),
      CalendarSyncState.expired => (
          Icons.lock_clock_rounded,
          LocaleKeys.calendarView_sync_expired.tr(),
          const Color(0xFFD97706),
        ),
      CalendarSyncState.failed => (
          Icons.error_outline_rounded,
          LocaleKeys.calendarView_sync_failed.tr(),
          const Color(0xFFDC2626),
        ),
      _ => (
          Icons.cloud_done_rounded,
          LocaleKeys.calendarView_sync_synced.tr(),
          palette.textMuted,
        ),
    };

    final pending = status.pendingWrites;
    final tooltip = pending > 0
        ? '$label · ${LocaleKeys.calendarView_sync_pending.plural(
            pending,
            args: [
              '$pending',
            ],
          )}'
        : label;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: status.state == CalendarSyncState.expired
            ? onReconnect
            : () => workspace.refresh(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: CalendarMetrics.controlSize - 6,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(CalendarMetrics.controlRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SpinningWhenBusy(
                busy: status.state == CalendarSyncState.syncing,
                child: Icon(icon, size: 13, color: tint),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1,
                  color: tint,
                  fontVariations: const [FontVariation.weight(590)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpinningWhenBusy extends StatefulWidget {
  const _SpinningWhenBusy({required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  State<_SpinningWhenBusy> createState() => _SpinningWhenBusyState();
}

class _SpinningWhenBusyState extends State<_SpinningWhenBusy>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.busy) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_SpinningWhenBusy old) {
    super.didUpdateWidget(old);
    if (widget.busy && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.busy && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.busy
      ? RotationTransition(turns: _controller, child: widget.child)
      : widget.child;
}

/// Which calendars are shown, and what kinds of thing.
class CalendarFilterButton extends StatelessWidget {
  const CalendarFilterButton({super.key, required this.workspace});

  final CalendarWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    final active = workspace.filter.isActive;
    return Builder(
      builder: (context) => CalendarControlButton(
        icon: Icons.tune_rounded,
        tooltip: LocaleKeys.calendarView_filter.tr(),
        active: active,
        onPressed: () => _open(context),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final filter = workspace.filter;
    final calendars = workspace.calendars;

    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.calendarView_filter.tr()),
        AppMenuItem(
          label: LocaleKeys.calendarView_filters_events.tr(),
          icon: Icons.event_rounded,
          selected: filter.showEvents,
          onSelected: () => workspace.setFilter(
            filter.copyWith(showEvents: !filter.showEvents),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.calendarView_filters_reminders.tr(),
          icon: Icons.notifications_rounded,
          selected: filter.showReminders,
          onSelected: () => workspace.setFilter(
            filter.copyWith(showReminders: !filter.showReminders),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.calendarView_filters_completed.tr(),
          icon: Icons.check_circle_rounded,
          selected: filter.showCompleted,
          onSelected: () => workspace.setFilter(
            filter.copyWith(showCompleted: !filter.showCompleted),
          ),
        ),
        if (calendars.length > 1) ...[
          const AppMenuSeparator(),
          AppMenuHeader(LocaleKeys.calendarView_calendars.tr()),
          for (final calendar in calendars)
            AppMenuItem(
              label: calendar.name,
              iconWidget: CalendarColorDot(color: calendar.color),
              selected: calendar.isVisible,
              onSelected: () => workspace.setCalendarVisible(
                calendar.id,
                !calendar.isVisible,
              ),
            ),
        ],
        if (filter.isActive) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.calendarView_filters_reset.tr(),
            icon: Icons.restart_alt_rounded,
            onSelected: () => workspace.setFilter(const CalendarFilter()),
          ),
        ],
      ],
    );
  }
}
