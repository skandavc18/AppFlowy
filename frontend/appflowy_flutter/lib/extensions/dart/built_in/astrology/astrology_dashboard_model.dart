import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/template_pieces.dart'
    as pieces;
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:flutter/material.dart' show Icons;

const astrologyInputWidgetType = 'ext.astrology.input';
const astrologyChartWidgetType = 'ext.astrology.chart';
const astrologyDashaWidgetType = 'ext.astrology.dasha';
const astrologyShadbalaWidgetType = 'ext.astrology.shadbala';
const astrologyAshtakavargaWidgetType = 'ext.astrology.ashtakavarga';
const astrologyPlacementsWidgetType = 'ext.astrology.placements';
const astrologyPanchangaWidgetType = 'ext.astrology.panchanga';
const astrologyLibraryWidgetType = 'ext.astrology.library';
const astrologyEventsWidgetType = 'ext.astrology.events';
const astrologyDraftKey = 'astrology_input_draft';

/// A single dashboard, not a bundle with a shared events database.
///
/// The application registers this template separately from the widgets. Do not
/// set extensionId: the catalogue must still offer to enable Astrology while
/// its widgets are disabled.
WorkspaceTemplate astrologyDashboardTemplate() => WorkspaceTemplate(
      id: 'vedic_astrology',
      category: TemplateCategory.knowledge,
      label: () => 'Astrology dashboard template',
      description: () =>
          'Vedic charts, dashas and strengths, with saved horoscopes and a '
          'separate life-events table for each person.',
      icon: Icons.auto_awesome_rounded,
      accent: DashboardAccent.amber,
      keywords: const [
        'astrology',
        'vedic',
        'jyotish',
        'horoscope',
        'jhora',
        'birth chart',
      ],
      requires: const {'astrology'},
      build: () => [
        TemplatePart(
          key: 'dashboard',
          name: () => 'Astrology dashboard template',
          blueprint: TemplateDashboard((_) => buildAstrologyDashboard()),
        ),
      ],
    );

/// A JHora-inspired arrangement on the dashboard's responsive 12-column grid.
/// Paired half-width cards stay adjacent at every even-column breakpoint;
/// thirds round up to nine columns on an eight-column canvas and split rows.
///
/// The input card is the full-width header. Only it stores a profile; every
/// astrology renderer reads [astrologyInputFromDashboard], optionally overlaid
/// with the controller's ephemeral [astrologyDraftKey] value. This function
/// performs no IO, and an unsaved/template-preview events card stays unbound.
DashboardDocument buildAstrologyDashboard({
  AstrologyInput input = const AstrologyInput(),
  bool library = true,
  String libraryId = '',
  String eventsViewId = '',
}) {
  final chartRow = library ? 12 : 7;
  return DashboardDocument(
    sections: [
      pieces.section([
        pieces.widget(
          astrologyInputWidgetType,
          w: 12,
          h: 7,
          title: 'Birth details',
          settings: {
            'profile': input.toJson(),
            'library': library,
            'library_id': libraryId,
          },
        ),
        if (library)
          pieces.widget(
            astrologyLibraryWidgetType,
            y: 7,
            w: 12,
            h: 5,
            title: 'Saved horoscopes',
          ),
        pieces.widget(
          astrologyChartWidgetType,
          y: chartRow,
          w: 6,
          h: 7,
          title: 'Lagna · D-1',
          settings: const {'division': 1},
        ),
        pieces.widget(
          astrologyChartWidgetType,
          x: 6,
          y: chartRow,
          w: 6,
          h: 7,
          title: 'Navamsha · D-9',
          settings: const {'division': 9},
        ),
        pieces.widget(
          astrologyPanchangaWidgetType,
          y: chartRow + 7,
          w: 6,
          h: 7,
          title: 'Panchanga',
        ),
        pieces.widget(
          astrologyChartWidgetType,
          x: 6,
          y: chartRow + 7,
          w: 6,
          h: 7,
          title: 'Transit · D-1',
          settings: const {'transit': true},
        ),
        pieces.widget(
          astrologyPlacementsWidgetType,
          y: chartRow + 14,
          w: 12,
          h: 7,
          title: 'Planetary & special lagnas',
        ),
        pieces.widget(
          astrologyShadbalaWidgetType,
          y: chartRow + 21,
          w: 6,
          h: 8,
          title: 'Shadbala',
        ),
        pieces.widget(
          astrologyDashaWidgetType,
          x: 6,
          y: chartRow + 21,
          w: 6,
          h: 8,
          title: 'Vimshottari dasha',
        ),
        pieces.widget(
          astrologyAshtakavargaWidgetType,
          y: chartRow + 29,
          w: 12,
          h: 8,
          title: 'Ashtakavarga',
        ),
        pieces.widget(
          astrologyEventsWidgetType,
          y: chartRow + 37,
          w: 12,
          h: 8,
          title: 'Life events',
          source: pieces.table(eventsViewId, name: 'Life events'),
        ),
      ]),
    ],
    variables: const [
      // An option with no default/choices starts at null. Dashboard state is
      // Object?-valued, so it can hold an AstrologyInput without serializing it.
      // Declaring the key prevents layout edits from pruning the live draft.
      DashboardVariable(key: astrologyDraftKey, label: 'Birth details draft'),
    ],
    settings: const DashboardSettings(showControlBar: false),
  );
}

DashboardWidgetSpec? _inputCard(DashboardDocument document) {
  for (final widget in document.allWidgets) {
    if (widget.type == astrologyInputWidgetType) {
      return widget;
    }
  }
  return null;
}

/// The first input card owns the shared profile, even if it has been moved.
/// Missing input means live time/location; malformed saved input is an error,
/// never a silent replacement with today's horoscope.
AstrologyInput astrologyInputFromDashboard(DashboardDocument document) {
  final profile = _inputCard(document)?.settings['profile'];
  if (profile == null) {
    return const AstrologyInput();
  }
  if (profile is! Map) {
    throw const FormatException(
      'The dashboard birth profile must be an object.',
    );
  }
  return AstrologyInput.fromJson(astrologyMap(profile));
}

/// Update only the owning input card's profile. No section/widget identities,
/// placements, custom settings, other cards or database bindings are replaced.
/// A document without an input card is returned unchanged.
DashboardDocument withAstrologyInput(
  DashboardDocument document,
  AstrologyInput input,
) {
  final card = _inputCard(document);
  return card == null
      ? document
      : document.withWidget(card.withSettings({'profile': input.toJson()}));
}

bool isAstrologyLibrary(DashboardDocument document) =>
    _inputCard(document)?.flag('library') ?? false;

/// A root library uses its own real view id, not a copied/stale setting.
String astrologyLibraryId(DashboardDocument document, String viewId) =>
    isAstrologyLibrary(document)
        ? viewId
        : _inputCard(document)?.setting('library_id') ?? '';

/// Only an Astrology life-events card bound to a database identifies this
/// person's events. An unrelated table or page card is not an events store.
String astrologyEventsViewId(DashboardDocument document) {
  for (final widget in document.allWidgets) {
    if (widget.type == astrologyEventsWidgetType &&
        widget.source.kind == DashboardSourceKind.database &&
        widget.source.isBound) {
      return widget.source.viewId;
    }
  }
  return '';
}

const _planetLabels = [
  'Sun',
  'Moon',
  'Mars',
  'Mercury',
  'Jupiter',
  'Venus',
  'Saturn',
  'Rahu',
  'Ketu',
];

/// TemplateService treats the first RichText column as PRIMARY. No invented
/// events are seeded; these are ordinary editable database fields and rows.
const TemplateTable astrologyLifeEventsTable = TemplateTable(
  columns: [
    TemplateColumn.text('Event name'),
    TemplateColumn.date('Date'),
    TemplateColumn.select('Dasha', _planetLabels),
    TemplateColumn.select('Antardasha', _planetLabels),
    TemplateColumn.select('Pratyantardasha', _planetLabels),
    TemplateColumn.text('Notes'),
  ],
);
