import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_data_source.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/templates/built_in/template_pieces.dart'
    as pieces;
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:flutter/material.dart' show Icons, immutable;

const astrologyInputWidgetType = 'ext.astrology.input';
const astrologyChartWidgetType = 'ext.astrology.chart';
const astrologyDashaWidgetType = 'ext.astrology.dasha';
const astrologyShadbalaWidgetType = 'ext.astrology.shadbala';
const astrologyAshtakavargaWidgetType = 'ext.astrology.ashtakavarga';
const astrologyPlacementsWidgetType = 'ext.astrology.placements';
const astrologyPanchangaWidgetType = 'ext.astrology.panchanga';
const astrologyLibraryWidgetType = 'ext.astrology.library';
const astrologyEventsWidgetType = 'ext.astrology.events';
const astrologyDateAnalysisWidgetType = 'ext.astrology.date_analysis';
const astrologyDraftKey = 'astrology_input_draft';
const astrologyTransitKey = 'astrology_transit';

/// The Transit details tab of the birth card, held in dashboard state only:
/// it is never saved with the horoscope.
@immutable
class AstrologyTransitState {
  const AstrologyTransitState({
    this.active = false,
    this.applied = false,
    this.utc,
    this.place,
  });

  /// The Transit details tab is the one shown.
  final bool active;

  /// Apply has been pressed. Opening the tab alone changes no reading.
  final bool applied;

  /// The applied transit moment. Null follows the current moment.
  final DateTime? utc;

  /// Where the transit is cast. Null is the birthplace.
  final AstrologyPlace? place;

  /// Panchanga, placements and dasha cards read the applied transit while
  /// the tab is open; birth-fixed cards stay natal.
  bool get following => active && applied;

  AstrologyTransitState withActive(bool active) => AstrologyTransitState(
        active: active,
        applied: applied,
        utc: utc,
        place: place,
      );

  /// Applies [utc] (null: now) at [place] (null: the birthplace).
  AstrologyTransitState withMoment(DateTime? utc, {AstrologyPlace? place}) =>
      AstrologyTransitState(
        active: active,
        applied: true,
        utc: utc?.toUtc(),
        place: place,
      );

  @override
  bool operator ==(Object other) =>
      other is AstrologyTransitState &&
      other.active == active &&
      other.applied == applied &&
      other.utc == utc &&
      astrologySamePlace(other.place, place);

  @override
  int get hashCode => Object.hash(
        active,
        applied,
        utc,
        place?.name,
        place?.latitude,
        place?.longitude,
        place?.timeZone,
        place?.isDeviceLocation,
      );
}

/// Places have no value equality of their own.
bool astrologySamePlace(AstrologyPlace? a, AstrologyPlace? b) =>
    identical(a, b) ||
    (a != null &&
        b != null &&
        a.name == b.name &&
        a.latitude == b.latitude &&
        a.longitude == b.longitude &&
        a.timeZone == b.timeZone &&
        a.isDeviceLocation == b.isDeviceLocation);

AstrologyTransitState astrologyTransitState(DashboardStateValues state) {
  final value = state[astrologyTransitKey];
  return value is AstrologyTransitState ? value : const AstrologyTransitState();
}

/// The birth settings cast for [utc] (null: now) at [place], or at the
/// birthplace when [place] is null. A transit never reuses a manual birth-time
/// UTC offset, which may predate a DST change, unless the birthplace has no
/// IANA zone and that offset is its only clock.
AstrologyInput astrologyTransitInput(
  AstrologyInput natal,
  DateTime? utc, {
  AstrologyPlace? place,
}) {
  final at = place ?? natal.place;
  return AstrologyInput(
    utc: utc?.toUtc(),
    place: at,
    utcOffsetMinutes: place == null && at != null && at.timeZone.trim().isEmpty
        ? natal.utcOffsetMinutes
        : null,
    style: natal.style,
    ayanamsa: natal.ayanamsa,
    ayanamsaOffsetArcseconds: natal.ayanamsaOffsetArcseconds,
    trueNode: natal.trueNode,
    dashaYearDays: natal.dashaYearDays,
  );
}

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

/// A JHora-like arrangement on the dashboard's responsive 12-column grid:
/// birth details on top; the charts down the left beside the dasha, with the
/// panchanga under it; Shadbala and Ashtakavarga below; then the life events,
/// placements and date analysis. Heights let each card's usual content show
/// without scrolling on a desktop canvas, and both halves of the chart band
/// end together. Half-width cards stay side by side at every even-column
/// breakpoint.
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
  final band = library ? 14 : 9;
  // Three 14-row charts beside the dasha (29) and panchanga (13).
  final below = band + 42;
  return DashboardDocument(
    sections: [
      pieces.section([
        pieces.widget(
          astrologyInputWidgetType,
          w: 12,
          h: 9,
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
            y: 9,
            w: 12,
            h: 5,
            title: 'Saved horoscopes',
          ),
        pieces.widget(
          astrologyChartWidgetType,
          y: band,
          w: 6,
          h: 14,
          title: 'Lagna · D-1',
          settings: const {'division': 1},
        ),
        pieces.widget(
          astrologyDashaWidgetType,
          x: 6,
          y: band,
          w: 6,
          h: 29,
          title: 'Vimshottari dasha',
        ),
        pieces.widget(
          astrologyChartWidgetType,
          y: band + 14,
          w: 6,
          h: 14,
          title: 'Navamsha · D-9',
          settings: const {'division': 9},
        ),
        pieces.widget(
          astrologyChartWidgetType,
          y: band + 28,
          w: 6,
          h: 14,
          title: 'Transit · D-1',
          settings: const {'transit': true},
        ),
        pieces.widget(
          astrologyPanchangaWidgetType,
          x: 6,
          y: band + 29,
          w: 6,
          h: 13,
          title: 'Panchanga',
        ),
        pieces.widget(
          astrologyShadbalaWidgetType,
          y: below,
          w: 12,
          h: 14,
          title: 'Shadbala',
        ),
        pieces.widget(
          astrologyAshtakavargaWidgetType,
          y: below + 14,
          w: 12,
          h: 32,
          title: 'Ashtakavarga',
        ),
        pieces.widget(
          astrologyEventsWidgetType,
          y: below + 46,
          w: 12,
          h: 12,
          title: 'Life events',
          source: pieces.table(eventsViewId, name: 'Life events'),
        ),
        pieces.widget(
          astrologyPlacementsWidgetType,
          y: below + 58,
          w: 12,
          h: 21,
          title: 'Planetary & special lagnas',
        ),
        pieces.widget(
          astrologyDateAnalysisWidgetType,
          y: below + 79,
          w: 12,
          h: 19,
          title: 'Date analysis',
        ),
      ]),
    ],
    variables: const [
      // An option with no default/choices starts at null. Dashboard state is
      // Object?-valued, so it can hold an AstrologyInput without serializing it.
      // Declaring the key prevents layout edits from pruning the live draft.
      DashboardVariable(key: astrologyDraftKey, label: 'Birth details draft'),
      DashboardVariable(key: astrologyTransitKey, label: 'Transit details'),
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

/// Columns filled from each row's Date by the events sync. Names identify
/// them; users may reorder, hide or delete them without breaking the table.
const astrologyDashaColumns = [
  'Dasha',
  'Antardasha',
  'Pratyantardasha',
  'Sookshma dasha',
];
const astrologyMoonNakshatraColumn = 'Moon nakshatra';

/// Indexed like [VedicBody.values].
const astrologyTransitColumns = [
  'Transit Sun',
  'Transit Moon',
  'Transit Mars',
  'Transit Mercury',
  'Transit Jupiter',
  'Transit Venus',
  'Transit Saturn',
  'Transit Rahu',
  'Transit Ketu',
];
const astrologyCalculatedForColumn = 'Calculated for';

/// TemplateService treats the first RichText column as PRIMARY. No invented
/// events are seeded; these are ordinary editable database fields and rows.
const TemplateTable astrologyLifeEventsTable = TemplateTable(
  columns: [
    TemplateColumn.text('Event name'),
    TemplateColumn.date('Date'),
    TemplateColumn.select('Dasha', _planetLabels),
    TemplateColumn.select('Antardasha', _planetLabels),
    TemplateColumn.select('Pratyantardasha', _planetLabels),
    TemplateColumn.select('Sookshma dasha', _planetLabels),
    TemplateColumn.text('Moon nakshatra'),
    TemplateColumn.text('Transit Sun'),
    TemplateColumn.text('Transit Moon'),
    TemplateColumn.text('Transit Mars'),
    TemplateColumn.text('Transit Mercury'),
    TemplateColumn.text('Transit Jupiter'),
    TemplateColumn.text('Transit Venus'),
    TemplateColumn.text('Transit Saturn'),
    TemplateColumn.text('Transit Rahu'),
    TemplateColumn.text('Transit Ketu'),
    TemplateColumn.text('Calculated for'),
    TemplateColumn.text('Notes'),
  ],
);
