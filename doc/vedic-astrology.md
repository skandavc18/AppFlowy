# Vedic astrology

Enable **Vedic astrology** in Extensions. In a document, type `/astrology`:
the menu offers charts, Navamsha, dasha, Shadbala, Ashtakavarga, planetary/special
lagna placements, and Panchanga. Every block can switch between these readings,
North/South Indian layouts, and the supported Parashari divisional charts.
Click a sign for its planets, degrees, nakshatras and padas.

Retrograde planets appear in parentheses, such as `(Sa)` or `(Me)`, instead of
an `Rx` suffix. Full details still spell out **Retrograde**. The division label uses a
theme-matched center medallion in North Indian charts, or the open center in
South Indian charts. The **Vimshottari** card shows the lords running now (or
at the Transit details moment) and lays the periods out as a tree, like
Jagannatha Hora: opened periods (Mahadasha → Antardasha → Pratyantardasha)
stack as indented planet-tinted rows, the selected period's overview sits under
them, and its nine subperiods hang one step deeper, joined by connector lines.
Each subperiod row shows its span and exact start and end; the running one
draws its connector and a bottom progress track in its planet color, with the
elapsed percentage and a soft glow. Cards have no outlines: each lord has its
own gentle, well-separated tint (Mars red, Sun orange, Jupiter gold, Mercury
green, Moon aqua, Rahu blue, Saturn indigo, Ketu violet, Venus pink), drawn as
a soft diagonal gradient that sits on the page with a contact shadow and a
diffuse ambient one; badges carry a light top highlight. Text on every tint
keeps AA contrast in light, dark and paper modes. On hover or keyboard focus a
row lifts slightly, deepens its tint and shadow, grows its badge and nudges its
arrow; pressing settles it back. Click a row
(or press Enter / Space while focused) to open it one level deeper; click an
opened parent row, **Back** or **All dashas** to return. The Sookshma leaf
opens its own detail view. Current period jumps directly to the active
four-lord path. The overview gives exact start and end times with per-endpoint
UTC offsets and the time zone.
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

In **Templates**, choose **Astrology dashboard template**. The top card has two
tabs, **Birth details** and **Transit details**. Birth details accepts
a name, local date/time and birthplace. Click the date or time field (or its
calendar/clock icon) for the same compact picker that database date cells use:
one outlined date | time box above the calendar. Click the month or the year in
the calendar's header to choose from a list instead of paging month by month;
the year list covers 1800 to 2399 and opens on the shown year, and its arrows
page it. Choosing a month or year only moves the calendar; click a day to
choose it. Type the time as `HH:mm:ss` (24-hour). **Apply** updates the draft;
**Cancel**, Escape or clicking outside leaves it unchanged. Direct keyboard entry
remains available. **Today** uses the birthplace's clock, or the device clock until a
place is chosen. Blank date and time fields mean the moment **Generate** or
**Save** is clicked; there is no live toggle. **Generate** previews the input across
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
name, Date, Dasha, Antardasha, Pratyantardasha, Sookshma dasha, Moon
nakshatra, Transit Sun … Transit Ketu, Calculated for and Notes columns.

### Transit details

The **Transit details** tab has a date, a time and a place; every other
setting comes from the birth details. Opening the tab changes no card, and
nothing you type or pick is shown until you press **Apply** (below the fields;
Enter in a field applies too). **Now** fills in the current date and time and
then, once the device location is read, the current location; it does not
apply them. If the location is unavailable or permission is denied, the
fields keep the birthplace's clock and a note explains why. Search the place
field for any city (only the typed query is sent), or clear it to use the
birthplace. Times are read on the chosen place's own clock. Leaving both date
and time blank applies the live current moment, which refreshes each minute;
a blank date or time alone uses today or the current time there. The status
next to **Apply** says whether the fields are applied. The tab, moment and
place reset when the dashboard is reopened.

The transit chart always shows the applied transit (the current moment at the
birthplace until something is applied). While the Transit details tab is open
and a transit has been applied, **Panchanga** and **Planetary & special
lagnas** follow it too and show a **Transit · …** badge (with the place when
it is not the birthplace), and the Vimshottari card highlights the periods
running then, with a **Current dasha · …** badge. The birth charts (D-1, D-9
and other vargas), **Shadbala** and **Ashtakavarga** always stay natal.

New dashboards use a JHora-like arrangement: **Birth details** across the top;
then D-1, D-9 and the transit chart down the left half, beside the Vimshottari
card (top right) and Panchanga (bottom right), both halves ending together;
then full-width Shadbala and Ashtakavarga, the Life events table, Placements
and Date analysis. Every card is tall enough to show its usual content without
scrolling on a desktop window, including the Vimshottari tree down to a
Pratyantardasha's nine Sookshma dashas. Existing arrangements are not moved or
resized; drag a card's bottom edge to enlarge it.

### Automatic life-event columns

Add or change an event's **Date** and the row is filled from the person's
saved birth details a moment later:

- **Dasha → Sookshma dasha**: the natal Vimshottari lords running at that
  instant (blank outside the natal 120-year cycle).
- **Moon nakshatra**: the transiting Moon's nakshatra, pada and lord, such as
  `Rohini, pada 2 · lord Moon`.
- **Transit Sun … Transit Ketu**: sign and degree, `R` when retrograde, then
  the whole-sign house from the natal Lagna (`H`) and natal Moon (`M`), such as
  `Aquarius 5°12′ R · H10 · M11`.
- **Calculated for**: the instant used. A date without a time means local
  noon of the date shown in the Grid (this computer's time zone), and says so;
  give the date a time for the exact Moon and Sookshma dasha.

Values are ordinary cells: sort, filter or edit them. A row is recalculated
when its date changes or the person's birth details are saved again; your
edits are otherwise kept. The first calculation of rows entered before this
feature only fills empty cells. **Recalculate** (the refresh icon on the Life
events card) overwrites every calculated cell of every dated row. Removing a
date clears its calculated values; Event name and Notes are never touched.
Existing tables gain the new columns once, after Pratyantardasha; columns you
later delete, rename or retype are not recreated or written.

### Date analysis card

New dashboards include a **Date analysis** card; add it to existing dashboards
from **Add widget → Astrology · Date analysis**. It starts at *now* at the
birthplace. Choose any date (time optional: blank means noon) and the
birthplace, current location or another searched place. It shows:

- the natal Mahadasha, Antardasha, Pratyantardasha and Sookshma dasha with
  their exact start/end;
- each graha's transit sign/degree, nakshatra and pada, retrograde state, and
  houses from the natal Lagna and Moon, plus Sade Sati / Ardhashtama /
  Ashtama Shani notes;
- panchanga: vara and lord, tithi, nakshatra, yoga and karana with their end
  times (found from the actual longitudes and speeds), sunrise/sunset and the
  Moon/Sun signs;
- muhurta: Brahma muhurta (14th of 15 night muhurtas), Rahu Kalam, Yamaganda
  and Gulika Kalam (weekday eighths of daytime), Abhijit (8th of 15 day
  muhurtas; not used on Wednesday), the planetary hora in effect, and Tara and
  Chandra bala from the natal Moon. Without a saved birth time only the date's
  own panchanga, transits and muhurta appear.

### Jagannatha Hora files and PDF reports

The birth-details card has **Open .jhd**, **Save .jhd**, **Save PDF** and
**Print**.

- **Open .jhd** reads a Jagannatha Hora birth file into the dashboard draft;
  review it, then **Save** to keep it. The file name becomes the chart name,
  as in JHora. Date, local time, time zone, longitude and latitude are read in
  JHora's packed `D.MMSS` notation (east longitudes and zones are negative);
  city and country are used when present. Older files that store planet
  longitudes after line 8 are accepted and those longitudes ignored. When the
  file's zone matches the place's historical IANA rules the zone is kept;
  otherwise its fixed offset is kept (a local-mean-time offset with seconds is
  shown rounded to the minute while the birth instant stays exact). Style,
  ayanamsha, node and dasha-year settings, which a .jhd does not store, come
  from the dashboard.
- **Save .jhd** writes the same 18-line layout JHora 8 uses (CRLF, Latin-1;
  characters outside Latin-1 become `?`). Live horoscopes are frozen at the
  current second and device location first.
- **Save PDF** / **Print** produce an A4 report: birth data, D-1 and D-9 charts
  in the selected style, panchanga at birth, planetary positions (longitude,
  nakshatra/pada/lord, house, D-9, speed, retrograde, chara karaka), special
  lagnas (Bhava, Hora, Ghati, Gulika, Maandi, Sri) and the Sun-based upagrahas
  (Dhuma, Vyatipata, Parivesha, Indrachapa, Upaketu), D-1…D-30 signs, the full
  Vimshottari Mahadasha/Antardasha table with the dasha running on the report
  date, Shadbala components and ratios, and the Ashtakavarga BAV/SAV table.
  Fonts are bundled; nothing is uploaded.

Without a place, **Generate** and **Save** request the device's current
location. A denied permission or unavailable sensor is shown explicitly;
there is no guessed default city. Enter a place or coordinates instead.
Charts that follow the current moment refresh each minute while the
application is open and resumed.

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
and `vedic_chart_view_test.dart`. `astrology_ephemeris_test.dart` and
`astrology_panchanga_ephemeris_test.dart` use the real
Windows `sweph.dll` from the app Debug bundle or `build/astrology_ephemeris/Release`;
an explicit `ASTROLOGY_TEST_LIBRARY` Dart define can name another build. The
native group reports a skip if no library has been built. Tests use temporary
ephemeris directories, never the user's workspace data. The native panchanga
test checks every limb's end time by recalculating one second before and after
it. `astrology_jhd_test.dart` reads the layouts of the sample files shipped
with JHora 8 (including local-mean-time and older 18-line files) and round
trips east/west/north/south places.

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