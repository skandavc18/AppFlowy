import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:flutter/material.dart';

import 'astrology/astrology_block.dart';
import 'astrology/astrology_chart_panel.dart';
import 'astrology/astrology_dashboard_widgets.dart';
import 'astrology/astrology_engine.dart';
import 'astrology/astrology_model.dart';

class AstrologyExtension extends AppFlowyExtension {
  @override
  DartExtensionInfo get info => const DartExtensionInfo(
        id: 'astrology',
        name: 'Vedic astrology',
        description: 'Interactive North/South Indian charts, dashas, Shadbala, '
            'Ashtakavarga and saved horoscope dashboards. Offline Swiss Ephemeris; '
            'location permission is requested only when a chart needs it.',
      );

  @override
  Future<void> activate(ExtensionContext context) async {
    final ctx = context as DartExtensionContext;
    AstrologyRuntime.active.value = true;
    ctx.scope.onDispose(
      () {
        AstrologyRuntime.active.value = false;
        AstrologyEngine.instance.clearCache();
      },
    );
    // Separate slash entries share one renderer/schema. They are also choices
    // inside every block, so no insertion choice is a permanent limitation.
    for (final entry in const [
      (astrologyBlockType, 'Astrology', AstrologyView.chart, 1),
      (
        'extension_astrology_navamsha',
        'Astrology · Navamsha D-9',
        AstrologyView.chart,
        9,
      ),
      (
        'extension_astrology_dasha',
        'Astrology · Dasha table',
        AstrologyView.dasha,
        1,
      ),
      (
        'extension_astrology_shadbala',
        'Astrology · Shadbala',
        AstrologyView.shadbala,
        1,
      ),
      (
        'extension_astrology_ashtakavarga',
        'Astrology · Ashtakavarga',
        AstrologyView.ashtakavarga,
        1,
      ),
      (
        'extension_astrology_placements',
        'Astrology · Planetary & special lagnas',
        AstrologyView.placements,
        1,
      ),
      (
        'extension_astrology_panchanga',
        'Astrology · Panchanga & key info',
        AstrologyView.panchanga,
        1,
      ),
    ]) {
      ctx.blocks.define(
        type: entry.$1,
        builder: (configuration) => AstrologyBlockBuilder(
          configuration: configuration,
        ),
        parser: AstrologyNodeParser(entry.$1),
        slashName: entry.$2,
        slashKeywords: [
          'astrology',
          'vedic',
          'horoscope',
          'jyotish',
          'kundali',
          entry.$3.name,
        ],
        slashDescription:
            'Birth or live transit · ${entry.$3.label} · North/South Indian',
        slashIcon: Icons.auto_awesome_rounded,
        newNode: () => astrologyNode(
          type: entry.$1,
          view: entry.$3,
          division: entry.$4,
        ),
        alignable: true,
      );
    }
    for (final widget in astrologyDashboardWidgets()) {
      ctx.dashboardWidgets.add(widget);
    }
  }
}
