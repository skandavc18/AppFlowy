import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_block_shell.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_text.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// How a progress bar is drawn.
enum ProgressStyle {
  /// A hairline rule — the quietest reading, for a page full of them.
  line,

  /// The default rounded track.
  bar,

  /// A thick track, for a block that is the point of the page.
  thick,

  /// Ten separate cells, which reads as "how many of ten".
  segmented,

  /// A dial with the figure in the middle.
  ring;

  static ProgressStyle fromValue(Object? value) =>
      ProgressStyle.values.firstWhere(
        (s) => s.name == value,
        orElse: () => ProgressStyle.bar,
      );

  String get label => switch (this) {
        ProgressStyle.line => LocaleKeys.interactive_progress_styleLine.tr(),
        ProgressStyle.bar => LocaleKeys.interactive_progress_styleBar.tr(),
        ProgressStyle.thick => LocaleKeys.interactive_progress_styleThick.tr(),
        ProgressStyle.segmented =>
          LocaleKeys.interactive_progress_styleSegmented.tr(),
        ProgressStyle.ring => LocaleKeys.interactive_progress_styleRing.tr(),
      };

  IconData get icon => switch (this) {
        ProgressStyle.line => Icons.horizontal_rule_rounded,
        ProgressStyle.bar => Icons.linear_scale_rounded,
        ProgressStyle.thick => Icons.view_stream_rounded,
        ProgressStyle.segmented => Icons.view_week_rounded,
        ProgressStyle.ring => Icons.donut_large_rounded,
      };

  double get thickness => switch (this) {
        ProgressStyle.line => 4,
        ProgressStyle.bar => 9,
        ProgressStyle.thick => 16,
        ProgressStyle.segmented => 14,
        ProgressStyle.ring => 8,
      };
}

class ProgressBlockKeys {
  const ProgressBlockKeys._();

  static const String type = 'interactive_progress';

  /// How far along, in the same units as [maximum].
  static const String value = 'value';

  /// What "finished" means. 100 unless somebody counts something else.
  static const String maximum = 'maximum';

  /// A second, quieter mark on the track — "we wanted to be here".
  static const String target = 'target';

  /// Show a percentage rather than the raw value.
  static const String showPercent = 'show_percent';

  /// One of [ProgressStyle].
  static const String style = 'style';
}

Node progressNode({
  double value = 0,
  double maximum = 100,
  String label = '',
  InteractiveAccent accent = InteractiveAccent.blue,
}) =>
    Node(
      type: ProgressBlockKeys.type,
      attributes: {
        ProgressBlockKeys.value: value,
        ProgressBlockKeys.maximum: maximum,
        ProgressBlockKeys.showPercent: true,
        InteractiveBlockKeys.label: label,
        InteractiveBlockKeys.accent: accent.name,
        InteractiveBlockKeys.size: InteractiveSize.medium.name,
      },
    );

class ProgressBlockComponentBuilder extends BlockComponentBuilder {
  ProgressBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ProgressBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
      actionTrailingBuilder: (context, state) =>
          actionTrailingBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class ProgressBlockComponent extends BlockComponentStatefulWidget {
  const ProgressBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ProgressBlockComponent> createState() => ProgressBlockComponentState();
}

class ProgressBlockComponentState extends State<ProgressBlockComponent>
    with BlockComponentConfigurable, InteractiveBlockMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  /// What is being dragged, before it is worth writing to the document.
  double? _dragging;

  ProgressStyle get _style =>
      ProgressStyle.fromValue(node.attributes[ProgressBlockKeys.style]);

  double get _maximum {
    final stored = doubleAttribute(ProgressBlockKeys.maximum, fallback: 100);
    return stored <= 0 ? 100 : stored;
  }

  double get _value =>
      _dragging ??
      doubleAttribute(ProgressBlockKeys.value, fallback: 0)
          .clamp(0, _maximum)
          .toDouble();

  double? get _target {
    final stored = node.attributes[ProgressBlockKeys.target];
    return stored is num ? stored.toDouble().clamp(0, _maximum) : null;
  }

  bool get _showPercent =>
      boolAttribute(ProgressBlockKeys.showPercent, fallback: true);

  double get _fraction => _maximum == 0 ? 0 : (_value / _maximum).clamp(0, 1);

  String get _readout => _showPercent
      ? '${(_fraction * 100).round()}%'
      : '${_trim(_value)} / ${_trim(_maximum)}';

  static String _trim(double value) =>
      value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(1);

  void _setFromLocal(double dx, double width) {
    if (!editable || width <= 0) {
      return;
    }
    setState(() => _dragging = (dx / width).clamp(0, 1) * _maximum);
  }

  Future<void> _commitDrag() async {
    final value = _dragging;
    if (value == null) {
      return;
    }
    setState(() => _dragging = null);
    await writeAttributes({
      ProgressBlockKeys.value: double.parse(value.toStringAsFixed(2)),
    });
  }

  Future<void> _askForNumber(String key, String title, double current) async {
    final answer = await showAFTextFieldDialog(
      context: context,
      title: title,
      initialValue: _trim(current),
    );
    final parsed = double.tryParse(answer?.trim() ?? '');
    if (parsed == null) {
      return;
    }
    await writeAttributes({key: parsed});
  }

  List<AppMenuEntry> _menu() => interactiveMenuEntries(
        extra: [
          AppMenuItem(
            label: LocaleKeys.interactive_menu_style.tr(),
            icon: Icons.style_rounded,
            subtitle: _style.label,
            submenu: [
              for (final style in ProgressStyle.values)
                AppMenuItem(
                  label: style.label,
                  icon: style.icon,
                  selected: style == _style,
                  enabled: editable,
                  onSelected: () => unawaited(
                    writeAttributes({ProgressBlockKeys.style: style.name}),
                  ),
                ),
            ],
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_progress_setValue.tr(),
            icon: Icons.tune_rounded,
            enabled: editable,
            onSelected: () => unawaited(
              _askForNumber(
                ProgressBlockKeys.value,
                LocaleKeys.interactive_progress_setValue.tr(),
                _value,
              ),
            ),
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_progress_setMaximum.tr(),
            icon: Icons.straighten_rounded,
            enabled: editable,
            onSelected: () => unawaited(
              _askForNumber(
                ProgressBlockKeys.maximum,
                LocaleKeys.interactive_progress_setMaximum.tr(),
                _maximum,
              ),
            ),
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_progress_setTarget.tr(),
            icon: Icons.flag_rounded,
            enabled: editable,
            onSelected: () => unawaited(
              _askForNumber(
                ProgressBlockKeys.target,
                LocaleKeys.interactive_progress_setTarget.tr(),
                _target ?? _maximum,
              ),
            ),
          ),
          AppMenuItem(
            label: LocaleKeys.interactive_progress_showPercent.tr(),
            icon: _showPercent
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            enabled: editable,
            onSelected: () => unawaited(
              writeAttributes({ProgressBlockKeys.showPercent: !_showPercent}),
            ),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final tone = accent.resolve(palette);
    final style = _style;

    final head = Row(
      children: [
        Expanded(
          child: InteractiveFocusGuard(
            child: InteractiveEditableText(
              value: blockLabel,
              enabled: editable,
              palette: palette,
              hint: LocaleKeys.interactive_progress_labelHint.tr(),
              style: InteractiveType.strong(palette, size: 13),
              onChanged: (value) =>
                  writeAttributes({InteractiveBlockKeys.label: value}),
            ),
          ),
        ),
        if (style != ProgressStyle.ring) ...[
          const SizedBox(width: 12),
          Text(
            _readout,
            style: InteractiveType.strong(
              palette,
              size: 12.5,
              color: tone.strong,
            ).copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );

    final track = _Track(
      fraction: _fraction,
      target: _target == null || _maximum == 0
          ? null
          : (_target! / _maximum).clamp(0.0, 1.0),
      tone: tone,
      palette: palette,
      style: style,
      animate: _dragging == null,
      onScrub: editable ? _setFromLocal : null,
      onScrubEnd: editable ? () => unawaited(_commitDrag()) : null,
    );

    return decorateInteractiveBlock(
      widget: widget,
      editorState: editorState,
      padding: padding,
      child: InteractiveBlockShell(
        node: node,
        size: blockSize,
        semanticsLabel:
            '${LocaleKeys.interactive_progress_name.tr()} $_readout',
        menuBuilder: _menu,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: style == ProgressStyle.ring
              ? Row(
                  children: [
                    _Ring(
                      fraction: _fraction,
                      readout: _readout,
                      tone: tone,
                      palette: palette,
                      animate: _dragging == null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: head),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    head,
                    const SizedBox(height: 9),
                    track,
                  ],
                ),
        ),
      ),
    );
  }
}

/// A dial with the figure in the middle.
class _Ring extends StatelessWidget {
  const _Ring({
    required this.fraction,
    required this.readout,
    required this.tone,
    required this.palette,
    required this.animate,
  });

  static const double _diameter = 76;

  final double fraction;
  final String readout;
  final InteractiveTone tone;
  final InteractivePalette palette;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _diameter,
      height: _diameter,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: fraction),
        duration: animate ? InteractiveMetrics.settle : Duration.zero,
        curve: InteractiveMetrics.curve,
        builder: (context, value, _) => CustomPaint(
          painter: _RingPainter(
            fraction: value,
            fill: tone.strong,
            track: palette.isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.07),
            thickness: ProgressStyle.ring.thickness,
          ),
          child: Center(
            child: Text(
              readout,
              style: InteractiveType.figure(palette, size: 17),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.fraction,
    required this.fill,
    required this.track,
    required this.thickness,
  });

  final double fraction;
  final Color fill;
  final Color track;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = (math.min(size.width, size.height) - thickness) / 2;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(centre, radius, base);

    if (fraction <= 0) {
      return;
    }
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [fill.withValues(alpha: 0.75), fill],
      ).createShader(Rect.fromCircle(center: centre, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0, 1),
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.fill != fill ||
      oldDelegate.track != track;
}

class _Track extends StatelessWidget {
  const _Track({
    required this.fraction,
    required this.target,
    required this.tone,
    required this.palette,
    required this.style,
    required this.animate,
    this.onScrub,
    this.onScrubEnd,
  });

  /// How many cells the segmented reading is cut into.
  static const int _segments = 10;

  final double fraction;
  final double? target;
  final InteractiveTone tone;
  final InteractivePalette palette;
  final ProgressStyle style;
  final bool animate;
  final void Function(double dx, double width)? onScrub;
  final VoidCallback? onScrubEnd;

  @override
  Widget build(BuildContext context) {
    final height = style.thickness;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final track = style == ProgressStyle.segmented
            ? _buildSegments(height)
            : _buildBar(width, height);

        if (onScrub == null) {
          return track;
        }

        return MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => onScrub!(details.localPosition.dx, width),
            onTapUp: (_) => onScrubEnd?.call(),
            onHorizontalDragStart: (details) =>
                onScrub!(details.localPosition.dx, width),
            onHorizontalDragUpdate: (details) =>
                onScrub!(details.localPosition.dx, width),
            onHorizontalDragEnd: (_) => onScrubEnd?.call(),
            child: Padding(
              // A thin bar is a small target; the padding is the hit area.
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: track,
            ),
          ),
        );
      },
    );
  }

  Color get _trackColour => palette.isDark
      ? Colors.white.withValues(alpha: 0.09)
      : Colors.black.withValues(alpha: 0.062);

  Widget _buildBar(double width, double height) {
    final radius = style == ProgressStyle.line ? height : height;
    return Stack(
      children: [
        Container(
          height: height,
          decoration: BoxDecoration(
            color: _trackColour,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: fraction),
          duration: animate ? InteractiveMetrics.settle : Duration.zero,
          curve: InteractiveMetrics.curve,
          builder: (context, value, _) => Container(
            height: height,
            width: math.max(value * width, value > 0 ? height : 0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [tone.strong.withValues(alpha: 0.82), tone.strong],
              ),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: style == ProgressStyle.thick
                  ? [
                      BoxShadow(
                        color: tone.strong.withValues(alpha: 0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                        spreadRadius: -4,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
        if (target != null)
          Positioned(
            left: (target! * width - 1).clamp(0.0, math.max(0, width - 2)),
            child: Container(
              width: 2,
              height: height,
              decoration: BoxDecoration(
                color: palette.text.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSegments(double height) {
    final filled = (fraction * _segments).round();
    return Row(
      children: [
        for (var i = 0; i < _segments; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: animate ? InteractiveMetrics.hover : Duration.zero,
              curve: InteractiveMetrics.curve,
              height: height,
              decoration: BoxDecoration(
                color: i < filled ? tone.strong : _trackColour,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          if (i != _segments - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}
