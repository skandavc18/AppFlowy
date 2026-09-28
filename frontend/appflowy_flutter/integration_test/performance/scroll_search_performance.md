# Offline scroll / Find AFTER fixture

**Authored only: not compiled, run, visually reviewed or measured.** No FPS result
is supplied by this change. It complements, but does not rerun or certify, the
existing operation-count/unit-test baseline.

## Entry point and consent

`integration_test/performance/scroll_search_performance_test.dart` is an isolated
entry point, not normal AppFlowy startup. Required: Windows and
`--dart-define=PERF_SCROLL_SEARCH=true`. It displays a temporary fixture route.
No normal app main, auth, preferences, GetIt registrations, workspace/user data,
HTTP, native input, native source edits, screenshots or new plugins are used.
Synthetic PNG bytes are generated in memory only when the fixture executes.

Options:

| Define | Meaning |
| --- | --- |
| `PERF_THEME=light` | `light`, `dark` or `paper`; one appearance per run |
| `PERF_RUN=scroll_search` | Synthetic driver report label |
| `PERF_OUTPUT_DIRECTORY=<absolute directory>` | Direct JSON receipt; required in Release |

No platform test override or `debugSemantics` is used. No semantics handle is
acquired. Find is controlled through its real controller API, not keyboard input;
there is no inferred-physical-key hazard or claim of keyboard routing coverage.

## What is measured

- Six approximately two-second real-clock windows: N=10/50/100, active Find and
  closed Find retaining the same query. Two independent panes per retained tab:
  real DashboardCards and a real package AppFlowyEditor with 1,000 occurrences.
- N/2 text cards, N/2 unknown-widget cards per tab. The supported page embed is
  separate from these N cards. There are **2N mounted cards and two editors**,
  including the previously queried, open-but-offstage hidden tab. All cards are
  eager; this is not production dashboard virtualization or service-backed pages.
- One actual 3000×2000 synthetic PNG reused across gallery-like image faces.
  The scrolling preload resolves on the real clock before mounting and retains
  its stream/ImageInfo. It is not N distinct cold photos, a painted rectangle,
  `FolderGalleryCard`, cache-manager loading or network performance.
- Identical source bytes through the plain decoder bypass and production
  `CoverImageProvider`: unique-key cold, retained-cache warm, and cold with an
  explicitly injected 80ms byte-availability delay. Decode dimensions, estimated
  RGBA size, source-to-decoded time, first image UI frame and that frame's engine
  build/raster durations are separate. Warm-up/order/cache effects still exist;
  repeat runs before drawing conclusions. This is a same-build policy comparison,
  **not** a historical app-version or global FPS baseline.

Only Flutter `PointerScrollEvent`s are delivered to this native fixture's view.
100 input slots are scheduled over two seconds, alternating both scrollables;
late slots are skipped, not burst-replayed. Events and actual duration are
reported. No pump loop, persistent frame callback or timer forces idle frames.
The fixture-only binding suppresses Flutter 3.27 LiveTest's automatic idle-frame
loop: benchmark policy at draw time, with normal widget `scheduleFrame` and
`scheduleForcedFrame` requests admitted through the superclass. It does not
override production widgets, native rendering or the engine clock.
Setup uses a fixed pair of pumps and event futures, plus a passive 220ms allowance
for the real Find entrance animation outside timing. Frame callbacks are passive;
engine frame numbers assign batched samples, not callback arrival time; each
timing's raw timestamps supply the durations and inter-frame intervals. Terminal
frame receipts have a ten-second watchdog. Empty samples fail.

Raw frame timings and min/max/mean/p50/p95/p99 build/raster/total-span distributions
are reported, as are frame-start intervals. These are **not presentation FPS**:
input cadence, intentional idle intervals and external desktop load affect them.
There is no arbitrary 60Hz target or loosened regression timing assertion.
Typical work is intended to fit roughly 30 seconds, but native batching/setup
and machine load can extend it; the overall test watchdog is two minutes.

Assertions check exact 1,000 native paragraph word rectangles against highlight
rectangles/current marker, both scroll offsets moving, retained element/editor
identity, unchanged selection, no forbidden secondary document reads, and zero
read deltas during active/closed/hidden measurement windows. Closed Find has no
matches/highlights/subscription. Hidden Find is revoked with one owner revision
before timing. Operation callbacks are deliberately not installed: they are
assert-only in production and would misleadingly read as zero in AOT.

## Owner-run instructions (not executed during authoring)

After other owners' unit validation is finished, run the native fixture **before
the normal Release-then-Debug bundle restoration**. Use an idle, visible fixture
window and keep size/DPR/theme identical across repeats. Do not point a command
at the normal app's user profile or launch its main entry point. Compilation may
reuse desktop build output, so do not mistake the fixture executable for a normal
AppFlowy bundle.

From `C:\AppFlowy\frontend\appflowy_flutter`, the existing driver can collect a
Debug run (requires the normal Flutter VM-service connection):

```powershell
flutter drive -d windows --debug --driver=test_driver/large_page_performance_driver.dart --target=integration_test/performance/scroll_search_performance_test.dart --dart-define=PERF_SCROLL_SEARCH=true --dart-define=PERF_RUN=scroll_search_debug --dart-define=PERF_THEME=light
```

Driver output: `build/performance/large_page_scroll_search_debug.json` via
`binding.reportData`. Use a distinct `PERF_RUN` for each repeat/theme.

For native Release, the driver is **not** an AOT transport: `integrationDriver`
requires a VM service. Build this entry point and launch its own executable;
the direct receipt does not need a debug protocol or integration-report plugin:

```powershell
flutter build windows --release --target=integration_test/performance/scroll_search_performance_test.dart --dart-define=PERF_SCROLL_SEARCH=true --dart-define=PERF_THEME=light --dart-define=PERF_OUTPUT_DIRECTORY=C:/AppFlowy/build/performance --dart-define=INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false
& .\build\windows\x64\runner\Release\AppFlowy.exe
```

The direct path also supports Debug by replacing `--release` and `Release` with
`--debug` and `Debug`. Output is a new unique directory each time:
`C:/AppFlowy/build/performance/scroll_search_<mode>_<unique>/report.json`.
It is flushed after `allTestsPassed`, including a false result on test failure;
require **both** `test_success: true` and `measurement_complete: true`. A missing
receipt, timeout, empty sample or incomplete report is not success. Reports omit
raw test failures, paths, source text, identifiers and stack traces. The tiny
completed fixture window remains open; close only that process/window yourself.

Finally restore and verify the normal app using the existing Windows bundle task
(normal `lib/main.dart` entry point): Release first, Debug last, both refreshed
executables and Debug kernel asset verified. Do not run the fixture after that
restoration without restoring again. This authoring change performs none of
these commands, launches, tests or builds.