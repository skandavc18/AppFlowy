# Large-page loading and scrolling performance

## Windows startup profiling (2026-09-20)

The normal Release application was measured over three controlled relaunches of
the same workspace, without clearing OS/application caches or changing saved
settings. The user approved normal closes and restarts. These are **relaunch
samples, not cold-boot benchmarks**.

| Baseline sample | Native SDK initialization | Application initialization | Process → first raster | Process → page host frame |
| --- | ---: | ---: | ---: | ---: |
| 1 | 8,280.227 ms | 8,952.032 ms | 11,635.184 ms | 12,553.476 ms |
| 2 | 2,040.120 ms | 2,392.661 ms | 4,153.541 ms | 4,669.391 ms |
| 3 | 2,066.229 ms | 2,484.531 ms | 3,450.300 ms | 3,925.254 ms |

Device identification took only 2.7–3.1 ms, ruling out the initially suspected
Windows device-info query. A previous startup log places roughly seven seconds
between `CollabKVDB::open` entering and returning. No database repair, migration,
encryption or authentication checks were removed to improve those timings.

### Build configuration defect

The Flutter Release bundle contained the **Debug Rust backend**: its staged
122,320,384-byte `dart_ffi.dll` matched the development artifact. RocksDB's actual
native build output reports `OPT_LEVEL = Some(0)` and `DEBUG = Some(true)`.
`NDEBUG` in RocksDB's C++ build script disables assertions; it does **not** mean
that compiler optimization is enabled. Flutter's Release flag does not rebuild
this separately staged DLL.

`tool/build_windows_backend.ps1` now builds the locked Rust sources as an
optimized Windows `cdylib`, verifies Cargo's artifact/profile response, and only
then stages it. `tool/build_windows_bundles.ps1` invokes this before either
Flutter configuration, includes Rust inputs and the staged DLL in its input
snapshot, and verifies the bundled native hash against the build result. Both
Flutter bundles still receive the same native backend; Debug retains Flutter's
JIT/debugging behavior and separate data-location policy. Startup ordering,
database formats, device identity and recovery remain unchanged.

The rebuilt native DLL is 59,550,208 bytes; its Cargo artifact reports
optimization level 3, and the actual RocksDB build output now reports
`OPT_LEVEL = Some(3)` / `DEBUG = Some(false)`. Nine isolated build-guard checks
reject failed, unoptimized, wrong-path, duplicate and empty artifacts without
replacing the staged runtime. Six bundle-parity checks and 20 privacy/bounded
capture checks also pass. The capture tests never launch an application.

### Measured result and remaining limit

A second three-launch baseline was captured immediately before the final
rebuild, still using the old backend. Compare against that faster repeat
baseline rather than attributing all variation from the original run to the
change. Both batches used the same saved workspace and the same profiling flag.

| Batch / sample | Native SDK (ms) | Initialization (ms) | Process → first raster (ms) | Process → page host (ms) |
| --- | ---: | ---: | ---: | ---: |
| Repeat baseline / 1 | 6,485.52 | 6,895.51 | 8,975.52 | 9,527.55 |
| Repeat baseline / 2 | 1,979.71 | 2,441.84 | 2,978.03 | 3,489.95 |
| Repeat baseline / 3 | 1,876.08 | 2,278.97 | 2,854.69 | 3,357.41 |
| Optimized / 1 | 6,102.61 | 6,565.06 | 8,679.63 | 9,317.19 |
| Optimized / 2 | 641.05 | 1,033.16 | 1,602.90 | 2,141.41 |
| Optimized / 3 | 700.27 | 1,165.86 | 1,917.41 | 2,475.13 |

Three-sample medians: native SDK **1,979.71 → 700.27 ms** (64.63% lower),
initialization **2,441.84 → 1,165.86 ms** (52.25% lower), first raster
**2,978.03 → 1,917.41 ms** (35.61% lower), page host
**3,489.95 → 2,475.13 ms** (29.08% lower). All nine measured processes across
the original/repeat/optimized batches had responsive windows, all required
milestones, zero detected error markers, and normal exit code zero.

**The slow first sample is not solved:** the optimized batch still took 8.68 s
to first raster and 9.32 s to the page host. Its native initialization alone
took 6.10 s. OS caches, file loading and scheduling were not controlled; these
results are not evidence of uniformly sub-two-second startup or a cold-boot
speedup. Further native database-open profiling is needed for the residual
delay, without weakening recovery or consistency checks. Reports:
`startup-release-before.json`, `startup-release-before-repeat.json`, and
`startup-release-after.json` under `build/performance/`.

### Final bundle verification

Both normal bundles were built Release first, Debug last and independently
rechecked against **4,791 current input hashes**, **1,179 matching functional
assets**, and **36 native components**. Both contain the same optimized backend
(SHA-256 `38BBE9453818155E3E48093E5381EBA02135B5923751170FE408AE6798950371`).
All four executable/runtime artifacts are newer than their own build starts
and the latest changed application source; Debug's kernel remains present.

| Artifact under `frontend/appflowy_flutter/build/windows/x64/runner/` | UTC on 2026-09-20 |
| --- | --- |
| `Release/AppFlowy.exe` | 09:56:09 |
| `Release/data/app.so` | 09:55:08 |
| `Debug/AppFlowy.exe` | 09:59:19 |
| `Debug/data/flutter_assets/kernel_blob.bin` | 09:58:22 |

### Reproduction and timing boundaries

After saving work and normally closing AppFlowy, build with
`tool/build_windows_bundles.ps1`, then run `tool/profile_windows_startup.ps1`
with a distinct `-Label` and `-Runs 3`. The app's `--profile-startup` flag enables
fixed symbolic phase names, monotonic microsecond durations and success flags.
It does not log account IDs, document contents or exceptions in the timing data.
The runner discards other output and records only heuristic error-line counts.

Initialization durations use Dart's monotonic clock. Process-to-frame arrival
times also include native/DLL loading and stdout delivery/scheduling. The page
milestone is the **plugin host's first frame**, not completion of every embedded
renderer or network request. The runner refuses existing AppFlowy processes,
verifies the process image, checks window responsiveness, and closes only its
own launches normally; it never force-kills. Reopen Release after measurement.
Reports are in `build/performance/startup-{label}.json`; current reports also
hash the native DLL and AOT/kernel payload, since an unchanged native launcher
hash alone does not identify application code.

## Debug/Release functional parity and memory follow-up (2026-09-16)

After confirming the dashboard leak fix, the user reported high remaining RAM
and missing Release features. There were real functional differences, not just
different optimization levels:

- `FeatureFlagTask` skipped saved flag initialization outside Debug. Flags now
  load in every build, with the existing released-feature defaults unchanged.
- Removed compiler-mode gates from supported legacy imports, JSON/raw database
  exports, data-export/dry-run health controls, feature-flag settings, shared-page
  refresh, mobile notification unarchive, and custom cloud-provider choices.
  Existing permissions, file pickers, server-change confirmations and the
  `Env.enableCustomCloud` setting remain in effect.
- Billing now uses the **same existing restricted server list and cloud-owner
  checks in both modes**, rather than copying Debug bypasses into Release.
  Payment **return URLs**, not payment backend routing, follow the configured
  web domain instead of compiler mode. No payment request was made during tests.
- Native Debug testing exposed a separate popup animation defect: the default
  back curve supplied negative values to opacity and nested intervals. The
  route now defaults to a bounded easing curve, clamps custom curve output,
  disposes its owned curve, and uses listener-free item opacity mappings instead
  of allocating status-listening curves on every build. Animations remain on.

**Profiles are not features:** `appFlowyApplicationDataDirectory()` still defaults
to `data_dev` in Debug and `data` in Release; a configured custom location can
override that. These folders can contain different accounts, pages and dashboard
content even with identical capabilities. They were **not merged, replaced or
migrated**. Compare the same workspace and Settings > Manage data location before
interpreting different content as a missing feature. Debug diagnostics, JIT and
integration-test infrastructure intentionally remain different from Release.

### Validation and reproducibility

- **273 regressions passed** across 17 files; targeted analysis of **20 Dart
  paths** was clean. This includes 12 frame-by-frame popup cases (8ms steps,
  default/undershoot/overshoot/no-animation, light/dark/paper).
- **The same 25 isolated functional cases passed in native Windows Release and
  Debug**, with clean process exits: saved flags, plugin/extension catalogs,
  billing restrictions, actual settings/import/export menus, canceled exports,
  cloud choices and notification controls in all three themes. They use
  in-memory storage and fake file pickers, not normal startup or user data.
  This is not an end-to-end test of every legacy database file or cloud service.
- `tool/test_windows_feature_parity.ps1` runs the standalone native fixture and
  validates its result files. Release has no VM service; the fixture writes a
  report and the wrapper closes its window through normal WM_CLOSE. A direct
  Dart `exit()` interrupted native teardown; `SystemNavigator.pop()` alone did
  not close this runner. Accessibility is explicitly **on** before test handle
  baselines, avoiding a first-window platform-handle timing false positive.
- `test/unit_test/shared/build_mode_feature_guard_test.dart` rejects functional
  compiler-mode checks, with narrow documented exceptions for diagnostics,
  test infrastructure and legacy profile isolation. It failed on 14 production
  files before the parity changes and passes afterward.
- `tool/build_windows_bundles.ps1` now includes staged sources in freshness
  checks, verifies stable input hashes across both builds, and invokes
  `tool/verify_windows_bundle_parity.ps1`. The final normal bundles used the
  same **3,820 inputs**, contain **1,179 byte-identical functional assets** and
  the same **36 native components**, including an identical Rust backend.
  Native optimized DLLs and JIT/AOT payloads need not be byte-identical.
  Six positive/negative bundle-verifier checks passed in temporary fixtures.

Final normal builds ran Release first, Debug last. Under
`frontend/appflowy_flutter/build/windows/x64/runner/`, executable/runtime UTC
timestamps were **Release: 11:00:13 / 10:59:22**, **Debug: 11:02:42 / 11:01:44**.
Both were independently checked against the build manifest and latest source.
Reports: `build/performance/windows-bundles.json`,
`build-mode-parity-{release,debug}.json`, `build-mode-parity-regressions.log` and
`build-mode-parity-analysis.log` (all under `build/performance/`).

### Why Debug still uses substantial memory

The fresh normal Debug app (PID 30060) started at 16:34:22 local and was verified
responsive. A 15-second startup/idle sample averaged **940.6 MiB working set**,
**705.7 MiB private memory**, **2.36% of one logical CPU**, and **0.018% 3D GPU**.
A subsequent small VM query reported **342.0 MiB Dart heap usage**, **385.5 MiB
heap capacity**, and about **1 MiB external usage**. There were zero spinner
states/inspector reference records and no checked startup or lifecycle errors.
These are overlapping counters, not values to add or a precise native-heap
attribution. No full inspector map or heap dump was requested.

Debug carries JIT code, kernel data, development metadata and a larger engine;
the normal Debug kernel is **179.1 MiB on disk**, versus **47.7 MiB** for Release
AOT code. File size is not resident memory, but illustrates the different runtime
payloads. Both also retain live tab/editor/database models, native engine/backend
allocations, decoded media and caches. The VM/allocator can retain freed capacity
for reuse rather than immediately reducing Windows working set.

Verified cache examples, **not measured occupancy**: history previews are capped
at four entries/16 MiB per surface; `DocumentImageLoader` retains up to 128 image
futures (24 MiB per fetched/file image limit, 1600px decode-width cap, **no total
byte budget**); open database `RowCache` retains loaded row metadata/cells until
view disposal. These are optimization leads, not proof they account for specific
portions of the observed RAM or that no other leaks remain. A controlled
same-workspace Release comparison and longer post-GC retention analysis are
needed before assigning exact savings or diagnosing continued growth.

## Resource-lifecycle audit (2026-09-16)

The running normal Windows Debug process, not a test or build process, initially
held approximately **1,620 MiB working set / 1,365 MiB private memory**. Windows
reported **91% of one logical CPU** (not 91% of the whole machine), **24% 3D GPU
activity**, and approximately **213 MiB shared GPU memory**. These are separate
counters; working set, private memory and GPU memory must not be added together.

### Live evidence

- Of 1,051 retained ticker instances, exactly **four were active and unmuted**.
  All four belonged to collection-preview loading spinners inside a dashboard.
- Their elements and the dashboard's detached `PageVersionHost` were **inactive,
  not unmounted**, with no parent above the host. The controllers had completed
  loading, but their inactive widgets could not rebuild to replace the spinners.
- The app was displaying a locked-page placard. No HTML/native WebView widgets
  were mounted, so browser texture capture was not the cause of this snapshot.
- Stopping only the four proven-inactive spinner tickers through the local VM
  reduced the subsequent ten-sample CPU average to **3.38% of one logical CPU**
  (0–9.21%) and both sampled 3D GPU engines to **0%**. Private memory was flat
  across that sample. This was a diagnostic intervention, not a permanent fix.
- A GC left about **487 MB Dart heap**. The Flutter inspector retained **672,372
  reference records**, with **112,063 errors since startup**. Inspector records
  use weak targets but still retain their bookkeeping. Profiling flags were off
  before inspection and were restored afterward. A later oversized inspector
  query itself inflated memory, so that later peak is not an app baseline.

### Independently reproduced and corrected defects

- `TabsState.closeView` and the close-other-tabs handler dropped page managers
  without disposing them. `PageNotifier.dispose` also failed to dispose its
  owned plugin, leaving constructor-created `ViewListener`s and initialized
  plugin blocs behind. Ownership now releases once, including secondary pages.
- Repeated/duplicate page opens construct a notifier before deduplication. The
  discarded incoming notifier is now released without calling `dispose` on
  uninitialized late-final plugin blocs or disposing the already-open instance.
- `SecondaryView` did not dispose its animation controller. Removing it during
  animation reproduces Flutter's **disposed with an active Ticker** exception.
  It also allocated a new status-listening `CurvedAnimation` on every resize.
  The curve is now reused and both are disposed; cancelled transitions use
  `orCancel`, and stale closing completions cannot collapse a reopened pane.
- The secondary resize grip now cancels its hover timer, and queued page-fade
  callbacks check mounting before updating state.

The new `test/widget_test/resource_lifecycle_test.dart` failed **nine tests**
before these fixes; its three animated-history snapshot tests already passed.
Coverage also exercises 100 tab open/close cycles, secondary-to-primary ownership
transfer, interrupted open/close, and pending hover teardown. The native entry
point is `integration_test/performance/resource_lifecycle_test.dart`; it uses
in-memory fixtures, never normal startup, backend, credentials or live preferences.

### Dashboard recurrence: root cause confirmed

The user reproduced the GPU spike on dashboard opening after the tab/secondary
cleanup fixes. The rebuilt process again contained four inactive spinner states,
26,825 recorded Flutter errors and 160,944 inspector records. The decisive live
state was `_BookEmbedPreviewState`: its **element was defunct**, its **State was
still ready**, `flip` was **NotInitialized**, and the mixin had already created a
ticker. The following album preview was still inactive with no flip controller.

Both book and album previews used a `late final AnimationController` initializer
and accessed it unconditionally in `dispose()`. Loading, empty and non-cover
layouts could reach disposal without ever reading that field. Its first access
then called `createTicker`/`TickerMode.getNotifier` on an already-defunct element,
throwing **"Looking up a deactivated widget's ancestor is unsafe."** Flutter
clears its inactive roots before unmount traversal; this exception aborted the
remaining teardown, leaving the sibling spinners and their listeners alive.

`book_embed_preview.dart` and `album_embed_preview.dart` now keep nullable owned
controllers behind their lazy getters and dispose only existing instances. No
controller is constructed during teardown, and unused cover layouts remain lazy.
The same independently reproduced bug in `calendar_sync_indicator.dart` is fixed
the same way. No animation, rendering quality, refresh rate or theme was disabled.

`test/widget_test/dashboard_resource_lifecycle_test.dart` uses the **real**
collection preview widgets with controlled in-memory repositories. The book plus
four sibling spinners and idle calendar tests both failed with the exact unsafe
ancestor exception before their fixes. All **42 cases pass** after the fixes:
loading/empty and every book/album layout, removal mid-cover-animation, slideshow
timer teardown, four-sibling disposal, and idle calendar removal in light/dark/
paper. Real labels are loaded before intentionally pending spinners; untranslated
key strings initially caused test-only book-cover overflow. These tests are also
included in the native Windows resource-lifecycle entry point.

Final validation: **230 tests in nine regression files passed**, targeted
analysis of all five follow-up Dart paths was clean, and **48 widget cases passed
on the Windows engine** (the native runner's +50 includes setup/teardown).
Normal Release then Debug bundles were verified fresh against all changed
production sources and each build start: Release EXE/AOT at **08:47:23 /
08:46:42 UTC**, Debug EXE/kernel at **08:49:32 / 08:48:50 UTC** on 2026-09-16.
Both executables live under `frontend/appflowy_flutter/build/windows/x64/runner/`
at `Release/AppFlowy.exe` and `Debug/AppFlowy.exe`.

The fresh normal Debug app was left open on the actual home dashboard. A
30-second idle sample averaged **0.028% 3D GPU**, **0.817% of one logical CPU**,
**739.2 MiB private memory / 968.7 MiB working set**. Three Templates/Home
round-trips verified zero mounted dashboard States while away and exactly one
active State on return. The post-reopen 15-second sample averaged **0.049% GPU**,
**0.513% of one CPU**, **684.8 MiB private / 927.3 MiB working set**. Zero loading
spinner States and zero unsafe-ancestor/ticker-disposal errors remained.
One direct VM-invoked Templates callback ran during a Flutter build and produced
a markNeedsBuild diagnostic; it did not recur during sampling and was not the
teardown failure. Profiling was off and debug reporting restored afterward.
Report: `build/performance/dashboard-resource-verification.json`. These are
short Debug idle observations, not guarantees for all content or long sessions.

The earlier secondary-pane defect was real but did not fix this dashboard path.
Short resource samples and these regressions do not establish that every possible
resource leak or the separately reported sleep/wake issue is solved.

---

Investigated 2026-09-13 on Windows: Flutter 3.27.4 / Dart 3.6.2,
`appflowy_editor` revision `470c4e7`, Profile/AOT, 1280x800 logical viewport,
1.25 device pixel ratio, reported 120Hz display.

## Latest follow-up: lighter resistance and high-refresh drag pacing

The next request was to reduce resistance slightly and improve visible scrolling
on a 120Hz screen. This pass separates **input cadence** from rendering cost.

### Measured cause and scope

- The pinned Windows engine already reads the DWM refresh interval and requests
  1ms timer resolution on Windows 10+. No app-level 60Hz/30Hz limiter was found.
  The `min(elapsed, 1/30)` constants cap integration after a delayed frame; they
  do **not** throttle the frame rate and were not reduced to `1/120`.
- New unpumped native measurements let the engine drive a three-second page
  animation, recording frame timestamps, actual offsets and raster completion.
  Before this change, callback cadence was **120.00/119.67Hz**, with **8.333ms
  median and 8.334ms p99 intervals**. Raster completion was 120.11/119.74Hz.
  This confirms rendering capability, not physical monitor presentation or a
  guarantee on every live document.
- The earlier real-user input recording contained trackpad updates mostly
  **14–18ms apart** (roughly 60–70Hz), not 120Hz. Flutter's built-in resampling
  processes touch only, not trackpad pans. Reproducing 60Hz input on a 120Hz
  test display showed an unchanged scroll offset on intervening frames.

### Implemented

- Desktop direct-manipulation gain changes **0.55 → 0.60** (about 9% more travel
  for the same movement). Desktop-only coast friction changes **5.0 → 4.4**
  (12% less decay; about 14% longer travel at the same release velocity).
  Velocity caps, no repeated-fling boost, spring return, and the separate custom
  viewer/mouse-wheel tuning are retained.
- `FrameSyncedScrollPan` distributes only confirmed drag distance over native
  frame callbacks on Windows/Linux displays above 90Hz. Each packet keeps its
  own deadline of at most **16.67ms**; the bounded queue holds at most four
  segments and bypasses buffering above 96 scaled pixels. This intentionally
  trades a small amount of drag latency for more even movement, not invented
  future motion or additional momentum.
- A helper is owned by the mounted scroll region and linked to its exact
  controller-backed position. The original gesture arena still selects the
  winner; only that position's accepted physics calls are buffered. Frame ticks
  update the real position with the same direction, scaling, notifications,
  semantics and viewport layout. No paint-only transforms, synthetic pointer
  events, dependency patches or second ballistic engine were introduced.
- Already-high-rate input, low-refresh displays, explicit widget physics,
  active custom viewers, global opt-out and reduced motion retain their direct
  path. Boundaries/reversals are synchronous. Release drains pending distance
  before Flutter computes the ballistic transition; cancellation, takeover and
  unmount cannot leave an old ticker moving the page. Shared-controller views
  are independent, and disposal is guarded against re-entrant scroll listeners.

### Native coarse-input comparison

The real PDF/CSV fixture sends 150 updates using a 60Hz wall-clock target, with
**no `tester.pump` during the measured drag**, and records engine frames whose
actual scroll offset changed. Both configurations use the same current gain
and travel exactly **1,080px**, with no preview admissions during the drag.

| Pacing | Actual input Hz | Frames with movement | Movement updates/second | Movement gaps >12.5ms | UI p99 / worst |
| --- | ---: | ---: | ---: | ---: | ---: |
| Off | 60.05 | 149 | 59.60 | 147 | 0.695 / 2.267ms |
| On | 60.06 | 288 | 115.18 | 9 | 1.080 / 1.710ms |

Paced raster worst was 3.524ms. Input delivery still varied from 0.15–40.11ms;
the paced run's movement-gap p99 was 16.67ms and its worst was 33.33ms. Therefore
this is a demonstrated improvement in visible update cadence, **not locked
120fps everywhere**. Cold preview loads, live-page work, OS/GPU scheduling and
Debug/JIT overhead remain separate limits. Physical display presents were not
measured. First report: `build/performance/large_page_frame_pacing_after.json`;
engine baseline: `large_page_frame_cadence_before.json`.

The reversed-order run (`PERF_PACING_FIRST=true`) also passed:

| Pacing / order | Actual input Hz | Frames with movement | Movement updates/second | Movement gaps >12.5ms | UI p99 / worst |
| --- | ---: | ---: | ---: | ---: | ---: |
| On / first | 59.97 | 286 | 113.80 | 13 | 0.973 / 2.322ms |
| Off / second | 60.01 | 149 | 59.60 | 139 | 0.939 / 2.490ms |

Both again travelled exactly 1,080px. Paced raster worst was 5.279ms; the worst
movement gap remained 33.33ms. Report:
`build/performance/large_page_frame_pacing_repeat.json`. Together the runs show
about **114–115 moving updates/second versus 60**, not a fixed 120fps guarantee.
Unit regressions cover exact distance, deadlines, release velocity, cancellation,
re-entrant disposal, independent shared views, fallbacks, and matching real-editor
embed/margin trajectories in both layouts.

## Previous follow-up: controlled trackpad coasting and elastic edges

On 2026-09-14 the user confirmed scrolling is much better, but reported occasional
acceleration/overshooting around embeds and requested macOS-like coasting with
edge bounce. This pass changes the **Windows/Linux premium input policy**, not
document contents or the already-improved preview admission rules.

### Reproduced and fixed

- The default quadratic Windows velocity estimator could invent a reverse
  release after a fast-to-slow gesture: a -68.75px/s tail estimated +155.65px/s;
  a stopped tail estimated +232.14px/s. Guarded recent-sample macOS estimation
  now follows the actual tail, caps it to the latest segment, and rejects
  wrong-direction momentum. Timestamp gaps reset stale samples. The root input
  dispatcher also records the end timestamp, because Flutter does not feed end
  packets into its tracker and batched delivery can mask a real pause.
- Existing direct manipulation remains scaled **once at 0.55**; no synthetic
  wheel impulse or secondary animation is added to trackpad movement. The same
  scale is applied before elastic edge resistance and once to release velocity.
- Desktop scrollables now have rubber-band resistance and a damped spring at
  both ends. Release speed is capped at 4,800px/s, with no iOS-style repeated-fling
  boost. A new touch on the trackpad stops the old coast immediately.
- Coasting uses exponential drag (`friction=5`), with at most release-velocity/5
  additional travel before an edge. Its trajectory is invariant when lazy item
  extents change. Spring re-entry explicitly transitions back to friction, so
  inward releases do not change speed depending on whether layout restarts.
  Flutter 3.27's fast bouncing simulation was not adopted unchanged: its
  time-dependent constant-deceleration term is not restart-invariant.
- Discrete mouse-wheel input remains bounded/exact-distance and clamps at edges;
  it cannot leave an elastic scroll position idle out of range. Elastic bounce
  applies to direct manipulation/coasting, not extra wheel-notch travel.
- Global opt-out/reduced motion, explicit per-widget physics, native macOS/mobile
  behavior, page-first inactive embed routing, and light/dark/paper surfaces are
  preserved. No theme surfaces or SDK/Pub Cache files changed.

### Validation and native evidence

Regression coverage compares frame-by-frame coasting over real deferred CSV
frames/custom-viewer gates with the identical gesture over page margins, in both
normal and shrink-wrapped editors. It includes stopped/reversed tails, release-only
pauses, repeated swipes, 60/120Hz decay, both edge springs and layout restarts.

The offline Windows Profile PDF/CSV fixture passed again, including two new
released-trackpad phases. Each moved **369.6px during input, then 368.05px while
coasting** (369.61px theoretical maximum at 1,848.07px/s release). Both trajectories
decelerated monotonically to zero and admitted **zero new bodies during input or
coasting**. This is deterministic fixture evidence, not a replay of the user's
whole live workspace or a claim every native embed renders at 120Hz.

| Phase | Frames | UI p99 / worst | Raster p99 / worst | UI frames >16.67ms |
| --- | ---: | ---: | ---: | ---: |
| Deferred held pan 1 | 556 | 0.99 / 6.46ms | 2.26 / 3.11ms | 0 |
| Deferred held pan 2 | 537 | 1.14 / 1.96ms | 1.99 / 2.80ms | 0 |
| Released coast 1 | 220 | 0.88 / 1.43ms | 2.06 / 2.56ms | 0 |
| Released coast 2 | 206 | 0.68 / 1.86ms | 2.05 / 2.49ms | 0 |

The coast timing phases include input and the recorder's delivery/idle wait;
trajectory assertions isolate motion itself. Held-pan eager comparison UI p99
was 47.44/29.73ms; the first eager pass also had a cold **491.15ms raster spike**.
Post-scroll deferred loading still peaked at **31.75/34.89ms UI** and **64.79/12.41ms
raster**. These residual first-load costs are not hidden or described as solved.
Report: `build/performance/large_page_embed_kinetic_coast.json`; same native
driver/target as below, with `PERF_RUN=embed_kinetic_coast`.

## Previous follow-up: stuttering while passing embed blocks

The user confirmed the previous changes feel better, with remaining stutters
specifically while scrolling past page embeds. This pass targets preview-body
mounting and layout, rather than changing scroll speed again.

### Implemented

- `PageEmbedLoadScope` owns a per-page loading queue. Eligible blocks opt in
  through `PageEmbedPreviewScope`; bounded `ResizableMedia` frames use
  `DeferredPageEmbed` without moving the editor block or its resize handles.
- Before first mount, a preview must intersect the clipped viewport plus a
  small preload margin (20% of viewport, capped at 128 logical pixels), and all
  enclosing scroll positions must have been idle for 80ms. At most one ready
  preview is admitted per frame. Scrolling/disposal cancels pending admission;
  no geometry walk runs per scroll pixel while a fling is active.
- A static themed preview placeholder reserves the exact frame size. Clicking,
  Enter/Space, or accessibility activation can load it immediately. Once loaded,
  the body stays mounted while its block is retained by the existing editor
  virtualization. It is not removed when scrolling resumes. Code-block editing,
  intrinsic/loose frames and non-page viewers keep their immediate path.
- `MaterializedFileBuilder` starts file lookup/download only when mounted and
  retains its future across rebuilds. Source/name/auth-header changes start a new
  request; immutable header snapshots and revision keys prevent stale data from
  appearing as a different file. No global file/credential cache was introduced.
- External folder/album frames reserve their known 340px default before remote
  metadata arrives, preventing the previous 420→340px layout jump.
- `CsvPreview` replaces an eager all-row intrinsic-width table with lazy rows.
  Column widths are measured from at most 32 rows, clamped to 96–280px, and shared
  by every row. Full cell text wraps and stays selectable. Existing simple
  delimiter parsing and the 1,000-row preview limit are unchanged.

### Native Profile evidence

`embed_scroll_benchmark_test.dart` uses the real custom page, normal editor
services, production overlay/scroll hierarchy, and 24 fixed-size previews
alternating local pdfrx PDF and CSV (120 rows × 6 columns). It measures preview
bodies, **not backend-dependent Office routing, every embed type, or the user's
complete live page**. Runs alternate eager/deferred/deferred/eager with fresh
editor state and files. Every pass travels 6,292 logical pixels with unchanged
frame sizes and no idle-load scroll displacement.

With the final lazy CSV renderer present in both configurations:

| Mode / run | Scroll frames | UI p99 / worst | UI frames >16.67ms | New bodies during scroll |
| --- | ---: | ---: | ---: | ---: |
| Eager 1 | 528 | 41.026 / 52.698ms | 8 | 16 |
| Deferred 1 | 526 | 1.234 / 2.714ms | 0 | 0 |
| Deferred 2 | 525 | 0.923 / 1.727ms | 0 | 0 |
| Eager 2 | 549 | 28.497 / 34.379ms | 8 | 16 |

Deferred raster p99 was 2.503 / 1.912ms, worst 2.952 / 2.766ms. Three newly visible
bodies loaded after each deferred pass. **Idle-load UI peaks remain 32.074 /
36.305ms**; this is not uniformly sub-16ms first-use loading. Before CSV
virtualization, deferred idle-load peaks were 1,378.181 / 609.646ms: merely moving
an eager table's work out of scrolling was not sufficient, hence the row fix.
Those earlier measurements are retained separately, not mixed into the final
eager/deferred comparison.

Reports: `build/performance/large_page_embed_mount_lazy_rows.json` (final), and
`large_page_embed_mount_before_csv_virtualization.json` (intermediate). Repeat
with the existing performance driver, target
`integration_test/performance/embed_scroll_benchmark_test.dart`, Windows Profile,
and a distinct `PERF_RUN` label. Synthetic test localization warnings arise from
the isolated fixture, not missing production translations.

Scope limits: the editor's existing block cache and model construction remain;
some parent block metadata/provider work still starts before preview admission.
Deferral covers fixed resizable preview bodies, not every intrinsic image/video,
database renderer, or already-running native viewer. No accessibility disabling,
live editor reparenting, Pub Cache patch, or document data changes were used.

## Earlier live-page follow-up: user reported no perceived improvement

**The earlier synthetic improvement did not establish that the user's real page
was fixed.** The actual Debug app was inspected and a local recording of the
user's trackpad interaction was collected without recording document text.
The page used the new custom renderer and virtualized layout; it was not an old
binary. It contained mixed prose, a folder preview, external/media embeds,
diagrams and extension content, with only one code block.

The recording lasted 170.6 seconds, but input occupied only about 3.95 seconds:
three trackpad gestures, 18 updates, and two inertia-cancel events (26 events
total). In the input window plus two seconds of settling, 229 sampled frames had:

| Metric | p99 | Worst | Frames >16.67ms |
| --- | ---: | ---: | ---: |
| UI | 59.134ms | 73.104ms | 22 |
| Raster | 8.889ms | 29.359ms | 1 |

These are **Debug diagnostic timings, not Profile/AOT production FPS**. Frame
callback receipt time approximates the interaction window. The long capture
overwrote early timeline events, so the retained timeline cannot prove raw
pointer loss. CPU samples implicated widget mounting/rebuilding, layout and
semantics, not code tokenization. `SEMANTICS (root)` names a pipeline owner; it
does not prove that every tab or the sidebar was traversed on every scroll.

### Additional trace-backed fixes

- `FlowyOverlay` creates an inner `MaterialApp` which was replacing the outer
  scrolling policy with default `MaterialScrollBehavior`. It now forwards
  `ScrollConfiguration.of(context)`. Regression tests reproduced native physics
  despite enabled kinetic scrolling. A fresh runtime confirmed premium physics
  now reach the real page and sidebar; disabled/reduced-motion and inactive
  embed behavior are retained. This is an input-policy correction, **not a
  demonstrated frame-time cure**.
- `BlockActionList.topOffsetForFirstLine` now reuses up to 32 measured heights,
  keyed by effective style, scale and height behavior. System-font changes clear
  the cache; native text painters are disposed immediately.
- `BlockActionList` retains its mounted button row across hover-only parent
  rebuilds. Context/editor/action changes invalidate it; a stable forwarding
  callback always invokes the latest handler. The add button subscribes to
  layout direction, and inherited light/dark/paper themes continue to update.
- `ScrollHoverSuppression` suspends only mouse annotations while the immediate
  page scrolls, including its ballistic tail. This avoids starting hover effects
  as blocks move beneath a stationary pointer. Child state, semantics, actual
  clicks, drags and scroll events are retained. Nested embed scrolling does not
  suppress page hover. Box and sliver hit-test coordinates are preserved.

### What remains unverified

Local saved-gesture replays use 26 events and normalize input scaling to avoid
claiming a win just because the page moves less. Restarting initially changed
window geometry, and one replay included extra live gestures; those runs are not
valid direct comparisons. Later geometry-matched runs still contained UI stalls.
The latest warm detailed replay (`live-scroll-replay-hover-warm`) had UI p99
78.431ms / worst155.746ms with 15/206 frames >16.67ms; raster remained below budget.
This **does not demonstrate an end-to-end scrolling speedup**. Hot-reload/JIT,
cache state, background work and changed frame populations prevent treating it
as a controlled production comparison.

The pinned editor still lays out/carries semantics for a cache of at least two
viewports on each side. Adding another semantics boundary is not a traversal
cache in Flutter 3.27.4, and semantics must not be disabled to hide the cost.
At this stage bounded heavy-embed activation/cache sizing and controlled Profile
measurement were still outstanding. The latest section above records the
subsequent bounded-preview work and native fixture measurements; these older
Debug traces alone did not establish that the whole-page problem was resolved.

## Follow-up: real editable pages and trapped embed scrolling

The first pass below was **not sufficient** for the reported problem. The user
confirmed stuttering of the whole page under trackpad scrolling, on pages with
code, tables/collections, images and media, and also requested an escape from
scrolling trapped inside embeds.

A second offline fixture, `heavy_code_scroll_benchmark_test.dart`, uses the
**real executable code-block renderer, custom page renderer, and enabled editor
selection/keyboard/scroll services**. It contains 60 120-line code blocks
(auto/JavaScript/Python), 120 paragraphs, and 300 trackpad samples per pass.
Before the follow-up fixes, with the first-pass cache fixes already present:

| Pass | UI p99 / worst | Raster p99 / worst |
| --- | ---: | ---: |
| Initial mount (3 frames only) | 443.949 / 443.949ms | 269.826 / 269.826ms |
| First trackpad scroll (300 frames) | 89.171 / 97.697ms | 8.959 / 21.647ms |
| Repeat trackpad scroll (300 frames) | 12.724 / 19.912ms | 7.824 / 9.256ms |

Both passes moved the page 7,920 logical pixels. The first pass had 22 UI
frames above 16.67ms. This reproduces an actual frame-time problem; it is not
the earlier scroll-scaling bug. It remains a synthetic code-heavy page, not a
measurement of the user's complete mixed-content page or every viewer type.

### Follow-up implementation

- **Code parsing off the UI isolate:** `loadSyntaxHighlightedTextSpan` sends
  only strings and the highlighter's plain token nodes to a worker. One worker
  runs at a time. Queued obsolete work is skipped; a running worker finishes
  off-thread and its obsolete result is ignored (it is not forcibly killed).
  The same bounded cache, language normalization and theme styling are reused.
- **Idle-first coloring:** `DeferredCodeHighlight` shows the complete editable
  text immediately, reuses warm spans, and schedules uncached coloring after
  80ms of idle time. New scrolling, edits or unmount invalidate pending work.
  The rich-text widget/keys, selection and document data remain in place.
- **No browser just to read JavaScript:** `SandboxedCodeRunner` no longer builds
  an invisible 1x1 WebView for every JavaScript block. Run starts a headless
  sandbox lazily and awaits readiness. Stop/language changes/disposal invalidate
  late results and close it. Worker source is inserted as source, not `new Function`,
  so the restrictive CSP does not need `unsafe-eval` added to it.
- **Page-first embed scrolling:** the custom page renderer applies the existing
  click/focus activation model to its scrollable built-in and registered extension
  blocks, in both lazy and shrink-wrapped layouts. Click in to scroll the embed;
  click outside or press plain Escape to return scrolling to the page.
- **Custom-viewer compatibility:** `ScrollGestureGate` filters only wheel and
  trackpad event delivery to inactive descendants. PDF/canvas/platform-view
  handlers cannot join those gesture arenas. The enclosing page receives the
  original event; there is no synthetic scroll engine. Mouse annotations and
  tap-region identity are preserved for hover, link cursors and text-field focus.
  The child is not rebuilt from scratch or moved to a different layout on activation.
- **Escape when the document retains focus:** gated page embeds observe plain
  Escape without claiming the key or stealing keyboard focus; an open modal route
  keeps first refusal. Native scroll activities stop without resetting offsets.

The code-heavy follow-up regression set passed 216 tests, including real-editor
embed activation/Escape/click-outside, native and PDF-style input, transformed
clicks, text-field tap regions, resizing, highlighter parity/cancellation and the
no-eager-browser regression. The initial no-eager-browser test failed on the old
implementation because displaying code invoked the WebView platform immediately.
Two after-change Windows Profile runs passed, including native JavaScript
first-click execution, rerunning, and stopping during sandbox startup without
publishing a late result.

### Follow-up measurements

Both after-runs used the same fixture, 300 frames per scroll pass and 7,920 logical
pixels of page movement. The table retains both runs, including cold raster spikes:

| Run / pass | UI p99 / worst | Raster p99 / worst | UI frames >16.67ms |
| --- | ---: | ---: | ---: |
| Before / first scroll | 89.171 / 97.697ms | 8.959 / 21.647ms | 22 |
| After 1 / first scroll | 12.666 / 14.078ms | 14.121 / 50.119ms | 0 |
| After 2 / first scroll | 7.244 / 8.674ms | 6.159 / 20.753ms | 0 |
| Before / repeat scroll | 12.724 / 19.912ms | 7.824 / 9.256ms | 1 |
| After 1 / repeat scroll | 8.120 / 13.688ms | 7.302 / 12.941ms | 0 |
| After 2 / repeat scroll | 5.245 / 16.559ms | 6.745 / 9.955ms | 0 |

Budget counts above use raw samples >16,667 microseconds, not Flutter's rounded
summary threshold. At 120Hz (>8,333 microseconds), the first after-scroll still had
17 UI / 7 raster misses in run 1 and 1 UI / 2 raster misses in run 2. First-scroll
raster frames >16.67ms were 2 before, 3 after in run 1, and 2 after in run 2.
Thus the demonstrated UI-thread stutter is substantially reduced, but this is
**not a claim of uniformly smooth 120Hz rendering or eliminated cold raster work**.
Runs occurred in separate app processes on the same machine; they do not control
OS/GPU caches. Even the repeat invocation with `--no-build` rebuilt the Profile
target, so it is not a no-rebuild experiment.

Reports: `build/performance/large_page_heavy_before.json`,
`large_page_heavy_after_first_run.json`, and `large_page_heavy_after.json`.
Reproduce using the driver below with
`--target=integration_test/performance/heavy_code_scroll_benchmark_test.dart` and
an appropriate `PERF_RUN` label. These fixtures deliberately avoid normal app
startup helpers and the user's live workspace.

Remaining limits: a very large individual code block still lays out its text;
off-thread parsing does not virtualize its lines. Embed gating applies to immediate
page children, not a rewrite of every nested renderer. Deactivation stops native
Scrollable activities; a custom viewer's independently implemented coasting may
need its own cancellation hook. Full media/table loading and actual mixed-workspace
page-open timings remain separate follow-up work.

The first-pass results below are retained as a separate baseline, not evidence
that a plain-text test proved a media-heavy page smooth.

## First-pass conclusions

- **Lazy loading will help, but several surfaces already virtualize widgets.**
  Ordinary document pages and album/folder grids are examples.
- The largest demonstrated rendering difference is shrink-wrapped editors:
  **2,000 blocks mounted versus 27** for the normal editor. Baseline
  pump-to-first-frame was **582ms versus 21.36ms**.
- Lazy widgets do not eliminate full model conversion, full-table reads,
  all-thumbnail prefetch, or background CPU work.
- Three focused fixes are implemented: nested-scroll ownership, a bounded
  syntax-span cache, and cached album projections/counters.
- Pagination, viewport-based heavy-embed loading and active-tab scheduling below are
  **recommendations, not implemented features** in this change.

## Measurements and limitations

Separate backend/data readiness, first usable frame, and scrolling. The new
benchmark is offline and synthetic: it does not start the normal app, change
SharedPreferences, read a real workspace, or call connected accounts. These
are **not** measured sidebar-click-to-ready times for the user's actual pages.

Microbenchmarks warm once and retain seven samples plus the median. Operation
counts are explicit below. Editor mounting begins after model conversion and
uses default package renderers, without the app's decorations, heavy embeds,
spell checking or version recording. Each mount is one observation, not a
population percentile. Raw reports are in `build/performance/`.

| Workload | Before | After |
| --- | ---: | ---: |
| Convert 100 blocks to nodes | 0.401ms | 0.552ms |
| Convert 1,000 blocks to nodes | 3.801ms | 3.846ms |
| Convert 10,000 blocks to nodes | 46.236ms | 41.053ms |
| Explicit Dart highlighting, 80 generated lines, 10 identical reads | 19.354ms | 0.003ms |
| Auto-detected highlighting, same fixture, 10 identical reads | 280.540ms | 0.003ms |
| 10,000-item album, 100 reads of projections/counters | 54.744ms | Below 1us timer resolution |
| Normal editor mount, 2,000 blocks | 27 built; 21.36ms | 27 built; 15.896ms |
| Shrink-wrapped editor mount, 2,000 blocks | 2,000 built; 582ms | 2,000 built; 499.651ms |

The cache measurements are best-case repeat reads, **not whole-page speedups**.
Stable album getter loops can also be optimized/hoisted by AOT; a reported zero
does not mean zero cost. Document conversion and editor virtualization were not
changed: their timing variation is not attributed to these fixes.

The baseline's first normal-editor mount included a **50.14ms raster frame**
(only two sampled frames). Subsequent text-only wheel scrolling was much cheaper:

| Scroll pass, 137 frames each | Before UI/raster p99 | After UI/raster p99 |
| --- | ---: | ---: |
| First | 1.119 / 1.507ms | 1.193 / 1.339ms |
| Repeat | 0.929 / 2.967ms | 1.245 / 5.481ms |

Worst raster duration across those scroll passes was 7.329ms, below the display's
8.33ms budget. This fixture does not prove media-heavy pages are smooth. Initial
raster work is a separate lead; these numbers alone cannot identify font,
image, shader or driver costs. Debug/JIT is not a production FPS baseline.

## Verified architecture

Source paths below are relative to `frontend/appflowy_flutter`.

| Surface | Already lazy/bounded | Remaining eager work |
| --- | --- | --- |
| Normal document | Package `PageBlockComponent` uses `ScrollablePositionedList.builder` when `EditorScrollController.shrinkWrap` is false. | `DocumentBloc._initAppFlowyEditorState` converts the entire protobuf document before mounting. |
| Shrink-wrapped document | No top-level block virtualization. | Package uses `SingleChildScrollView` + `Column`; `RowDocument` defaults to this mode. |
| Folder gallery | `SliverGrid` with builder delegate. | Listing data and per-card preview work need separate budgets. |
| Album grid/masonry | `GridView.builder` / `MasonryGridView.count`; thumbnails request a decode width. | Full model, sorting/grouping, metadata and remote thumbnail warming. |
| Album timeline | Grids inside groups are lazy. | Grouping and the list of group slivers are prepared up front. |
| Database grid | Normal path uses `ReorderableListView.builder` and 500px cache extent. | Row metadata/notifiers, cell contexts and intrinsic row layout. |
| Alternate table views | Several presentation lists/grids are lazy. | `TableRowSource` reads all cell text/metas and builds all cards/properties. |
| Dashboard | Repaint boundaries and transform-only drag updates exist. | `DashboardPage._buildBoard` mounts all sections and their card bodies in a scrolling column. |
| Canvas | Existing visible-scene culling. | Requires its own large-scene profile; not the dashboard renderer. |

Document path: `DocumentPage` -> `DocumentBloc.initial` ->
`DocumentService.openDocument` -> `DocumentDataPB.toDocument` -> `EditorState`
-> `AppFlowyEditorPage` -> package lazy/eager renderer.
`lib/plugins/document/application/document_data_pb_extension.dart` recursively
decodes attributes/external rich-text JSON on the UI isolate. The full model
supports selection, undo, search, remote operations and block paths. Do not
blindly move live nodes/editor state into `compute`: nodes own Flutter keys,
layer links and listeners. Use plain data/bytes at an isolate boundary, then
construct live editor state on the UI isolate with a measured work budget.

## Implemented fixes

### Nested scroll ownership

App-wide `PremiumScrollScope` was nested again by album, folder, book and other
surfaces. Tests reproduced **100 input pixels -> 30.25 content pixels** instead
of **55** (`0.55 * 0.55`), plus inner scopes overriding the global opt-out.
`lib/shared/scrolling/premium_scroll_behavior.dart` now tracks ownership with
an inherited marker, including across `ScrollConfiguration.copyWith` wrappers.
The outer setting/configuration wins. Tests cover distance/velocity, exact wheel
distance, opt-out, live toggling and reduced motion. Wheel tuning is unchanged;
native bookmark scrolling and PDF exclusions remain. This fixes input
consistency, not an independently demonstrated frame-rate issue.

### Bounded syntax highlighting reuse

`lib/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart`
previously parsed on every call; auto-detection tries 16 grammars. Immutable spans
are now cached by exact source, effective grammar and light/dark/paper appearance.
Caller font/style is applied to the root afresh. LRU limits: **32 entries and
256Ki UTF-16 source code units total** (not a claimed 256KiB heap limit).
Oversized entries still render fully but are not retained. Tests cover edits,
themes/fonts, aliases/fallback, immutability, recency and both eviction limits.
The first-pass cache alone did not optimize initial parsing; the follow-up above
adds idle scheduling and worker-isolate parsing for editable page code blocks.

### Album derived data

`lib/workspace/application/collections/album/album_controller.dart` now computes
counts on item adoption and lazily reuses visual/playable projections. Media/order
changes invalidate them; selection/favourites do not. Input lists are snapshotted
so external mutations cannot leave counts stale. Same-id thumbnail arrivals and
newly seeded dates still update the result. Authentication/reconnect is unchanged.

## Prioritized dynamic/lazy-loading roadmap

### P1: Visible-first media requests and tile-local updates

`ProviderController.refresh` waits for `listAll`. `_warmThumbnails` requests
**all** thumbnails, six per batch; every batch notifies the controller.
`AlbumHost._syncProviderItems` then reconstructs the entire synthetic view/media
listing and calls `setItems`. `_readCachedThumbnails` checks files serially.
Six at a time bounds concurrency, **not total work**. Reconstructing N items
for each six-thumbnail batch approaches quadratic total conversion work.
Network waits do not themselves block raster: callbacks, conversion, allocations,
decoding and rebuilds are distinct costs.

Publish cached/first-page metadata immediately. Prioritize visible tiles and a
small ahead/behind margin through one bounded, deduplicated queue per account/
controller. Cancel/deprioritize offscreen queued work. Notify tiles by id and
coalesce deliveries instead of rebuilding the collection. Retain display-size
decoding and bounded memory/disk caches. Preserve auth banners, cached images,
generation guards and retries. Global sorting/search/grouping must not silently
become “loaded pages only” when introducing cursor-based pagination.

### P1: Viewport activation of heavy dashboard/embedded bodies

Keep cheap geometry/placeholders mounted; activate expensive bodies near the
viewport. Begin with bounded read-only previews, not focused editable documents
or playing media. Retain measured heights to preserve scroll anchors. Lazy
sections alone do not help one section containing hundreds of cards. Preserve
section geometry/drop targets independently of active bodies. Do not reparent
GlobalKey editor/database subtrees during gestures. Keep WebView2's route,
minimum-size and teardown protections. RepaintBoundary does not defer a child's
model initialization or network requests.

### P2: Range-based table reads and incremental refresh

`DatabaseController.open` loads fields/all row metadata, then groups/layout and
starts rollup recalculation. `TableRowSource.load` reads fields, location markers,
all cell text and all row metadata sequentially; `_rebuild` converts all properties.
`RowCache.rowInfos` copies the list on access and row listeners recreate cell
contexts on shared notifications. Add cursor/range reads with stable row ids and
requested field ids, coalesce refreshes, apply deltas and share reads between
widgets bound to one table. Keep global sorts/filters/aggregates authoritative on
the backend, not derived from a partial viewport. Profile `IntrinsicHeight` before
changing row layout: deleting it arbitrarily breaks wrapped/mixed-height cells.

### P2: Background work budgets and active-tab lifecycle

- Spell checking already debounces 400ms and yields every 40 blocks; dictionary
  decoding already uses an isolate. `attach` does not synchronously sweep the
  document before first paint. A fixed block count is not a time budget, however:
  a huge paragraph can dominate. Prioritize visible/dirty blocks and short slices.
- `_nodeWithId` scans the tree; repeated clear/dirty lookups should use an index
  or one traversal.
- Version recorders can capture on open, subject to policy. Serialization/hashing
  costs CPU even if deduplication avoids a write. Moving work must preserve the
  promised opening snapshot, not silently snapshot a later edited document.
- `HomeStack` retains tabs in `IndexedStack`; this does not pause timers,
  subscriptions or requests. Add explicit active-page signals. `TickerMode` alone
  only mutes tickers, not timers, network or backend work.

## Reproduction and next profiling pass

From `frontend/appflowy_flutter`, run
`flutter drive --no-pub --profile --no-dds --target=integration_test/performance/large_page_benchmark_test.dart --driver=test_driver/large_page_performance_driver.dart --dart-define=PERF_RUN=baseline -d windows`.
Repeat with `PERF_RUN=after`. Reports:
`build/performance/large_page_baseline.json` and `large_page_after.json`.
Do not replace the isolated fixture with normal integration startup helpers:
those change SharedPreferences and can redirect the live workspace.

Next measure actual mixed pages with 10/100/1,000 embeds, 100/1,000/10,000 rows/
media objects and 1/5/10 tabs. Separate new-process cold opens from warm reopen/
scroll passes; test wheel and precision trackpad. Record navigation -> model ready
-> usable frame, UI/raster percentiles, allocation/GC, peak memory, request counts
and active resources. Budgets: 16.67ms at 60Hz, 8.33ms at 120Hz; do not add UI and
raster durations and call that FPS. Unit tests assert structural behavior, not
machine-dependent wall-clock thresholds.

## Validation

- Original implementation: 7/20 new structural cases passed; 13 failed as
  expected. Both virtualization cases passed before changes.
- First-pass regression set: **154 focused tests passed**. Code-heavy follow-up:
  **216 tests passed**. Live-page/hover follow-up: **317 tests passed**. Final
  bounded-preview and CSV run across 28 explicit regression files: **418 passed**.
- Earlier desktop coasting/edge regression run: **454 tests passed** across
  29 explicit files (including viewer, activation, loading, code and album checks).
- Current frame-pacing regression run: **491 tests passed** across 30 explicit
  files, including 36 Windows/Linux pacing and lifecycle cases.
- Targeted static analysis of all **48 changed/new Dart files: clean**.
- Baseline and after-change Profile benchmarks: **passed**, including two
  follow-up heavy-code runs, native JavaScript lifecycle checks, and both
  four-pass native PDF/CSV comparisons (before/after lazy CSV rows). The latest
  four-pass PDF/CSV runs with released-coast trajectories, unpumped engine
  cadence and coarse-input pacing comparisons passed in both pacing orders.
- A separately checked older `file_preview_test.dart` HTML direct-scroll test
  still expects the former single `window.scrollBy` string. The richer fallback
  already exists in `HEAD`; this unrelated pre-existing mismatch was not changed
  or included among the passing regression sets. Its other eight tests passed.
- Normal-app Windows bundles (`lib/main.dart`) were built **Release first, Debug
  last**. Both executables and their AOT/kernel payloads were verified refreshed
  by these builds and newer than the last edited application source
  (2026-09-14 08:37:40 UTC). Both payloads remained present after mode switching.
  `AF: Build and Verify Windows Bundles` uses a fresh PowerShell task, preserves
  generated Flutter cache/native launchers before rebuilding, and checks current
  build-start timestamps rather than accepting a reused launcher or AOT payload.
  Its verification manifest is `build/performance/windows-bundles.json`.

| Artifact under `frontend/appflowy_flutter/build/windows/x64/runner/` | Verified build timestamp (UTC, 2026-09-14) |
| --- | --- |
| `Release/AppFlowy.exe` | 10:00:27 |
| `Release/data/app.so` | 09:59:58 |
| `Debug/AppFlowy.exe` | 10:01:57 |
| `Debug/data/flutter_assets/kernel_blob.bin` | 10:01:22 |

The fresh Debug executable was launched separately and verified responsive with
an AppFlowy main window and a process start newer than the executable. Startup
logs contained none of the checked fatal, missing-kernel, unhandled-exception or
widget/rendering-exception markers. All four files still matched the verified
build manifest. No live-scroll recorder is attached; startup verification is
not a frame-time measurement of the user's live page.