# Site gesture implementation — execution pending

No terminal commands, tests, compilation, builds, installs, app/window closes,
images, or memory writes were performed. Editor diagnostics are not a compile
or native runtime result. Main must validate before treating this as working.

## Narrow native follow-up (2026-09-28; still NO execution)

### Popup integration for main

Public API (already exported): `Future<bool> WindowsInAppWebViewController.rejectWindow(int windowId)`.
Import `package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart`.
Exact call inside the app's `onCreateWindow(controller, action)`:
`await (controller.platform as WindowsInAppWebViewController).rejectWindow(action.windowId);`
Then **return true**, including when rejection throws (catch locally; never fall
through to false/null/error, whose legacy meaning is same-view navigation).

Read all current `bookmark_web_view.dart` branches; main must apply the call:
- In the early guard branch: dead/inactive/mismatched controller, absent URI,
  or no accepted user activation. Do not skip rejection because the app's guard
  failed; use the callback's original controller, not `_controller`.
- Before dispatching an allowed external scheme to `onOpenExternally`, and for
  every other non-http(s) denial. Catch an external callback exception as well;
  it must not become native same-view fallback.
- Keep the current **user-activated http(s) Windows return false** branch. Native
  now removes the pending entry, marks Handled and completes once before its
  same-view GET navigation. Do not reject that branch first.
- Keep non-Windows behavior, activation policy, blocking toggle/CDP filters and
  Reader lifetime guards unchanged. Popup safety is independent of the adblock
  toggle in the inspected source.

The bool return from rejectWindow is an ACK: true = found/owned and completion
calls succeeded; false = already consumed/disposed/wrong owner or failed COM
completion. It is NOT the onCreateWindow return value. Never return it directly.
Real `onCreateWindow: true` windowId adoption remains pending until adoption or
explicit rejection; there is no arbitrary adoption timeout. Disposal denies all
that opener's remaining requests. Duplicate/late fallback replies cannot navigate
after rejection/adoption; callbacks use a weak opener lifetime guard.

### UNKNOWN recovery protocol

- New internal `querySiteGesturePolicyState([x,y])` returns
  `{status: site|browser|indeterminate|invalidated, epoch: int}`. The original
  boolean/null `querySiteGesturePolicy` remains for older callers/fixtures.
- Busy, CDP failure/malformed result, or aged query = **indeterminate**. Cancel,
  navigation, native detach, suspension or disposal = **invalidated**, never a
  license to deliver late input to a different document. Flutter detach/rebind,
  hit-test loss, resize, lifecycle and scope-policy changes also retire the owner.
- The query still uses `Runtime.evaluate` timeout **50ms**, in the exact shared
  touch slot. Dart's explicit **150ms Timer** discards buffered input on deadline
  and is cancelled on end/cancel/detach/dispose/normal reply. Timeout does NOT
  release the native slot or launch parallel CDP.
- After the real reply, an indeterminate/timed-out gesture disables history and
  browser ZoomFactor interpretation. New samples can ask
  `siteGestureFallbackReady(epoch)` (host state only; no CDP). At most one actual
  readiness call is outstanding, with no queued sample list or timer polling.
- Once ready, the NEXT actual sample establishes a fresh time/pan/scale baseline
  at the original hit position. Only subsequent real movement is sent. No stale
  accumulated pan/scale or old End is replayed. The native 250ms delivery bound,
  cancel ACK fences and absolute-move coalescing remain unchanged.
- Recovered packets append an epoch (9 single-contact / 11 paired values).
  Native validates it even for Start/Cancel, closing navigation-after-readiness
  races without cancelling a newer page's stream. Existing 6/8/10-value packets
  remain accepted. CSS touch-action is left to Chromium; no fake click, wheel
  conversion, forced browser zoom or global touch-action override is added.

### Exact files in this follow-up

Changed (all relative to this package):
- `lib/src/in_app_webview/custom_platform_view.dart`
- `lib/src/in_app_webview/in_app_webview_controller.dart`
- `windows/custom_platform_view/custom_platform_view.cc`
- `windows/in_app_webview/in_app_webview.cpp`
- `windows/in_app_webview/in_app_webview.h`
- `windows/in_app_webview/in_app_webview_manager.cpp`
- `windows/in_app_webview/webview_channel_delegate.cpp`
- `windows/in_app_webview/trackpad_touch_queue.h`
- `windows/types/new_window_requested_args.cpp`
- `windows/types/new_window_requested_args.h`
- `test/site_gestures_test.dart` (the prior new test, adjusted/expanded)
- `SITE_GESTURES_HANDOFF.md`

New:
- `windows/types/pending_window_request.h` (actual production lifecycle helper)
- `windows/test/pending_window_request_test.cpp` (same helper: reject/adopt,
  remove-before-COM, ownership, duplicate fallback, failed put, disposal)
- `windows/test/site_gesture_unknown_test.cpp` (same production queue: 600ms
  query stall, 1000 busy attempts without queue growth, fresh recovery,
  duplicate callbacks, cancel/close and navigation-after-readiness fences)
- `test/reject_window_test.dart` (public API + actual callback/mock channel)

The two new C++ files are standalone fixture entrypoints, not yet wired into a
runner. Main must compile/run them with the existing native fixture toolchain
(unknown fixture needs the same nlohmann.json include as site_gestures_test).
No app source or app-root integration fixture was edited.

### Still blocked / deliberate limits

- A CDP callback that NEVER returns still owns the shared native slot: dispatching
  around it would violate the single-slot requirement. This patch recovers the
  continuing gesture once the slot really settles, not while it remains hung.
  Motion made before readiness is deliberately lost; no zero-latency/FPS claim.
- A touch dispatch itself exceeding the existing 250ms bound still cancels its
  DOM stream; this is not an unbounded restart/replay mechanism.
- There is no shared coordinator for app-owned Runtime.evaluate traffic, so main
  must NOT wrap both-axes-disabled file WebViews in automatic site arbitration.
  Primary scope remains native-scroll-enabled bookmark/default WebViews. The
  explicit `preferWebsiteGestures` override is preserved.
- No tests/builds/runtime/real Maps verification or visual review was performed.
  Main owns formatting, compilation, tests and both normal runnable bundles.

## Host integration (main / BookmarkWebPage owner)

Public export: `package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart`.

API: `WindowsWebViewGestureScope({Key? key, bool preferWebsiteGestures = false,
required Widget child})`; lookup: `WindowsWebViewGestureScope.maybeOf(context)`.

- Existing scroll-enabled/bookmark-history WebViews automatically query the hit
  region once per trackpad gesture. No scope is required for those views.
- Wrap the actual `InAppWebView` in `WindowsWebViewGestureScope(child: ...)` if
  the host disables **both** native scroll axes but needs site arbitration.
- `preferWebsiteGestures: true` is a deliberate per-view fallback: bypass the
  query, disable AppFlowy/browser-history interpretation for that gesture, and
  send site pan/pinch regardless of host axis filters. Do not enable globally
  for all ordinary articles; use a host/user choice for opaque interactive sites.
- Main's `sharedScrollActivationRegion` / `ScrollGestureGate` / whole-page
  routing must allow the descendant Windows recognizer to win and must not
  perform parallel raw-listener scrolling/history for the same WebView hit.
  Keep ordinary wheel routing unchanged. This patch does **not** modify those
  app surfaces or BookmarkWebPage/Reader/adblock.
- This scope is not a synchronous hit-region ownership callback. In a
  both-axes-disabled host, automatic non-site pans still respect those filters
  (and are not replayed into an ancestor after the arena is accepted). Main
  needs to account for that limitation when integrating whole-page scrolling.

## Implementation

- New `windows/in_app_webview/site_gesture_policy.h`: one bounded
  `Runtime.evaluate` at gesture start, inspecting touch-action, horizontal
  overflow and target/ancestor pointer/touch handler metadata. No domains,
  document text, credentials, URLs or listener source are returned.
- The existing `TrackpadTouchQueue` owns **one shared slot** for that query and
  `Input.dispatchTouchEvent`. Query execution budget: 50ms; Dart wait: 150ms;
  existing native freshness: 250ms. Timeout does not falsely release the slot.
  One latest Dart update and native absolute-move coalescing bound pending work.
- Existing six-value touchscreen and eight-value single trackpad packets remain.
  Ten-value trackpad packets append second-contact X/Y. Start/move carry both
  contacts atomically; terminal packets carry no DOM contacts.
- A late one-to-two-contact Start cancels the old DOM stream through the same
  queue and awaits its ACK. It retains the original native/Flutter clock mapping
  at the last actual contact sample, rather than retiming the pinch to arrival.
- Detected/manual site pinch updates DOM contact separation and center, never
  `put_ZoomFactor`. Confirmed ordinary targets retain existing browser zoom and
  article history behavior. A pan that becomes browser zoom cancels its touch.
- Tiny pan gestures defer touchStart; native CSS-pixel travel guard cancels a
  sub-slop release instead of emulating a click. Navigation, lifecycle, resize,
  offstage re-hit, policy changes and disposal invalidate stale work.
- Physical mouse, six-value touchscreen, native wheel multiplier six,
  compositor/resource ownership and asynchronous texture disposal ACK are kept.
- Private fixture-only `_getSiteGestureDiagnostics('offline-fixture-v1')`
  returns browser ZoomFactor, queue-idle and physical cursor position/visibility.
  It reads state only; it does not warp/hide the cursor or issue CDP commands.

## New tests / coordinator commands

From `C:\AppFlowy\frontend\appflowy_flutter` (nothing below has been run):

1. `flutter test packages/flutter_inappwebview_windows/test/site_gestures_test.dart`
2. In x64 VS Developer PowerShell:
   `& .\packages\flutter_inappwebview_windows\windows\test\run_site_gestures_test.ps1`
   (optional `-JsonInclude` for an existing nlohmann.json installation).
3. Existing queue regression, also unmodified:
   `& .\packages\flutter_inappwebview_windows\windows\test\run_trackpad_touch_queue_test.ps1`
4. `flutter test integration_test/performance/webview_site_gestures_test.dart -d windows --release --dart-define=WEBVIEW_SITE_GESTURES_CONSENT=true`
5. Repeat step 4 with `--debug` instead of `--release`. Coordinate any app/build
   ownership before enabling consent. The fixture binds only loopback HTTP,
   uses a new temp WebView profile, blocks external resources via CSP, enables
   the semantics baseline in setUp, supplies physical keys, and awaits the
   actual `[0,1,2,3,4,5]` texture disposal stages before environment disposal.
6. Main runs analysis/formatting and builds/verifies both runnable bundles,
   Release first and Debug last, using the existing project build task.

New test sources:
- `test/site_gestures_test.dart`: routing, timestamps, bounded pending query,
  fresh-sample timeout/busy recovery, tiny gestures, normal history/zoom, hidden tabs, resize,
  pause, cancel/navigation, scope override, wheel/modified wheel, six-value
  touch, mouse button protocol, late callbacks and disposal ACK.
- `windows/test/site_gestures_test.cpp`: actual production queue/serializer,
  paired coalescing, late-pinch timestamps, contact-count cancellation fence,
  stale timing, policy serialization/generation, close and duplicate callbacks.
- `integration_test/performance/webview_site_gestures_test.dart` (app root):
  actual WebView2 DOM-local canvas zoom/pan, unchanged browser ZoomFactor and
  physical cursor, automatic CSS/scroll/handler/shadow target classification,
  normal article back/forward/browser zoom, cancel/navigation/resize/offstage,
  tiny gesture no-click, native wheel and mouse, texture disposal ACK.

## Known limitations / required follow-up

- None of the above tests has executed; WebView2/CDP behavior and Debug/Release
  compilation remain unverified. No claim about real Google Maps is made.
- Existing package `touch_timing_test.dart` and `scroll_settings_test.dart` mocks
  return null for the new query and some assert immediate touchStart. They need
  coordinator-approved migration: return false for article query, true for site
  cases, pump the async reply, and expect the intentionally deferred touchStart
  and age. Existing fixtures were not edited under the new-tests-only constraint.
- Cross-origin iframe internals, closed shadow roots, transformed iframe
  coordinate systems and document/window delegated-only handlers cannot be
  classified reliably by this bounded query. Use the explicit per-view override.
  Same-origin iframe traversal and open shadow hit testing are best effort.
- Pointer-move listeners can be observational rather than interactive; automatic
  detection is conservative and may prefer a website in such a region.
- Superseded by the narrow follow-up above: indeterminate/busy/slow policy now
  recovers on fresh continuing samples after actual native readiness. Invalidated
  gestures and gestures ending before the reply still cannot replay. Missing or
  legacy channels without an epoch fence still fail closed.
- The synthesized pair starts 48 logical pixels apart, supports pan/scale/
  rotation and is clamped at viewport edges. Very small hit regions, viewport
  clipping and extreme scale limits may distort contact geometry.
- Browser-default behavior in forced-site mode is Chromium's own touch-action
  behavior, potentially visual viewport zoom, not necessarily ZoomFactor.
  Sites implementing only wheel-based zoom may not respond to touch pinch.
- No runtime physical-touch hardware regression is claimed. Package tests
  assert the unchanged six-value route; native fixture intentionally avoids OS
  touch injection and physical mouse positioning.