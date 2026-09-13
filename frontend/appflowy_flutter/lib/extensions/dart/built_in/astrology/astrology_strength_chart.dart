import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'astrology_model.dart';
import 'astrology_shadbala_graph.dart';
import 'shadbala.dart';

/// A readable, horizontally pannable host for the seven-planet strength plot.
///
/// Values and selection stay controlled by the caller. The existing graph
/// owns signed percentage geometry, accessible details, and its focus nodes; this host
/// owns only the horizontal viewport. Focusing a clipped planet reveals it
/// without moving the enclosing card's vertical scroll position.
class AstrologyStrengthChart extends StatefulWidget {
  const AstrologyStrengthChart({
    super.key,
    required this.rows,
    required this.selected,
    required this.onSelected,
  });

  final List<ShadbalaRow> rows;
  final VedicBody? selected;
  final ValueChanged<VedicBody> onSelected;

  @override
  State<AstrologyStrengthChart> createState() => _AstrologyStrengthChartState();
}

class _AstrologyStrengthChartState extends State<AstrologyStrengthChart> {
  final _controller = ScrollController();
  final _viewport = GlobalKey();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_revealFocusedBar);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_revealFocusedBar);
    _controller.dispose();
    super.dispose();
  }

  void _revealFocusedBar() {
    final focus = FocusManager.instance.primaryFocus;
    final target = focus?.context;
    if (target == null ||
        target.findAncestorStateOfType<_AstrologyStrengthChartState>() !=
            this) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !target.mounted ||
          FocusManager.instance.primaryFocus != focus ||
          !_controller.hasClients) {
        return;
      }
      final bar = target.findRenderObject();
      final viewport = _viewport.currentContext?.findRenderObject();
      if (bar is! RenderBox ||
          viewport is! RenderBox ||
          !bar.hasSize ||
          !viewport.hasSize ||
          viewport.size.isEmpty) {
        return;
      }
      final left = bar.localToGlobal(Offset.zero, ancestor: viewport).dx;
      final right = left + bar.size.width;
      const margin = 4.0;
      final shift = left < margin
          ? left - margin
          : right > viewport.size.width - margin
              ? right - viewport.size.width + margin
              : 0.0;
      if (shift == 0) return;
      final position = _controller.position;
      final direction = position.axisDirection == AxisDirection.right ? 1 : -1;
      _controller.jumpTo(
        (position.pixels + shift * direction)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // Leave room for the axis as well as seven >=44px targets. At 2x text the
    // slots grow to fit percentages as well as the planet abbreviations.
    final minimumWidth = (64 + 7 * math.max(72.0, scaler.scale(72))).toDouble();
    final outerPosition = Scrollable.maybeOf(context)?.position;
    return LayoutBuilder(
      key: _viewport,
      builder: (context, constraints) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          key: const ValueKey('shadbala-graph-horizontal-scroll'),
          controller: _controller,
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: math
                .max(
                  constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : minimumWidth,
                  minimumWidth,
                )
                .toDouble(),
            child: ListenableBuilder(
              // Re-anchor an open details portal when either viewport moves.
              listenable: Listenable.merge([_controller, outerPosition]),
              builder: (context, child) => AstrologyShadbalaGraph(
                rows: widget.rows,
                selected: widget.selected,
                onSelected: widget.onSelected,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
