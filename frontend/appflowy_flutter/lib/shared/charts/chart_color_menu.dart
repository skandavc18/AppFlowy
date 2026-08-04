import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/charts/chart_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

String chartPaletteLabel(ChartPaletteName name) => switch (name) {
      ChartPaletteName.classic => LocaleKeys.charts_paletteClassic.tr(),
      ChartPaletteName.ocean => LocaleKeys.charts_paletteOcean.tr(),
      ChartPaletteName.sunset => LocaleKeys.charts_paletteSunset.tr(),
      ChartPaletteName.meadow => LocaleKeys.charts_paletteMeadow.tr(),
      ChartPaletteName.berry => LocaleKeys.charts_paletteBerry.tr(),
      ChartPaletteName.slate => LocaleKeys.charts_paletteSlate.tr(),
    };

/// The menu behind the colour chip: a set to draw in, then each series on its
/// own for anyone who wants to say exactly.
List<AppMenuEntry> chartColorEntries({
  required ChartSpec spec,
  required ChartData data,
  required ChartPalette palette,
  required ValueChanged<ChartSpec> onChanged,
}) {
  final circular = spec.type.isCircular;
  final names = circular
      ? [
          if (data.series.isNotEmpty)
            for (final point in data.series.first.points) point.label,
        ]
      : [for (final series in data.series) series.name];

  return [
    AppMenuHeader(LocaleKeys.charts_palette.tr()),
    for (final name in ChartPaletteName.values)
      AppMenuCustom(
        builder: (context) => _PaletteRow(
          name: name,
          palette: palette,
          selected: name == spec.palette,
          onTap: () {
            AppMenuScope.maybeOf(context)?.close();
            onChanged(spec.copyWith(palette: name));
          },
        ),
      ),
    if (names.isNotEmpty) ...[
      const AppMenuSeparator(),
      AppMenuHeader(LocaleKeys.charts_seriesColors.tr()),
      for (var index = 0; index < names.length; index++)
        AppMenuCustom(
          builder: (context) => _SeriesRow(
            label: names[index],
            index: index,
            spec: spec,
            palette: palette,
            onChanged: onChanged,
          ),
        ),
    ],
    if (spec.colors.isNotEmpty) ...[
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.charts_resetAllColors.tr(),
        icon: Icons.restart_alt_rounded,
        onSelected: () => onChanged(spec.copyWith(colors: const {})),
      ),
    ],
  ];
}

/// One named set, shown as the colours it actually is.
class _PaletteRow extends StatefulWidget {
  const _PaletteRow({
    required this.name,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ChartPaletteName name;
  final ChartPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PaletteRow> createState() => _PaletteRowState();
}

class _PaletteRowState extends State<_PaletteRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette.withSet(widget.name);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _hovered ? widget.palette.chipHover : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: widget.selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: widget.palette.strongLabel,
                      )
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  chartPaletteLabel(widget.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: widget.palette.text(
                    size: 12.5,
                    color: widget.palette.strongLabel,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              for (var index = 0; index < 5; index++)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: palette.colorAt(index),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One series, with the swatches that repaint it.
class _SeriesRow extends StatefulWidget {
  const _SeriesRow({
    required this.label,
    required this.index,
    required this.spec,
    required this.palette,
    required this.onChanged,
  });

  final String label;
  final int index;
  final ChartSpec spec;
  final ChartPalette palette;
  final ValueChanged<ChartSpec> onChanged;

  @override
  State<_SeriesRow> createState() => _SeriesRowState();
}

class _SeriesRowState extends State<_SeriesRow> {
  bool _open = false;

  ChartColors get _colors => ChartColors.of(widget.palette, widget.spec);

  String get _key => chartColorKey(widget.label, widget.index);

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final current = _colors.at(widget.index, widget.label);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Row(
          palette: palette,
          color: current,
          label:
              widget.label.isEmpty ? LocaleKeys.charts_rows.tr() : widget.label,
          open: _open,
          chosen: _colors.isChosen(widget.index, widget.label),
          onTap: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: ChartMetrics.hoverDuration,
          curve: ChartMetrics.hoverCurve,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      for (final color in ChartColors.swatches)
                        _Swatch(
                          color: color,
                          selected: ChartColors.packed(current) ==
                              ChartColors.packed(color),
                          onTap: () => widget.onChanged(
                            widget.spec
                                .withColor(_key, ChartColors.packed(color)),
                          ),
                        ),
                      if (_colors.isChosen(widget.index, widget.label))
                        _Swatch(
                          color: palette.chip,
                          selected: false,
                          icon: Icons.restart_alt_rounded,
                          iconColor: palette.label,
                          onTap: () => widget
                              .onChanged(widget.spec.withColor(_key, null)),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.palette,
    required this.color,
    required this.label,
    required this.open,
    required this.chosen,
    required this.onTap,
  });

  final ChartPalette palette;
  final Color color;
  final String label;
  final bool open;
  final bool chosen;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _hovered || widget.open
                ? palette.chipHover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: palette.text(
                    size: 12.5,
                    color: palette.strongLabel,
                    weight: widget.chosen ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              AnimatedRotation(
                duration: ChartMetrics.hoverDuration,
                curve: ChartMetrics.hoverCurve,
                turns: widget.open ? 0.5 : 0,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 15,
                  color: palette.label,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatefulWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
    this.iconColor,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? iconColor;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: ChartMetrics.hoverDuration,
            curve: ChartMetrics.hoverCurve,
            width: 20,
            height: 20,
            transform: Matrix4.diagonal3Values(
              _hovered ? 1.12 : 1,
              _hovered ? 1.12 : 1,
              1,
            ),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.color,
              borderRadius: BorderRadius.circular(6),
              border: widget.selected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: widget.selected
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.55),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: widget.icon == null
                ? null
                : Icon(widget.icon, size: 12, color: widget.iconColor),
          ),
        ),
      );
}
