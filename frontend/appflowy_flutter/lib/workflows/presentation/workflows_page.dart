import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workflows/application/workflow_background.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workflows/application/workflow_templates.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'workflow_background_dialog.dart';
import 'workflow_editor.dart';
import 'workflow_forms.dart';
import 'workflow_history.dart';
import 'workflow_style.dart';

enum _Filter { all, on, off, history }

/// Every workflow, the templates to start from, and the history of runs.
/// Opening one swaps the list for its editor.
class WorkflowsPage extends StatefulWidget {
  const WorkflowsPage({super.key, this.manager});

  /// Injected by tests; the app uses the shared instance.
  final WorkflowManager? manager;

  @override
  State<WorkflowsPage> createState() => _WorkflowsPageState();
}

class _WorkflowsPageState extends State<WorkflowsPage> {
  WorkflowManager get _manager => widget.manager ?? WorkflowManager.instance;

  final TextEditingController _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String? _openId;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    unawaited(_manager.store.ensureLoaded());
    unawaited(_manager.log.ensureLoaded());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create(Workflow draft) async {
    if (_creating) {
      return;
    }
    setState(() => _creating = true);
    try {
      final workflow = await _manager.create(draft);
      if (mounted) {
        setState(() => _openId = workflow.id);
      }
    } on Object catch (error) {
      if (mounted) {
        showSnackBarMessage(context, '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Future<void> _runNow(Workflow workflow) async {
    final run = await _manager.runNow(workflow);
    if (!mounted || run == null) {
      return;
    }
    showSnackBarMessage(
      context,
      run.status == WorkflowRunStatus.failed
          ? LocaleKeys.workflows_editor_runFailed.tr(args: [run.message])
          : LocaleKeys.workflows_editor_runSucceeded.tr(),
    );
  }

  Future<void> _delete(Workflow workflow) => showCancelAndDeleteDialog(
        context: context,
        title: LocaleKeys.workflows_delete_title.tr(args: [_nameOf(workflow)]),
        description: LocaleKeys.workflows_delete_description.tr(),
        confirmLabel: LocaleKeys.workflows_menu_delete.tr(),
        closeOnAction: true,
        onDelete: () => unawaited(_manager.delete(workflow)),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _manager,
        _manager.store,
        _manager.log,
        _manager.scheduler,
      ]),
      builder: (context, _) {
        final openId = _openId;
        if (openId != null && _manager.store.byId(openId) != null) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(32, 22, 32, 16),
            child: WorkflowEditor(
              key: ValueKey('workflow-editor-$openId'),
              workflowId: openId,
              manager: _manager,
              onClose: () => setState(() => _openId = null),
              onOpen: (id) => setState(() => _openId = id),
            ),
          );
        }
        return _list(context);
      },
    );
  }

  Widget _list(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final store = _manager.store;
    final settings = store.settings;
    final query = _search.text.trim().toLowerCase();
    final all = [...store.workflows]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final shown = [
      for (final workflow in all)
        if ((_filter != _Filter.on || workflow.enabled) &&
            (_filter != _Filter.off || !workflow.enabled) &&
            (query.isEmpty ||
                workflow.name.toLowerCase().contains(query) ||
                workflow.description.toLowerCase().contains(query)))
          workflow,
    ];
    final enabled = all.where((workflow) => workflow.enabled).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 26, 40, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            creating: _creating,
            onNew: () => unawaited(
              _create(
                Workflow.create(name: LocaleKeys.workflows_untitled.tr()),
              ),
            ),
            onBackground: () => unawaited(
              showWorkflowBackgroundDialog(context, manager: _manager),
            ),
          ),
          const SizedBox(height: 18),
          if (settings.pausedAll)
            _Banner(
              glyph: 'pause',
              accent: DashboardAccent.amber,
              message: LocaleKeys.workflows_paused_banner.tr(),
              action: LocaleKeys.workflows_paused_resume.tr(),
              onAction: () => unawaited(
                _manager.updateSettings(settings.copyWith(pausedAll: false)),
              ),
            )
          else if (WorkflowBackground.isSupported &&
              enabled > 0 &&
              !settings.keepRunningInBackground)
            _Banner(
              glyph: 'moon',
              accent: DashboardAccent.blue,
              message: LocaleKeys.workflows_foreground_banner.tr(),
              action: LocaleKeys.workflows_foreground_action.tr(),
              onAction: () => unawaited(
                _manager.updateSettings(
                  settings.copyWith(keepRunningInBackground: true),
                ),
              ),
            ),
          _Stats(workflows: all, runs: _manager.log.runs),
          const SizedBox(height: 18),
          Row(
            children: [
              WorkflowSegmented<_Filter>(
                values: _Filter.values,
                selected: _filter,
                labelOf: (filter) => switch (filter) {
                  _Filter.all => LocaleKeys.workflows_tabs_all.tr(),
                  _Filter.on => LocaleKeys.workflows_tabs_on.tr(),
                  _Filter.off => LocaleKeys.workflows_tabs_off.tr(),
                  _Filter.history => LocaleKeys.workflows_tabs_history.tr(),
                },
                onChanged: (filter) => setState(() => _filter = filter),
              ),
              const Spacer(),
              if (_filter != _Filter.history)
                SizedBox(
                  width: 240,
                  child: _SearchField(
                    controller: _search,
                    onChanged: () => setState(() {}),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _filter == _Filter.history
                ? const WorkflowRunList(padding: EdgeInsets.only(bottom: 32))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 40),
                    children: [
                      if (all.isEmpty)
                        _EmptyState(
                          creating: _creating,
                          onNew: () => unawaited(
                            _create(
                              Workflow.create(
                                name: LocaleKeys.workflows_untitled.tr(),
                              ),
                            ),
                          ),
                        )
                      else if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Text(
                            LocaleKeys.workflows_empty_noMatches
                                .tr(args: [_search.text.trim()]),
                            textAlign: TextAlign.center,
                            style: DashboardType.caption(palette)
                                .copyWith(fontSize: 13),
                          ),
                        )
                      else
                        for (final workflow in shown)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _WorkflowCard(
                              key: ValueKey('workflow-card-${workflow.id}'),
                              workflow: workflow,
                              manager: _manager,
                              onOpen: () =>
                                  setState(() => _openId = workflow.id),
                              onRunNow: () => unawaited(_runNow(workflow)),
                              onDuplicate: () async {
                                final copy = await _manager.duplicate(
                                  workflow,
                                  name: LocaleKeys.workflows_copyName
                                      .tr(args: [_nameOf(workflow)]),
                                );
                                if (mounted) {
                                  setState(() => _openId = copy.id);
                                }
                              },
                              onDelete: () => unawaited(_delete(workflow)),
                            ),
                          ),
                      const SizedBox(height: 26),
                      _Templates(
                        busy: _creating,
                        onUse: (template) => unawaited(
                          _create(template.build(template.title)),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

String _nameOf(Workflow workflow) => workflow.name.trim().isEmpty
    ? LocaleKeys.workflows_untitled.tr()
    : workflow.name;

class _Header extends StatelessWidget {
  const _Header({
    required this.creating,
    required this.onNew,
    required this.onBackground,
  });

  final bool creating;
  final VoidCallback onNew;
  final VoidCallback onBackground;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Row(
      children: [
        const WorkflowGlyphTile(
          glyph: 'infinity',
          accent: WorkflowVisuals.triggerAccent,
          size: 44,
          glyphSize: 22,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.workflows_title.tr(),
                style: DashboardType.title(palette),
              ),
              const SizedBox(height: 4),
              Text(
                LocaleKeys.workflows_subtitle.tr(),
                style: DashboardType.caption(palette).copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        WorkflowButton(
          key: const ValueKey('workflow-background-button'),
          label: LocaleKeys.workflows_backgroundButton.tr(),
          glyph: 'moon',
          onPressed: onBackground,
        ),
        const SizedBox(width: 8),
        WorkflowButton(
          key: const ValueKey('workflow-new-button'),
          label: LocaleKeys.workflows_newWorkflow.tr(),
          glyph: 'plus',
          kind: WorkflowButtonKind.primary,
          busy: creating,
          onPressed: onNew,
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.glyph,
    required this.accent,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final String glyph;
  final DashboardAccent accent;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final strong = palette.strongFor(accent);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        decoration: BoxDecoration(
          color: strong.withValues(alpha: palette.isDark ? 0.16 : 0.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: strong.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            WorkflowGlyphTile(glyph: glyph, accent: accent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: DashboardType.body(palette).copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(width: 12),
            WorkflowButton(label: action, onPressed: onAction),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.workflows, required this.runs});

  final List<Workflow> workflows;
  final List<WorkflowRun> runs;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todays = runs.where((run) => !run.startedAt.isBefore(today));
    final failed =
        todays.where((run) => run.status == WorkflowRunStatus.failed).length;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _Stat(
          glyph: 'infinity',
          value: '${workflows.length}',
          label: LocaleKeys.workflows_stats_workflows.tr(),
          accent: DashboardAccent.neutral,
        ),
        _Stat(
          glyph: 'power',
          value: '${workflows.where((workflow) => workflow.enabled).length}',
          label: LocaleKeys.workflows_stats_on.tr(),
          accent: DashboardAccent.green,
        ),
        _Stat(
          glyph: 'history',
          value: '${todays.length}',
          label: LocaleKeys.workflows_stats_runsToday.tr(),
          accent: DashboardAccent.blue,
        ),
        _Stat(
          glyph: failed > 0 ? 'warning' : 'check-circle',
          value: '$failed',
          label: LocaleKeys.workflows_stats_failedToday.tr(),
          accent: failed > 0 ? DashboardAccent.red : DashboardAccent.neutral,
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.glyph,
    required this.value,
    required this.label,
    required this.accent,
  });

  final String glyph;
  final String value;
  final String label;
  final DashboardAccent accent;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Container(
      width: 176,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          WorkflowGlyphTile(glyph: glyph, accent: accent, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: DashboardType.figure(palette, size: 20)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      DashboardType.caption(palette).copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return TextEntryShortcuts(
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.border.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            WorkspaceGlyph.named(
              'magnifying-glass',
              size: 15,
              color: palette.textMuted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('workflow-search'),
                controller: controller,
                onChanged: (_) => onChanged(),
                style: DashboardType.body(palette).copyWith(fontSize: 13),
                cursorColor: palette.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: LocaleKeys.workflows_search.tr(),
                  hintStyle:
                      DashboardType.caption(palette).copyWith(fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The trigger and its steps as a short row of tiles.
class _Chain extends StatelessWidget {
  const _Chain({required this.workflow, this.size = 32});

  final Workflow workflow;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final shown = workflow.steps.take(3).toList();
    final extra = workflow.steps.length - shown.length;
    Widget link() => Container(
          width: 10,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: palette.border,
            borderRadius: BorderRadius.circular(1),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkflowGlyphTile(
          glyph: WorkflowVisuals.triggerGlyph(workflow.trigger.kind),
          accent: WorkflowVisuals.triggerAccent,
          size: size,
        ),
        for (final step in shown) ...[
          link(),
          WorkflowGlyphTile(
            glyph: WorkflowVisuals.stepGlyph(step.kind),
            accent: WorkflowVisuals.stepAccent(step.kind),
            size: size,
          ),
        ],
        if (extra > 0) ...[
          link(),
          Container(
            height: size,
            constraints: BoxConstraints(minWidth: size),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: palette.sunken,
              borderRadius: BorderRadius.circular(size * 0.3),
            ),
            child: Text(
              '+$extra',
              style: DashboardType.caption(palette).copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _WorkflowCard extends StatelessWidget {
  const _WorkflowCard({
    super.key,
    required this.workflow,
    required this.manager,
    required this.onOpen,
    required this.onRunNow,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Workflow workflow;
  final WorkflowManager manager;
  final VoidCallback onOpen;
  final VoidCallback onRunNow;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final last = manager.log.latestFor(workflow.id);
    final running = manager.scheduler.isRunning(workflow.id);
    final next = manager.scheduler.nextRunOf(workflow);
    final steps = workflow.steps.length;
    final summary = [
      describeWorkflowTrigger(workflow.trigger),
      if (steps == 1)
        LocaleKeys.workflows_card_oneStep.tr()
      else
        LocaleKeys.workflows_card_steps.tr(args: ['$steps']),
    ].join(' · ');
    final status = running
        ? LocaleKeys.workflows_card_running.tr()
        : last == null
            ? LocaleKeys.workflows_card_neverRun.tr()
            : '${WorkflowVisuals.runStatusName(last.status)} · '
                '${LocaleKeys.workflows_card_lastRun.tr(
                args: [
                  describeWorkflowTime(last.startedAt),
                ],
              )}';
    final statusAccent = running
        ? DashboardAccent.blue
        : last == null
            ? DashboardAccent.neutral
            : WorkflowVisuals.runAccent(last.status);
    return WorkflowSurface(
      onTap: onOpen,
      semanticLabel: _nameOf(workflow),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          _Chain(workflow: workflow),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _nameOf(workflow),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.body(palette).copyWith(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!workflow.isComplete) ...[
                      const SizedBox(width: 8),
                      WorkflowPill(
                        label: LocaleKeys.workflows_card_needsSetup.tr(),
                        accent: DashboardAccent.amber,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      DashboardType.caption(palette).copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: palette.strongFor(statusAccent),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        [
                          status,
                          if (next != null && workflow.enabled)
                            LocaleKeys.workflows_card_nextRun
                                .tr(args: [describeWorkflowTime(next)]),
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.caption(palette)
                            .copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          WorkflowSwitch(
            key: ValueKey('workflow-switch-${workflow.id}'),
            value: workflow.enabled,
            semanticLabel: workflow.enabled
                ? LocaleKeys.workflows_card_turnOff.tr()
                : LocaleKeys.workflows_card_turnOn.tr(),
            onChanged: workflow.isComplete || workflow.enabled
                ? (value) => unawaited(manager.setEnabled(workflow, value))
                : null,
          ),
          const SizedBox(width: 4),
          Builder(
            builder: (anchor) => WorkflowIconButton(
              glyph: 'dots-three',
              tooltip: LocaleKeys.workflows_menu_more.tr(),
              onPressed: () => showAppMenuForWidget<void>(
                context: anchor,
                entries: [
                  AppMenuItem(
                    label: LocaleKeys.workflows_menu_open.tr(),
                    iconWidget: WorkspaceGlyph.named('pen', size: 16),
                    onSelected: onOpen,
                  ),
                  AppMenuItem(
                    label: LocaleKeys.workflows_menu_runNow.tr(),
                    iconWidget: WorkspaceGlyph.named('play', size: 16),
                    enabled: workflow.steps.isNotEmpty,
                    onSelected: onRunNow,
                  ),
                  AppMenuItem(
                    label: LocaleKeys.workflows_menu_duplicate.tr(),
                    iconWidget: WorkspaceGlyph.named('duplicate', size: 16),
                    onSelected: onDuplicate,
                  ),
                  const AppMenuSeparator(),
                  AppMenuItem(
                    label: LocaleKeys.workflows_menu_delete.tr(),
                    iconWidget: WorkspaceGlyph.named('trash', size: 16),
                    destructive: true,
                    onSelected: onDelete,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.creating, required this.onNew});

  final bool creating;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              WorkflowGlyphTile(
                glyph: 'clock',
                accent: WorkflowVisuals.triggerAccent,
                size: 44,
              ),
              _EmptyLink(),
              WorkflowGlyphTile(
                glyph: 'filter',
                accent: DashboardAccent.purple,
                size: 44,
              ),
              _EmptyLink(),
              WorkflowGlyphTile(
                glyph: 'file-plus',
                accent: DashboardAccent.blue,
                size: 44,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            LocaleKeys.workflows_empty_title.tr(),
            style: DashboardType.sectionTitle(palette).copyWith(fontSize: 18),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              LocaleKeys.workflows_empty_body.tr(),
              textAlign: TextAlign.center,
              style: DashboardType.sectionSubtitle(palette),
            ),
          ),
          const SizedBox(height: 18),
          WorkflowButton(
            label: LocaleKeys.workflows_empty_scratch.tr(),
            glyph: 'plus',
            kind: WorkflowButtonKind.primary,
            busy: creating,
            onPressed: onNew,
          ),
        ],
      ),
    );
  }
}

class _EmptyLink extends StatelessWidget {
  const _EmptyLink();

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Container(
      width: 28,
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: palette.border,
    );
  }
}

class _Templates extends StatelessWidget {
  const _Templates({required this.busy, required this.onUse});

  final bool busy;
  final ValueChanged<WorkflowTemplate> onUse;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          LocaleKeys.workflows_templates_title.tr(),
          style: DashboardType.sectionTitle(palette),
        ),
        const SizedBox(height: 4),
        Text(
          LocaleKeys.workflows_templates_body.tr(),
          style: DashboardType.caption(palette).copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 12.0;
            final columns = (constraints.maxWidth / 300).floor().clamp(1, 4);
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final template in workflowTemplates)
                  SizedBox(
                    width: width,
                    child: _TemplateCard(
                      key: ValueKey('workflow-template-${template.id}'),
                      template: template,
                      onUse: busy ? null : () => onUse(template),
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

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({super.key, required this.template, this.onUse});

  final WorkflowTemplate template;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final preview = template.build(template.title);
    return WorkflowSurface(
      onTap: onUse,
      semanticLabel: template.title,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Chain(workflow: preview, size: 28),
          const SizedBox(height: 12),
          Text(
            template.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DashboardType.body(palette).copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            template.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: DashboardType.caption(palette).copyWith(
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
