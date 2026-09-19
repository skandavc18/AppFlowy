import 'dart:async';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/url_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/progress_bar.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The value a progress or counter cell holds, read out of its text.
double? readNumericCell(String raw) => double.tryParse(raw.trim());

/// How a number is written back into a text cell.
String writeNumericCell(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(
          RegExp(r'\.$'),
          '',
        );

/// A reminder cell keeps the moment and the reminder it created, so the row
/// can show the time without asking the store and still reach the reminder.
({DateTime? at, String reminderId}) parseReminderCell(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return (at: null, reminderId: '');
  }
  final parts = trimmed.split('|');
  return (
    at: DateTime.tryParse(parts.first),
    reminderId: parts.length > 1 ? parts[1] : '',
  );
}

String encodeReminderCell(DateTime at, String reminderId) =>
    '${at.toIso8601String()}|$reminderId';

/// Rebuilds a cell's text when the column's alignment changes.
///
/// A text cell fills its column, so an `Align` around it does nothing — the
/// alignment has to reach the field itself.
class PropertyAlignedText extends StatelessWidget {
  const PropertyAlignedText({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.builder,
  });

  final String viewId;
  final String fieldId;
  final Widget Function(BuildContext context, TextAlign align) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PropertyStyles>(
      valueListenable: PropertyStyleRegistry.instance.listenable(viewId),
      builder: (context, styles, _) => builder(
        context,
        styles[fieldId]?.align?.textAlign ?? TextAlign.start,
      ),
    );
  }
}

/// Wraps a text cell so a marked column draws its own control.
///
/// The column is still a text column underneath — sorting, filtering and CSV
/// export all keep working — and this is only how it is read and edited.
class PropertyStyledTextCell extends StatelessWidget {
  const PropertyStyledTextCell({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.rowId,
    required this.controller,
    required this.bloc,
    required this.childBuilder,
    this.compact = true,
  });

  final String viewId;
  final String fieldId;
  final String rowId;
  final TextEditingController controller;
  final TextCellBloc bloc;

  /// The plain cell, laid out with the column's own alignment.
  final Widget Function(BuildContext context, TextAlign align) childBuilder;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PropertyStyles>(
      valueListenable: PropertyStyleRegistry.instance.listenable(viewId),
      builder: (context, styles, _) {
        final style = styles.cellStyle(fieldId, rowId);
        final align = style?.align?.textAlign ?? TextAlign.start;
        if (style == null || style.kind == PropertyStyleKind.plain) {
          return childBuilder(context, align);
        }
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _buildStyled(context, style),
        );
      },
    );
  }

  void _write(String value) => bloc.add(TextCellEvent.updateText(value));

  Widget _buildStyled(BuildContext context, PropertyStyle style) {
    final palette = interactivePaletteOf(context);
    final tone = InteractiveAccent.fromValue(style.accent).resolve(palette);
    final raw = controller.text;

    return switch (style.kind) {
      PropertyStyleKind.progress => _ProgressCell(
          value: readNumericCell(raw) ?? 0,
          maximum: style.maximum,
          showPercent: style.showPercent,
          showButtons: style.showButtons,
          step: style.progressStep,
          palette: palette,
          accent: const ['neutral', 'green'].contains(style.accent)
              ? null
              : tone.strong,
          compact: compact,
          onChanged: (value) => _write(formatProgressNumber(value)),
        ),
      PropertyStyleKind.counter => _CounterCell(
          value: readNumericCell(raw) ?? 0,
          step: style.step,
          minimum: style.minimum,
          maximum: style.counterMaximum,
          palette: palette,
          tone: tone,
          onChanged: (value) => _write(writeNumericCell(value)),
        ),
      PropertyStyleKind.button => _ButtonCell(
          style: style,
          cellText: raw,
          palette: palette,
          tone: tone,
          onWrite: _write,
        ),
      PropertyStyleKind.reminder => _ReminderCell(
          raw: raw,
          rowId: rowId,
          palette: palette,
          onWrite: _write,
        ),
      _ => childBuilder(context, style.align?.textAlign ?? TextAlign.start),
    };
  }
}

/// Grid controls usable by a form without a TextCellBloc or an early write.
class PropertyValueControl extends StatelessWidget {
  const PropertyValueControl({
    super.key,
    required this.style,
    required this.value,
    required this.onChanged,
    this.onOpenRow,
    this.enabled = true,
  });

  final PropertyStyle style;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onOpenRow;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final tone = InteractiveAccent.fromValue(style.accent).resolve(palette);
    final child = switch (style.kind) {
      PropertyStyleKind.progress => _ProgressCell(
          value: readNumericCell(value) ?? 0,
          maximum: style.maximum,
          showPercent: style.showPercent,
          showButtons: style.showButtons,
          step: style.progressStep,
          palette: palette,
          accent: const ['neutral', 'green'].contains(style.accent)
              ? null
              : tone.strong,
          compact: false,
          enabled: enabled,
          onChanged: (number) => onChanged(formatProgressNumber(number)),
        ),
      PropertyStyleKind.counter => _CounterCell(
          value: readNumericCell(value) ?? 0,
          step: style.step,
          minimum: style.minimum,
          maximum: style.counterMaximum,
          palette: palette,
          tone: tone,
          onChanged: (number) => onChanged(writeNumericCell(number)),
        ),
      PropertyStyleKind.button => _ButtonCell(
          style: style,
          cellText: value,
          palette: palette,
          tone: tone,
          onWrite: onChanged,
          onOpenRow: onOpenRow,
        ),
      _ => Text(value),
    };
    final active = enabled &&
        (style.kind != PropertyStyleKind.button ||
            style.buttonAction != PropertyButtonAction.openRow ||
            onOpenRow != null);
    return Semantics(
      enabled: active,
      child: ExcludeFocus(
        excluding: !active,
        child: IgnorePointer(ignoring: !active, child: child),
      ),
    );
  }
}

class _ProgressCell extends StatefulWidget {
  const _ProgressCell({
    required this.value,
    required this.maximum,
    required this.showPercent,
    required this.showButtons,
    required this.step,
    required this.palette,
    this.accent,
    required this.compact,
    required this.onChanged,
    this.enabled = true,
  });

  final double value;
  final double maximum;
  final bool showPercent;
  final bool showButtons;
  final double step;
  final InteractivePalette palette;
  final Color? accent;
  final bool compact;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<_ProgressCell> createState() => _ProgressCellState();
}

class _ProgressCellState extends State<_ProgressCell> {
  final _focusNode = FocusNode(debugLabel: 'Property progress');
  bool _focused = false;

  /// Keep the latest input while storage catches up. An earlier echoed write
  /// must not move the next click back to an older value.
  final List<double> _pending = [];

  /// What is being dragged, before it is worth writing to the row.
  double? _dragging;

  double _clamp(double value) =>
      value.isFinite ? value.clamp(0.0, widget.maximum) : 0;

  double get _committed =>
      _clamp(_pending.isEmpty ? widget.value : _pending.last);

  double get _value => _dragging ?? _committed;

  /// Remove floating-point addition noise, not fractional steps. Preserve an
  /// exact bound even when it has more significant digits than the readout.
  double _settle(double value) {
    final clamped = _clamp(value);
    return clamped == widget.maximum
        ? clamped
        : _clamp(double.parse(clamped.toStringAsPrecision(15)));
  }

  double _stepped(bool increase) {
    final value = _committed;
    final step = widget.step;
    // Test the remaining distance before adding, so even huge finite steps
    // cannot overflow to infinity and accidentally reset the bar to zero.
    return increase
        ? step >= widget.maximum - value
            ? widget.maximum
            : _settle(value + step)
        : step >= value
            ? 0
            : _settle(value - step);
  }

  String _readout(double value) => widget.showPercent
      ? '${(value / widget.maximum * 100).round()}%'
      : '${formatProgressNumber(value)}/${formatProgressNumber(widget.maximum)}';

  @override
  void didUpdateWidget(covariant _ProgressCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.maximum != oldWidget.maximum || !widget.enabled) {
      _dragging = null;
      _pending.clear();
    }
    if (!widget.enabled) {
      _focusNode.unfocus();
    }
    final incoming = _clamp(widget.value);
    if (incoming == _clamp(oldWidget.value)) {
      return;
    }
    final acknowledged = _pending.indexOf(incoming);
    if (acknowledged >= 0) {
      _pending.removeRange(0, acknowledged + 1);
    } else {
      // A real external edit, rather than one of our in-flight writes.
      _pending.clear();
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _commit(double value) {
    if (!mounted || !widget.enabled || _dragging != null) {
      return;
    }
    final next = _clamp(value);
    if (next == _committed) {
      return;
    }
    setState(() {
      _pending.add(next);
      // A draft host may intentionally never echo values back.
      if (_pending.length > 64) {
        _pending.removeAt(0);
      }
    });
    widget.onChanged(next);
  }

  void _adjust(bool increase) => _commit(_stepped(increase));

  void _scrub(double position) {
    if (!mounted || !widget.enabled || !position.isFinite) {
      return;
    }
    _focusNode.requestFocus();
    setState(() {
      _dragging = _settle(position.clamp(0.0, 1.0) * widget.maximum);
    });
  }

  void _endScrub() {
    final settled = _dragging;
    if (settled == null) {
      return;
    }
    setState(() => _dragging = null);
    _commit(settled);
  }

  void _cancelScrub() {
    if (mounted && _dragging != null) {
      setState(() => _dragging = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final colors = ProgressBarColors.of(context, accent: widget.accent);
    final value = _value;
    final readout = _readout(value);
    final canDecrease =
        widget.enabled && _dragging == null && _stepped(false) < value;
    final canIncrease =
        widget.enabled && _dragging == null && _stepped(true) > value;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final size = widget.compact ? 28.0 : 32.0;

    return CallbackShortcuts(
      bindings: widget.enabled
          ? {
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  _adjust(true),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                  _adjust(true),
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  _adjust(false),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  _adjust(false),
              const SingleActivator(LogicalKeyboardKey.numpadAdd): () =>
                  _adjust(true),
              const SingleActivator(LogicalKeyboardKey.numpadSubtract): () =>
                  _adjust(false),
              const SingleActivator(LogicalKeyboardKey.home): () => _commit(0),
              const SingleActivator(LogicalKeyboardKey.end): () =>
                  _commit(widget.maximum),
            }
          : const {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : InteractiveMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(InteractiveMetrics.controlRadius),
            border: Border.all(
              color: _focused && widget.enabled
                  ? colors.fill.withValues(alpha: 0.7)
                  : colors.fill.withValues(alpha: 0),
            ),
          ),
          child: Row(
            children: [
              if (widget.showButtons) ...[
                _ProgressStepButton(
                  key: const ValueKey('property-progress-decrease'),
                  icon: Icons.remove_rounded,
                  label: LocaleKeys.interactive_counter_decrease.tr(),
                  palette: palette,
                  colors: colors,
                  size: size,
                  onPressed: canDecrease ? () => _adjust(false) : null,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                key: const ValueKey('property-progress-value'),
                child: Semantics(
                  container: true,
                  slider: true,
                  enabled: widget.enabled,
                  focusable: widget.enabled,
                  focused: _focused && widget.enabled,
                  label: LocaleKeys.interactive_progress_name.tr(),
                  value: readout,
                  increasedValue: canIncrease ? _readout(_stepped(true)) : null,
                  decreasedValue:
                      canDecrease ? _readout(_stepped(false)) : null,
                  onIncrease: canIncrease ? () => _adjust(true) : null,
                  onDecrease: canDecrease ? () => _adjust(false) : null,
                  excludeSemantics: true,
                  child: FocusableActionDetector(
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    onFocusChange: (focused) =>
                        setState(() => _focused = focused),
                    child: PropertyProgressTrack(
                      fraction: value / widget.maximum,
                      fill: widget.enabled
                          ? colors.fill
                          : colors.fill.withValues(alpha: 0.45),
                      highlight: widget.enabled
                          ? colors.highlight
                          : colors.highlight.withValues(alpha: 0.45),
                      track: colors.track,
                      hitHeight: size,
                      animate: _dragging == null,
                      readout: Tooltip(
                        message: readout,
                        excludeFromSemantics: true,
                        child: Text(
                          readout,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: InteractiveType.strong(
                            palette,
                            size: 11.5,
                            weight: FontWeight.w500,
                            color: widget.enabled
                                ? palette.textSecondary
                                : palette.textMuted,
                          ).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      onScrub: widget.enabled ? _scrub : null,
                      onScrubEnd: widget.enabled ? _endScrub : null,
                      onScrubCancel: widget.enabled ? _cancelScrub : null,
                    ),
                  ),
                ),
              ),
              if (widget.showButtons) ...[
                const SizedBox(width: 4),
                _ProgressStepButton(
                  key: const ValueKey('property-progress-increase'),
                  icon: Icons.add_rounded,
                  label: LocaleKeys.interactive_counter_increase.tr(),
                  palette: palette,
                  colors: colors,
                  size: size,
                  onPressed: canIncrease ? () => _adjust(true) : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressStepButton extends StatelessWidget {
  const _ProgressStepButton({
    super.key,
    required this.icon,
    required this.label,
    required this.palette,
    required this.colors,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final InteractivePalette palette;
  final ProgressBarColors colors;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final foreground = WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.disabled)
          ? palette.textMuted.withValues(alpha: 0.45)
          : states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? colors.ink
              : palette.textSecondary,
    );
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        child: TextButton(
          onPressed: onPressed,
          style: ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size.square(size)),
            maximumSize: WidgetStatePropertyAll(Size.square(size)),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
            animationDuration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : InteractiveMetrics.hover,
            splashFactory: NoSplash.splashFactory,
            foregroundColor: foreground,
            iconColor: foreground,
            backgroundColor: WidgetStatePropertyAll(
              colors.fill.withValues(alpha: 0),
            ),
            overlayColor: WidgetStatePropertyAll(
              colors.fill.withValues(alpha: 0.2),
            ),
            shape: const WidgetStatePropertyAll(CircleBorder()),
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.focused)
                    ? colors.fill
                    : colors.fill.withValues(alpha: 0),
              ),
            ),
          ),
          child: Icon(icon, size: 16),
        ),
      ),
    );
  }
}

/// The bar a progress cell draws.
///
/// ⚠️ It paints rather than measuring: a grid row is laid out inside an
/// `IntrinsicHeight`, and a `LayoutBuilder` throws when it is measured that
/// way — which took the whole table down with it.
class PropertyProgressTrack extends StatelessWidget {
  const PropertyProgressTrack({
    super.key,
    required this.fraction,
    required this.fill,
    required this.track,
    this.highlight,
    this.height = 6,
    this.hitHeight = 28,
    this.animate = true,
    this.readout,
    this.onScrub,
    this.onScrubEnd,
    this.onScrubCancel,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final Color? highlight;
  final double height;
  final double hitHeight;

  /// Direct manipulation paints the current value, never a trailing tween.
  final bool animate;

  /// The readout shares the bar's hit area rather than stealing track width.
  final Widget? readout;

  /// Reports where along the bar the pointer is, as 0..1.
  final ValueChanged<double>? onScrub;

  /// The pointer was let go, so the value is worth storing.
  final VoidCallback? onScrubEnd;

  /// Cancellation discards a preview, rather than storing an abandoned drag.
  final VoidCallback? onScrubCancel;

  @override
  Widget build(BuildContext context) {
    Widget bar = AppFlowyProgressBar(
      fraction: fraction,
      fill: fill,
      track: track,
      highlight: highlight,
      height: height,
      animate: animate,
    );

    // Both the readout and the whitespace are usable, not just six pixels
    // of paint. These widgets all support a grid row's intrinsic measurement.
    bar = ConstrainedBox(
      constraints: BoxConstraints(minHeight: hitHeight),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (readout != null) ...[
              readout!,
              const SizedBox(height: 3),
            ],
            bar,
          ],
        ),
      ),
    );

    if (onScrub == null) {
      return bar;
    }

    return Builder(
      builder: (context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _EagerHorizontalDrag:
                GestureRecognizerFactoryWithHandlers<_EagerHorizontalDrag>(
              _EagerHorizontalDrag.new,
              (recognizer) => recognizer
                ..onStart = (details) {
                  _report(context, details.localPosition.dx);
                }
                ..onUpdate = (details) {
                  _report(context, details.localPosition.dx);
                }
                ..onEnd = (_) {
                  if (recognizer.cancelled) {
                    onScrubCancel?.call();
                  } else {
                    onScrubEnd?.call();
                  }
                }
                ..onCancel = () {
                  onScrubCancel?.call();
                },
            ),
          },
          child: bar,
        ),
      ),
    );
  }

  void _report(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    if (!width.isFinite || width <= 0 || !dx.isFinite) {
      return;
    }
    onScrub!((dx / width).clamp(0.0, 1.0));
  }
}

/// Claim a primary pointer before the grid's scroll/tap recognizers do.
/// Accepting in rejectGesture instead leaves TWO owners of the same drag.
/// A click still reports a position through onStart and commits through onEnd.
class _EagerHorizontalDrag extends HorizontalDragGestureRecognizer {
  bool cancelled = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    cancelled = false;
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  /// Two-finger scrolling is navigation, not a request to change a cell.
  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}

  @override
  void handleEvent(PointerEvent event) {
    // DragGestureRecognizer calls onEnd even for a cancelled accepted drag.
    if (event is PointerCancelEvent) {
      cancelled = true;
    }
    super.handleEvent(event);
  }
}

class _CounterCell extends StatelessWidget {
  const _CounterCell({
    required this.value,
    required this.step,
    required this.minimum,
    required this.maximum,
    required this.palette,
    required this.tone,
    required this.onChanged,
  });

  final double value;
  final double step;
  final double? minimum;
  final double? maximum;
  final InteractivePalette palette;
  final InteractiveTone tone;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final canDecrease = minimum == null || value - step >= minimum!;
    final canIncrease = maximum == null || value + step <= maximum!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InteractiveIconButton(
            icon: Icons.remove_rounded,
            tooltip: LocaleKeys.interactive_counter_decrease.tr(),
            palette: palette,
            accent: tone.strong,
            size: 22,
            iconSize: 14,
            onPressed: canDecrease ? () => onChanged(value - step) : null,
          ),
          SizedBox(
            width: 44,
            child: Center(
              child: Text(
                writeNumericCell(value),
                style: InteractiveType.body(palette).copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          InteractiveIconButton(
            icon: Icons.add_rounded,
            tooltip: LocaleKeys.interactive_counter_increase.tr(),
            palette: palette,
            accent: tone.strong,
            size: 22,
            iconSize: 14,
            onPressed: canIncrease ? () => onChanged(value + step) : null,
          ),
        ],
      ),
    );
  }
}

class _ButtonCell extends StatelessWidget {
  const _ButtonCell({
    required this.style,
    required this.cellText,
    required this.palette,
    required this.tone,
    required this.onWrite,
    this.onOpenRow,
  });

  final PropertyStyle style;
  final String cellText;
  final InteractivePalette palette;
  final InteractiveTone tone;
  final ValueChanged<String> onWrite;
  final VoidCallback? onOpenRow;

  @override
  Widget build(BuildContext context) {
    final label = style.buttonLabel.isNotEmpty
        ? style.buttonLabel
        : LocaleKeys.interactive_button_defaultLabel.tr();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InteractiveButton(
          label: label,
          emphasis: InteractiveEmphasis.ghost,
          size: InteractiveControlSize.small,
          palette: palette,
          accent: InteractiveAccent.fromValue(style.accent),
          onPressed: () => unawaited(_run(context)),
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context) async {
    switch (style.buttonAction) {
      case PropertyButtonAction.openRow:
        onOpenRow?.call();
        return;
      case PropertyButtonAction.openView:
        final target = style.buttonTarget.trim();
        if (target.isEmpty) {
          return;
        }
        final result = await ViewBackendService.getView(target);
        if (!context.mounted) {
          return;
        }
        result.fold(
          (view) => context.read<TabsBloc>().openPlugin(view),
          (_) => showToastNotification(
            message: LocaleKeys.interactive_button_targetMissing.tr(),
          ),
        );
      case PropertyButtonAction.openUrl:
        final target =
            style.buttonTarget.isNotEmpty ? style.buttonTarget : cellText;
        if (target.trim().isNotEmpty) {
          await afLaunchUrlString(target.trim(), context: context);
        }
      case PropertyButtonAction.setValue:
        onWrite(style.buttonTarget);
      case PropertyButtonAction.copyValue:
        await Clipboard.setData(ClipboardData(text: cellText));
        if (context.mounted) {
          showToastNotification(
            message: LocaleKeys.interactive_button_copied.tr(),
          );
        }
    }
  }
}

class _ReminderCell extends StatelessWidget {
  const _ReminderCell({
    required this.raw,
    required this.rowId,
    required this.palette,
    required this.onWrite,
  });

  final String raw;
  final String rowId;
  final InteractivePalette palette;
  final ValueChanged<String> onWrite;

  @override
  Widget build(BuildContext context) {
    final cell = parseReminderCell(raw);
    final at = cell.at;
    final overdue = at != null && at.isBefore(DateTime.now());
    final tone = (overdue ? InteractiveAccent.red : InteractiveAccent.blue)
        .resolve(palette);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_compose(context, cell.reminderId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Row(
            children: [
              Icon(
                at == null
                    ? Icons.notifications_none_rounded
                    : Icons.notifications_active_rounded,
                size: 14,
                color: at == null ? palette.textMuted : tone.strong,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  at == null
                      ? LocaleKeys.interactive_reminder_empty.tr()
                      : formatCellMoment(at),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InteractiveType.body(palette).copyWith(
                    fontSize: 13,
                    color: at == null
                        ? palette.textMuted
                        : (overdue ? tone.strong : palette.text),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _compose(BuildContext context, String existingId) async {
    final created = await showReminderComposer(
      context,
      kind: ReminderKind.row,
      objectId: rowId,
    );
    if (created == null) {
      return;
    }
    if (existingId.isNotEmpty && existingId != created.id) {
      await ReminderStore.instance.remove(existingId);
    }
    onWrite(encodeReminderCell(created.scheduledAt, created.id));
  }
}

/// "Today · 10:00", "3 Aug · 14:30".
String formatCellMoment(DateTime at, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  final days =
      DateTime(at.year, at.month, at.day).difference(startOfToday).inDays;
  final time = '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';
  final day = switch (days) {
    0 => LocaleKeys.interactive_reminder_today.tr(),
    1 => LocaleKeys.interactive_reminder_tomorrow.tr(),
    -1 => LocaleKeys.interactive_reminder_yesterday.tr(),
    _ => '${at.day} ${_months[(at.month - 1).clamp(0, 11)]}'
        '${at.year == today.year ? '' : ' ${at.year}'}',
  };
  return '$day · $time';
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Wraps a link cell so a bookmark column shows the site and page path.
class PropertyStyledUrlCell extends StatelessWidget {
  const PropertyStyledUrlCell({
    super.key,
    required this.viewId,
    required this.fieldId,
    required this.rowId,
    required this.controller,
    required this.bloc,
    required this.childBuilder,
  });

  final String viewId;
  final String fieldId;
  final String rowId;
  final TextEditingController controller;
  final URLCellBloc bloc;
  final Widget Function(BuildContext context, TextAlign align) childBuilder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PropertyStyles>(
      valueListenable: PropertyStyleRegistry.instance.listenable(viewId),
      builder: (context, styles, _) {
        final style = styles.cellStyle(fieldId, rowId);
        final align = style?.align?.textAlign ?? TextAlign.start;
        if (style == null || style.kind != PropertyStyleKind.link) {
          return childBuilder(context, align);
        }
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final url = controller.text.trim();
            if (url.isEmpty) {
              return childBuilder(context, align);
            }
            return BookmarkChip(url: url, thumbnail: style.showThumbnail);
          },
        );
      },
    );
  }
}

/// A link set directly on the cell: a favicon, the site and a quiet page path.
/// Its destination becomes clearer on hover/focus, not a boxed control.
class BookmarkChip extends StatefulWidget {
  const BookmarkChip({
    super.key,
    required this.url,
    this.thumbnail = true,
  });

  final String url;
  final bool thumbnail;

  @override
  State<BookmarkChip> createState() => _BookmarkChipState();
}

class _BookmarkChipState extends State<BookmarkChip> {
  final _focusNode = FocusNode(debugLabel: 'Bookmark URL');
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _open() => unawaited(afLaunchUrlString(widget.url, context: context));

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final site = bookmarkHost(widget.url);
    final host = site ?? widget.url;
    final display = bookmarkDisplayUrl(widget.url);
    // The site is already the headline; do not repeat it on the second line.
    final detail = display.startsWith('$host/')
        ? display.substring(host.length + 1)
        : display;
    final active = _hovered || _focused;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : InteractiveMetrics.hover;
    // AnimatedDefaultTextStyle replaces, rather than merges, inherited type.
    final hostStyle = DefaultTextStyle.of(context).style.merge(
          InteractiveType.strong(
            palette,
            size: 13,
            weight: FontWeight.w500,
            color: active ? palette.accent : palette.text,
          ).copyWith(
            decoration: active ? TextDecoration.underline : TextDecoration.none,
            decorationColor: palette.accent.withValues(alpha: 0.5),
            decorationThickness: 1,
          ),
        );

    return Tooltip(
      message: widget.url,
      waitDuration: const Duration(milliseconds: 450),
      excludeFromSemantics: true,
      child: Semantics(
        key: const ValueKey('bookmark-link'),
        link: true,
        focusable: true,
        focused: _focused,
        label: widget.url,
        onTap: _open,
        child: ExcludeSemantics(
          child: FocusableActionDetector(
            focusNode: _focusNode,
            mouseCursor: SystemMouseCursors.click,
            onShowHoverHighlight: (hovered) =>
                setState(() => _hovered = hovered),
            onFocusChange: (focused) => setState(() => _focused = focused),
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.enter, includeRepeats: false):
                  ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
                  ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _open();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _open,
              child: Padding(
                key: const ValueKey('bookmark-link-surface'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.thumbnail)
                      _Favicon(host: site ?? '', palette: palette)
                    else
                      SizedBox.square(
                        dimension: 20,
                        child: Icon(
                          Icons.link_rounded,
                          size: 16,
                          color: palette.textMuted,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedDefaultTextStyle(
                            duration: duration,
                            curve: InteractiveMetrics.curve,
                            style: hostStyle,
                            child: Text(
                              host,
                              key: const ValueKey('bookmark-link-host'),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.thumbnail &&
                              detail.isNotEmpty &&
                              detail != host) ...[
                            const SizedBox(height: 2),
                            Text(
                              detail,
                              key: const ValueKey('bookmark-link-path'),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: InteractiveType.caption(palette).copyWith(
                                fontSize: 11.5,
                                height: 1.3,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    AnimatedOpacity(
                      key: const ValueKey('bookmark-link-open-indicator'),
                      opacity: active ? 1 : 0,
                      duration: duration,
                      curve: InteractiveMetrics.curve,
                      child: Icon(
                        Icons.north_east_rounded,
                        size: 14,
                        color: palette.accent,
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

class _Favicon extends StatelessWidget {
  const _Favicon({required this.host, required this.palette});

  final String host;
  final InteractivePalette palette;

  @override
  Widget build(BuildContext context) {
    // An unavailable site icon is still a link, not a random coloured badge.
    final fallback = SizedBox.square(
      dimension: 20,
      child: Icon(Icons.public_rounded, size: 18, color: palette.textMuted),
    );

    if (host.isEmpty) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        'https://$host/favicon.ico',
        width: 20,
        height: 20,
        cacheWidth: (20 * MediaQuery.devicePixelRatioOf(context)).ceil(),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => fallback,
        // No spinner or empty icon space while a slow site is loading.
        frameBuilder: (context, child, frame, _) =>
            frame == null ? fallback : child,
      ),
    );
  }
}
