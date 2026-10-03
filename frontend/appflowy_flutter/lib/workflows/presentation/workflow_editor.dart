import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workflows/application/workflow_format.dart';
import 'package:appflowy/workflows/application/workflow_manager.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workflows/application/workflow_services.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'workflow_forms.dart';
import 'workflow_history.dart';
import 'workflow_inputs.dart';
import 'workflow_style.dart';

const _triggerNode = '__trigger';

/// Builds one workflow: its trigger and steps on the left, the selected
/// node's settings on the right, and its runs a tab away. Every change is
/// saved as it is made.
class WorkflowEditor extends StatefulWidget {
  const WorkflowEditor({
    super.key,
    required this.workflowId,
    required this.onClose,
    required this.onOpen,
    this.manager,
  });

  final String workflowId;
  final VoidCallback onClose;

  /// Opens another workflow (a duplicate) in this editor's place.
  final ValueChanged<String> onOpen;
  final WorkflowManager? manager;

  @override
  State<WorkflowEditor> createState() => _WorkflowEditorState();
}

class _WorkflowEditorState extends State<WorkflowEditor> {
  WorkflowManager get _manager => widget.manager ?? WorkflowManager.instance;

  Workflow? _draft;
  String _selected = _triggerNode;
  Timer? _saveTimer;
  bool _dirty = false;
  bool _runsTab = false;
  bool _running = false;
  bool _testing = false;
  bool _listening = false;
  String _testError = '';
  bool _testStopped = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _draft = _manager.store.byId(widget.workflowId);
    _manager.addListener(_onChanged);
    _manager.store.addListener(_onChanged);
    _manager.scheduler.addListener(_onChanged);
  }

  @override
  void dispose() {
    _manager.removeListener(_onChanged);
    _manager.store.removeListener(_onChanged);
    _manager.scheduler.removeListener(_onChanged);
    final draft = _draft;
    if (_listening && draft != null) {
      _manager.cancelTriggerSample(draft);
    }
    unawaited(_flush());
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) {
      return;
    }
    final stored = _manager.store.byId(widget.workflowId);
    if (stored == null) {
      if (!_closing && _manager.store.isLoaded) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onClose());
      }
      return;
    }
    final draft = _draft;
    setState(() {
      _draft = draft == null
          ? stored
          : draft.copyWith(
              enabled: stored.enabled,
              enabledAt: stored.enabledAt,
            );
    });
  }

  void _update(Workflow next) {
    setState(() => _draft = next);
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final draft = _draft;
    if (!_dirty || draft == null) {
      return;
    }
    _dirty = false;
    final stored = _manager.store.byId(draft.id);
    if (stored == null) {
      return;
    }
    await _manager.save(
      draft.copyWith(enabled: stored.enabled, enabledAt: stored.enabledAt),
    );
  }

  void _select(String node) {
    if (node == _selected) {
      return;
    }
    final draft = _draft;
    if (_listening && draft != null) {
      _manager.cancelTriggerSample(draft);
    }
    setState(() {
      _selected = node;
      _testError = '';
      _testStopped = false;
    });
  }

  Future<void> _setEnabled(bool value) async {
    await _flush();
    final draft = _draft;
    if (draft == null) {
      return;
    }
    await _manager.setEnabled(draft, value);
  }

  Future<void> _runNow() async {
    await _flush();
    final draft = _draft;
    if (draft == null || _running) {
      return;
    }
    setState(() => _running = true);
    final run = await _manager.runNow(_manager.store.byId(draft.id) ?? draft);
    if (!mounted) {
      return;
    }
    setState(() => _running = false);
    final message = switch (run?.status) {
      WorkflowRunStatus.succeeded =>
        LocaleKeys.workflows_editor_runSucceeded.tr(),
      WorkflowRunStatus.failed =>
        LocaleKeys.workflows_editor_runFailed.tr(args: [run!.message]),
      WorkflowRunStatus.filtered =>
        LocaleKeys.workflows_editor_runFiltered.tr(),
      WorkflowRunStatus.waiting => LocaleKeys.workflows_editor_runWaiting.tr(
          args: [describeWorkflowTime(run!.resumeAt ?? DateTime.now())],
        ),
      _ => LocaleKeys.workflows_editor_runStarted.tr(),
    };
    showSnackBarMessage(context, message);
  }

  Future<void> _testTrigger() async {
    await _flush();
    final draft = _draft;
    if (draft == null) {
      return;
    }
    setState(() {
      _testing = true;
      _testError = '';
      _listening = draft.trigger.kind == WorkflowTriggerKind.webhook;
    });
    try {
      final sample = await _manager.sampleTrigger(draft);
      if (!mounted) {
        return;
      }
      final latest = _draft;
      if (latest != null) {
        _update(
          latest.withSample(
            Workflow.triggerSampleKey,
            previewWorkflowValue(workflowJsonSafe(sample)),
          ),
        );
      }
    } on StateError {
      // Cancelled while waiting for a webhook.
    } on WorkflowStepException catch (error) {
      _testError = error.message;
    } on Object catch (error) {
      _testError = '$error';
    } finally {
      if (mounted) {
        setState(() {
          _testing = false;
          _listening = false;
        });
      }
    }
  }

  Future<void> _testStep(WorkflowStep step) async {
    await _flush();
    final draft = _draft;
    if (draft == null) {
      return;
    }
    setState(() {
      _testing = true;
      _testError = '';
      _testStopped = false;
    });
    final result = await _manager.testStep(draft, step);
    if (!mounted) {
      return;
    }
    setState(() {
      _testing = false;
      _testStopped = result.stopped;
      _testError = result.error;
    });
    final latest = _draft;
    if (!result.isError && !result.stopped && latest != null) {
      _update(latest.withSample(step.id, previewWorkflowValue(result.output)));
    }
  }

  Future<void> _addStep(BuildContext anchor, int index) async {
    final draft = _draft;
    if (draft == null || draft.steps.length >= Workflow.maximumSteps) {
      return;
    }
    AppMenuItem item(WorkflowStepKind kind) => AppMenuItem(
          label: WorkflowVisuals.stepName(kind),
          subtitle: WorkflowVisuals.stepAbout(kind),
          iconWidget: WorkflowGlyphTile(
            glyph: WorkflowVisuals.stepGlyph(kind),
            accent: WorkflowVisuals.stepAccent(kind),
            size: 20,
            radius: 6,
          ),
          value: kind,
        );
    final kind = await showAppMenuForWidget<WorkflowStepKind>(
      context: anchor,
      placement: AppMenuPlacement.below,
      width: 320,
      maxHeight: 560,
      entries: [
        AppMenuHeader(LocaleKeys.workflows_step_group_workspace.tr()),
        item(WorkflowStepKind.createPage),
        item(WorkflowStepKind.appendToPage),
        item(WorkflowStepKind.addRow),
        AppMenuHeader(LocaleKeys.workflows_step_group_alerts.tr()),
        item(WorkflowStepKind.notify),
        item(WorkflowStepKind.reminder),
        AppMenuHeader(LocaleKeys.workflows_step_group_web.tr()),
        item(WorkflowStepKind.httpRequest),
        AppMenuHeader(LocaleKeys.workflows_step_group_logic.tr()),
        item(WorkflowStepKind.filter),
        item(WorkflowStepKind.delay),
        item(WorkflowStepKind.formatter),
        item(WorkflowStepKind.code),
        item(WorkflowStepKind.storage),
      ],
    );
    final latest = _draft;
    if (kind == null || latest == null || !mounted) {
      return;
    }
    final step = WorkflowStep.create(latest.nextStepId(), kind);
    _update(latest.insertStep(index, step));
    _select(step.id);
  }

  Future<void> _workflowMenu(BuildContext anchor) async {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    await showAppMenuForWidget<void>(
      context: anchor,
      entries: [
        AppMenuItem(
          label: LocaleKeys.workflows_menu_duplicate.tr(),
          iconWidget: WorkspaceGlyph.named('duplicate', size: 16),
          onSelected: () => unawaited(_duplicate()),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.workflows_menu_delete.tr(),
          iconWidget: WorkspaceGlyph.named('trash', size: 16),
          destructive: true,
          onSelected: () => unawaited(_delete()),
        ),
      ],
    );
  }

  Future<void> _duplicate() async {
    await _flush();
    final draft = _draft;
    if (draft == null) {
      return;
    }
    final copy = await _manager.duplicate(
      draft,
      name: LocaleKeys.workflows_copyName.tr(args: [_nameOf(draft)]),
    );
    if (mounted) {
      widget.onOpen(copy.id);
    }
  }

  Future<void> _delete() async {
    final draft = _draft;
    if (draft == null) {
      return;
    }
    await showCancelAndDeleteDialog(
      context: context,
      title: LocaleKeys.workflows_delete_title.tr(args: [_nameOf(draft)]),
      description: LocaleKeys.workflows_delete_description.tr(),
      confirmLabel: LocaleKeys.workflows_menu_delete.tr(),
      closeOnAction: true,
      onDelete: () {
        _dirty = false;
        _saveTimer?.cancel();
        _closing = true;
        unawaited(
          _manager.delete(draft).then((_) {
            if (mounted) {
              widget.onClose();
            }
          }),
        );
      },
    );
  }

  static String _nameOf(Workflow workflow) => workflow.name.trim().isEmpty
      ? LocaleKeys.workflows_untitled.tr()
      : workflow.name;

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft == null) {
      return const SizedBox.shrink();
    }
    final palette = DashboardPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopBar(
          workflow: draft,
          running: _running || _manager.scheduler.isRunning(draft.id),
          onBack: () async {
            await _flush();
            widget.onClose();
          },
          onRename: (name) => _update(draft.copyWith(name: name)),
          onRunNow: draft.steps.isEmpty ? null : () => unawaited(_runNow()),
          onEnabled: draft.isComplete || draft.enabled
              ? (value) => unawaited(_setEnabled(value))
              : null,
          onMenu: (anchor) => unawaited(_workflowMenu(anchor)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            WorkflowSegmented<bool>(
              values: const [false, true],
              selected: _runsTab,
              labelOf: (runs) => runs
                  ? LocaleKeys.workflows_editor_tabs_runs.tr()
                  : LocaleKeys.workflows_editor_tabs_editor.tr(),
              onChanged: (runs) => setState(() => _runsTab = runs),
            ),
            const SizedBox(width: 12),
            if (!draft.isComplete && !_runsTab)
              Expanded(
                child: WorkflowHint(
                  LocaleKeys.workflows_editor_incomplete.tr(),
                  glyph: 'warning',
                  accent: DashboardAccent.amber,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _runsTab
              ? WorkflowRunList(
                  workflowId: draft.id,
                  padding: const EdgeInsets.only(bottom: 24),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 880;
                    final canvas = _Canvas(
                      workflow: draft,
                      selected: _selected,
                      onSelect: _select,
                      onAdd: (anchor, index) =>
                          unawaited(_addStep(anchor, index)),
                    );
                    final inspector = _inspector(draft);
                    if (!wide) {
                      return SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            canvas,
                            const SizedBox(height: 20),
                            inspector,
                          ],
                        ),
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: palette.sunken.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: DashboardGridBackdrop(
                              palette: palette,
                              step: 22,
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 28,
                                ),
                                child: canvas,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 400,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 32),
                            child: inspector,
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _inspector(Workflow draft) {
    if (_selected == _triggerNode) {
      return _TriggerInspector(
        key: ValueKey('trigger-${draft.trigger.kind.name}'),
        workflow: draft,
        webhookAddress: _manager.webhookAddress(draft),
        testing: _testing,
        listening: _listening,
        error: _testError,
        onChanged: (trigger) {
          final kindChanged = trigger.kind != draft.trigger.kind;
          var next = draft.copyWith(trigger: trigger);
          if (kindChanged) {
            next = next.copyWith(
              samples: {
                for (final entry in draft.samples.entries)
                  if (entry.key != Workflow.triggerSampleKey)
                    entry.key: entry.value,
              },
            );
          }
          _update(next);
        },
        onTest: () => unawaited(_testTrigger()),
        onCancelTest: () => _manager.cancelTriggerSample(draft),
      );
    }
    final index = draft.indexOfStep(_selected);
    if (index < 0) {
      return const SizedBox.shrink();
    }
    final step = draft.steps[index];
    return _StepInspector(
      key: ValueKey('step-${step.id}'),
      workflow: draft,
      step: step,
      number: index + 2,
      testing: _testing,
      error: _testError,
      stopped: _testStopped,
      storage: _manager.store.storage,
      onChanged: (next) => _update(draft.replaceStep(next)),
      onTest: () => unawaited(_testStep(step)),
      onMove: (offset) => _update(draft.moveStep(step.id, offset)),
      onDuplicate: () {
        final copy = step.withId(draft.nextStepId());
        _update(draft.insertStep(index + 1, copy));
        _select(copy.id);
      },
      onDelete: () {
        _update(draft.removeStep(step.id));
        _select(_triggerNode);
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.workflow,
    required this.running,
    required this.onBack,
    required this.onRename,
    required this.onRunNow,
    required this.onEnabled,
    required this.onMenu,
  });

  final Workflow workflow;
  final bool running;
  final VoidCallback onBack;
  final ValueChanged<String> onRename;
  final VoidCallback? onRunNow;
  final ValueChanged<bool>? onEnabled;
  final ValueChanged<BuildContext> onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Row(
      children: [
        WorkflowIconButton(
          glyph: 'arrow-left',
          tooltip: LocaleKeys.workflows_editor_back.tr(),
          onPressed: onBack,
        ),
        const SizedBox(width: 8),
        WorkflowGlyphTile(
          glyph: WorkflowVisuals.triggerGlyph(workflow.trigger.kind),
          accent: WorkflowVisuals.triggerAccent,
          size: 34,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _NameField(
            key: ValueKey('name-${workflow.id}'),
            value: workflow.name,
            onChanged: onRename,
          ),
        ),
        const SizedBox(width: 12),
        if (running)
          WorkflowPill(
            label: LocaleKeys.workflows_card_running.tr(),
            accent: DashboardAccent.blue,
          )
        else if (!workflow.isComplete)
          WorkflowPill(
            label: LocaleKeys.workflows_card_needsSetup.tr(),
            accent: DashboardAccent.amber,
          ),
        const SizedBox(width: 10),
        WorkflowButton(
          label: LocaleKeys.workflows_editor_runNow.tr(),
          glyph: 'play',
          busy: running,
          onPressed: onRunNow,
        ),
        const SizedBox(width: 12),
        Text(
          workflow.enabled
              ? LocaleKeys.workflows_editor_on.tr()
              : LocaleKeys.workflows_editor_off.tr(),
          style: DashboardType.body(palette, color: palette.textSecondary)
              .copyWith(fontSize: 12.5),
        ),
        const SizedBox(width: 8),
        WorkflowSwitch(
          key: const ValueKey('workflow-editor-enabled'),
          value: workflow.enabled,
          onChanged: onEnabled,
          semanticLabel: workflow.enabled
              ? LocaleKeys.workflows_card_turnOff.tr()
              : LocaleKeys.workflows_card_turnOn.tr(),
        ),
        const SizedBox(width: 6),
        Builder(
          builder: (anchor) => WorkflowIconButton(
            glyph: 'dots-three',
            tooltip: LocaleKeys.workflows_menu_more.tr(),
            onPressed: () => onMenu(anchor),
          ),
        ),
      ],
    );
  }
}

class _NameField extends StatefulWidget {
  const _NameField({super.key, required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return TextEntryShortcuts(
      child: TextField(
        key: const ValueKey('workflow-name-field'),
        controller: _controller,
        onChanged: widget.onChanged,
        style: DashboardType.title(palette, size: 20),
        cursorColor: palette.accent,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: LocaleKeys.workflows_editor_namePlaceholder.tr(),
          hintStyle: DashboardType.title(palette, size: 20).copyWith(
            color: palette.textMuted,
          ),
        ),
      ),
    );
  }
}

/// The trigger and its steps as a vertical flow, with a way in between each.
class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.workflow,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
  });

  final Workflow workflow;
  final String selected;
  final ValueChanged<String> onSelect;
  final void Function(BuildContext anchor, int index) onAdd;

  @override
  Widget build(BuildContext context) {
    final trigger = workflow.trigger;
    final triggerSummary = describeWorkflowTrigger(trigger);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _FlowNode(
              key: const ValueKey('workflow-node-trigger'),
              number: 1,
              eyebrow: LocaleKeys.workflows_trigger_when.tr(),
              title: WorkflowVisuals.triggerName(trigger.kind),
              subtitle:
                  triggerSummary == WorkflowVisuals.triggerName(trigger.kind)
                      ? WorkflowVisuals.triggerAbout(trigger.kind)
                      : triggerSummary,
              glyph: WorkflowVisuals.triggerGlyph(trigger.kind),
              accent: WorkflowVisuals.triggerAccent,
              selected: selected == _triggerNode,
              needsSetup: !trigger.isConfigured,
              onTap: () => onSelect(_triggerNode),
            ),
            for (var index = 0; index < workflow.steps.length; index++) ...[
              _Connector(onAdd: (anchor) => onAdd(anchor, index)),
              _FlowNode(
                key: ValueKey('workflow-node-${workflow.steps[index].id}'),
                number: index + 2,
                eyebrow: LocaleKeys.workflows_trigger_then.tr(),
                title: WorkflowVisuals.stepTitle(workflow.steps[index]),
                subtitle: describeWorkflowStep(workflow.steps[index]).isEmpty
                    ? WorkflowVisuals.stepAbout(workflow.steps[index].kind)
                    : describeWorkflowStep(workflow.steps[index]),
                glyph: WorkflowVisuals.stepGlyph(workflow.steps[index].kind),
                accent: WorkflowVisuals.stepAccent(workflow.steps[index].kind),
                selected: selected == workflow.steps[index].id,
                needsSetup: !workflow.steps[index].isConfigured,
                onTap: () => onSelect(workflow.steps[index].id),
              ),
            ],
            _Connector(
              last: true,
              onAdd: (anchor) => onAdd(anchor, workflow.steps.length),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowNode extends StatelessWidget {
  const _FlowNode({
    super.key,
    required this.number,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.glyph,
    required this.accent,
    required this.selected,
    required this.needsSetup,
    required this.onTap,
  });

  final int number;
  final String eyebrow;
  final String title;
  final String subtitle;
  final String glyph;
  final DashboardAccent accent;
  final bool selected;
  final bool needsSetup;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return WorkflowSurface(
      onTap: onTap,
      selected: selected,
      semanticLabel: '$number. $title',
      highlight: needsSetup
          ? palette.strongFor(DashboardAccent.amber).withValues(alpha: 0.6)
          : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          WorkflowGlyphTile(glyph: glyph, accent: accent, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$number. ${eyebrow.toUpperCase()}',
                  style: DashboardType.sectionLabel(palette).copyWith(
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.body(palette).copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.caption(palette).copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          if (needsSetup) ...[
            const SizedBox(width: 8),
            WorkflowPill(
              label: LocaleKeys.workflows_card_needsSetup.tr(),
              accent: DashboardAccent.amber,
            ),
          ],
        ],
      ),
    );
  }
}

/// The line between two nodes, with the way to add a step there.
class _Connector extends StatelessWidget {
  const _Connector({required this.onAdd, this.last = false});

  final ValueChanged<BuildContext> onAdd;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final line = Container(
      width: 2,
      height: last ? 14 : 12,
      color: palette.border.withValues(alpha: 0.8),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        Builder(
          builder: (anchor) => last
              ? WorkflowButton(
                  key: const ValueKey('workflow-add-step'),
                  label: LocaleKeys.workflows_step_add.tr(),
                  glyph: 'plus',
                  onPressed: () => onAdd(anchor),
                )
              : Tooltip(
                  message: LocaleKeys.workflows_step_add.tr(),
                  child: _PlusButton(onPressed: () => onAdd(anchor)),
                ),
        ),
        if (!last) line,
      ],
    );
  }
}

class _PlusButton extends StatefulWidget {
  const _PlusButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_PlusButton> createState() => _PlusButtonState();
}

class _PlusButtonState extends State<_PlusButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Semantics(
      button: true,
      label: LocaleKeys.workflows_step_add.tr(),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _hovered = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? palette.accent : palette.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: _hovered
                    ? palette.accent
                    : palette.border.withValues(alpha: 0.9),
              ),
              boxShadow: palette.cardShadow(),
            ),
            child: WorkspaceGlyph.named(
              'plus',
              size: 14,
              color: _hovered ? palette.onAccent : palette.textSecondary,
              role: WorkspaceGlyphRole.preserveInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The panel's heading: what is selected, and what it is for.
class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({
    required this.glyph,
    required this.accent,
    required this.eyebrow,
    required this.title,
    required this.about,
    this.trailing,
  });

  final String glyph;
  final DashboardAccent accent;
  final String eyebrow;
  final String title;
  final String about;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WorkflowGlyphTile(glyph: glyph, accent: accent, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: DashboardType.sectionLabel(palette).copyWith(
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(title, style: DashboardType.sectionTitle(palette)),
              const SizedBox(height: 2),
              Text(
                about,
                style: DashboardType.caption(palette).copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Test button, its warning, and what the test produced.
class _TestPanel extends StatelessWidget {
  const _TestPanel({
    required this.label,
    required this.testing,
    required this.error,
    required this.sample,
    required this.onTest,
    this.warning,
    this.waitingLabel,
    this.onCancel,
    this.stopped = false,
  });

  final String label;
  final bool testing;
  final String error;
  final Object? sample;
  final VoidCallback onTest;
  final String? warning;

  /// Shown while [testing] instead of a spinner on the button.
  final String? waitingLabel;
  final VoidCallback? onCancel;
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  LocaleKeys.workflows_editor_sample.tr(),
                  style: DashboardType.eyebrow(palette),
                ),
              ),
              if (testing && waitingLabel != null && onCancel != null)
                WorkflowButton(
                  label: LocaleKeys.workflows_editor_cancel.tr(),
                  kind: WorkflowButtonKind.quiet,
                  onPressed: onCancel,
                )
              else
                WorkflowButton(
                  key: const ValueKey('workflow-test-button'),
                  label: label,
                  glyph: 'play',
                  busy: testing,
                  onPressed: onTest,
                ),
            ],
          ),
          if (warning != null) ...[
            const SizedBox(height: 8),
            WorkflowHint(warning!, glyph: 'info'),
          ],
          const SizedBox(height: 10),
          if (testing && waitingLabel != null)
            Row(
              children: [
                SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    waitingLabel!,
                    style: DashboardType.body(palette).copyWith(fontSize: 12.5),
                  ),
                ),
              ],
            )
          else if (error.isNotEmpty)
            WorkflowHint(
              stopped
                  ? '${LocaleKeys.workflows_editor_stopped.tr()}: $error'
                  : '${LocaleKeys.workflows_editor_testFailed.tr()}: $error',
              glyph: stopped ? 'filter' : 'warning',
              accent: stopped ? DashboardAccent.amber : DashboardAccent.red,
            )
          else if (sample == null)
            WorkflowHint(LocaleKeys.workflows_editor_noSample.tr())
          else
            WorkflowDataPreview(value: sample),
        ],
      ),
    );
  }
}

class _TriggerInspector extends StatelessWidget {
  const _TriggerInspector({
    super.key,
    required this.workflow,
    required this.webhookAddress,
    required this.testing,
    required this.listening,
    required this.error,
    required this.onChanged,
    required this.onTest,
    required this.onCancelTest,
  });

  final Workflow workflow;
  final String webhookAddress;
  final bool testing;
  final bool listening;
  final String error;
  final ValueChanged<WorkflowTrigger> onChanged;
  final VoidCallback onTest;
  final VoidCallback onCancelTest;

  @override
  Widget build(BuildContext context) {
    final trigger = workflow.trigger;
    return WorkflowSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _InspectorHeader(
            glyph: WorkflowVisuals.triggerGlyph(trigger.kind),
            accent: WorkflowVisuals.triggerAccent,
            eyebrow: '1. ${LocaleKeys.workflows_trigger_when.tr()}',
            title: WorkflowVisuals.triggerName(trigger.kind),
            about: LocaleKeys.workflows_trigger_pick.tr(),
          ),
          const SizedBox(height: 18),
          WorkflowTriggerForm(
            trigger: trigger,
            webhookAddress: webhookAddress,
            onChanged: onChanged,
          ),
          const SizedBox(height: 18),
          _TestPanel(
            label: LocaleKeys.workflows_editor_testTrigger.tr(),
            testing: testing,
            error: error,
            sample: workflow.samples[Workflow.triggerSampleKey],
            onTest: onTest,
            waitingLabel:
                listening ? LocaleKeys.workflows_editor_listening.tr() : null,
            onCancel: listening ? onCancelTest : null,
          ),
        ],
      ),
    );
  }
}

class _StepInspector extends StatelessWidget {
  const _StepInspector({
    super.key,
    required this.workflow,
    required this.step,
    required this.number,
    required this.testing,
    required this.error,
    required this.stopped,
    required this.storage,
    required this.onChanged,
    required this.onTest,
    required this.onMove,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Workflow workflow;
  final WorkflowStep step;
  final int number;
  final bool testing;
  final String error;
  final bool stopped;
  final Map<String, Object?> storage;
  final ValueChanged<WorkflowStep> onChanged;
  final VoidCallback onTest;
  final ValueChanged<int> onMove;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final index = workflow.indexOfStep(step.id);
    final groups = workflowDataGroups(
      workflow,
      beforeStepId: step.id,
      storage: storage,
    );
    return WorkflowSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _InspectorHeader(
            glyph: WorkflowVisuals.stepGlyph(step.kind),
            accent: WorkflowVisuals.stepAccent(step.kind),
            eyebrow: '$number. ${LocaleKeys.workflows_trigger_then.tr()}',
            title: WorkflowVisuals.stepName(step.kind),
            about: WorkflowVisuals.stepAbout(step.kind),
            trailing: Builder(
              builder: (anchor) => WorkflowIconButton(
                glyph: 'dots-three',
                tooltip: LocaleKeys.workflows_menu_more.tr(),
                onPressed: () => showAppMenuForWidget<void>(
                  context: anchor,
                  entries: [
                    AppMenuItem(
                      label: LocaleKeys.workflows_step_moveUp.tr(),
                      iconWidget: WorkspaceGlyph.named('arrow-left', size: 16),
                      enabled: index > 0,
                      onSelected: () => onMove(-1),
                    ),
                    AppMenuItem(
                      label: LocaleKeys.workflows_step_moveDown.tr(),
                      iconWidget: WorkspaceGlyph.named('arrow-right', size: 16),
                      enabled: index < workflow.steps.length - 1,
                      onSelected: () => onMove(1),
                    ),
                    AppMenuItem(
                      label: LocaleKeys.workflows_step_duplicate.tr(),
                      iconWidget: WorkspaceGlyph.named('duplicate', size: 16),
                      enabled: workflow.steps.length < Workflow.maximumSteps,
                      onSelected: onDuplicate,
                    ),
                    const AppMenuSeparator(),
                    AppMenuItem(
                      label: LocaleKeys.workflows_step_delete.tr(),
                      iconWidget: WorkspaceGlyph.named('trash', size: 16),
                      destructive: true,
                      onSelected: onDelete,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          WorkflowTextInput(
            label: LocaleKeys.workflows_step_rename.tr(),
            hint: WorkflowVisuals.stepName(step.kind),
            value: step.label,
            onChanged: (text) => onChanged(step.withLabel(text)),
          ),
          const SizedBox(height: 16),
          WorkflowStepForm(
            step: step,
            dataGroups: groups,
            onChanged: onChanged,
          ),
          const SizedBox(height: 18),
          _TestPanel(
            label: LocaleKeys.workflows_editor_testStep.tr(),
            testing: testing,
            error: error,
            stopped: stopped,
            sample: workflow.samples[step.id],
            onTest: onTest,
            warning: step.kind.isUtility
                ? null
                : LocaleKeys.workflows_editor_testWarning.tr(),
          ),
        ],
      ),
    );
  }
}
