import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/database/card/card.dart';
import 'package:appflowy/mobile/presentation/presentation.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_bloc.dart';
import 'package:appflowy/plugins/database/calendar/application/unschedule_event_bloc.dart';
import 'package:appflowy/plugins/database/grid/presentation/grid_page.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/setting_menu.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../application/row/row_controller.dart';
import '../../widgets/row/row_detail.dart';
import 'calendar_stage.dart';
import 'toolbar/calendar_setting_bar.dart';

class CalendarPageTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  final _toggleExtension = ToggleExtensionNotifier();

  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) {
    return CalendarPage(
      key: _makeValueKey(controller),
      view: view,
      databaseController: controller,
      shrinkWrap: shrinkWrap,
    );
  }

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) {
    return CalendarSettingBar(
      key: _makeValueKey(controller),
      databaseController: controller,
      toggleExtension: _toggleExtension,
    );
  }

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) {
    return DatabaseViewSettingExtension(
      key: _makeValueKey(controller),
      viewId: controller.viewId,
      databaseController: controller,
      toggleExtension: _toggleExtension,
    );
  }

  @override
  void dispose() {
    _toggleExtension.dispose();
    super.dispose();
  }

  ValueKey _makeValueKey(DatabaseController controller) {
    return ValueKey(controller.viewId);
  }
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.view,
    required this.databaseController,
    this.shrinkWrap = false,
  });

  final ViewPB view;
  final DatabaseController databaseController;
  final bool shrinkWrap;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final _eventController = EventController<CalendarDayEvent>();
  late final CalendarBloc _calendarBloc;

  @override
  void initState() {
    super.initState();
    _calendarBloc = CalendarBloc(
      databaseController: widget.databaseController,
    )..add(const CalendarEvent.initial());
  }

  @override
  void dispose() {
    _calendarBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CalendarControllerProvider(
      controller: _eventController,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(
            value: _calendarBloc,
          ),
          BlocProvider(
            create: (context) => PageAccessLevelBloc(view: widget.view)
              ..add(
                PageAccessLevelEvent.initial(),
              ),
          ),
        ],
        child: MultiBlocListener(
          listeners: [
            BlocListener<CalendarBloc, CalendarState>(
              listenWhen: (p, c) => p.initialEvents != c.initialEvents,
              listener: (context, state) {
                _eventController.removeWhere((_) => true);
                _eventController.addAll(state.initialEvents);
              },
            ),
            BlocListener<CalendarBloc, CalendarState>(
              listenWhen: (p, c) => p.deleteEventIds != c.deleteEventIds,
              listener: (context, state) {
                _eventController.removeWhere(
                  (element) =>
                      state.deleteEventIds.contains(element.event!.eventId),
                );
              },
            ),
            BlocListener<CalendarBloc, CalendarState>(
              // Event create by click the + button or double click on the
              // calendar
              listenWhen: (p, c) => p.newEvent != c.newEvent,
              listener: (context, state) {
                if (state.newEvent != null) {
                  _eventController.add(state.newEvent!);
                }
              },
            ),
            BlocListener<CalendarBloc, CalendarState>(
              // When an event is rescheduled
              listenWhen: (p, c) => p.updateEvent != c.updateEvent,
              listener: (context, state) {
                if (state.updateEvent != null) {
                  _eventController.removeWhere(
                    (element) =>
                        element.event!.eventId ==
                        state.updateEvent!.event!.eventId,
                  );
                  _eventController.add(state.updateEvent!);
                }
              },
            ),
            BlocListener<CalendarBloc, CalendarState>(
              listenWhen: (p, c) => p.openRow != c.openRow,
              listener: (context, state) {
                if (state.openRow != null) {
                  showEventDetails(
                    context: context,
                    databaseController: _calendarBloc.databaseController,
                    rowMeta: state.openRow!,
                  );
                }
              },
            ),
          ],
          child: BlocBuilder<CalendarBloc, CalendarState>(
            builder: (context, state) {
              return ValueListenableBuilder<bool>(
                valueListenable: widget.databaseController.isLoading,
                builder: (_, value, ___) {
                  if (value) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }
                  return _buildCalendar(
                    context,
                    _eventController,
                    state.settings?.firstDayOfWeek ?? 0,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar(
    BuildContext context,
    EventController eventController,
    int firstDayOfWeek,
  ) =>
      _buildStage(context, firstDayOfWeek);

  /// The modern calendar: month, week, day, agenda and year over the same
  /// table, plus reminders and any connected account.
  ///
  /// Mobile gets the same readings, only laid out for a narrow window.
  Widget _buildStage(BuildContext context, int firstDayOfWeek) {
    final compact = UniversalPlatform.isMobile;
    final settings = _calendarBloc.state.settings;
    final paddingLeft =
        context.read<DatabasePluginWidgetBuilderSize>().paddingLeft;
    final horizontalPadding =
        context.read<DatabasePluginWidgetBuilderSize>().horizontalPadding;
    return Padding(
      padding: EdgeInsets.only(
        left: paddingLeft + (horizontalPadding == 0 || compact ? 0 : 8),
        right: horizontalPadding == 0 || compact ? 0 : 8,
      ),
      child: CalendarStage(
        view: widget.view,
        databaseController: widget.databaseController,
        firstDayOfWeek: firstDayOfWeek,
        showWeekends: settings?.showWeekends ?? true,
        showWeekNumbers: settings?.showWeekNumbers ?? false,
        compact: compact,
        onOpenRow: (rowId) {
          final rowMeta =
              widget.databaseController.rowCache.getRow(rowId)?.rowMeta;
          if (rowMeta == null) {
            return;
          }
          if (compact) {
            context.push(
              MobileRowDetailPage.routeName,
              extra: {
                MobileRowDetailPage.argRowId: rowId,
                MobileRowDetailPage.argDatabaseController:
                    widget.databaseController,
              },
            );
            return;
          }
          showEventDetails(
            context: context,
            databaseController: widget.databaseController,
            rowMeta: rowMeta,
          );
        },
        onDuplicateRow: (rowId) => _calendarBloc.add(
          CalendarEvent.duplicateEvent(widget.databaseController.viewId, rowId),
        ),
        onDeleteRow: (rowId) => _calendarBloc.add(
          CalendarEvent.deleteEvent(widget.databaseController.viewId, rowId),
        ),
        toolbarTrailing: compact
            ? null
            : UnscheduledEventsButton(
                databaseController: widget.databaseController,
              ),
      ),
    );
  }
}

void showEventDetails({
  required BuildContext context,
  required DatabaseController databaseController,
  required RowMetaPB rowMeta,
}) {
  final rowController = RowController(
    rowMeta: rowMeta,
    viewId: databaseController.viewId,
    rowCache: databaseController.rowCache,
  );

  FlowyOverlay.show(
    context: context,
    builder: (BuildContext overlayContext) {
      return BlocProvider.value(
        value: context.read<UserWorkspaceBloc>(),
        child: RowDetailPage(
          rowController: rowController,
          databaseController: databaseController,
          userProfile: context.read<CalendarBloc>().userProfile,
        ),
      );
    },
  );
}

class UnscheduledEventsButton extends StatefulWidget {
  const UnscheduledEventsButton({super.key, required this.databaseController});

  final DatabaseController databaseController;

  @override
  State<UnscheduledEventsButton> createState() =>
      _UnscheduledEventsButtonState();
}

class _UnscheduledEventsButtonState extends State<UnscheduledEventsButton> {
  final PopoverController _popoverController = PopoverController();

  @override
  Widget build(BuildContext context) {
    return BlocProvider<UnscheduleEventsBloc>(
      create: (_) =>
          UnscheduleEventsBloc(databaseController: widget.databaseController)
            ..add(const UnscheduleEventsEvent.initial()),
      child: BlocBuilder<UnscheduleEventsBloc, UnscheduleEventsState>(
        builder: (context, state) {
          return AppFlowyPopover(
            direction: PopoverDirection.bottomWithCenterAligned,
            triggerActions: PopoverTriggerFlags.none,
            controller: _popoverController,
            offset: const Offset(0, 8),
            constraints: const BoxConstraints(maxWidth: 282, maxHeight: 600),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Theme.of(context).dividerColor),
                  borderRadius: Corners.s6Border,
                ),
                side: BorderSide(color: Theme.of(context).dividerColor),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              onPressed: () {
                if (state.unscheduleEvents.isNotEmpty) {
                  if (UniversalPlatform.isMobile) {
                    _showUnscheduledEventsMobile(state.unscheduleEvents);
                  } else {
                    _popoverController.show();
                  }
                }
              },
              child: FlowyTooltip(
                message: LocaleKeys.calendar_settings_noDateHint.plural(
                  state.unscheduleEvents.length,
                  namedArgs: {'count': '${state.unscheduleEvents.length}'},
                ),
                child: FlowyText.regular(
                  "${LocaleKeys.calendar_settings_noDateTitle.tr()} (${state.unscheduleEvents.length})",
                  fontSize: 10,
                ),
              ),
            ),
            popupBuilder: (_) => MultiBlocProvider(
              providers: [
                BlocProvider.value(
                  value: context.read<CalendarBloc>(),
                ),
                BlocProvider.value(
                  value: context.read<UserWorkspaceBloc>(),
                ),
              ],
              child: UnscheduleEventsList(
                databaseController: widget.databaseController,
                unscheduleEvents: state.unscheduleEvents,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showUnscheduledEventsMobile(List<CalendarEventPB> events) =>
      showMobileBottomSheet(
        context,
        builder: (_) {
          return Column(
            children: [
              FlowyText(
                LocaleKeys.calendar_settings_unscheduledEventsTitle.tr(),
              ),
              UnscheduleEventsList(
                databaseController: widget.databaseController,
                unscheduleEvents: events,
              ),
            ],
          );
        },
      );
}

class UnscheduleEventsList extends StatelessWidget {
  const UnscheduleEventsList({
    super.key,
    required this.unscheduleEvents,
    required this.databaseController,
  });

  final List<CalendarEventPB> unscheduleEvents;
  final DatabaseController databaseController;

  @override
  Widget build(BuildContext context) {
    final cells = [
      if (!UniversalPlatform.isMobile)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: FlowyText(
            LocaleKeys.calendar_settings_clickToAdd.tr(),
            fontSize: 10,
            color: Theme.of(context).hintColor,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ...unscheduleEvents.map(
        (event) => UnscheduledEventCell(
          event: event,
          onPressed: () {
            if (UniversalPlatform.isMobile) {
              context.push(
                MobileRowDetailPage.routeName,
                extra: {
                  MobileRowDetailPage.argRowId: event.rowMeta.id,
                  MobileRowDetailPage.argDatabaseController: databaseController,
                },
              );
              context.pop();
            } else {
              showEventDetails(
                context: context,
                rowMeta: event.rowMeta,
                databaseController: databaseController,
              );
              PopoverContainer.of(context).close();
            }
          },
        ),
      ),
    ];

    final child = ListView.separated(
      itemBuilder: (context, index) => cells[index],
      itemCount: cells.length,
      separatorBuilder: (context, index) =>
          VSpace(GridSize.typeOptionSeparatorHeight),
      shrinkWrap: true,
    );

    if (UniversalPlatform.isMobile) {
      return Flexible(child: child);
    }

    return child;
  }
}

class UnscheduledEventCell extends StatelessWidget {
  const UnscheduledEventCell({
    super.key,
    required this.event,
    required this.onPressed,
  });

  final CalendarEventPB event;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return UniversalPlatform.isMobile
        ? MobileUnscheduledEventTile(event: event, onPressed: onPressed)
        : DesktopUnscheduledEventTile(event: event, onPressed: onPressed);
  }
}

class DesktopUnscheduledEventTile extends StatelessWidget {
  const DesktopUnscheduledEventTile({
    super.key,
    required this.event,
    required this.onPressed,
  });

  final CalendarEventPB event;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: FlowyButton(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        text: FlowyText(
          event.title.isEmpty
              ? LocaleKeys.calendar_defaultNewCalendarTitle.tr()
              : event.title,
          fontSize: 11,
        ),
        onTap: onPressed,
      ),
    );
  }
}

class MobileUnscheduledEventTile extends StatelessWidget {
  const MobileUnscheduledEventTile({
    super.key,
    required this.event,
    required this.onPressed,
  });

  final CalendarEventPB event;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MobileSettingItem(
      name: event.title.isEmpty
          ? LocaleKeys.calendar_defaultNewCalendarTitle.tr()
          : event.title,
      onTap: onPressed,
    );
  }
}
