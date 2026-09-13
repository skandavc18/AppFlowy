# Vedic astrology

Enable **Vedic astrology** in Extensions. In a document, type `/astrology`:
the menu offers charts, Navamsha, dasha, Shadbala, Ashtakavarga, planetary/special
lagna placements, and Panchanga. Every block can switch between these readings,
North/South Indian layouts, and the supported Parashari divisional charts.
Click a sign for its planets, degrees, nakshatras and padas.

Retrograde planets appear in parentheses, such as `(Sa)` or `(Me)`, instead of
an `Rx` suffix. Full details still spell out **Retrograde**. The division label uses a
theme-matched center medallion in North Indian charts, or the open center in
South Indian charts. Click anywhere on a dasha period card (or press Enter /
Space while focused) to open its full-card overview and subperiod list. Back
and breadcrumbs return to its parents; the Sookshma leaf opens its own detail
view. Current period jumps directly to the active four-lord path. Start and end
dates are spaced separately, with exact times and per-endpoint UTC offsets.
The vertical **Shadbala** graph plots each planet's total as a percentage of its
own required minimum: `total ÷ minimum × 100`, so 360 virupas against a minimum
of 300 is **120%**. The shared percentage axis includes 100% (minimum met), with
no per-planet threshold strokes. Hover or keyboard focus reveals the percentage,
all six raw strengths, required strength and ratio; the numeric table retains
virupas and rupas. The calculation convention is under **Method details**, not
the chart title. No planet is highlighted by default; select a planet to highlight
it and retain its breakdown. Scrolling over an unselected astrology card scrolls
the surrounding page. Click the card to select it and scroll its contents; the
selection outline and scroll activation use the same state. Hover or keyboard
focus alone does not select a dashboard card. Click outside or press an unhandled
Escape to deselect it and return scrolling to the page. The first click still
works on buttons, fields and charts. Editor embeds activate on click or keyboard
focus; enlarged views and dialogs scroll immediately.
Cards have no visible scrollbar rails, including on narrow charts and tables.

## Saved horoscopes

In **Templates**, choose **Astrology dashboard template**. The top card accepts
a name, local date/time and birthplace. Click the date or time field (or its
calendar/clock icon) for a compact calendar popover with month/year navigation
and hour, minute and second pickers. **Apply** updates the draft; **Cancel**,
Escape or clicking outside leaves it unchanged. Direct keyboard entry remains
available. **Today** uses the birthplace's clock, or the device clock until a
place is chosen. **Generate** previews the input across
all cards; **Save as person’s dashboard** creates an actual child dashboard.
Repeat to add people. The template's **Saved horoscopes** table sits directly
below **Birth details**, with **Name**, **Date of birth**, **Time of birth** and
**Place of birth** columns. Click anywhere on a row, or press Enter / Space
while it is focused, to open that person's dashboard. The sidebar works too.
Dates and times use the saved birthplace's timezone or manual offset, with the
UTC offset shown below the time—not this computer's timezone. Missing details
say **Not saved**; invalid profiles say **Unavailable** without losing their
dashboard links. The table refreshes on saved-profile and child-page changes;
**Refresh** / **Retry** also rereads the saved dashboards. It appears only on the
template/library dashboard, never on an individual person's dashboard. Existing
saved layouts are preserved.

**Save changes** updates a person's profile without replacing its arrangement
or notes.
Each person owns a separate, ordinary editable **Life events** Grid with Event
name, Date, Dasha, Antardasha, Pratyantardasha and Notes columns. Its dasha
columns are manually editable planet choices, not inferred event predictions.

Blank/live inputs use the current clock and request the device's current
location. A denied permission or unavailable sensor is shown explicitly;
there is no guessed default city. Enter a place or coordinates instead. The
transit card can switch between current location and birthplace. Live charts
refresh each minute while the application is open and resumed.

Birthplace suggestions drop down while typing after at least three characters
and a short pause. Choose a result with the mouse, or use Up/Down and Enter;
Escape or leaving the field dismisses the list. **Search** also supports an
explicit two-character query and retry. A typed name is not automatically
treated as a chosen location. Suggestions use the keyless **Photon** geocoder
with OpenStreetMap data, not Nominatim's autocomplete-prohibited public API.
Only the place query is sent; names, birth dates/times and device coordinates
are not included. The bounded query cache is in memory only. Photon's public
demo has fair-use limits and no availability guarantee; throttled/offline
searches offer manual coordinates instead of fabricated results.
Coordinates and the IANA time zone are displayed and editable;
verify the zone near political boundaries. A manual UTC offset overrides IANA
rules and resolves duplicated daylight-saving clock times. Nonexistent dates
and DST gaps are rejected. A saved horoscope freezes its actual UTC instant.

## Ayanamsha settings

The birth-details form shows an **Ayanamsha** selector without opening Advanced.
**Lahiri** remains the default. Available presets are **B.V. Raman**, **KP
(Krishnamurti)**, **Pushya Paksha**, **Yukteshwar**, **Surya Siddhanta**, and the
existing **True Chitra**. These use Swiss Ephemeris modes 3, 5, 29, 7, 21 and 27,
respectively; Surya Siddhanta selects its ayanamsha, not a different planetary
ephemeris. Devadutta is deferred until its reference definition is supplied;
it is not silently mapped to another preset.

**Custom adjustment** adds or subtracts degrees, arcminutes and fractional
arcseconds from the selected preset, like JHora's correction panel. Adding a
positive correction increases the ayanamsha and decreases sidereal longitudes.
**Reset adjustment to zero** removes it. Hiding the panel does not reset it.
Generate recalculates the dashboard draft; Save stores the settings with that
person. The birth UTC instant, timezone and location remain unchanged. Charts,
vargas, dasha and lagnas are recalculated, and live transits inherit the settings.
Chart captions and Panchanga identify an active correction.

## Calculations and limits

- Swiss Ephemeris **2.10.3** through pinned `sweph 3.2.1+2.10.3`, using bundled
  planet/Moon ephemerides for **1800–2399**. Geocentric apparent sidereal
  positions with speed; Lahiri is the default. The presets and signed
  corrections above, and mean/true Rahu, are selectable. Ketu is Rahu's antipode.
- Whole-sign houses. D1, Parashari D2, D3, D4, D7, D9, D10, D12 and unequal
  Parashari D30 sign mappings. Detail degrees/nakshatras remain the original
  D1 position, not a claimed physical position in a divisional chart.
- Jaimini **chara karakas** appear in Planetary & special lagnas. Choose the
  seven-planet system (Sun–Saturn; default) or eight-karaka system (adds Rahu
  and a separate Pitri role). Original, unrounded degrees within the D1 sign
  are ranked highest to lowest: AK, AmK, BK, MK, [PiK], PK, GK, DK. Rahu alone
  uses `30° − degree within sign`; Ketu and special lagnas are excluded.
  Other retrograde planets are not reversed. Differences within 1e-10 degrees
  are reported as tied/unresolved roles, not assigned by an arbitrary
  secondary rule. The detail table includes full names, ranking degrees and
  traditional significations, not predictions.
- Vimshottari: full 120-year cycle with Mahadasha, Antardasha,
  Pratyantardasha and **Sookshma dasha**. Default year 365.25636 days; 365.25 and
  360 are selectable. The birth mahadasha retains its elapsed pre-birth
  portion when subdivided. Cumulative integer microsecond boundaries keep all
  nine subperiods contiguous through the fourth level.
- Unreduced Parashari BAV, SAV and inspectable Prastara contributions. Planet
  totals are 48, 49, 39, 54, 56, 52, 39. SAV totals **337**; the separately
  displayed 49-point Lagna BAV is not added to SAV.
- Bhava/Hora/Ghati Lagna: sunrise Sun plus elapsed minutes × 0.25/0.5/1.25.
  Gulika/Maandi: ascendant at the beginning/middle of Saturn's eighth of the
  day or night. Sri Lagna uses the elapsed fraction of the Moon's nakshatra.
  Hindu sunrise uses the geocentric disc center without refraction. Pre-dawn
  belongs to the previous Vedic day. No invented sunrise at polar latitudes:
  dependent lagnas and full Shadbala are explicitly unavailable there.
- **Shadbala uses the tested JHora 8 reference convention**, not coarse
  motion-state strength buckets. The UI retains all six components and their
  breakdown. Continuous mean-longitude Cheshta uses the traditional 1900
  midnight/76°E LMT tables and a wrap-safe mean/true midpoint. Its coordinate
  reference stays consistent when changing ayanamsha. Drekkana strength uses
  male/neutral/female planets in the first/middle/last decan. Required minima
  for Sun through Saturn are **300, 360, 300, 420, 390, 330, 300** virupas.
- Reference-compatible Dig uses equal-house angular points from the ascendant;
  Natonnata uses the Sun's corresponding angular arc. Varsha/Masa use 360/30-day
  cycles, independent of the dasha-year option. Horas use elapsed equal hours
  from the preceding sunrise. A bright Moon (elongation 90°–270°) is benefic;
  a dark Moon is malefic even while waxing. Mercury is malefic when sharing a
  sign with a malefic. Sun Ayana and Moon Paksha are doubled without adding
  their displayed Cheshta again. Natural strengths retain JHora's legacy
  weights (60, 51.43, 17.14, 25.70, 34.28, 42.85, 8.57).
- **Legacy Ayana is not physical declination:** it uses the traditional 15°
  kranti table with a fixed 23° reference, as observed in JHora's 1900, 1999,
  and 2026 component tables. The actual chart ayanamsha and planetary
  longitudes are never rounded to whole degrees. Drik interpolates bounded
  full/partial Parashari aspect points. Yuddha retains northern latitude and
  apparent disc diameters; the reference cases do not certify planetary war.
  These choices are explicit under Method details. Different JHora settings,
  ephemeris versions and traditions can differ; this is not certification of
  every configurable JHora calculation or of the tables over six centuries.

The software provides traditional astrology calculations, not scientifically
validated predictions or medical, financial or other professional advice.

## Sources and licensing

- Swiss Ephemeris and its data: Astrodienst AG, AGPL-3.0 open-source path,
  compatible with AppFlowy's AGPL distribution. See the dependency's preserved
  notices and https://www.astro.com/swisseph/swephprg.htm . No professional
  license is bundled or required for the AGPL path.
- Classical bindu rules and motion-state methodology were cross-checked with
  Maitreya (Martin Pettau, GPL-2.0-or-later),
  https://github.com/martin-pe/maitreya8/tree/master/src/jyotish .
- Continuous Cheshta and tabular kranti: B.V. Raman, *Graha and Bhava Balas*,
  1942, §§72–75 and §§87–107. Formula examples and native JHora component
  tables are regression fixtures; no proprietary calculation code is copied.
- Special lagna and dasha conventions were cross-checked with PyJHora
  (AGPL-3.0), https://github.com/naturalstupid/PyJHora . AppFlowy does not
  depend on a local Python installation or a remotely hosted astrology API.
- Coordinate-to-zone mapper: `lat_lng_to_timezone`, MIT. Historical zone rules:
  `timezone` bundled IANA database. Current location: `geolocator`, MIT.
- Place suggestions: [Photon](https://photon.komoot.io/), built on
  [OpenStreetMap data © contributors](https://www.openstreetmap.org/copyright),
  available under ODbL. The dropdown includes a clickable attribution.
  [Photon's public-server policy](https://github.com/komoot/photon#demo-server)
  permits reasonable search-as-you-type use; larger deployments should use a
  dedicated Photon instance. The adapter accepts an injected HTTPS endpoint.

## Verification

Tests live in `frontend/appflowy_flutter/test/unit_test/extensions/astrology*`
and `vedic_chart_view_test.dart`. `astrology_ephemeris_test.dart` uses the real
Windows `sweph.dll` from the app Debug bundle or `build/astrology_ephemeris/Release`;
an explicit `ASTROLOGY_TEST_LIBRARY` Dart define can name another build. The
native group reports a skip if no library has been built. Tests use temporary
ephemeris directories, never the user's workspace data.

The screenshot regression uses 2026-09-11 19:16:15 at UTC+05:30,
12°59′ N / 77°35′ E. Its ayanamsa settings were not visible, so the test uses a
documented 0.1° comparison tolerance, not an exact-settings claim. Dedicated
tests pin sign/pada boundaries, full dasha partitions, DST gaps/overlaps,
bindu totals, all six strength sums, polar handling, previews, form validation,
chart hit testing, and saved-person hierarchy/failure recovery.

`shadbala_reference_test.dart` pins independently read JHora 8 totals and
components for **1999-12-18 15:15 IST** and **2026-09-11 19:16:09 IST** in
Bangalore (12°59′ N, 77°35′ E), plus historical and lunar-phase checks. The
1999 rounded percentages are **121, 109, 129, 101, 165, 132, 110**. Component
tolerance is 0.06 virupa for older true-position ephemerides, printed precision
and mean-table precision—not an arbitrary percentage allowance. Pure tests
also cover the published mean-Cheshta example, angle wrap, period boundaries,
hora boundaries and missing polar events. Ayanamsha tests use every native
preset, signed fractional corrections, unchanged UTC/DST, saved drafts and
paper/light/dark surfaces at narrow widths and enlarged text.