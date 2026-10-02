import 'dart:async';

import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'astrology_birth_form.dart';
import 'astrology_block.dart';
import 'astrology_chart_panel.dart';
import 'astrology_chart_selector.dart';
import 'astrology_controls.dart';
import 'astrology_dashboard_model.dart';
import 'astrology_dashboard_service.dart';
import 'astrology_date_analysis.dart';
import 'astrology_date_analysis_view.dart';
import 'astrology_engine.dart';
import 'astrology_events_sync.dart';
import 'astrology_file_actions.dart';
import 'astrology_horoscope_library.dart';
import 'astrology_model.dart';
import 'astrology_style.dart';
import 'astrology_transit_form.dart';

AstrologyInput _input(DashboardWidgetContext context) {
  final draft = context.controller.state[astrologyDraftKey];
  if (draft is AstrologyInput) return draft;
  return astrologyInputFromDashboard(context.controller.document);
}

/// Cards that follow an applied transit while the Transit details tab is open.
const _transitFollowing = {
  AstrologyView.panchanga,
  AstrologyView.placements,
  AstrologyView.dasha,
};

/// Icons that follow the chosen icon style (Vivid artwork or line).
const _viewIcons = {
  AstrologyView.chart: Icons.auto_awesome_rounded,
  AstrologyView.dasha: Icons.view_timeline_rounded,
  AstrologyView.shadbala: Icons.balance_rounded,
  AstrologyView.ashtakavarga: Icons.grid_on_rounded,
  AstrologyView.placements: Icons.public_rounded,
  AstrologyView.panchanga: Icons.wb_sunny_rounded,
};

/// Default spans: each card's usual content shows without scrolling on a
/// desktop canvas, matching the template's JHora-like arrangement.
const _viewSpans = {
  AstrologyView.chart: (6, 14),
  AstrologyView.dasha: (6, 29),
  AstrologyView.shadbala: (12, 14),
  AstrologyView.ashtakavarga: (12, 32),
  AstrologyView.placements: (12, 21),
  AstrologyView.panchanga: (6, 13),
};

/// A control and its charts are siblings: listen to the same dashboard
/// controller, not an inherited widget that only one sibling could see.
List<DashboardWidgetDefinition> astrologyDashboardWidgets() => [
      DashboardWidgetDefinition(
        type: astrologyInputWidgetType,
        // Birth details steer a whole dashboard. A page's Astrology block
        // carries its own, so that block is the page's version of this card.
        pageBlock: astrologyBlockType,
        extensionId: 'astrology',
        requiresScrollActivation: true,
        label: () => 'Horoscope birth details',
        icon: Icons.person_rounded,
        group: DashboardWidgetGroup.controls,
        defaultColumnSpan: 12,
        defaultRowSpan: 9,
        minimumColumnSpan: 4,
        minimumRowSpan: 5,
        showsTitleByDefault: false,
        padding: EdgeInsets.zero,
        keywords: const [
          'astrology',
          'birth',
          'horoscope',
          'name',
          'date',
          'time',
          'place',
        ],
        defaultSettings: const {'library': true},
        builder: (context) => ListenableBuilder(
          listenable: Listenable.merge(
            [context.controller, AstrologyRuntime.active],
          ),
          builder: (_, __) => _BirthCard(context: context),
        ),
      ),
      for (final entry in const {
        astrologyChartWidgetType: AstrologyView.chart,
        astrologyDashaWidgetType: AstrologyView.dasha,
        astrologyShadbalaWidgetType: AstrologyView.shadbala,
        astrologyAshtakavargaWidgetType: AstrologyView.ashtakavarga,
        astrologyPlacementsWidgetType: AstrologyView.placements,
        astrologyPanchangaWidgetType: AstrologyView.panchanga,
      }.entries)
        DashboardWidgetDefinition(
          type: entry.key,
          // The same reading is a page block of its own.
          pageBlock: entry.value == AstrologyView.chart
              ? astrologyBlockType
              : 'extension_astrology_${entry.value.name}',
          extensionId: 'astrology',
          requiresScrollActivation: true,
          label: () => 'Astrology · ${entry.value.label}',
          icon: _viewIcons[entry.value]!,
          group: DashboardWidgetGroup.data,
          defaultColumnSpan: _viewSpans[entry.value]!.$1,
          defaultRowSpan: _viewSpans[entry.value]!.$2,
          minimumColumnSpan: 3,
          minimumRowSpan: 5,
          padding: const EdgeInsets.all(6),
          keywords: ['astrology', 'vedic', 'horoscope', entry.value.name],
          headerTrailing: entry.value == AstrologyView.chart
              ? (context) => ListenableBuilder(
                    listenable: Listenable.merge(
                      [context.controller, AstrologyRuntime.active],
                    ),
                    builder: (_, __) => _ChartHeaderActions(context: context),
                  )
              : _transitFollowing.contains(entry.value)
                  ? (context) => ListenableBuilder(
                        listenable: context.controller,
                        builder: (_, __) => _TransitBadge(context: context),
                      )
                  : null,
          builder: (context) => ListenableBuilder(
            listenable: context.controller,
            builder: (_, __) =>
                _ReadingCard(context: context, view: entry.value),
          ),
          configure: (context) => [
            DashboardConfigButton(
              label: 'Birth details / location',
              icon: Icons.tune_rounded,
              onPressed: () => _configure(context),
            ),
            if (entry.value == AstrologyView.chart) ...[
              DashboardConfigChoice(
                label: 'Divisional chart',
                value: '${context.spec.integer('division', fallback: 1)}',
                choices: [
                  for (final division in astrologyDivisions.entries)
                    DashboardChoice(
                      value: '${division.key}',
                      label: division.value,
                    ),
                ],
                onChanged: (value) =>
                    context.setSettings({'division': int.parse(value)}),
              ),
              DashboardConfigToggle(
                label: 'Transit chart (follows Transit details)',
                value: context.spec.flag('transit'),
                onChanged: (value) => context.setSettings({'transit': value}),
              ),
            ],
          ],
        ),
      DashboardWidgetDefinition(
        type: astrologyLibraryWidgetType,
        pageBlock: astrologyBlockType,
        extensionId: 'astrology',
        requiresScrollActivation: true,
        label: () => 'Saved horoscopes',
        icon: Icons.people_rounded,
        group: DashboardWidgetGroup.content,
        defaultColumnSpan: 12,
        defaultRowSpan: 5,
        minimumColumnSpan: 3,
        minimumRowSpan: 2,
        keywords: const ['astrology', 'people', 'saved', 'horoscopes'],
        builder: (context) => ListenableBuilder(
          listenable: Listenable.merge(
            [context.controller, AstrologyRuntime.active],
          ),
          builder: (_, __) {
            // The index belongs only to the template/library dashboard, not
            // a person's dashboard or an individually inserted editor block.
            if (!isAstrologyLibrary(context.controller.document)) {
              return const SizedBox.shrink();
            }
            return AstrologyHoroscopeLibrary(
              libraryViewId: context.controller.viewId,
              enabled: AstrologyRuntime.active.value,
              refreshToken: context.controller.refreshToken,
              onOpen: (person) {
                if (context.context.mounted) {
                  context.context.read<TabsBloc>().openPlugin(person);
                }
              },
            );
          },
        ),
      ),
      DashboardWidgetDefinition(
        type: astrologyEventsWidgetType,
        pageBlock: astrologyBlockType,
        extensionId: 'astrology',
        requiresScrollActivation: true,
        label: () => 'Horoscope life events',
        icon: Icons.history_rounded,
        group: DashboardWidgetGroup.data,
        defaultColumnSpan: 12,
        defaultRowSpan: 12,
        minimumColumnSpan: 4,
        minimumRowSpan: 5,
        keywords: const [
          'astrology',
          'events',
          'notes',
          'dasha',
          'antardasha',
          'pratyantardasha',
          'sookshma',
          'transit',
        ],
        headerTrailing: (context) {
          final id = context.spec.source.viewId;
          if (id.isEmpty || context.controller.viewId.isEmpty) {
            return const SizedBox.shrink();
          }
          return _EventsRecalculate(viewId: id, context: context);
        },
        builder: (context) {
          final id = context.spec.source.viewId;
          if (id.isEmpty || context.controller.viewId.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Save a named horoscope above to create its own editable Life events grid.\n'
                  'Add a date to any event to fill its dasha, antardasha, pratyantardasha, '
                  'sookshma dasha, Moon nakshatra and transits automatically.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EventsStatus(
                key: ValueKey('astrology-events-status-$id'),
                viewId: id,
              ),
              Expanded(
                child: DashboardViewBuilder(
                  viewId: id,
                  revision: context.refreshToken,
                  builder: (_, view) =>
                      Provider<DatabasePluginWidgetBuilderSize>.value(
                    value: const DatabasePluginWidgetBuilderSize(
                      horizontalPadding: 0,
                      showScrollbars: false,
                    ),
                    child: ScrollConfiguration(
                      behavior: NoScrollbarBehavior(
                        ScrollConfiguration.of(context.context),
                      ),
                      child: IgnorePointer(
                        ignoring: !context.isTypable,
                        child: DatabaseTabBarView(
                          key: ValueKey('astrology-events-${view.id}'),
                          view: view,
                          shrinkWrap: false,
                          showActions: false,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      DashboardWidgetDefinition(
        type: astrologyDateAnalysisWidgetType,
        pageBlock: astrologyBlockType,
        extensionId: 'astrology',
        requiresScrollActivation: true,
        label: () => 'Astrology · Date analysis',
        icon: Icons.event_available_rounded,
        group: DashboardWidgetGroup.data,
        defaultColumnSpan: 12,
        defaultRowSpan: 19,
        minimumColumnSpan: 4,
        minimumRowSpan: 5,
        padding: const EdgeInsets.all(6),
        keywords: const [
          'astrology',
          'date',
          'dasha',
          'transit',
          'panchanga',
          'muhurta',
          'rahu kalam',
          'tara bala',
        ],
        builder: (context) => ListenableBuilder(
          listenable: context.controller,
          builder: (_, __) {
            try {
              return AstrologyDateAnalysisView(
                key: ValueKey('astrology-date-analysis-${context.spec.id}'),
                natal: _input(context),
                preview: context.controller.viewId.isEmpty,
              );
            } on Object catch (error) {
              return Center(
                child: Text('This horoscope could not be read: $error'),
              );
            }
          },
        ),
        configure: (context) => [
          DashboardConfigButton(
            label: 'Birth details / location',
            icon: Icons.tune_rounded,
            onPressed: () => _configure(context),
          ),
        ],
      ),
    ];

Future<void> _configure(DashboardWidgetContext context) async {
  if (!context.isTypable ||
      context.controller.viewId.isEmpty ||
      !AstrologyRuntime.active.value) {
    return;
  }
  try {
    final result = await showAstrologyInputDialog(
      context.context,
      input: _input(context),
    );
    if (result == null ||
        !context.context.mounted ||
        !AstrologyRuntime.active.value) {
      return;
    }
    await AstrologyEngine.instance.calculate(result);
    if (!context.context.mounted) return;
    _setDraft(context.controller, result);
  } on Object catch (error) {
    showToastNotification(message: '$error', type: ToastificationType.error);
  }
}

void _setDraft(DashboardController controller, AstrologyInput input) {
  // Cards added individually need the same declared key as the template;
  // otherwise a later layout edit prunes their live input from dashboard state.
  if (controller.document.variableFor(astrologyDraftKey) == null) {
    controller.edit(
      (document) => document.withVariable(
        const DashboardVariable(
          key: astrologyDraftKey,
          label: 'Birth details draft',
        ),
      ),
    );
  }
  controller.setValue(astrologyDraftKey, input);
}

void _setTransit(DashboardController controller, AstrologyTransitState value) {
  // Declared like the draft, or a layout edit prunes the tab and its moment.
  if (controller.document.variableFor(astrologyTransitKey) == null &&
      !controller.isReadOnly) {
    controller.edit(
      (document) => document.withVariable(
        const DashboardVariable(
          key: astrologyTransitKey,
          label: 'Transit details',
        ),
      ),
    );
  }
  controller.setValue(astrologyTransitKey, value);
}

const _birthTab = 'astrology-tab-birth';
const _transitTab = 'astrology-tab-transit';

class _BirthCard extends StatelessWidget {
  const _BirthCard({required this.context});
  final DashboardWidgetContext context;

  Future<void> _save(AstrologyInput input) async {
    final controller = context.controller;
    if (!AstrologyRuntime.active.value) {
      throw StateError('Astrology is disabled.');
    }
    // Saving follows a successful real calculation, not just field validation.
    await AstrologyEngine.instance.calculate(input);
    if (!context.context.mounted || !AstrologyRuntime.active.value) return;
    await controller.flush();
    final library = isAstrologyLibrary(controller.document);
    final saved = await AstrologyDashboardService.instance.savePerson(
      libraryViewId: astrologyLibraryId(controller.document, controller.viewId),
      existingViewId: library ? null : controller.viewId,
      input: input,
      document: library ? null : controller.document,
    );
    if (!context.context.mounted) return;
    if (!library) {
      // adoptFromView deliberately declines while a resize/write is in flight.
      // Merge into the LATEST arrangement so neither the new birth details nor
      // a layout edit made during Save can be lost to an old controller echo.
      controller.edit((document) => withAstrologyInput(document, input));
      controller.setValue(astrologyDraftKey, null);
      await controller.flush();
      // Changed birth details change every event's dashas and houses.
      final events = astrologyEventsViewId(controller.document);
      if (events.isNotEmpty) {
        unawaited(AstrologyEventsSync.instance.recalculate(events));
      }
    }
    if (!context.context.mounted) return;
    controller.refresh();
    if (library) context.context.read<TabsBloc>().openPlugin(saved);
  }

  @override
  Widget build(BuildContext buildContext) {
    try {
      final controller = context.controller;
      final library = isAstrologyLibrary(controller.document);
      final running = AstrologyRuntime.active.value;
      final enabled =
          context.isTypable && controller.viewId.isNotEmpty && running;
      final input = _input(context);
      final transit = astrologyTransitState(controller.state);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                AstrologyTabs(
                  key: const ValueKey('astrology-details-tabs'),
                  tabs: const [
                    AstrologyTab(
                      id: _birthTab,
                      label: 'Birth details',
                      icon: Icons.person_rounded,
                    ),
                    AstrologyTab(
                      id: _transitTab,
                      label: 'Transit details',
                      icon: Icons.timelapse_rounded,
                    ),
                  ],
                  selected: transit.active ? _transitTab : _birthTab,
                  onSelected: !running
                      ? null
                      : (id) => _setTransit(
                            controller,
                            astrologyTransitState(controller.state)
                                .withActive(id == _transitTab),
                          ),
                ),
                // Birth files belong to the birth details, not a transit.
                if (!transit.active)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (!library)
                        AstrologyButton(
                          id: 'astrology-open-library',
                          label: 'All horoscopes / add another person',
                          icon: Icons.people_rounded,
                          onPressed: !enabled
                              ? null
                              : () => unawaited(_openLibrary(context)),
                        ),
                      AstrologyFileActions(
                        input: () => _input(context),
                        enabled: enabled,
                        onImported: (input) async {
                          if (buildContext.mounted &&
                              AstrologyRuntime.active.value) {
                            _setDraft(controller, input);
                          }
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(
            // Both stay mounted: switching tabs keeps an unsaved birth draft.
            child: IndexedStack(
              index: transit.active ? 1 : 0,
              sizing: StackFit.expand,
              children: [
                AstrologyBirthForm(
                  input: input,
                  enabled: enabled,
                  showTitle: false,
                  saveLabel:
                      library ? 'Save as person’s dashboard' : 'Save changes',
                  onGenerate: (input) async {
                    if (!AstrologyRuntime.active.value) {
                      throw StateError('Astrology is disabled.');
                    }
                    await AstrologyEngine.instance.calculate(input);
                    if (buildContext.mounted && AstrologyRuntime.active.value) {
                      _setDraft(controller, input);
                    }
                  },
                  onSave: _save,
                ),
                AstrologyTransitForm(
                  key: const ValueKey('astrology-transit-form'),
                  natal: input,
                  utc: transit.utc,
                  place: transit.place,
                  applied: transit.applied,
                  enabled: running && controller.viewId.isNotEmpty,
                  onApplied: (utc, place) => _setTransit(
                    controller,
                    astrologyTransitState(controller.state)
                        .withMoment(utc, place: place),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } on Object catch (error) {
      return Center(
        child: Text('The stored birth details could not be read: $error'),
      );
    }
  }
}

Future<void> _openLibrary(DashboardWidgetContext context) async {
  try {
    final id = astrologyLibraryId(
      context.controller.document,
      context.controller.viewId,
    );
    final result = await ViewBackendService.getView(id);
    if (!context.context.mounted) return;
    result.fold(
      (view) => context.context.read<TabsBloc>().openPlugin(view),
      (error) => showToastNotification(
        message: error.msg,
        type: ToastificationType.error,
      ),
    );
  } on Object catch (error) {
    showToastNotification(message: '$error', type: ToastificationType.error);
  }
}

void _setReadingSettings(
  DashboardWidgetContext context,
  Map<String, Object?> settings,
) {
  if (!context.context.mounted ||
      !context.isTypable ||
      !AstrologyRuntime.active.value) {
    return;
  }
  context.controller.edit((document) {
    final current = document.widgetById(context.spec.id);
    return current == null
        ? document
        : document.withWidget(current.withSettings(settings));
  });
}

class _ChartHeaderActions extends StatelessWidget {
  const _ChartHeaderActions({required this.context});
  final DashboardWidgetContext context;

  @override
  Widget build(BuildContext buildContext) {
    final spec =
        context.controller.document.widgetById(context.spec.id) ?? context.spec;
    final enabled = context.isTypable && AstrologyRuntime.active.value;
    AstrologyInput input;
    try {
      input = _input(context);
    } on Object {
      // The reading body already explains a malformed saved profile.
      return const SizedBox.shrink();
    }
    final palette = AstrologyPalette.of(buildContext);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          tooltip: input.style == IndianChartStyle.north
              ? 'Switch to South Indian'
              : 'Switch to North Indian',
          icon: WorkspaceGlyph(
            Icons.swap_horiz_rounded,
            size: 16,
            color:
                enabled ? palette.muted : palette.muted.withValues(alpha: 0.5),
            role: enabled
                ? WorkspaceGlyphRole.standard
                : WorkspaceGlyphRole.preserveInk,
          ),
          color: palette.muted,
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints.tightFor(width: 26, height: 26),
          onPressed: !enabled
              ? null
              : () {
                  final latest = _input(context);
                  _setDraft(
                    context.controller,
                    latest.copyWith(
                      style: latest.style == IndianChartStyle.north
                          ? IndianChartStyle.south
                          : IndianChartStyle.north,
                    ),
                  );
                },
        ),
        const SizedBox(width: 6),
        Flexible(
          child: AstrologyChartSelector(
            key: ValueKey('astrology-chart-selector-${spec.id}'),
            value: spec.integer('division', fallback: 1),
            onChanged: !enabled
                ? null
                : (value) => _setReadingSettings(context, {'division': value}),
          ),
        ),
      ],
    );
  }
}

class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.context, required this.view});
  final DashboardWidgetContext context;
  final AstrologyView view;

  @override
  Widget build(BuildContext buildContext) {
    try {
      final natal = _input(context);
      final spec = context.controller.document.widgetById(context.spec.id) ??
          context.spec;
      final transit = astrologyTransitState(context.controller.state);
      // A transit chart always shows the applied transit; panchanga and
      // placements (and the dasha's reading date) follow it while the Transit
      // details tab is open and Apply has been pressed. Everything else is
      // fixed by the birth.
      final transitChart = spec.flag('transit');
      final following = transit.following && _transitFollowing.contains(view);
      final castForTransit =
          transitChart || (following && view != AstrologyView.dasha);
      final input = castForTransit
          ? astrologyTransitInput(natal, transit.utc, place: transit.place)
          : natal;
      final rawDivision = spec.integer('division', fallback: 1);
      final division =
          astrologyDivisions.containsKey(rawDivision) ? rawDivision : 1;
      return AstrologyChartPanel(
        input: input,
        view: view,
        division: division,
        transit: castForTransit,
        dashaAt: following ? transit.utc : null,
        refreshToken: context.controller.refreshToken,
        preview: context.controller.viewId.isEmpty,
        onConfigure:
            context.isTypable ? () => unawaited(_configure(context)) : null,
      );
    } on Object catch (error) {
      return Center(
        child: Text('This horoscope could not be read: $error'),
      );
    }
  }
}

/// Names a transit-following card while an applied transit is shown.
class _TransitBadge extends StatelessWidget {
  const _TransitBadge({required this.context});
  final DashboardWidgetContext context;

  @override
  Widget build(BuildContext buildContext) {
    final transit = astrologyTransitState(context.controller.state);
    if (!transit.following) return const SizedBox.shrink();
    final palette = AstrologyPalette.of(buildContext);
    var moment = 'now';
    final utc = transit.utc;
    if (utc != null) {
      try {
        final input =
            astrologyTransitInput(_input(context), null, place: transit.place);
        moment = '${astrologyLocalDate(input, utc)} '
            '${astrologyLocalClock(input, utc)}';
      } on Object {
        moment = '${utc.toIso8601String().substring(0, 16)} UTC';
      }
    }
    final place = transit.place?.name.split(',').first.trim() ?? '';
    if (place.isNotEmpty) moment = '$moment · $place';
    final label = context.spec.type == astrologyDashaWidgetType
        ? 'Current dasha · $moment'
        : 'Transit · $moment';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        key: ValueKey('astrology-transit-badge-${context.spec.id}'),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkspaceGlyph(
                Icons.timelapse_rounded,
                size: 14,
                color: palette.accent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation.weight(600)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line key to the calculated columns, and the current fill status.
/// Mounting starts a pass, so a table opened for the first time is filled.
class _EventsStatus extends StatefulWidget {
  const _EventsStatus({super.key, required this.viewId});

  final String viewId;

  @override
  State<_EventsStatus> createState() => _EventsStatusState();
}

class _EventsStatusState extends State<_EventsStatus> {
  @override
  void initState() {
    super.initState();
    AstrologyEventsSync.instance.watch(widget.viewId);
  }

  @override
  void didUpdateWidget(_EventsStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId) {
      AstrologyEventsSync.instance.watch(widget.viewId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: palette.muted,
          fontSize: 11.5,
        );
    return ValueListenableBuilder<AstrologyEventsStatus>(
      valueListenable: AstrologyEventsSync.instance.status(widget.viewId),
      builder: (context, status, _) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Dates fill the dashas, Moon nakshatra and transits '
                    'automatically (no time = noon). Transits: sign degree · '
                    'R retrograde · H house from natal Lagna · M house from '
                    'natal Moon.',
              ),
              if (status.message.isNotEmpty)
                TextSpan(
                  text: '  ${status.message}',
                  style: TextStyle(
                    color: status.failed ? palette.danger : palette.accent,
                  ),
                ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}

class _EventsRecalculate extends StatelessWidget {
  const _EventsRecalculate({required this.viewId, required this.context});

  final String viewId;
  final DashboardWidgetContext context;

  @override
  Widget build(BuildContext buildContext) {
    final palette = AstrologyPalette.of(buildContext);
    return ValueListenableBuilder<AstrologyEventsStatus>(
      valueListenable: AstrologyEventsSync.instance.status(viewId),
      builder: (_, status, __) => IconButton(
        key: ValueKey('astrology-events-recalculate-$viewId'),
        tooltip: 'Recalculate every dated event (replaces edited values)',
        icon: status.busy
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : WorkspaceGlyph(
                Icons.refresh_rounded,
                size: 16,
                color: palette.muted,
              ),
        color: palette.muted,
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints.tightFor(width: 26, height: 26),
        onPressed:
            status.busy || !context.isTypable || !AstrologyRuntime.active.value
                ? null
                : () => unawaited(
                      AstrologyEventsSync.instance.recalculate(
                        viewId,
                        force: true,
                      ),
                    ),
      ),
    );
  }
}
