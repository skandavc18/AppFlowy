import 'dart:async';

import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:flutter/material.dart';

import 'astrology_model.dart';
import 'astrology_style.dart';

/// A compact chart-type pill; the full names remain in the tooltip and menu
/// when a narrow card can only accommodate the divisional number.
class AstrologyChartSelector extends StatefulWidget {
  const AstrologyChartSelector({
    super.key,
    required this.value,
    this.onChanged,
  });

  final int value;
  final ValueChanged<int>? onChanged;

  @override
  State<AstrologyChartSelector> createState() => _AstrologyChartSelectorState();
}

class _AstrologyChartSelectorState extends State<AstrologyChartSelector> {
  bool _open = false;

  int get _division =>
      astrologyDivisions.containsKey(widget.value) ? widget.value : 1;

  Future<void> _show(BuildContext anchor) async {
    if (_open || widget.onChanged == null) return;
    setState(() => _open = true);
    try {
      final palette = AstrologyPalette.of(context);
      final selected = await showAppMenuForWidget<int>(
        context: anchor,
        width: 280,
        entries: [
          const AppMenuHeader('Divisional chart'),
          for (final option in astrologyDivisions.entries)
            AppMenuItem(
              label: option.value,
              value: option.key,
              selected: option.key == _division,
              trailing: option.key == _division
                  ? Icon(Icons.check_rounded, size: 16, color: palette.accent)
                  : null,
            ),
        ],
      );
      // A card may have been removed or the extension disabled while the
      // menu was open. Never apply a selection through an obsolete callback.
      if (!mounted || widget.onChanged == null || selected == null) return;
      if (selected != _division) widget.onChanged!(selected);
    } finally {
      if (mounted) setState(() => _open = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final label = astrologyDivisions[_division]!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth <
            MediaQuery.textScalerOf(context).scale(12) / 12 * 175;
        return Align(
          alignment: Alignment.centerRight,
          widthFactor: 1,
          heightFactor: 1,
          child: Tooltip(
            message: 'Chart type: $label',
            excludeFromSemantics: true,
            child: Semantics(
              label: 'Chart type',
              value: label,
              child: Builder(
                builder: (anchor) => TextButton(
                  onPressed: widget.onChanged == null
                      ? null
                      : () => unawaited(_show(anchor)),
                  style: TextButton.styleFrom(
                    foregroundColor: palette.ink,
                    disabledForegroundColor: palette.muted,
                    overlayColor: palette.accent.withValues(alpha: 0.10),
                    backgroundColor:
                        _open ? palette.selection : palette.control,
                    disabledBackgroundColor: palette.control,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.standard,
                    shape: const StadiumBorder(),
                    textStyle:
                        Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontSize: 12,
                              height: 1.2,
                            ),
                  ).copyWith(
                    side: WidgetStateProperty.resolveWith(
                      (states) => BorderSide(
                        color: states.contains(WidgetState.focused)
                            ? palette.accent
                            : palette.line.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            compact ? 'D-$_division' : label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _open ? 0.5 : 0,
                          duration: AppMenuMetrics.hoverDuration,
                          child: const Icon(
                            Icons.expand_more_rounded,
                            size: 16,
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
      },
    );
  }
}
