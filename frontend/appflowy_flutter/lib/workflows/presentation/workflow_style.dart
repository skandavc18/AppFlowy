import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Names, glyphs and colours for every kind of trigger and step.
abstract final class WorkflowVisuals {
  static String triggerGlyph(WorkflowTriggerKind kind) => switch (kind) {
        WorkflowTriggerKind.manual => 'cursor',
        WorkflowTriggerKind.schedule => 'clock',
        WorkflowTriggerKind.webhook => 'link-simple',
        WorkflowTriggerKind.feed => 'article',
        WorkflowTriggerKind.databaseRow => 'table',
        WorkflowTriggerKind.newPage => 'file-text',
        WorkflowTriggerKind.appStart => 'rocket',
      };

  static String stepGlyph(WorkflowStepKind kind) => switch (kind) {
        WorkflowStepKind.httpRequest => 'globe',
        WorkflowStepKind.createPage => 'file-plus',
        WorkflowStepKind.appendToPage => 'pen',
        WorkflowStepKind.addRow => 'table',
        WorkflowStepKind.notify => 'bell-ringing',
        WorkflowStepKind.reminder => 'alarm',
        WorkflowStepKind.filter => 'filter',
        WorkflowStepKind.delay => 'hourglass',
        WorkflowStepKind.formatter => 'text',
        WorkflowStepKind.code => 'code',
        WorkflowStepKind.storage => 'database',
      };

  static const DashboardAccent triggerAccent = DashboardAccent.orange;

  static DashboardAccent stepAccent(WorkflowStepKind kind) => switch (kind) {
        WorkflowStepKind.createPage ||
        WorkflowStepKind.appendToPage ||
        WorkflowStepKind.addRow =>
          DashboardAccent.blue,
        WorkflowStepKind.notify ||
        WorkflowStepKind.reminder =>
          DashboardAccent.pink,
        WorkflowStepKind.httpRequest => DashboardAccent.teal,
        _ => DashboardAccent.purple,
      };

  static String triggerName(WorkflowTriggerKind kind) => switch (kind) {
        WorkflowTriggerKind.manual =>
          LocaleKeys.workflows_trigger_kind_manual.tr(),
        WorkflowTriggerKind.schedule =>
          LocaleKeys.workflows_trigger_kind_schedule.tr(),
        WorkflowTriggerKind.webhook =>
          LocaleKeys.workflows_trigger_kind_webhook.tr(),
        WorkflowTriggerKind.feed => LocaleKeys.workflows_trigger_kind_feed.tr(),
        WorkflowTriggerKind.databaseRow =>
          LocaleKeys.workflows_trigger_kind_databaseRow.tr(),
        WorkflowTriggerKind.newPage =>
          LocaleKeys.workflows_trigger_kind_newPage.tr(),
        WorkflowTriggerKind.appStart =>
          LocaleKeys.workflows_trigger_kind_appStart.tr(),
      };

  static String triggerAbout(WorkflowTriggerKind kind) => switch (kind) {
        WorkflowTriggerKind.manual =>
          LocaleKeys.workflows_trigger_about_manual.tr(),
        WorkflowTriggerKind.schedule =>
          LocaleKeys.workflows_trigger_about_schedule.tr(),
        WorkflowTriggerKind.webhook =>
          LocaleKeys.workflows_trigger_about_webhook.tr(),
        WorkflowTriggerKind.feed =>
          LocaleKeys.workflows_trigger_about_feed.tr(),
        WorkflowTriggerKind.databaseRow =>
          LocaleKeys.workflows_trigger_about_databaseRow.tr(),
        WorkflowTriggerKind.newPage =>
          LocaleKeys.workflows_trigger_about_newPage.tr(),
        WorkflowTriggerKind.appStart =>
          LocaleKeys.workflows_trigger_about_appStart.tr(),
      };

  static String stepName(WorkflowStepKind kind) => switch (kind) {
        WorkflowStepKind.httpRequest =>
          LocaleKeys.workflows_step_kind_httpRequest.tr(),
        WorkflowStepKind.createPage =>
          LocaleKeys.workflows_step_kind_createPage.tr(),
        WorkflowStepKind.appendToPage =>
          LocaleKeys.workflows_step_kind_appendToPage.tr(),
        WorkflowStepKind.addRow => LocaleKeys.workflows_step_kind_addRow.tr(),
        WorkflowStepKind.notify => LocaleKeys.workflows_step_kind_notify.tr(),
        WorkflowStepKind.reminder =>
          LocaleKeys.workflows_step_kind_reminder.tr(),
        WorkflowStepKind.filter => LocaleKeys.workflows_step_kind_filter.tr(),
        WorkflowStepKind.delay => LocaleKeys.workflows_step_kind_delay.tr(),
        WorkflowStepKind.formatter =>
          LocaleKeys.workflows_step_kind_formatter.tr(),
        WorkflowStepKind.code => LocaleKeys.workflows_step_kind_code.tr(),
        WorkflowStepKind.storage => LocaleKeys.workflows_step_kind_storage.tr(),
      };

  static String stepAbout(WorkflowStepKind kind) => switch (kind) {
        WorkflowStepKind.httpRequest =>
          LocaleKeys.workflows_step_about_httpRequest.tr(),
        WorkflowStepKind.createPage =>
          LocaleKeys.workflows_step_about_createPage.tr(),
        WorkflowStepKind.appendToPage =>
          LocaleKeys.workflows_step_about_appendToPage.tr(),
        WorkflowStepKind.addRow => LocaleKeys.workflows_step_about_addRow.tr(),
        WorkflowStepKind.notify => LocaleKeys.workflows_step_about_notify.tr(),
        WorkflowStepKind.reminder =>
          LocaleKeys.workflows_step_about_reminder.tr(),
        WorkflowStepKind.filter => LocaleKeys.workflows_step_about_filter.tr(),
        WorkflowStepKind.delay => LocaleKeys.workflows_step_about_delay.tr(),
        WorkflowStepKind.formatter =>
          LocaleKeys.workflows_step_about_formatter.tr(),
        WorkflowStepKind.code => LocaleKeys.workflows_step_about_code.tr(),
        WorkflowStepKind.storage =>
          LocaleKeys.workflows_step_about_storage.tr(),
      };

  /// A step's own name when it has one, otherwise its kind's.
  static String stepTitle(WorkflowStep step) =>
      step.label.isNotEmpty ? step.label : stepName(step.kind);

  static DashboardAccent runAccent(WorkflowRunStatus status) =>
      switch (status) {
        WorkflowRunStatus.succeeded => DashboardAccent.green,
        WorkflowRunStatus.failed => DashboardAccent.red,
        WorkflowRunStatus.filtered => DashboardAccent.amber,
        WorkflowRunStatus.running => DashboardAccent.blue,
        WorkflowRunStatus.waiting => DashboardAccent.purple,
        WorkflowRunStatus.cancelled => DashboardAccent.neutral,
      };

  static String runStatusName(WorkflowRunStatus status) => switch (status) {
        WorkflowRunStatus.running =>
          LocaleKeys.workflows_history_status_running.tr(),
        WorkflowRunStatus.succeeded =>
          LocaleKeys.workflows_history_status_succeeded.tr(),
        WorkflowRunStatus.failed =>
          LocaleKeys.workflows_history_status_failed.tr(),
        WorkflowRunStatus.filtered =>
          LocaleKeys.workflows_history_status_filtered.tr(),
        WorkflowRunStatus.waiting =>
          LocaleKeys.workflows_history_status_waiting.tr(),
        WorkflowRunStatus.cancelled =>
          LocaleKeys.workflows_history_status_cancelled.tr(),
      };

  static DashboardAccent stepStatusAccent(WorkflowStepStatus status) =>
      switch (status) {
        WorkflowStepStatus.succeeded => DashboardAccent.green,
        WorkflowStepStatus.failed => DashboardAccent.red,
        WorkflowStepStatus.filtered => DashboardAccent.amber,
        WorkflowStepStatus.waiting => DashboardAccent.purple,
        WorkflowStepStatus.skipped => DashboardAccent.neutral,
      };

  static String stepStatusName(WorkflowStepStatus status) => switch (status) {
        WorkflowStepStatus.succeeded =>
          LocaleKeys.workflows_history_status_succeeded.tr(),
        WorkflowStepStatus.failed =>
          LocaleKeys.workflows_history_status_failed.tr(),
        WorkflowStepStatus.filtered =>
          LocaleKeys.workflows_history_status_filtered.tr(),
        WorkflowStepStatus.waiting =>
          LocaleKeys.workflows_history_status_waiting.tr(),
        WorkflowStepStatus.skipped =>
          LocaleKeys.workflows_history_status_skipped.tr(),
      };

  static String causeName(WorkflowRunCause cause) => switch (cause) {
        WorkflowRunCause.manual =>
          LocaleKeys.workflows_history_cause_manual.tr(),
        WorkflowRunCause.test => LocaleKeys.workflows_history_cause_test.tr(),
        WorkflowRunCause.schedule =>
          LocaleKeys.workflows_history_cause_schedule.tr(),
        WorkflowRunCause.webhook =>
          LocaleKeys.workflows_history_cause_webhook.tr(),
        WorkflowRunCause.feed => LocaleKeys.workflows_history_cause_feed.tr(),
        WorkflowRunCause.databaseRow =>
          LocaleKeys.workflows_history_cause_databaseRow.tr(),
        WorkflowRunCause.newPage =>
          LocaleKeys.workflows_history_cause_newPage.tr(),
        WorkflowRunCause.appStart =>
          LocaleKeys.workflows_history_cause_appStart.tr(),
      };
}

/// "just now", "5 min ago", "in 3 min", "today at 09:00", "Oct 4, 17:30".
String describeWorkflowTime(DateTime at, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final gap = at.difference(reference);
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(at.year, at.month, at.day);
  final clock = DateFormat.Hm().format(at);
  if (gap.isNegative) {
    final past = -gap;
    if (past.inMinutes < 1) {
      return LocaleKeys.workflows_time_justNow.tr();
    }
    if (past.inMinutes < 60) {
      return LocaleKeys.workflows_time_minutesAgo.tr(
        args: ['${past.inMinutes}'],
      );
    }
    if (past.inHours < 24) {
      return LocaleKeys.workflows_time_hoursAgo.tr(args: ['${past.inHours}']);
    }
    return DateFormat.MMMd().add_Hm().format(at);
  }
  if (gap.inSeconds < 60) {
    return LocaleKeys.workflows_time_inMoments.tr();
  }
  if (gap.inMinutes < 60) {
    return LocaleKeys.workflows_time_inMinutes.tr(args: ['${gap.inMinutes}']);
  }
  if (day == today) {
    return LocaleKeys.workflows_time_todayAt.tr(args: [clock]);
  }
  if (day == today.add(const Duration(days: 1))) {
    return LocaleKeys.workflows_time_tomorrowAt.tr(args: [clock]);
  }
  return DateFormat.MMMd().add_Hm().format(at);
}

/// A rounded tile holding a glyph in one accent's colours.
class WorkflowGlyphTile extends StatelessWidget {
  const WorkflowGlyphTile({
    super.key,
    required this.glyph,
    required this.accent,
    this.size = 36,
    this.glyphSize,
    this.radius,
  });

  final String glyph;
  final DashboardAccent accent;
  final double size;
  final double? glyphSize;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final strong = palette.strongFor(accent);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          strong.withValues(alpha: palette.isDark ? 0.22 : 0.13),
          palette.surface,
        ),
        borderRadius: BorderRadius.circular(radius ?? size * 0.3),
        border: Border.all(
          color: strong.withValues(alpha: palette.isDark ? 0.34 : 0.22),
        ),
      ),
      child: WorkspaceGlyph.named(
        glyph,
        size: glyphSize ?? size * 0.5,
        color: palette.isDark
            ? Color.lerp(strong, Colors.white, 0.2)
            : Color.lerp(strong, palette.textPrimary, 0.25),
        role: WorkspaceGlyphRole.preserveInk,
      ),
    );
  }
}

enum WorkflowButtonKind { primary, secondary, quiet, danger }

/// The page's labelled control.
class WorkflowButton extends StatelessWidget {
  const WorkflowButton({
    super.key,
    required this.label,
    this.glyph,
    this.onPressed,
    this.kind = WorkflowButtonKind.secondary,
    this.tooltip,
    this.busy = false,
  });

  final String label;
  final String? glyph;
  final VoidCallback? onPressed;
  final WorkflowButtonKind kind;
  final String? tooltip;

  /// Shows a small spinner in place of the glyph and ignores presses.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final enabled = onPressed != null && !busy;
    final danger = palette.strongFor(DashboardAccent.red);
    final ink = !enabled
        ? palette.textMuted
        : switch (kind) {
            WorkflowButtonKind.primary => palette.onAccent,
            WorkflowButtonKind.danger => danger,
            WorkflowButtonKind.secondary => palette.textPrimary,
            WorkflowButtonKind.quiet => palette.textSecondary,
          };
    final rest = switch (kind) {
      WorkflowButtonKind.primary => palette.accent,
      WorkflowButtonKind.secondary => palette.raised,
      _ => palette.hoverBase,
    };
    final hovered = switch (kind) {
      WorkflowButtonKind.primary =>
        Color.alphaBlend(Colors.white.withValues(alpha: 0.12), palette.accent),
      WorkflowButtonKind.secondary => Color.alphaBlend(
          palette.hover.withValues(alpha: 0.7),
          palette.raised,
        ),
      WorkflowButtonKind.danger => danger.withValues(alpha: 0.1),
      WorkflowButtonKind.quiet => palette.hover,
    };
    final bordered = kind == WorkflowButtonKind.secondary;
    final button = TextButton(
      onPressed: enabled ? onPressed : null,
      style: WorkspaceChrome.controlStyle(context).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        foregroundColor: WidgetStatePropertyAll(ink),
        iconColor: WidgetStatePropertyAll(ink),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? palette.accent
                : bordered
                    ? palette.border.withValues(alpha: 0.6)
                    : palette.border.withValues(alpha: 0),
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (!enabled) {
            return kind == WorkflowButtonKind.primary
                ? palette.accent.withValues(alpha: 0.35)
                : rest;
          }
          return states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? hovered
              : rest;
        }),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.6, color: ink),
            )
          else if (glyph != null)
            WorkspaceGlyph.named(
              glyph!,
              size: 15,
              color: ink,
              role: kind == WorkflowButtonKind.primary || !enabled
                  ? WorkspaceGlyphRole.preserveInk
                  : WorkspaceGlyphRole.standard,
            ),
          if (busy || glyph != null) const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
    final message = tooltip;
    return message == null || message.isEmpty
        ? button
        : Tooltip(message: message, child: button);
  }
}

/// A square borderless control with a tooltip.
class WorkflowIconButton extends StatelessWidget {
  const WorkflowIconButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    this.onPressed,
    this.size = 30,
    this.color,
  });

  final String glyph;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final enabled = onPressed != null;
    final ink = enabled
        ? color ?? palette.textSecondary
        : palette.textMuted.withValues(alpha: 0.5);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: WorkspaceChrome.controlStyle(context).copyWith(
        minimumSize: WidgetStatePropertyAll(Size.square(size)),
        maximumSize: WidgetStatePropertyAll(Size.square(size)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => enabled &&
                  (states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused))
              ? palette.hover
              : palette.hoverBase,
        ),
      ),
      icon: WorkspaceGlyph.named(
        glyph,
        size: 16,
        color: ink,
        role: color != null || !enabled
            ? WorkspaceGlyphRole.preserveInk
            : WorkspaceGlyphRole.standard,
      ),
    );
  }
}

/// An on/off switch that answers to the keyboard and to screen readers.
class WorkflowSwitch extends StatefulWidget {
  const WorkflowSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;

  @override
  State<WorkflowSwitch> createState() => _WorkflowSwitchState();
}

class _WorkflowSwitchState extends State<WorkflowSwitch> {
  bool _focused = false;
  bool _hovered = false;

  void _toggle() => widget.onChanged?.call(!widget.value);

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final enabled = widget.onChanged != null;
    final duration =
        WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration);
    final track = widget.value
        ? palette.accent
        : Color.alphaBlend(
            palette.textMuted.withValues(alpha: _hovered ? 0.42 : 0.32),
            palette.surface,
          );
    return Semantics(
      toggled: widget.value,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? _toggle : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        onShowHoverHighlight: (hovered) => setState(() => _hovered = hovered),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: enabled ? _toggle : null,
          child: ExcludeSemantics(
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: AnimatedContainer(
                duration: duration,
                curve: WorkspaceTokens.curve,
                width: 34,
                height: 20,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _focused
                        ? palette.accent
                        : palette.accent.withValues(alpha: 0),
                    width: 1.5,
                  ),
                ),
                child: AnimatedAlign(
                  duration: duration,
                  curve: WorkspaceTokens.curve,
                  alignment: widget.value
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: widget.value
                          ? palette.onAccent
                          : palette.isPaper
                              ? palette.raised
                              : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: palette.shadowColor.withValues(alpha: 0.25),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
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

/// A raised surface that lifts on hover when it can be pressed.
class WorkflowSurface extends StatefulWidget {
  const WorkflowSurface({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.selected = false,
    this.radius = 16,
    this.highlight,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final double radius;

  /// A coloured outline, for something that needs attention.
  final Color? highlight;
  final String? semanticLabel;

  @override
  State<WorkflowSurface> createState() => _WorkflowSurfaceState();
}

class _WorkflowSurfaceState extends State<WorkflowSurface> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final interactive = widget.onTap != null;
    final lifted = interactive && (_hovered || _focused);
    final outline = widget.selected
        ? palette.accent
        : widget.highlight ??
            (_focused
                ? palette.accent.withValues(alpha: 0.6)
                : palette.border
                    .withValues(alpha: palette.isDark ? 0.5 : 0.42));
    final surface = AnimatedContainer(
      duration: WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
      curve: WorkspaceTokens.curve,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: outline,
          width: widget.selected ? 1.5 : 1,
        ),
        boxShadow: palette.cardShadow(raised: lifted || widget.selected),
      ),
      child: widget.child,
    );
    if (!interactive) {
      return surface;
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: surface,
        ),
      ),
    );
  }
}

/// A small rounded label in one accent's colours.
class WorkflowPill extends StatelessWidget {
  const WorkflowPill({
    super.key,
    required this.label,
    required this.accent,
    this.dot = true,
  });

  final String label;
  final DashboardAccent accent;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final strong = palette.strongFor(accent);
    final ink = palette.isDark
        ? Color.lerp(strong, Colors.white, 0.25)!
        : Color.lerp(strong, palette.textPrimary, 0.35)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong.withValues(alpha: palette.isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: strong, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mutually exclusive choices laid side by side.
class WorkflowSegmented<T> extends StatelessWidget {
  const WorkflowSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.expand = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// Share the available width equally.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final segments = [
      for (final value in values)
        _Segment(
          label: labelOf(value),
          selected: value == selected,
          onTap: () => onChanged(value),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final segment in segments)
            expand ? Expanded(child: segment) : segment,
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: TextButton(
        onPressed: onTap,
        style: WorkspaceChrome.controlStyle(context).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          foregroundColor: WidgetStatePropertyAll(
            selected ? palette.textPrimary : palette.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (selected) {
              return palette.raised;
            }
            return states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
                ? palette.hover
                : palette.hoverBase;
          }),
          elevation: WidgetStatePropertyAll(selected ? 1.0 : 0.0),
          shadowColor: WidgetStatePropertyAll(palette.shadowColor),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// A small heading over a group of fields.
class WorkflowLabel extends StatelessWidget {
  const WorkflowLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: DashboardType.eyebrow(palette),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A sentence of help under a field.
class WorkflowHint extends StatelessWidget {
  const WorkflowHint(this.text, {super.key, this.glyph, this.accent});

  final String text;
  final String? glyph;
  final DashboardAccent? accent;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final color =
        accent == null ? palette.textMuted : palette.strongFor(accent!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (glyph != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: WorkspaceGlyph.named(
              glyph!,
              size: 14,
              color: color,
              role: WorkspaceGlyphRole.preserveInk,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            style: DashboardType.caption(
              palette,
              color: accent == null ? null : color,
            ).copyWith(fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }
}
