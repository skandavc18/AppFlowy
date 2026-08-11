import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/text_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/cell/bloc/url_cell_bloc.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_composer.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
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
          palette: palette,
          tone: tone,
          compact: compact,
          onChanged: (value) => _write(writeNumericCell(value)),
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

class _ProgressCell extends StatefulWidget {
  const _ProgressCell({
    required this.value,
    required this.maximum,
    required this.showPercent,
    required this.palette,
    required this.tone,
    required this.compact,
    required this.onChanged,
  });

  final double value;
  final double maximum;
  final bool showPercent;
  final InteractivePalette palette;
  final InteractiveTone tone;
  final bool compact;
  final ValueChanged<double> onChanged;

  @override
  State<_ProgressCell> createState() => _ProgressCellState();
}

class _ProgressCellState extends State<_ProgressCell> {
  /// What is being dragged, before it is worth writing to the row.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final maximum = widget.maximum;
    final value = _dragging ?? widget.value;
    final fraction = maximum <= 0 ? 0.0 : (value / maximum).clamp(0.0, 1.0);
    final readout = widget.showPercent
        ? '${(fraction * 100).round()}%'
        : '${writeNumericCell(value)}/${writeNumericCell(maximum)}';

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 8,
        vertical: widget.compact ? 6 : 9,
      ),
      child: Row(
        children: [
          Expanded(
            child: PropertyProgressTrack(
              fraction: fraction,
              fill: widget.tone.strong,
              track: widget.palette.isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.07),
              onScrub: (position) =>
                  setState(() => _dragging = position * maximum),
              onScrubEnd: () {
                final settled = _dragging;
                setState(() => _dragging = null);
                if (settled != null) {
                  widget.onChanged(settled);
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            readout,
            style: InteractiveType.caption(widget.palette).copyWith(
              fontSize: 11.5,
              color: widget.palette.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
    this.height = 7,
    this.onScrub,
    this.onScrubEnd,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final double height;

  /// Reports where along the bar the pointer is, as 0..1.
  final ValueChanged<double>? onScrub;

  /// The pointer was let go, so the value is worth storing.
  final VoidCallback? onScrubEnd;

  @override
  Widget build(BuildContext context) {
    Widget bar = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraction.clamp(0.0, 1.0)),
      duration: InteractiveMetrics.settle,
      curve: InteractiveMetrics.curve,
      builder: (context, drawn, _) => SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: _TrackPainter(fraction: drawn, fill: fill, track: track),
        ),
      ),
    );

    // The bar is a small target, so the padding around it is the hit area.
    bar = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: bar,
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
                  onScrubEnd?.call();
                }
                ..onCancel = () {
                  onScrubEnd?.call();
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
    if (width <= 0) {
      return;
    }
    onScrub!((dx / width).clamp(0.0, 1.0));
  }
}

/// ⚠️ A plain drag loses the arena to the grid's own horizontal scroll, so the
/// bar could be pushed but never moved. Accepting a rejection is what claims
/// the pointer; it also means a plain click reports a position through
/// `onStart`.
class _EagerHorizontalDrag extends HorizontalDragGestureRecognizer {
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);
}

class _TrackPainter extends CustomPainter {
  const _TrackPainter({
    required this.fraction,
    required this.fill,
    required this.track,
  });

  final double fraction;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (fraction <= 0) {
      return;
    }
    final width = math.max(fraction * size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, math.min(width, size.width), size.height),
        radius,
      ),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.fill != fill ||
      oldDelegate.track != track;
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
  });

  final PropertyStyle style;
  final String cellText;
  final InteractivePalette palette;
  final InteractiveTone tone;
  final ValueChanged<String> onWrite;

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
        // The row is already open behind this cell; nothing further to do
        // without a second surface to send somebody to.
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

/// Wraps a link cell so a bookmark column draws a card rather than underlined
/// text.
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

/// A link drawn the way the bookmark collection draws one: a favicon, the
/// site and the page, on a soft tile.
class BookmarkChip extends StatelessWidget {
  const BookmarkChip({
    super.key,
    required this.url,
    this.thumbnail = true,
  });

  final String url;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final host = bookmarkHost(url) ?? url;
    final display = bookmarkDisplayUrl(url, maxLength: 48);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(afLaunchUrlString(url, context: context)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(5, 4, 9, 4),
            decoration: BoxDecoration(
              color: Color.alphaBlend(
                palette.hover.withValues(alpha: palette.isDark ? 0.7 : 0.9),
                palette.surface,
              ),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: palette.border.withValues(alpha: 0.30),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (thumbnail) ...[
                  _Favicon(host: host, palette: palette),
                  const SizedBox(width: 8),
                ] else ...[
                  Icon(Icons.link_rounded, size: 14, color: palette.textMuted),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: InteractiveType.strong(palette, size: 12),
                      ),
                      if (thumbnail && display != host)
                        Text(
                          display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: InteractiveType.caption(palette)
                              .copyWith(fontSize: 10.5),
                        ),
                    ],
                  ),
                ),
              ],
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
    final initial = host.isEmpty ? '?' : host.characters.first.toUpperCase();
    final hue = _hueOf(host);
    final fallback = Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(1, hue, 0.42, palette.isDark ? 0.36 : 0.86)
            .toColor(),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        initial,
        style: InteractiveType.strong(
          palette,
          size: 11,
          color: HSLColor.fromAHSL(1, hue, 0.5, palette.isDark ? 0.86 : 0.28)
              .toColor(),
        ),
      ),
    );

    if (host.isEmpty) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        'https://$host/favicon.ico',
        width: 22,
        height: 22,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
        // A missing favicon must not leave a spinner on every row.
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }

  /// A stable hue per site, so the same host always wears the same colour.
  static double _hueOf(String host) {
    var hash = 2166136261;
    for (final unit in host.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0xFFFFFFFF;
    }
    return (hash % 360).toDouble();
  }
}
