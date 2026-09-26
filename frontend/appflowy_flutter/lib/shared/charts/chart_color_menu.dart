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
      AppMenuItem(
        label: chartPaletteLabel(name),
        selected: name == spec.palette,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < 5; index++)
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: _colorSample(palette.withSet(name).colorAt(index)),
              ),
          ],
        ),
        onSelected: () => onChanged(spec.copyWith(palette: name)),
      ),
    if (names.isNotEmpty) ...[
      const AppMenuSeparator(),
      AppMenuHeader(LocaleKeys.charts_seriesColors.tr()),
      for (var index = 0; index < names.length; index++)
        AppMenuItem(
          label:
              names[index].isEmpty ? LocaleKeys.charts_rows.tr() : names[index],
          iconWidget: _colorSample(
            ChartColors.of(palette, spec).at(index, names[index]),
          ),
          submenu: [
            // Standard menu entries have real arrow/Enter navigation and
            // selected semantics. Their swatches are data, not default icons.
            for (final color in ChartColors.swatches)
              AppMenuItem(
                label:
                    '#${(ChartColors.packed(color) & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                iconWidget: _colorSample(color),
                selected: ChartColors.packed(
                      ChartColors.of(palette, spec).at(index, names[index]),
                    ) ==
                    ChartColors.packed(color),
                onSelected: () => onChanged(
                  spec.withColor(
                    chartColorKey(names[index], index),
                    ChartColors.packed(color),
                  ),
                ),
              ),
            if (ChartColors.of(palette, spec)
                .isChosen(index, names[index])) ...[
              const AppMenuSeparator(),
              AppMenuItem(
                label: LocaleKeys.charts_resetColor.tr(),
                icon: Icons.restart_alt_rounded,
                onSelected: () => onChanged(
                  spec.withColor(chartColorKey(names[index], index), null),
                ),
              ),
            ],
          ],
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

Widget _colorSample(Color color) => Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
