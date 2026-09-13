import 'dart:async';

import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
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
import 'astrology_dashboard_model.dart';
import 'astrology_dashboard_service.dart';
import 'astrology_engine.dart';
import 'astrology_horoscope_library.dart';
import 'astrology_model.dart';
import 'astrology_style.dart';

AstrologyInput _input(DashboardWidgetContext context) {
  final draft = context.controller.state[astrologyDraftKey];
  if (draft is AstrologyInput) return draft;
  return astrologyInputFromDashboard(context.controller.document);
}

/// A control and its charts are siblings: listen to the same dashboard
/// controller, not an inherited widget that only one sibling could see.
List<DashboardWidgetDefinition> astrologyDashboardWidgets() => [
      DashboardWidgetDefinition(
        type: astrologyInputWidgetType,
        extensionId: 'astrology',
        requiresScrollActivation: true,
        label: () => 'Horoscope birth details',
        icon: Icons.person_rounded,
        group: DashboardWidgetGroup.controls,
        defaultColumnSpan: 12,
        defaultRowSpan: 7,
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
          extensionId: 'astrology',
          requiresScrollActivation: true,
          label: () => 'Astrology · ${entry.value.label}',
          icon: entry.value == AstrologyView.chart
              ? Icons.auto_awesome_rounded
              : Icons.table_chart_rounded,
          group: DashboardWidgetGroup.data,
          defaultColumnSpan: 6,
          defaultRowSpan: 8,
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
                label: 'Current-day transit',
                value: context.spec.flag('transit'),
                onChanged: (value) => context.setSettings({'transit': value}),
              ),
            ],
          ],
        ),
      DashboardWidgetDefinition(
        type: astrologyLibraryWidgetType,
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
        extensionId: 'astrology',
        requiresScrollActivation: true,
        label: () => 'Horoscope life events',
        icon: Icons.event_note_rounded,
        group: DashboardWidgetGroup.data,
        defaultColumnSpan: 12,
        defaultRowSpan: 8,
        minimumColumnSpan: 4,
        minimumRowSpan: 5,
        keywords: const [
          'astrology',
          'events',
          'notes',
          'dasha',
          'antardasha',
          'pratyantardasha',
        ],
        builder: (context) {
          final id = context.spec.source.viewId;
          if (id.isEmpty || context.controller.viewId.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Save a named horoscope above to create its own editable Life events grid.\n'
                  'Event name · Date · Dasha · Antardasha · Pratyantardasha · Notes',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return DashboardViewBuilder(
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
          );
        },
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
      final enabled = context.isTypable &&
          controller.viewId.isNotEmpty &&
          AstrologyRuntime.active.value;
      return Column(
        children: [
          if (!library)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    !enabled ? null : () => unawaited(_openLibrary(context)),
                icon: const Icon(Icons.people_rounded, size: 16),
                label: const Text('All horoscopes / add another person'),
              ),
            ),
          Expanded(
            child: AstrologyBirthForm(
              input: _input(context),
              enabled: enabled,
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
          icon: const Icon(Icons.swap_horiz_rounded, size: 16),
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
      var input = _input(context);
      final spec = context.controller.document.widgetById(context.spec.id) ??
          context.spec;
      final transit = spec.flag('transit');
      final atBirthplace = spec.flag('transit_at_birthplace');
      if (transit) {
        // A transit is NOW in the place chosen for transits, never the natal
        // UTC offset (which may have been daylight saving decades ago).
        input = AstrologyInput(
          place: atBirthplace ? input.place : null,
          style: input.style,
          ayanamsa: input.ayanamsa,
          ayanamsaOffsetArcseconds: input.ayanamsaOffsetArcseconds,
          trueNode: input.trueNode,
          dashaYearDays: input.dashaYearDays,
        );
      }
      final rawDivision = spec.integer('division', fallback: 1);
      final division =
          astrologyDivisions.containsKey(rawDivision) ? rawDivision : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (view == AstrologyView.chart && transit)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: !context.isTypable
                    ? null
                    : () => _setReadingSettings(
                          context,
                          {'transit_at_birthplace': !atBirthplace},
                        ),
                child: Text(
                  atBirthplace ? 'At birthplace' : 'Current location',
                ),
              ),
            ),
          Expanded(
            child: AstrologyChartPanel(
              input: input,
              view: view,
              division: division,
              refreshToken: context.controller.refreshToken,
              preview: context.controller.viewId.isEmpty,
              onConfigure: context.isTypable
                  ? () => unawaited(_configure(context))
                  : null,
            ),
          ),
        ],
      );
    } on Object catch (error) {
      return Center(
        child: Text('This horoscope could not be read: $error'),
      );
    }
  }
}
