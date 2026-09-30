import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/blank/home/home_agenda.dart';
import 'package:appflowy/plugins/blank/home/home_customize.dart';
import 'package:appflowy/plugins/blank/home/home_hero.dart';
import 'package:appflowy/plugins/blank/home/home_arrangement.dart';
import 'package:appflowy/plugins/blank/home/home_rail.dart';
import 'package:appflowy/plugins/blank/home/home_search.dart';
import 'package:appflowy/plugins/blank/home/home_sections.dart';
import 'package:appflowy/plugins/blank/home/home_weather.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_add_menu.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_panel.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_place_picker.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_details.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/date_time/time_format_ext.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/local_page_store.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_query.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart'
    show ConfirmPopupStyle;
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/local_page_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_card.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_labels.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB, UserWorkspacePB;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Everything Home reads. Hosts and tests can replace any source; Home owns
/// (and disposes) whatever a factory returns.
@immutable
class WorkspaceHomeServices {
  const WorkspaceHomeServices({
    this.recents,
    this.favorites,
    this.agenda,
    this.locations,
    this.previews,
    this.weather,
    this.arrangement,
    this.pages,
    this.now,
    this.onSearch,
    this.onOpenView,
  });

  final ViewGallerySource Function()? recents;
  final ViewGallerySource Function()? favorites;
  final HomeAgendaSource Function()? agenda;
  final ViewGalleryLocations Function()? locations;
  final FolderGalleryPreviewCache Function()? previews;
  final HomeWeatherSource Function()? weather;

  /// Where Home keeps how it is arranged.
  final HomeArrangementStore Function()? arrangement;

  /// Where Home keeps its cover height; shared, so never disposed by Home.
  final LocalPageStore? pages;
  final DateTime Function()? now;
  final void Function(String initialQuery, bool contents)? onSearch;
  final ValueChanged<ViewPB>? onOpenView;
}

/// Supplies [WorkspaceHomeServices] to a Home built by the shell's plugin.
class WorkspaceHomeScope extends InheritedWidget {
  const WorkspaceHomeScope({
    super.key,
    required this.services,
    required super.child,
  });

  final WorkspaceHomeServices services;

  static WorkspaceHomeServices? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WorkspaceHomeScope>()?.services;

  @override
  bool updateShouldNotify(WorkspaceHomeScope oldWidget) =>
      services != oldWidget.services;
}

enum _JumpTab { recent, favorites }

/// Home: a landing page to pick work back up. The workspace cover with the
/// search bar laid across its edge; the pages worked on lately; and a side
/// rail with the time, the weather, the page to resume, a calendar, the
/// day's events and the reminders still waiting.
///
/// Every part can be moved, taken off and put back, and widgets from the
/// dashboard library can be added beside them. How Home is arranged is kept
/// on this device, for each workspace.
///
/// Building it never creates a page or a tab; the only writes are the
/// explicit actions somebody takes here.
class WorkspaceHomePage extends StatefulWidget {
  const WorkspaceHomePage({
    super.key,
    this.workspace,
    this.userName,
    this.onNavigate,
    this.onSearch,
    this.onOpenView,
    this.services,
  });

  /// Optional snapshots/callbacks for isolated hosts; otherwise the shell's.
  final UserWorkspacePB? workspace;
  final String? userName;
  final ValueChanged<TabsEvent>? onNavigate;
  final void Function(String initialQuery, bool contents)? onSearch;
  final ValueChanged<ViewPB>? onOpenView;
  final WorkspaceHomeServices? services;

  @override
  State<WorkspaceHomePage> createState() => _WorkspaceHomePageState();
}

class _WorkspaceHomePageState extends State<WorkspaceHomePage> {
  // Remembered for the session, like a scroll position, never persisted.
  static _JumpTab _jumpTab = _JumpTab.recent;
  static ViewGalleryLayout _jumpLayout = ViewGalleryLayout.gallery;

  late ViewGallerySource _recents;
  late ViewGallerySource _favorites;
  late HomeAgendaSource _agenda;
  late ViewGalleryLocations _locations;
  late FolderGalleryPreviewCache _previews;
  late HomeWeatherSource _weather;
  late LocalPageStore _pages;
  late HomeArrangementStore _arrangements;

  /// The dashboard widgets on Home, edited exactly as on a dashboard. It has
  /// no view, so it never writes anywhere itself: the layout store keeps it.
  late DashboardController _widgets;
  bool _customizing = false;

  /// The height a widget had when its grip was picked up.
  int? _resizeFrom;
  late DateTime Function() _clock;
  late DateTime _now;
  late DateTime _month;

  /// The day the events card shows; null follows today.
  DateTime? _selectedDay;
  WorkspaceHomeServices _services = const WorkspaceHomeServices();
  bool _bound = false;
  String? _workspaceId;
  Timer? _tick;

  bool _hasCoverOverride = false;
  String? _coverOverrideId;
  String? _coverOverrideStored;
  PageStyleCover? _coverOverride;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workspaceId = widget.workspace?.workspaceId ??
        context.read<UserWorkspaceBloc?>()?.state.currentWorkspace?.workspaceId;
    final previousWorkspaceId = _workspaceId;
    _workspaceId = workspaceId ?? previousWorkspaceId;
    if (_bound) {
      // Each workspace keeps its own arrangement, including the first time
      // the workspace becomes known after Home was already built.
      if (workspaceId != null && workspaceId != previousWorkspaceId) {
        unawaited(_arrangements.load(workspaceId));
      }
      // Another workspace has other pages; the landing page follows it.
      if (previousWorkspaceId != null &&
          workspaceId != null &&
          workspaceId != previousWorkspaceId) {
        _previews.clear();
        unawaited(_recents.load());
        unawaited(_favorites.load());
      }
      return;
    }
    _bound = true;
    final services = widget.services ??
        WorkspaceHomeScope.maybeOf(context) ??
        const WorkspaceHomeServices();
    _services = services;
    _clock = services.now ?? DateTime.now;
    _now = _clock();
    _recents = services.recents?.call() ?? RecentViewGallerySource();
    _favorites = services.favorites?.call() ?? FavoriteViewGallerySource();
    _agenda = services.agenda?.call() ?? HomeAgendaSource();
    _locations = services.locations?.call() ?? ViewGalleryLocations();
    _previews = services.previews?.call() ?? FolderGalleryPreviewCache();
    _weather = services.weather?.call() ?? HomeWeatherSource();
    _pages = services.pages ?? LocalPageStore.instance;
    _arrangements = services.arrangement?.call() ?? HomeArrangementStore();
    _widgets = DashboardController(
      viewId: '',
      document: _arrangements.arrangement.widgets,
    );
    _arrangements.addListener(_onArrangementChanged);
    _widgets.addListener(_onWidgetsChanged);
    unawaited(_arrangements.load(_workspaceId));
    for (final source in [_recents, _favorites]) {
      unawaited(source.load());
      source.addListener(_onPagesChanged);
    }
    _month = DateTime(_now.year, _now.month);
    _agenda.start(_now);
    _agenda.showMonth(_month, _now);
    _agenda.addListener(_onChanged);
    _locations.addListener(_onChanged);
    _weather.addListener(_onChanged);
    unawaited(_weather.start());
    // Minute-accurate without waking every second.
    _tick = Timer.periodic(const Duration(seconds: 15), (_) => _onTick());
  }

  void _onTick() {
    if (!mounted) return;
    final now = _clock();
    if (now.minute != _now.minute || now.day != _now.day) {
      final newDay = now.day != _now.day;
      setState(() => _now = now);
      // The coming days move on with the date.
      if (newDay) _agenda.showMonth(_month, now);
    }
  }

  void _onPagesChanged() {
    if (!mounted) return;
    _locations.request([..._recents.entries, ..._favorites.entries]);
    setState(() {});
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onArrangementChanged() {
    if (!mounted) return;
    final widgets = _arrangements.arrangement.widgets;
    if (_widgets.document != widgets) {
      _widgets.replace(widgets, remember: false);
    }
    setState(() {});
  }

  void _onWidgetsChanged() {
    if (!mounted) return;
    final layout = _arrangements.arrangement;
    if (layout.widgets != _widgets.document) {
      _arrangements.update(layout.withWidgets(_widgets.document));
    }
    setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    _arrangements.removeListener(_onArrangementChanged);
    _widgets.removeListener(_onWidgetsChanged);
    _widgets.dispose();
    _arrangements.dispose();
    for (final source in [_recents, _favorites]) {
      source.removeListener(_onPagesChanged);
      source.dispose();
    }
    _agenda.removeListener(_onChanged);
    _agenda.dispose();
    _locations.removeListener(_onChanged);
    _locations.dispose();
    _weather.removeListener(_onChanged);
    _weather.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ navigation

  ValueChanged<TabsEvent>? _navigation() {
    if (widget.onNavigate != null) return widget.onNavigate;
    final tabs = context.read<TabsBloc?>();
    return tabs == null || tabs.isClosed ? null : tabs.add;
  }

  void _open(ViewPB view) {
    final open = widget.onOpenView ?? _services.onOpenView;
    if (open != null) {
      open(view);
    } else {
      view.navigateTo();
    }
  }

  void _openInNewTab(ViewPB view) =>
      _navigation()?.call(TabsEvent.openTab(plugin: view.plugin(), view: view));

  bool _canOpenLibrary(PluginType type) =>
      getIt.isRegistered<PluginSandbox>() &&
      getIt<PluginSandbox>().supportPluginTypes.contains(type);

  void _openLibrary(PluginType type) {
    final navigate = _navigation();
    if (navigate == null || !_canOpenLibrary(type)) return;
    if (getIt.isRegistered<MenuSharedState>()) {
      getIt<MenuSharedState>().latestOpenView = null;
    }
    navigate(
      TabsEvent.openPlugin(
        plugin: makePlugin(pluginType: type),
        setLatest: false,
      ),
    );
  }

  void Function(GlobalKey, String, bool)? _searchHandler(BuildContext context) {
    final injected = widget.onSearch ?? _services.onSearch;
    if (injected != null) {
      return (_, query, contents) => injected(query, contents);
    }
    if (canShowHomeSearch(context)) {
      return (anchor, query, contents) => unawaited(
            showHomeSearch(
              context,
              anchorKey: anchor,
              initialQuery: query,
              contents: contents,
            ),
          );
    }
    final palette = CommandPalette.maybeOf(context);
    if (palette == null) return null;
    return (_, __, ___) => palette.toggle(
          workspaceBloc: context.read<UserWorkspaceBloc?>(),
          spaceBloc: context.read<SpaceBloc?>(),
        );
  }

  // --------------------------------------------------------------- agenda

  void _openAgendaItem(HomeAgendaItem item) {
    final reminder = item.reminder;
    if (reminder != null) {
      final attached = reminder.pageId.isNotEmpty ||
          reminder.objectId.isNotEmpty ||
          reminder.rowId.isNotEmpty;
      if (attached) {
        unawaited(_agenda.store.open(reminder));
      } else {
        unawaited(
          showCalendarEventDetails(context, event: reminder.toCalendarEvent()),
        );
      }
      return;
    }
    final event = item.event;
    if (event == null) return;
    if (event.url.isNotEmpty) {
      unawaited(afLaunchUrlString(event.url, context: context));
    } else {
      unawaited(showCalendarEventDetails(context, event: event));
    }
  }

  void _complete(HomeAgendaItem item) {
    final reminder = item.reminder;
    if (reminder != null) unawaited(_agenda.store.complete(reminder));
  }

  Future<void> _addReminder() async {
    final now = _clock();
    await showReminderComposer(
      context,
      initialWhen: DateTime(now.year, now.month, now.day, now.hour + 1),
    );
    if (mounted) await _agenda.refresh();
  }

  void _showMonth(DateTime month) {
    setState(() => _month = DateTime(month.year, month.month));
    _agenda.showMonth(_month, _clock());
  }

  void _showToday() {
    _selectedDay = null;
    _showMonth(_now);
  }

  // --------------------------------------------------------------- weather

  Future<void> _chooseWeatherPlace() async {
    final place = await showDashboardPlacePicker(
      context: context,
      palette: DashboardPalette.of(context),
      initialQuery: _weather.place?.name ?? '',
    );
    if (place == null || !mounted) return;
    await _weather.setPlace(
      HomeWeatherPlace(
        name: place.name,
        latitude: place.latitude,
        longitude: place.longitude,
      ),
    );
  }

  // --------------------------------------------------------------- pages

  List<ViewGalleryEntry> _entriesOf(ViewGallerySource source) =>
      viewGalleryEntriesWithRoot(
        source.entries,
        widget.workspace ??
            context.read<UserWorkspaceBloc?>()?.state.currentWorkspace,
      );

  Future<FolderGalleryPreview> _previewOf(ViewPB view) => _previews.previewFor(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
      );

  ViewGalleryFacts _facts(ViewLibrary library) => ViewGalleryFacts(
        library: library,
        now: _now,
        locationOf: _locations.nameOf,
      );

  Future<void> _showEntryMenu(
    ViewGalleryEntry entry,
    ViewGallerySource source,
    Offset position,
  ) async {
    final recents = source is RecentViewGallerySource;
    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: LocaleKeys.viewLibrary_open.tr(),
          icon: Icons.open_in_new_rounded,
          onSelected: () => _open(entry.view),
        ),
        if (_navigation() != null)
          AppMenuItem(
            label: LocaleKeys.viewLibrary_openInNewTab.tr(),
            icon: Icons.tab_rounded,
            onSelected: () => _openInNewTab(entry.view),
          ),
        const AppMenuSeparator(),
        if (source is FavoriteViewGallerySource)
          AppMenuItem(
            label: entry.pinned
                ? LocaleKeys.viewLibrary_unpin.tr()
                : LocaleKeys.viewLibrary_pin.tr(),
            icon: Icons.push_pin_rounded,
            onSelected: () => unawaited(source.setPinned(entry, !entry.pinned)),
          ),
        AppMenuItem(
          label: recents
              ? LocaleKeys.viewLibrary_removeFromRecents.tr()
              : LocaleKeys.viewLibrary_removeFromFavorites.tr(),
          icon: recents
              ? Icons.remove_circle_outline_rounded
              : Icons.star_border_rounded,
          onSelected: () => unawaited(source.forget(entry)),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- build

  String Function(DateTime) _timeFormatter(BuildContext context) {
    final format = context.watch<AppearanceSettingsCubit?>()?.state.timeFormat;
    return format == null ? DateFormat.jm().format : format.formatTime;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UserWorkspaceBloc?>()?.state;
    final workspace = widget.workspace ?? state?.currentWorkspace;
    final userProfile = state?.userProfile;
    final formatTime = _timeFormatter(context);
    final configuring = _widgets.configuringWidgetId;
    final configured =
        configuring == null ? null : _widgets.document.widgetById(configuring);
    return SizedBox.expand(
      child: WorkspaceSurface(
        kind: WorkspaceSurfaceKind.canvas,
        radius: 0,
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final inset = width < 360
                      ? WorkspaceTokens.space4
                      : WorkspaceTokens.pageInset(width);
                  return SingleChildScrollView(
                    key: const ValueKey('home-scroll'),
                    primary: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHero(
                          context,
                          workspace: workspace,
                          userProfile: userProfile,
                          inset: inset,
                        ),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1280),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                inset,
                                WorkspaceTokens.space6,
                                inset,
                                WorkspaceTokens.space12,
                              ),
                              child: _buildBody(
                                context,
                                userProfile: userProfile,
                                formatTime: formatTime,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // A widget's settings float over Home, as they do over a
            // dashboard, rather than pushing the columns about.
            if (configured != null)
              Positioned(
                top: 0,
                right: 0,
                bottom: 0,
                child: DashboardEditingScope(
                  controller: _widgets,
                  child: DashboardConfigPanel(
                    key: ValueKey('home-widget-settings-${configured.id}'),
                    controller: _widgets,
                    palette: DashboardPalette.of(context),
                    spec: configured,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  PageStyleCover? _coverOf(UserWorkspacePB? workspace) {
    if (workspace == null || workspace.workspaceId.trim().isEmpty) return null;
    // A just-chosen cover shows at once; the stored one wins once it changes.
    if (_hasCoverOverride &&
        _coverOverrideId == workspace.workspaceId &&
        _coverOverrideStored == workspace.cover) {
      return _coverOverride;
    }
    final stored = WorkspaceCoverCodec.decode(workspace.cover);
    if (stored == null && workspace.cover.trim().isEmpty) {
      return AutomaticViewCover.forWorkspace(name: workspace.name);
    }
    return stored;
  }

  /// The workspace cover with the search bar across its lower edge, and the
  /// quick jumps under it. The cover's height is kept on this device.
  Widget _buildHero(
    BuildContext context, {
    required UserWorkspacePB? workspace,
    required UserProfilePB? userProfile,
    required double inset,
  }) {
    final cover = _coverOf(workspace);
    final recents = _entriesOf(_recents);
    final favorites = _entriesOf(_favorites);
    final quick =
        (favorites.isNotEmpty ? favorites : recents.skip(1)).take(6).toList();

    Widget hero(Widget? iconActions, Widget? coverActions, Widget? _) =>
        LocalPageBuilder(
          pageId: localPageId('home', workspace?.workspaceId),
          store: _pages,
          builder: (context, page) => HomeHero(
            key: const ValueKey('home-header'),
            inset: inset,
            cover: cover != null && !cover.isNone
                ? ViewCoverImage(
                    cover: cover,
                    userProfile: userProfile,
                    width: double.infinity,
                  )
                : null,
            coverActions: coverActions,
            addCover: iconActions,
            coverView: page.view,
            coverBackend: page.heights,
            search: HomeSearchBar(onSearch: _searchHandler(context)),
            below: quick.isEmpty
                ? null
                : HomeQuickJump(
                    entries: quick,
                    alignment: WrapAlignment.center,
                    onOpen: (entry) => _open(entry.view),
                  ),
          ),
        );

    final canDecorate = workspace != null &&
        workspace.workspaceId.trim().isNotEmpty &&
        context.read<UserWorkspaceBloc?>() != null;
    if (!canDecorate) return hero(null, null, null);
    return WorkspaceCoverActions(
      workspace: workspace,
      userProfile: userProfile,
      generateDefaultWhenMissing: true,
      visible: false,
      layoutBuilder: hero,
      onCoverChanged: (cover) => setState(() {
        _hasCoverOverride = true;
        _coverOverrideId = workspace.workspaceId;
        _coverOverrideStored = workspace.cover;
        _coverOverride = cover;
      }),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required UserProfilePB? userProfile,
    required String Function(DateTime) formatTime,
  }) {
    final recentFacts = _facts(ViewLibrary.recents);
    final recents = _entriesOf(_recents);
    final resume = recents.isEmpty ? null : recents.first;
    final today = startOfDay(_now);
    final selected = _selectedDay ?? today;
    final monthStart = DateTime(_month.year, _month.month);

    final glance = HomeGlanceCard(
      now: _now,
      formatTime: formatTime,
      weather: HomeWeatherTile(
        source: _weather,
        onChoosePlace: () => unawaited(_chooseWeatherPlace()),
      ),
      resume: HomeResumeCard(
        entry: resume,
        caption: resume == null ? '' : recentFacts.captionOf(resume),
        details: resume == null ? '' : recentFacts.detailsOf(resume),
        loadPreview: (entry) => _previewOf(entry.view),
        userProfile: userProfile,
        onOpen: () {
          if (resume != null) _open(resume.view);
        },
        onOpenInNewTab: resume == null || _navigation() == null
            ? null
            : () => _openInNewTab(resume.view),
      ),
    );
    final calendar = HomeCalendarCard(
      month: monthStart,
      today: today,
      selected: selected,
      eventDays: _agenda.eventDays(
        calendarDayOffset(monthStart, -7),
        calendarDayOffset(DateTime(_month.year, _month.month + 1), 14),
      ),
      reminderDays: _agenda.reminderDays(),
      onMonthChanged: _showMonth,
      onSelect: (day) => setState(
        () => _selectedDay = isSameDay(day, today) ? null : startOfDay(day),
      ),
    );
    final events = HomeEventsCard(
      day: selected,
      today: today,
      events: _agenda.eventsOn(selected),
      upcoming: isSameDay(selected, today)
          ? _agenda.eventsAfter(today)
          : const <HomeAgendaItem>[],
      formatTime: formatTime,
      onOpen: _openAgendaItem,
      onToday: _showToday,
    );
    final reminders = HomeRemindersCard(
      reminders: _agenda.outstandingReminders(),
      now: _now,
      formatTime: formatTime,
      onOpen: _openAgendaItem,
      onComplete: _complete,
      onAdd: () => unawaited(_addReminder()),
    );
    final jumpBackIn =
        _buildJumpBackIn(context, resume: resume, userProfile: userProfile);

    final layout = _arrangements.arrangement;
    final dashboardPalette = DashboardPalette.of(context);
    final parts = <HomeBlock, Widget>{
      HomeBlock.glance: glance,
      HomeBlock.jumpBackIn: jumpBackIn,
      HomeBlock.calendar: calendar,
      HomeBlock.events: events,
      HomeBlock.reminders: reminders,
    };
    Widget? blockFor(String id) {
      final part = HomeBlock.fromId(id);
      if (part != null) return parts[part];
      final spec = layout.widgetFor(id);
      // A hidden widget keeps its place, and shows only while arranging.
      if (spec == null || (spec.hidden && !_customizing)) return null;
      return HomeWidgetCard(
        controller: _widgets,
        spec: spec,
        palette: dashboardPalette,
      );
    }

    final bar = HomeCustomizeBar(
      customizing: _customizing,
      onCustomize: () => setState(() => _customizing = true),
      onDone: _finishCustomizing,
      onReset: () => unawaited(_confirmReset()),
      addEntries: _addEntries,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context);
        final wide = constraints.maxWidth >= scale.scale(940);
        final railWidth =
            (constraints.maxWidth * 0.3).clamp(300.0, 360.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bar,
            const SizedBox(height: WorkspaceTokens.space3),
            if (_customizing)
              _buildArranging(
                layout,
                blockFor,
                wide: wide,
                railWidth: railWidth,
              )
            else
              _buildArranged(
                layout,
                blockFor,
                wide: wide,
                railWidth: railWidth,
                pairs: constraints.maxWidth >= scale.scale(620),
              ),
          ],
        );
      },
    );
  }

  /// Home as it is used: the main column beside the rail when there is room
  /// for both, otherwise one column that keeps the rail's cards together.
  Widget _buildArranged(
    HomeArrangement layout,
    Widget? Function(String id) blockFor, {
    required bool wide,
    required double railWidth,
    required bool pairs,
  }) {
    List<(String, Widget)> blocks(List<String> ids) => [
          for (final id in ids)
            if (blockFor(id) case final block?)
              (id, KeyedSubtree(key: ValueKey('home-part-$id'), child: block)),
        ];
    Widget stack(List<Widget> children, double gap) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) SizedBox(height: gap),
              children[index],
            ],
          ],
        );
    final main = blocks(layout.main);
    final side = blocks(layout.side);

    if (wide) {
      final mainColumn = stack(
        [for (final (_, block) in main) block],
        WorkspaceTokens.space8,
      );
      final sideColumn = stack(
        [for (final (_, block) in side) block],
        WorkspaceTokens.space4,
      );
      if (side.isEmpty) return mainColumn;
      if (main.isEmpty) return sideColumn;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: mainColumn),
          const SizedBox(width: WorkspaceTokens.space8),
          SizedBox(
            key: const ValueKey('home-rail'),
            width: railWidth,
            child: sideColumn,
          ),
        ],
      );
    }

    // One column: the glance card still leads when it heads the rail, then
    // the main column, then the rest of the rail — two abreast when they fit.
    final leads = side.isNotEmpty && side.first.$1 == HomeBlock.glance.name;
    final rest = [for (final (_, block) in leads ? side.skip(1) : side) block];
    final rows = <Widget>[];
    if (pairs) {
      for (var index = 0; index < rest.length; index += 2) {
        rows.add(
          index + 1 < rest.length
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: rest[index]),
                    const SizedBox(width: WorkspaceTokens.space4),
                    Expanded(child: rest[index + 1]),
                  ],
                )
              : rest[index],
        );
      }
    } else {
      rows.addAll(rest);
    }
    return stack(
      [
        if (leads) side.first.$2,
        for (final (_, block) in main) block,
        if (rows.isNotEmpty) stack(rows, WorkspaceTokens.space4),
      ],
      WorkspaceTokens.space8,
    );
  }

  /// Home while it is being arranged: every block in a frame that can be
  /// dragged, and a place at the end of each column to drop onto.
  Widget _buildArranging(
    HomeArrangement layout,
    Widget? Function(String id) blockFor, {
    required bool wide,
    required double railWidth,
  }) {
    bool accepts(String dragged) => _arrangements.arrangement.contains(dragged);

    Widget column(HomeColumn column) {
      final ids = layout.blocksIn(column);
      return Column(
        key: ValueKey('home-column-${column.name}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < ids.length; index++) ...[
            _buildFrame(
              layout,
              ids[index],
              column,
              index,
              ids.length,
              blockFor(ids[index]),
            ),
            const SizedBox(height: WorkspaceTokens.space4),
          ],
          HomeDropSlot(
            key: ValueKey('home-drop-${column.name}'),
            empty: ids.isEmpty,
            canAccept: accepts,
            onAccept: (dragged) => _moveBlock(
              dragged,
              column,
              _arrangements.arrangement.blocksIn(column).length,
            ),
          ),
        ],
      );
    }

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: column(HomeColumn.main)),
          const SizedBox(width: WorkspaceTokens.space8),
          SizedBox(
            key: const ValueKey('home-rail'),
            width: railWidth,
            child: column(HomeColumn.side),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeColumnCaption(label: LocaleKeys.landing_mainColumn.tr()),
        column(HomeColumn.main),
        const SizedBox(height: WorkspaceTokens.space8),
        HomeColumnCaption(label: LocaleKeys.landing_sideColumn.tr()),
        column(HomeColumn.side),
      ],
    );
  }

  Widget _buildFrame(
    HomeArrangement layout,
    String id,
    HomeColumn column,
    int index,
    int count,
    Widget? block,
  ) {
    final spec = layout.widgetFor(id);
    return HomeBlockFrame(
      key: ValueKey('home-frame-$id'),
      id: id,
      label: _blockLabel(id, spec),
      icon: _blockIcon(id, spec),
      inSide: column == HomeColumn.side,
      hidden: spec?.hidden ?? false,
      canAccept: (dragged) => _arrangements.arrangement.contains(dragged),
      onDrop: (dragged, before) =>
          _moveBlock(dragged, column, before ? index : index + 1),
      onMoveUp: index == 0 ? null : () => _moveBlock(id, column, index - 1),
      onMoveDown:
          index == count - 1 ? null : () => _moveBlock(id, column, index + 2),
      onMoveAcross: () => _moveBlock(
        id,
        column.other,
        _arrangements.arrangement.blocksIn(column.other).length,
      ),
      onRemove: () =>
          _arrangements.update(_arrangements.arrangement.remove(id)),
      onConfigure: spec == null ? null : () => _widgets.configure(spec.id),
      onResize:
          spec == null ? null : (distance) => _resizeWidget(spec.id, distance),
      child: block ?? const SizedBox.shrink(),
    );
  }

  // ------------------------------------------------------------- arranging

  void _moveBlock(String id, HomeColumn column, int slot) =>
      _arrangements.update(_arrangements.arrangement.move(id, column, slot));

  void _finishCustomizing() {
    _widgets.closeSettings();
    setState(() => _customizing = false);
    unawaited(_arrangements.flush());
  }

  Future<void> _confirmReset() async {
    if (_arrangements.arrangement.widgets.widgetCount == 0) {
      _arrangements.reset();
      return;
    }
    await showConfirmDialog(
      context: context,
      title: LocaleKeys.landing_resetLayoutTitle.tr(),
      description: LocaleKeys.landing_resetLayoutBody.tr(),
      confirmLabel: LocaleKeys.landing_resetLayout.tr(),
      style: ConfirmPopupStyle.cancelAndOk,
      onConfirm: (_) {
        _widgets.closeSettings();
        _arrangements.reset();
      },
    );
  }

  List<AppMenuEntry> _addEntries() => [
        for (final part in _arrangements.arrangement.missingBlocks)
          AppMenuItem(
            label: _partLabel(part),
            icon: _partIcon(part),
            onSelected: () => _arrangements.update(
              _arrangements.arrangement.add(part.name, part.homeColumn),
            ),
          ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.landing_addWidget.tr(),
          icon: Icons.widgets_rounded,
          onSelected: () => unawaited(_addDashboardWidget()),
        ),
      ];

  Future<void> _addDashboardWidget() async {
    final definition = await showDashboardWidgetPicker(
      context: context,
      palette: DashboardPalette.of(context),
    );
    if (definition == null || !mounted) return;
    // A wide widget — a table, a chart — reads best in the main column.
    final column =
        definition.defaultColumnSpan >= 6 ? HomeColumn.main : HomeColumn.side;
    _arrangements.update(
      _arrangements.arrangement.addWidget(definition.create(), column),
    );
    if (!_customizing) setState(() => _customizing = true);
  }

  /// Follows a widget's grip: its height snaps to whole height units, the
  /// same units its settings and a dashboard use.
  void _resizeWidget(String specId, double? distance) {
    final spec = _widgets.document.widgetById(specId);
    if (spec == null || distance == null) {
      _resizeFrom = null;
      return;
    }
    final density = _widgets.document.settings.density;
    final from = _resizeFrom ??= spec.placement.rowSpan;
    final start = from * density.rowHeight + (from - 1) * density.gap;
    final minimum = math.max(
      1,
      DashboardWidgetRegistry.definitionFor(spec.type)?.minimumRowSpan ?? 1,
    );
    final rows =
        ((start + distance + density.gap) / (density.rowHeight + density.gap))
            .round()
            .clamp(minimum, 40);
    if (rows == spec.placement.rowSpan) return;
    _widgets.edit(
      (document) => document.withWidget(
        spec.copyWith(placement: spec.placement.copyWith(rowSpan: rows)),
      ),
      transient: true,
    );
  }

  String _partLabel(HomeBlock part) => switch (part) {
        HomeBlock.glance => LocaleKeys.landing_glance.tr(),
        HomeBlock.jumpBackIn => LocaleKeys.landing_jumpBackIn.tr(),
        HomeBlock.calendar => LocaleKeys.landing_calendar.tr(),
        HomeBlock.events => LocaleKeys.landing_events.tr(),
        HomeBlock.reminders => LocaleKeys.landing_reminders.tr(),
      };

  IconData _partIcon(HomeBlock part) => switch (part) {
        HomeBlock.glance => Icons.today_rounded,
        HomeBlock.jumpBackIn => Icons.history_rounded,
        HomeBlock.calendar => Icons.calendar_month_rounded,
        HomeBlock.events => Icons.event_rounded,
        HomeBlock.reminders => Icons.notifications_active_rounded,
      };

  String _blockLabel(String id, DashboardWidgetSpec? spec) {
    final part = HomeBlock.fromId(id);
    if (part != null) return _partLabel(part);
    if (spec == null) return '';
    final title = spec.title.trim();
    if (title.isNotEmpty) return title;
    return DashboardWidgetRegistry.definitionFor(spec.type)?.label() ??
        spec.type;
  }

  IconData _blockIcon(String id, DashboardWidgetSpec? spec) {
    final part = HomeBlock.fromId(id);
    if (part != null) return _partIcon(part);
    final definition =
        spec == null ? null : DashboardWidgetRegistry.definitionFor(spec.type);
    return definition?.icon ?? Icons.widgets_rounded;
  }

  Widget _buildJumpBackIn(
    BuildContext context, {
    required ViewGalleryEntry? resume,
    required UserProfilePB? userProfile,
  }) {
    final palette = WorkspacePalette.of(context);
    final recentsTab = _jumpTab == _JumpTab.recent;
    final source = recentsTab ? _recents : _favorites;
    final library = recentsTab ? ViewLibrary.recents : ViewLibrary.favorites;
    final facts = _facts(library);
    final entries = recentsTab
        ? _entriesOf(source).where((entry) => entry.id != resume?.id).toList()
        : _entriesOf(source);
    final pluginType = recentsTab ? PluginType.recents : PluginType.favorites;

    Widget tab(_JumpTab value, String label) {
      final selected = _jumpTab == value;
      return Semantics(
        selected: selected,
        child: TextButton(
          key: ValueKey('home-jump-${value.name}'),
          onPressed: () => setState(() => _jumpTab = value),
          style: TextButton.styleFrom(
            foregroundColor:
                selected ? palette.primaryText : palette.secondaryText,
            backgroundColor: selected ? palette.surface : Colors.transparent,
            minimumSize: const Size(0, 30),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: const StadiumBorder(),
            elevation: 0,
            textStyle: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.metadata,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
          child: Text(label),
        ),
      );
    }

    final tabs = DecoratedBox(
      decoration: BoxDecoration(
        color: palette.hover,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Wrap(
          children: [
            tab(_JumpTab.recent, LocaleKeys.landing_recentTab.tr()),
            tab(_JumpTab.favorites, LocaleKeys.landing_favoritesTab.tr()),
          ],
        ),
      ),
    );
    final gallery = _jumpLayout == ViewGalleryLayout.gallery;
    final tools = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        IconButton(
          key: const ValueKey('home-jump-layout'),
          tooltip: gallery
              ? LocaleKeys.landing_listView.tr()
              : LocaleKeys.landing_gridView.tr(),
          onPressed: () => setState(
            () => _jumpLayout =
                gallery ? ViewGalleryLayout.list : ViewGalleryLayout.gallery,
          ),
          icon: WorkspaceGlyph(
            gallery ? Icons.view_list_rounded : Icons.grid_view_rounded,
            color: palette.secondaryText,
          ),
        ),
        if (_canOpenLibrary(pluginType) && _navigation() != null)
          TextButton.icon(
            key: const ValueKey('home-jump-view-all'),
            onPressed: () => _openLibrary(pluginType),
            style: TextButton.styleFrom(
              foregroundColor: palette.secondaryText,
              shape: const StadiumBorder(),
            ),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(LocaleKeys.landing_viewAll.tr()),
          ),
      ],
    );
    final title = Text(
      LocaleKeys.landing_jumpBackIn.tr(),
      style: WorkspaceTypography.style(context, WorkspaceTextRole.section),
    );

    return Column(
      key: const ValueKey('home-jump-back-in'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth < MediaQuery.textScalerOf(context).scale(560)
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: WorkspaceTokens.space2),
                        Wrap(
                          spacing: WorkspaceTokens.space2,
                          runSpacing: WorkspaceTokens.space2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [tabs, tools],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Flexible(child: title),
                        const SizedBox(width: WorkspaceTokens.space4),
                        tabs,
                        const Spacer(),
                        tools,
                      ],
                    ),
        ),
        const SizedBox(height: WorkspaceTokens.space4),
        if (entries.isEmpty)
          Padding(
            key: const ValueKey('home-jump-empty'),
            padding:
                const EdgeInsets.symmetric(vertical: WorkspaceTokens.space4),
            child: Text(
              source.isLoading
                  ? LocaleKeys.viewLibrary_loading.tr()
                  : recentsTab
                      ? LocaleKeys.landing_noRecent.tr()
                      : LocaleKeys.landing_noFavorites.tr(),
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.body,
                color: palette.mutedText,
              ),
            ),
          )
        else if (!gallery)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in entries.take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: ViewGalleryListRow(
                    key: ValueKey('home-jump-row-${entry.id}'),
                    entry: entry,
                    caption: facts.captionOf(entry),
                    details: facts.detailsOf(entry),
                    onOpen: () => _open(entry.view),
                    onMenu: (position) =>
                        _showEntryMenu(entry, source, position),
                  ),
                ),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 18.0;
              final layout = galleryLayoutFor(
                available: constraints.maxWidth,
                target: GalleryCardScale.small.target,
              );
              final growth =
                  (MediaQuery.textScalerOf(context).scale(14) / 14 - 1)
                          .clamp(0.0, double.infinity) *
                      24;
              final height =
                  (layout.cardWidth * 1.02).clamp(190.0, 300.0) + growth;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  // Three rows keep the wall level with the side rail.
                  for (final entry in entries.take(layout.columns * 3))
                    SizedBox(
                      width: layout.cardWidth,
                      height: height,
                      child: ViewGalleryCard(
                        key: ValueKey('home-jump-card-${entry.id}'),
                        entry: entry,
                        face: GalleryCardFace.page,
                        loadPreview: () => _previewOf(entry.view),
                        caption: facts.captionOf(entry),
                        details: facts.detailsOf(entry),
                        userProfile: userProfile,
                        onOpen: () => _open(entry.view),
                        onMenu: (position) =>
                            _showEntryMenu(entry, source, position),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}
