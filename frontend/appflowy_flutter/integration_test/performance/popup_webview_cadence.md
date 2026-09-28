# Popup WebView texture cadence: source findings and deferred measurements

Status: **author-only lifecycle/fixture corrections, all execution UNRUN**.
The prior Release trial exists but is **not a valid comparison baseline**.
No terminal, tests, builds, processes, downloads, images, goldens, or app launch
were run for these corrections. Editor diagnostics are not C++ compile proof.
There is no measured before/after gain and no FPS-policy/copy-scheduling fix.

## Failed prior trial (preserve, do not overwrite)

Read in full: `build/performance/popup_webview_cadence_baseline_release_20260927_114116_1.json`,
with `cadence-baseline_release_20260927_114116-build.log`, `-owner.log`,
and trial `_1.out.log` / `_1.err.log` in the same directory.

* All five DOM phases completed; report `success` is **false**. stdout records
  the framework's outstanding `SemanticsHandle` failure. The coordinator also
  reported exit `0xC0000005`; neither a flushed JSON nor `.done` makes that pass.
  These logs do not provide a crash stack proving this lifetime bug caused it.
* Reported display is ~120 Hz. DOM animation is ~120 Hz (wheel phase ~114 Hz).
  Animation has 203 captures, notifications, and unique callbacks, zero repeats,
  zero explicit cap drops; callback interval median/p95 **16.9161/24.986 ms**,
  callback CPU work **0.1623/0.2587 ms**. There is no repeated-copy evidence here.
* The old `left:5%`, 18%-wide marker translated by +/-160px can completely leave
  the 600px viewport. The raw animation capture gap is 2088.8597..2663.9538 ms;
  the resize phase has a similar ~500ms gap. The offscreen negative half-cycle
  explains the missing continuous damage. Do not label those gaps a compositor
  regression or compare the repaired fixture against this invalid workload.
* Idle phases have no native events; resize has three recreation events. Native
  wheel input and DOM scroll movement were recorded, not substituted with JS.

## Lifecycle correction and acknowledgement contract

Local SDK evidence: `windows/flutter/ephemeral/cpp_client_wrapper/core_implementations.cc`
stores a raw `PixelBufferTexture` / `GpuSurfaceTexture` address in C callback
user-data. Its unregister overload retains the completion closure until the C
API invokes it. `flutter_texture_registrar.h` explicitly documents asynchronous
unregister. The old destructor passed no completion, then destroyed the variant
and the bridge captured by its callback. That is a source-backed UAF risk.

`CustomPlatformView::Dispose` now removes channel/event handlers, detaches its
surface/cursor/history callbacks, permanently shuts down capture, and explicitly
disposes the renderer on its existing platform thread. `InAppWebView::Dispose`
uses the existing teardown order (including the unchanged queue close), even if
a pending history reply still retains the renderer. Keep-alive transfer detaches
the OLD callbacks before moving the renderer and does not close that renderer.

`RetireTexture` retains the **variant and bridge together** until actual
unregister completion; destroys variant before bridge; then sends the final
manager reply. No deferred callback captures a raw view, manager, or registrar.
Manager destruction/keep-alive retirement use the same path without needing a
Dart reply. Capture delegates retain a detachable platform-thread target, so a
queued delegate cannot dereference a destroyed bridge after shutdown.

Ownership investigation: manager `graphics_context_`, compositor, dispatcher,
and RoHelper are **inline static**, not per-manager teardown members. The bridge
now owns a `GraphicsContext` copy retaining its D3D device/context COM references,
rather than borrowing the static object's address. Factory access through its
RoHelper is confined to the live platform-thread phase. Capture pool/session/item
and event subscriptions are closed/released there; deferred bridge destruction
does not call a factory or depend on the manager/COM apartment. Capture factory,
threading, one-buffer policy, copy/flush and FPS limiter remain unchanged.

The environment's separately owned hidden controller is explicitly closed before
its dispose reply. Plugin shutdown retires views before environments. Controller
and environment Close HRESULT failures fail their channel request; no successful
acknowledgement is fabricated. This is not a claim that every unrelated plugin
callback or the reported crash has been runtime-verified.

Private `_startTextureLifecycleProbe('offline-fixture-v1')` allocates six numeric
stages: **0** owner callbacks detached, **1** capture shutdown returned,
**2** controller dispose returned, **3** unregister requested,
**4** unregister completed, **5** retained resources released. Stage 1 is not a
GPU fence or a per-HRESULT capture-close audit. Normal views have no lifecycle
event allocation, clock, timer, log, or per-frame lifecycle hook. Cadence probe
disabled-path behavior is unchanged. No URLs/user data are added to diagnostics.

`CustomPlatformViewState.controller` exposes the actual controller before
unmount. Repeated public `dispose()` calls share the SAME future, including the
widget's unawaited teardown. The fixture awaits that future, then environment
disposal, then permits `.done` after the final report flush. A failed but
quiescent test can be normally closed by its owner; failed/incomplete cleanup
never emits `.done`. The coordinator reads freshness, identity, schema,
quiescence and **success before CloseMainWindow**, preserves failure, and checks
the real exit code even for failed tests. It never force-exits/ignores a crash.

Fixture revision 2 holds its semantics baseline in `setUp`, before Flutter's
`testWidgets` records handle counts, and releases it in `tearDown`. Framework
leak verification is not disabled or replaced. The 18vw marker's left edge now
spans 5..77vw, keeping the whole marker within 5..95vw even between rAFs on
resize. Numeric sampled-bound checks detect invalid geometry. DOM-only rAF
observation, fixed phases and native wheel workload remain; no Flutter loop was
added. This workload change requires new baseline trials, not a gain claim.

## Deferred validation order — DO NOT run during the exclusive unit group

1. Wait for the other agent's app unit-test group to finish and explicit native
  ownership handoff. App cover/search/folder files, 16-node page fixtures,
  existing timestamp/stale-queue tests, pan/zoom and wheel gain **6** stay intact.
2. Format changed Dart only with the Dart editor formatter; refresh the native
  compilation database with the existing offline toolchain. Neither formatting
  nor compile-command regeneration was executed in this author-only pass.
3. Compile/run `texture_retirement_test.cpp` and existing observer/queue checks
  (`build/performance/run_cadence_observer.ps1` at repository root now includes
  the new pure helper). Run package `test/texture_disposal_test.dart` and existing
  input regressions. The fake registrar covers inline/delayed unregister,
  destruction without reply, graphics-owner loss, stopped texture callbacks,
  stale capture after release, and resource release before one final reply.
  It is NOT Windows-header, COM-threading, engine-shutdown or WebView proof.
4. Build and run the actual native fixture, inspect normal close/exit and numeric
  lifecycle stages in BOTH configurations, plus manager/plugin destruction and
  keep-alive transfer. No nonzero exit is acceptable. Missing completion is a
  failure requiring investigation, never a force-close workaround.
5. Collect fresh revision-2 baseline repeats, then identical after trials only
  after a separately measured/justified performance change. User performance
  item 9 remains open: these are lifecycle correctness and probe corrections,
  not a demonstrated bookmark scrolling/FPS improvement. The inactive explicit
  60-FPS truncation defect remains untouched.
6. After the unit group/native trials, restore and verify real **app-main**
  Release then Debug bundles (fresh executables AND payloads), and only then
  perform consented main-executable verification. A fixture exe is not delivery.

## Verified source facts

Paths below are relative to `packages/flutter_inappwebview_windows/windows/`
unless explicitly marked otherwise.

* `CMakeLists.txt` defines `HAVE_FLUTTER_D3D_TEXTURE` and builds the GPU bridge
  unless `FLUTTER_WEBVIEW_WINDOWS_USE_TEXTURE_FALLBACK` is set. This verifies
  the source default, not the binary currently running. The probe reports the
  backend actually compiled into its host.
* `TextureBridge::Start` in `custom_platform_view/texture_bridge.cc` creates a
  **one-buffer** capture pool and subscribes to `FrameArrived` once. `setSize`
  calls `Start`, but the running guard prevents repeated subscriptions.
  `StopInternal` removes that subscription. There is no 16 ms polling timer,
  100 ms timer, frame-count modulus, or manual begin-frame loop in this path.
* `GraphicsContext::CreateCaptureFramePool` uses the dispatcher-associated
  `IDirect3D11CaptureFramePoolStatics::Create`. A separate free-threaded factory
  exists but is **not called by this bridge**. Dispatcher congestion is a
  hypothesis to measure, not justification for changing threading/lifetimes.
* `OnFrameArrived` retrieves one frame, stores its D3D texture in `last_frame_`,
  applies `ShouldDropFrame`, recreates the pool if `needs_update_`, and calls
  `frame_available_`. `CustomPlatformView` wires that callback directly to
  `MarkTextureFrameAvailable`. The commented-out *size* callback is not an
  unused frame callback: size changes are registered through
  `view->onSurfaceSizeChanged` and call `NotifySurfaceSizeChanged`.
* The explicit bridge cap starts as `frame_duration_ = std::nullopt`.
  `CustomPlatformViewController.setFpsLimit` is an available Dart channel method,
  not a setting automatically applied by the widget. There is no caller in the
  inspected app `lib` or Windows plugin. `BookmarkWebPage` does not invoke it.
  **Neither a default 60 FPS cap nor an Explorer 5 FPS cap is established by
  this source.** Chromium/Windows/display cadence can still limit actual output.
* If a caller explicitly sets 60, the limiter compares integer-truncated
  milliseconds with a floating-point 16.666... ms duration. A 16.667 ms interval
  becomes 16 ms and is rejected; steady such intervals can produce alternating
  accepted/dropped frames. This is a real *conditional* defect, but not a
  source-proven cause for this bookmark, where that limiter is inactive.
  It is deliberately unchanged. No Dart FPS wiring or cap policy was changed.
* `TextureBridgeGpu::GetSurfaceDescriptor` holds the bridge mutex and calls
  `ProcessFrame(last_frame_)` on every running request with a cached frame.
  `ProcessFrame` performs GPU `CopyResource` and `Flush`, even if Flutter asks
  twice for the same capture. This avoids CPU readback but is not zero-copy.
  Its cost and duplicate-request frequency need measurement, not speculation.
* The fallback performs staging copy, `Map(D3D11_MAP_READ)`, RGBA/BGRA conversion,
  and Flutter pixel-buffer upload. It is not the default GPU path. Its constructor
  now uses the actual `view->surface()` instead of the nonexistent `webview_`.
  This does not establish that the fallback builds or is runtime-safe; it also
  requires separate native verification. No backend selection was changed.
* `InAppWebView::setSurfaceSize` applies size/rasterization scale/bounds and
  notifies even on repeated equal-size requests. Pool recreation happens on
  the next capture arrival, with its result unchecked by existing code.
  `setPosition` moves the child HWND; neither method drives a frame loop.
* `last_frame_` retains a D3D texture, not the capture-frame object. The getter
  and arrival handler still serialize on the same mutex. Deferred teardown
  lifetime is corrected above; single-buffer reuse and capture affinity are
  unchanged. No new frame scheduling or rendering policy was introduced.
* App `lib/plugins/collection/views/bookmark/bookmark_web_environment.dart`
  supplies only the existing `--disable-features=CalculateNativeWinOcclusion`
  argument. The fixture copies that argument, but uses a new temporary profile.
  No vsync flags, rate multipliers, or unbounded `setFpsLimit` calls were added.
* Native `InAppWebView::sendScroll` retains **wheel gain 6.0**, fractional
  accumulation, axis handling and `SendMouseInput`. The trackpad timestamp/
  stale-queue code, touch intent, pinch, history, navigation cancellation and
  bookmark environment/route lifecycle were not edited.

## Added diagnostics

`TextureCadenceProbe` is disabled until the private per-texture
`_startTextureCadenceProbe('offline-fixture-v1')` method is called. Normal app
code never calls it. It records at most 8192 numeric events over at most 12
seconds, on existing callbacks, under the existing mutex. Once the deadline is
observed it disarms; there is no timer keeping a static page awake. An idle
probe with no callbacks is bounded when stopped or when the next callback
arrives. No per-frame channel events, logs, page content, URLs, pixels or paths
are recorded. Disabled hooks do not allocate or read the clock. Storage is
released on stop/destruction. Explicit re-arming resets sequence and samples.

`_stopTextureCadenceProbe` returns backend, cap duration (`limit_ms = 0` means
no explicit cap), elapsed duration, truncation/expiry flags, and event rows:

`[kind, monotonic_relative_ms, capture_sequence, callback_work_ms]`

Kinds: 0 arrival, 1 successful texture acquisition, 2 cap rejection,
3 notification attempt, 4 GPU descriptor callback, 5 CPU buffer callback,
6 pool-recreation attempt. Acquisition increments the sequence even when the
cap subsequently rejects notification, matching the unchanged production
latest-frame behavior. Sequence zero means the cached capture predates arming.

Fake-clock `windows/test/texture_cadence_probe_test.cpp` checks disabled state,
latest-frame/duplicate/cap-rejected trace accounting, fractional timestamps,
restart fencing, no-callback expiry and flood bounds. It tests the observer,
**not** a changed queue or scheduling policy. Existing trackpad queue tests
remain the regression authority for that unchanged input policy.

## Isolated fixture

`popup_webview_cadence_test.dart` imports neither app main nor shared integration
helpers/auth/preferences. It requires explicit runtime consent, rejects external
WebView environment-variable overrides (without printing their values), creates
a temporary WebView2 profile, disables Dart WebView debug logging, serves only
CSP-restricted inline HTML, and disposes its own environment ID. Temporary locked
profile cleanup is left to the coordinator/OS, never an app-profile reset.
Machine/registry WebView policies can still affect a run; this is not a sandbox.

One warm-up then five fixed 4000 ms DOM rAF windows on the same view:

1. idle before (rAF observation, no pixel animation);
2. responsive fixed-marker animation;
3. native scrolling over 600 synthetic wrapping paragraphs: 50 Flutter wheel
   events, 20 logical-pixel delta, requested 40 ms spacing, actual send times
   recorded; no JS/Dart scroll-position assignments;
4. animation with three Flutter size changes, also exercising centered movement;
5. idle after (animation stopped, checking return to quiet delivery).

Reports include actual Chromium product/JS version, Dart version/build mode,
reported display Hz/DPR, raw DOM rAF and native event timestamps, median/p95
intervals, callback work and capture age, exact cap drops, repeated capture
callbacks, captures without callbacks in the window, pool-recreate attempts,
and supporting Flutter build/raster timing distributions. The rAF recorder is
capped at 2048 entries and has a duration+2000 ms failure deadline; Flutter
timings are capped at 4096. The fixture fails on expired/truncated native/DOM
records, hidden DOM, missing active capture/delivery, absent native scrolling,
or missing resize notification. It does **not** assert an invented 60 FPS pass
threshold. A static idle page may correctly deliver no textures.

## Coordinator commands — NOT executed

Obtain consent, save work, close AppFlowy, stop other native fixtures/builds,
and run serially on a visible, unoccluded window on the same monitor, power mode,
scale, WebView runtime and Flutter SDK. Do not use OS input automation or reuse
an app profile. Use the already provisioned offline toolchain/dependencies;
`--no-pub` avoids pub resolution, but this repo's existing CMake NuGet pre-build
target may still attempt dependency restoration. If cache/offline prerequisites
are missing, stop and coordinate rather than downloading or installing here.

From `C:\AppFlowy\frontend\appflowy_flutter`, an x64 VS Developer PowerShell can
compile/run the header-only observer test without Flutter/WebView dependencies:

```powershell
if (Get-Process AppFlowy -ErrorAction SilentlyContinue) { throw 'Close AppFlowy with consent first.' }
cl.exe /nologo /std:c++17 /EHsc /W4 /WX packages/flutter_inappwebview_windows/windows/test/texture_cadence_probe_test.cpp "/Fe:$env:TEMP\texture_cadence_probe_test.exe" "/Fo:$env:TEMP\texture_cadence_probe_test.obj"
if ($LASTEXITCODE -ne 0) { throw 'Cadence observer compilation failed.' }
& "$env:TEMP\texture_cadence_probe_test.exe"
if ($LASTEXITCODE -ne 0) { throw 'Cadence observer test failed.' }
```

Existing unchanged input-queue deterministic regression (uses existing JSON
headers, no dependency downloads in the script):

```powershell
& ./packages/flutter_inappwebview_windows/windows/test/run_trackpad_touch_queue_test.ps1
```

Capture the **instrumentation-only baseline**, Release first and Debug last:

```powershell
flutter drive --no-pub -d windows --release --driver=integration_test/performance/popup_webview_cadence_driver.dart --target=integration_test/performance/popup_webview_cadence_test.dart --dart-define=WEBVIEW_CADENCE_CONSENT=true --dart-define=PERF_RUN=baseline_release_1
flutter drive --no-pub -d windows --debug --driver=integration_test/performance/popup_webview_cadence_driver.dart --target=integration_test/performance/popup_webview_cadence_test.dart --dart-define=WEBVIEW_CADENCE_CONSENT=true --dart-define=PERF_RUN=baseline_debug_1
```

After a separately justified scheduling/copy change, rerun identical probes:

```powershell
flutter drive --no-pub -d windows --release --driver=integration_test/performance/popup_webview_cadence_driver.dart --target=integration_test/performance/popup_webview_cadence_test.dart --dart-define=WEBVIEW_CADENCE_CONSENT=true --dart-define=PERF_RUN=after_release_1
flutter drive --no-pub -d windows --debug --driver=integration_test/performance/popup_webview_cadence_driver.dart --target=integration_test/performance/popup_webview_cadence_test.dart --dart-define=WEBVIEW_CADENCE_CONSENT=true --dart-define=PERF_RUN=after_debug_1
```

Check each command's exit status before proceeding. Use at least three uniquely
labelled trials per mode (and a baseline repeat to quantify variance). Do not
compare Debug against Release. JSON goes to
`build/performance/popup_webview_cadence_<PERF_RUN>.json`; no report paths are
printed by the driver. `PERF_REFERENCE_HZ` defaults to 60 solely for *estimated*
missed-slot accounting; set it identically for both sides if using another
reference. There is no `setFpsLimit` call in the fixture.

`flutter drive` builds a **fixture executable**, not the app main. Before normal
app delivery, the coordinator must restore/build/verify both real app bundles
using the existing `AF: Build and Verify Windows Bundles` task (Release first,
Debug last), confirm freshness and required assets, then launch only with
consent. This research session did not produce runnable app bundles.

## Interpretation / limitations

* DOM 60 FPS alone is not composited WebView FPS. Compare DOM, native capture,
  notifications, unique capture callbacks and all callback intervals separately.
  Use whole raw traces to examine stalls, not only averages/medians.
* Texture callbacks are real Flutter texture acquisition calls, **not proof of
  GPU completion, new pixel content, or display presentation**. Sequence IDs
  identify acquired capture textures, not browser frame IDs or pixel hashes.
  Shared single-buffer reuse and stale destination data on existing failure
  paths cannot be disproved without additional GPU/presentation instrumentation.
* GPU work duration covers CPU `CopyResource`/`Flush` submission and descriptor
  preparation, not a GPU fence. CPU callback duration includes readback/swizzle
  but does not certify every copy succeeded. Arrival and callback timings start
  after the bridge mutex is acquired, so dispatcher delay versus lock wait is
  not independently resolved. Do not replace these with claims of GPU timings.
* Notifications can coalesce. Captures without callbacks include policy drops,
  overwritten latest frames and window-tail frames. Exact `cap_drops` is separate
  from `estimated_missed_reference_slots`, which is just an interval-based
  estimate and should not be read as dropped display frames (especially idle).
* DOM, Dart input and native clocks have separate origins. Native start/stop
  encloses the DOM window plus two channel boundaries; do not subtract absolute
  timestamps across clocks. Flutter FrameTiming is supplementary, may be batched
  across boundaries, and does not necessarily contain texture-only raster work.
  Sparse Flutter timings do not invalidate nonempty native callback evidence.
* This models a visible bookmark-sized renderer with its existing environment
  argument, not the full popup route/app UI, arbitrary remote content, all themes,
  or real-user trackpad velocity. It adds no production surface or theme change.
* Hypothesis guide: fast DOM + slow captures points upstream of Flutter delivery;
  fast captures + slow unique callbacks points at delivery/coalescing; expensive
  or repeated callback work makes the copy path worth investigating. None alone
  proves a root cause. Keep idle battery behavior and native input unchanged.

**No FPS improvement can be claimed until real-runtime baseline/comparison
reports exist.** Do not adopt guessed flags, remove vsync, force continuous
Flutter frames, increase wheel gain, or replace Chromium's scrolling to obtain
a better-looking number.