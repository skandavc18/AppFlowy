import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'workflow_style.dart';

/// A value shown as indented JSON in a quiet, selectable block.
class WorkflowDataPreview extends StatelessWidget {
  const WorkflowDataPreview({
    super.key,
    required this.value,
    this.maxLines = 14,
  });

  final Object? value;
  final int maxLines;

  static String format(Object? value) {
    if (value is String) {
      return value;
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } on Object {
      return '$value';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final lines = format(value).split('\n');
    final shown =
        lines.length > maxLines ? [...lines.take(maxLines), '…'] : lines;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        shown.join('\n'),
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Cascadia Code', 'Consolas', 'Menlo'],
          fontSize: 11.5,
          height: 1.45,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

/// Recent runs, newest first; of one workflow or of all of them.
class WorkflowRunList extends StatelessWidget {
  const WorkflowRunList({
    super.key,
    this.workflowId,
    this.padding = EdgeInsets.zero,
  });

  /// Null lists every workflow's runs, each labelled with its workflow.
  final String? workflowId;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final log = WorkflowRunLog.instance;
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final id = workflowId;
        final runs = id == null ? log.runs : log.runsFor(id);
        if (runs.isEmpty) {
          return _NoRuns(padding: padding);
        }
        return ListView.separated(
          padding: padding,
          itemCount: runs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => WorkflowRunTile(
            key: ValueKey(runs[index].id),
            run: runs[index],
            showWorkflow: id == null,
          ),
        );
      },
    );
  }
}

class _NoRuns extends StatelessWidget {
  const _NoRuns({required this.padding});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WorkflowGlyphTile(
                glyph: 'history',
                accent: WorkflowVisuals.triggerAccent,
                size: 44,
              ),
              const SizedBox(height: 12),
              Text(
                LocaleKeys.workflows_history_empty.tr(),
                style: DashboardType.sectionTitle(palette).copyWith(
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocaleKeys.workflows_history_emptyBody.tr(),
                textAlign: TextAlign.center,
                style: DashboardType.caption(palette).copyWith(fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One run: a summary line that opens into what each step did.
class WorkflowRunTile extends StatefulWidget {
  const WorkflowRunTile({
    super.key,
    required this.run,
    this.showWorkflow = false,
  });

  final WorkflowRun run;
  final bool showWorkflow;

  @override
  State<WorkflowRunTile> createState() => _WorkflowRunTileState();
}

class _WorkflowRunTileState extends State<WorkflowRunTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final run = widget.run;
    final duration = run.duration;
    final details = [
      WorkflowVisuals.causeName(run.cause),
      describeWorkflowTime(run.startedAt),
      if (duration != null)
        duration.inSeconds >= 1
            ? '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s'
            : LocaleKeys.workflows_history_duration
                .tr(args: ['${duration.inMilliseconds}']),
      if (run.status == WorkflowRunStatus.waiting && run.resumeAt != null)
        LocaleKeys.workflows_editor_runWaiting
            .tr(args: [describeWorkflowTime(run.resumeAt!)]),
    ].join(' · ');
    return WorkflowSurface(
      padding: EdgeInsets.zero,
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            hoverColor: palette.hover.withValues(alpha: 0.4),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  WorkflowPill(
                    label: WorkflowVisuals.runStatusName(run.status),
                    accent: WorkflowVisuals.runAccent(run.status),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.showWorkflow)
                          Text(
                            run.workflowName.isEmpty
                                ? LocaleKeys.workflows_untitled.tr()
                                : run.workflowName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashboardType.body(palette).copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashboardType.caption(palette)
                              .copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 140),
                    child: WorkspaceGlyph.named(
                      'caret-right',
                      size: 14,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (run.message.isNotEmpty && !_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 11),
              child: Text(
                run.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.caption(
                  palette,
                  color: run.status == WorkflowRunStatus.failed
                      ? palette.strongFor(WorkflowVisuals.runAccent(run.status))
                      : null,
                ).copyWith(fontSize: 12),
              ),
            ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _RunDetails(run: run),
            ),
        ],
      ),
    );
  }
}

class _RunDetails extends StatelessWidget {
  const _RunDetails({required this.run});

  final WorkflowRun run;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (run.message.isNotEmpty) ...[
          Text(
            run.message,
            style: DashboardType.body(palette).copyWith(fontSize: 12.5),
          ),
          const SizedBox(height: 10),
        ],
        if (run.trigger != null) ...[
          WorkflowLabel(LocaleKeys.workflows_history_trigger.tr()),
          WorkflowDataPreview(value: run.trigger, maxLines: 10),
          const SizedBox(height: 12),
        ],
        for (final step in run.steps) ...[
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: palette.strongFor(
                    WorkflowVisuals.stepStatusAccent(step.status),
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              if (step.kind != null) ...[
                WorkspaceGlyph.named(
                  WorkflowVisuals.stepGlyph(step.kind!),
                  size: 14,
                  color: palette.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  step.label.isNotEmpty
                      ? step.label
                      : step.kind == null
                          ? step.stepId
                          : WorkflowVisuals.stepName(step.kind!),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.body(palette).copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                WorkflowVisuals.stepStatusName(step.status),
                style: DashboardType.caption(palette).copyWith(fontSize: 11.5),
              ),
              if (step.durationMs > 0) ...[
                const SizedBox(width: 6),
                Text(
                  LocaleKeys.workflows_history_duration
                      .tr(args: ['${step.durationMs}']),
                  style:
                      DashboardType.caption(palette).copyWith(fontSize: 11.5),
                ),
              ],
            ],
          ),
          if (step.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Text(
                step.message,
                style: DashboardType.caption(
                  palette,
                  color: step.status == WorkflowStepStatus.failed
                      ? palette.strongFor(
                          WorkflowVisuals.stepStatusAccent(step.status),
                        )
                      : null,
                ).copyWith(fontSize: 12),
              ),
            ),
          if (step.output != null)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 6),
              child: WorkflowDataPreview(value: step.output, maxLines: 8),
            ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
