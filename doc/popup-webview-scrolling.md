# Popup WebView input timing and startup

## Scope and evidence (2026-09-26)

This change repairs verified input/lifecycle defects in the popup's Windows
WebView path. It does **not** establish that every reported cold-site stutter or
large scroll jump is fixed. The isolated Windows Debug renderer fixture now
passes against the installed WebView2 runtime. It uses synthetic HTML and its
own temporary profile; no live workspace, auth, OS input or application-profile
reset is involved. Final normal Release/Debug bundles are verified separately.

### Actual opener, not the system URL launcher

Source-verified paths (paths below are relative to `frontend/appflowy_flutter`):

- `lib/plugins/document/presentation/editor_plugins/link_preview/custom_link_preview.dart`:
  desktop `CustomLinkPreviewWidget.onTap` calls `openBookmarkPagePreview`.
- `lib/plugins/document/presentation/editor_plugins/link_embed/link_embed_block_component.dart`:
  the non-video `buildContent` tap calls the same opener.
- `lib/plugins/document/presentation/editor_plugins/bookmark/bookmark_block_component.dart`:
  the bookmark card tap also calls that opener; its separate Open in browser
  action calls `launchUrl(...externalApplication)`.
- `lib/plugins/collection/views/bookmark/bookmark_page_preview.dart`:
  `openBookmarkPagePreview` opens a `showGeneralDialog` containing `_LinkReader`.
  `_LinkReader._load` reads the link's bookmark record and constructs its
  `BookmarkController`, then builds `BookmarkReader`.
- `lib/plugins/collection/views/bookmark/bookmark_reader.dart`:
  `_stage → _livePage → BookmarkWebPage` (the `BookmarkWebPage` call was at line
  656 at investigation time). Library cards use `openBookmarkReader`, converging
  on this same reader. Standalone bookmarks also use it.
- `lib/workspace/application/collections/bookmark/bookmark_browser_reader.dart`:
  `readPageInBrowser` is a **headless metadata fallback**, not the popup's input
  surface. `BookmarkFetcher` may invoke it for a challenge response. It has its
  own load/settle work; no changes to that behavior are claimed here.

`afLaunchUri`/system-browser launch is not the in-app scrolling path. There is
no hardware trace proving which of the three entry points the reported gesture
came through, but their popup rendering/input implementation is shared.

### Verified timing loss

Before the change, `CustomPlatformViewController._setPointerUpdate` sent only
`[pointer, kind, x, y, size, pressure]`. Flutter's `PointerPanZoom*Event.timeStamp`
never crossed the channel. `InAppWebView::setPointerUpdate` converted the reserved
trackpad contact `0x3ffffffe` to `Input.dispatchTouchEvent`, without `timestamp`.
The old `TrackpadTouchQueue` retained one in-flight command and coalesced adjacent
absolute `touchMove` positions, but retained **no original timing**.

The [CDP Input definition](https://raw.githubusercontent.com/ChromeDevTools/devtools-protocol/master/pdl/domains/Input.pdl)
defines `dispatchTouchEvent.timestamp` as epoch seconds. Chromium's
[`GetEventTimeTicks` / `CreateWebTouchEvents`](https://raw.githubusercontent.com/chromium/chromium/main/content/browser/devtools/protocol/input_handler.cc)
use current time when it is absent. Thus delayed replies followed by a burst
can present a large coalesced displacement over a much shorter interval than
the actual gesture. That is an input velocity defect consistent with a false
fling, not proof that it accounts for every user's observed jump.

Runtime qualification: Chromium also has a feature-gated synthetic
pointer-action implementation. The reviewed current source passes the optional
timestamp into that branch but does not use it there. The installed WebView2
runtime preserved the original timestamp intervals in the executed native
fixture; no browser feature flags or assertions were changed to force a pass.
Other runtime versions are not certified by this one installed-runtime check.

### Verified cold-environment race

`BookmarkWebPage.initState` started `_prepareEnvironment`, but `_buildPage`
previously gated only on route `_ready`. The first `InAppWebView` could capture
`BookmarkWebEnvironment.instance == null`. The Windows adapter copies the
environment ID into its creation parameters once; the native manager resolves a
null ID to the default-environment creation path. The bookmark environment could
then complete unused while that first view kept the default environment.

This is **not** evidence of the same widget creating its native view twice on a
normal rebuild. It is a race between special-environment preparation and a
first view initialized with default-environment parameters. A cold opening can
therefore do both environment preparations unnecessarily.

### What the 320 ms backstop did and did not do

While `_ready` is false the page shows a spinner, not `InAppWebView` or its input
surface. There was no WebView wheel/trackpad backlog being captured while that
widget was absent. The startup tests now send input while absent and assert it
is not delivered or replayed after readiness.

There were real closing defects instead: the backstop was an uncancellable
delayed future, reverse cleared `_ready` without latching `_closing`, and a page
first mounted after route completion never subscribed to reverse at all.

## Implementation

- Trackpad packets append the original integer microsecond timestamp and known
  input age. The start deferred for bookmark axis classification keeps its
  original time and passes the classification interval as age. The native
  decoder accepts both StandardMessageCodec integer widths.
- The new production `windows/in_app_webview/trackpad_touch_queue.h` is an
  independently compilable policy/serializer, with an injected sender and steady
  clock for deterministic tests. WebView2 uses that exact implementation.
- Each gesture pairs its first original timestamp with host `steady_clock`
  arrival minus known age. All later samples use original **differences** from
  that pair. Epoch mapping is anchored once for the queue, not recalculated from
  wall time when each callback completes. Coalescing keeps the newest absolute
  position **and its timestamp together**.
- A 250 ms freshness bound checks queued residence and paired sample age. A
  stale in-flight start/move invalidates its unsent tail even if the newest
  coalesced move/end arrived recently. Negative, decreasing, duplicate-move,
  implausibly future, overflowing and non-finite samples cancel rather than
  being assigned a fabricated new time. This is a stale-delivery limit, not a
  tuned scroll gain, velocity limit or animation duration.
- Native `NavigationStarting` clears unsent gesture data synchronously, before
  the Dart notification. Cancellation never frees an occupied CDP slot. A
  required `touchCancel` fence precedes any new contact; only the newest pending
  gesture is retained. The cancellation is a control event at the last
  dispatched time, not an old release replayed with current time.
- Completion tokens prevent duplicate/late callbacks from freeing another
  call's slot. Callbacks retain only the queue; closing clears its sender and
  pending work. A failed cancellation fails closed for that view's trackpad
  queue rather than interleaving contacts in an unknown state or retrying
  indefinitely. Mouse-wheel input remains independent.
- Dart cancels interruption by navigation, mouse/wheel takeover, lifecycle loss
  or disposal instead of manufacturing `touchEnd`. Only the matching pointer's
  normal pan-end releases. Navigation invalidates Dart contacts even when a
  surface does not enable history gestures.
- `BookmarkWebPage` captures the environment result **before** mounting. A
  resolved null still allows the existing platform/default fallback. A 10-second
  wait timeout shows the existing unavailable/reload UI; retry observes the
  same preparation future rather than creating another environment. Successful
  opens continue to share `BookmarkWebEnvironment.ensure`.
- Route observation is installed even for late mounts. Reverse latches closing,
  cancels the owned backstop and removes the native subtree; environment,
  backstop and late-create completions cannot resurrect it. The existing 64 px
  minimum surface size remains enforced. Input is not blocked until network
  load completion.

### Preserved behavior

Chromium remains the scrolling/fling engine. There is no JavaScript scrolling
over live pages, no Dart kinetic replacement, no global wheel conversion, no
new browser flags, and no gain reduction. Native wheel multiplier **6.0** and
fractional remainders are unchanged; remainders are less than one native unit,
not an accumulated startup backlog. The direct trackpad gain and 48 px per-axis
sample bound are unchanged. Real touchscreen packets remain six values and use
the unchanged `SendPointerInput` branch. Horizontal bookmark history does not
inject touch contacts. Pinch and renderer/mouse cursor reconciliation remain.

No theme, Find, PDF, page-icon, main-app, preference, auth or backend files were
modified. Existing find/theme behavior within `BookmarkWebPage` is not rewritten.

## Tests executed

| Suite | Passing cases | Evidence |
| --- | ---: | --- |
| Existing package `scroll_settings_test.dart`, before changes | 14 | Baseline |
| Updated `scroll_settings_test.dart` + new `touch_timing_test.dart` | 22 | Real Flutter input routing and channel payloads; timestamps, delayed Dart replies, cursor/history/pinch, cancellation, touchscreen and wheel |
| New `bookmark_web_startup_test.dart` | 11 | Real BookmarkWebPage/Windows Dart adapter with mocked native channels; actual create parameters/counts, reuse, timeout/retry, absent-view input, reverse/late-mount and late-create disposal, light/dark/paper, minimum size |
| Existing reader layout/dismiss and permission suites | 95 | Reader/opener lifecycle and permissions retained |
| New standalone C++ `trackpad_touch_queue_test.cpp` | 19 | MSVC C++17 `/W4 /WX`; parses production JSON and drives delayed/inline/failed/duplicate callbacks |

Post-change total: **147 passing cases** (128 Flutter, 19 standalone C++).
The 14-case pre-change baseline is not added to that total.
Strict targeted Dart analysis and the scoped `git diff --check` also passed.

The C++ fixture checks `[100,90,75,55]` absolute positions, 10/20/30/35 ms timing,
and the delayed coalesced start/move/end intervals of **30 ms / 5 ms** despite
callbacks at 80/81/82 ms. It also covers a 2-second stall, fresh tails behind a
stale start, navigation/replacement fences, queued-start expiry, 1,000-move
boundedness, invalid/large timestamps, exact 250 ms expiry boundary and owner
lifetime. These are behavioral tests, not source-grep assertions.

The initial standalone compile caught an MSVC default-lambda name lookup and
was corrected before the 19-case pass. The first startup run was 8 pass / 3
fail because its fixture did not drain real-zone stream cancellation; a bounded
empty real-zone turn fixed the harness without advancing the route clock or
weakening disposal assertions. No application delay was relaxed.

## Reproduction / handoff to main

From `C:\AppFlowy\frontend\appflowy_flutter`, run the standalone native policy
fixture with
`& .\packages\flutter_inappwebview_windows\windows\test\run_trackpad_touch_queue_test.ps1`.
It compiles only the test executable into `build/popup-webview-native-tests`,
uses already-installed MSVC and nlohmann JSON headers, and performs no download
or app build. `-JsonInclude` can point to an existing JSON include directory.

Actual renderer fixture (**executed successfully in Windows Debug**):
`integration_test/performance/popup_webview_scrolling_test.dart`.
It was compiled/run with
`flutter drive --debug --no-pub --no-dds --driver=test_driver/large_page_performance_driver.dart --target=integration_test/performance/popup_webview_scrolling_test.dart -d windows --dart-define=PERF_RUN=popup_webview_scrolling`.
Run that verification before main's normal Release then Debug bundle builds.
The trackpad channel is now eight values: rebuild Dart and the native plugin
together. Hot-reloading new Dart against the old six-value native DLL is not
a valid test. The Debug driver command is the provided renderer verification;
no Release fixture-driver run is claimed.

That fixture uses only synthetic HTML and a newly created temporary WebView2
environment, refuses an external user-data-folder override, reuses one view
across navigations, has bounded event/future waits instead of polling, and does
not use live preferences/auth/helpers or OS cursor/keyboard injection. A bounded
80/600 ms busy handler deliberately loads **only the fixture renderer**. The
timestamp probe keeps DOM touch events observable; the final stage restores
normal native scrolling. It reports only event kinds, times, positions and
creation counts through the existing performance driver. Passing report:
`build/performance/large_page_popup_webview_scrolling.json` (application root).

### Installed-runtime results

- Under the 80ms renderer load, the surviving coalesced move retained **30ms**
  from touch start; release retained **35ms**, a **5ms** final interval.
- Under the 600ms load, the observed sequence was exactly `touchstart`, then
  `touchcancel`; no stale movement/release was replayed.
- Navigation fenced the old contact. The recovery gesture moved Chromium to
  `scrollY = 100.80000305175781` with **one** native view creation in total.
- No timestamp assertions, stale-delivery limits or browser flags were relaxed.
- The first application compile exposed the Windows RPC `small` macro colliding
  with a decoder local variable. Renaming it to `narrowValue` (and the other
  branch to `wideValue`) preserved both codec integer paths. The subsequent
  build and fixture passed.
- Log: repository-root `build/performance/popup-webview-native-verification-2.log`.
  The reported `integration_test` plugin warning did not prevent the driver from
  obtaining the passing result and writing the structured report. This is an
  input/lifecycle regression result, not a live-site smoothness benchmark.

## Modified paths

Relative to `frontend/appflowy_flutter`:

- `lib/plugins/collection/views/bookmark/bookmark_web_view.dart`
- `packages/flutter_inappwebview_windows/lib/src/in_app_webview/custom_platform_view.dart`
- `packages/flutter_inappwebview_windows/windows/CMakeLists.txt`
- `packages/flutter_inappwebview_windows/windows/custom_platform_view/custom_platform_view.cc`
- `packages/flutter_inappwebview_windows/windows/in_app_webview/in_app_webview.cpp`
- `packages/flutter_inappwebview_windows/windows/in_app_webview/in_app_webview.h`
- `packages/flutter_inappwebview_windows/windows/in_app_webview/trackpad_touch_queue.h` (new)
- `packages/flutter_inappwebview_windows/windows/test/trackpad_touch_queue_test.cpp` (new)
- `packages/flutter_inappwebview_windows/windows/test/run_trackpad_touch_queue_test.ps1` (new)
- `packages/flutter_inappwebview_windows/test/scroll_settings_test.dart`
- `packages/flutter_inappwebview_windows/test/touch_timing_test.dart` (new)
- `test/widget_test/bookmark_web_startup_test.dart` (new)
- `integration_test/performance/popup_webview_scrolling_test.dart` (new, Debug runtime pass)

Plus this repository-root `doc/popup-webview-scrolling.md` (new).
`bookmark_web_environment.dart`, reader/opener sources, metadata/browser-reader
sources and the existing reader test files were inspected but not modified.

## Remaining uncertainty

- The COM adapter and installed Chromium runtime passed the isolated Debug
  compilation/fixture run with its original DOM timestamp assertions. This is
  not a Release fixture run or certification of every WebView2 version.
- An already-dispatched command cannot be retracted while retaining one in
  flight. The policy discards unsent stale work and sends cancellation after the
  outstanding reply. An unreturned native callback still owns its slot; there
  is intentionally no unsafe timeout that starts another concurrent command.
- The first host arrival does not reveal input age accumulated **before** that
  initial clock pair. The known classification age is carried explicitly;
  subsequent lateness and queue residence are bounded without pretending the
  Flutter engine's timestamp origin equals the host clock's origin.
- The route backstop duration itself was not retuned. Cold WebView2 process/GPU
  startup, site JavaScript/layout/network/bot challenges, bookmark-record and
  snapshot IO, and parallel metadata/headless-browser work are not quantified
  or eliminated. No FPS, fling-distance improvement or cold-site latency
  percentage is claimed.