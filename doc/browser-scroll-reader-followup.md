# Embed scroll ownership and browser reading follow-up

## Status

The supported changes below are **delivered**. Focused widget/unit checks and
four native integration trials passed. Both normal Windows bundles were rebuilt
and independently verified; the selected Release app was reopened and its
runtime identity checked. Remaining format/visual limits are listed below.

This follow-up addresses the user's repeated reports rather than treating the
previous reduced-motion/layout tests as proof that normal scrolling worked.

## Reproduced causes and changes

- Dashboard activation previously gated Flutter physics but defaulted custom
  gesture filtering off. `ScrollActivationRegion` now filters custom wheel and
  trackpad handlers by default. Inactive embeds leave the original input with
  the parent; clicks, keyboard traversal and accessibility activation remain.
- Document embeds no longer interpret a native renderer's automatic focus as
  permission to scroll inside. Explicit clicks/Tab still activate them. Escape
  and outside clicks disengage without dropping drafts or resetting offsets.
- Disengagement cancels the renderer-owned file-adapter wheel/release activity,
  not merely descendant Flutter ScrollPositions.
- The root Premium dispatcher could claim an independent editor's wheel before
  the whole-file adapter. Enabled adapters now publish the existing exclusion;
  inactive gates filter that marker too. Ordinary nested source editors expose
  their own controller routing even when EditableText suppresses decoration.
- Preview boundaries and chrome ownership prevent nested/bare file renderers
  from borrowing an enclosing file's header adapter.
- Fallback toolbars use measured, physically right-aligned groups rather than
  percentage-width slots. PDF groups wrap. Filmstrip and Places use the album
  page's scrolling header with finite retained stages.
- Opened provider photos reuse the existing workspace photo renderer, giving
  them the same read-only Fit/OCR/fullscreen controls, right-aligned header, and
  fitted-photo wheel/trackpad page flow. Bare provider embeds remain separate.
- Local HTML/Markdown/mail use a bounded, revision-bound native scroll bridge:
  forward header-first travel; reverse header travel only after measured body
  consumption and explicit upper-boundary acknowledgement. Fractional/DPR
  rounding is retained without pretending it is a scroll boundary. A timeout
  never frees an unfinished native operation or accepts its stale result.

## Browser features

### Lightweight blocking

Windows bookmark reading uses a small static ad-network domain list installed
before target navigation through CDP URLPattern blocking. It has no downloaded
filter list, per-request Dart callback, or broad cosmetic substring selector.
The shield toggles blocking and reloads. Unsupported runtimes report the problem
and allow an explicit opt-out; this is not a claim that every ad is blocked.

Unsolicited popup handling uses an explicit native rejection operation that
marks the request handled, completes its deferral and removes its pending owner.
Activated HTTP links retain the existing same-view fallback. Opener-dependent
OAuth popup workflows are not emulated by this reading surface.

### Live / Reader / Offline

Reader extracts visible article text from the existing loaded browser; it does
not require saving first or start another hidden browser. The live renderer is
retained but excluded from input/focus/semantics and suspended where supported.
Reader has local Find and can save a passive text-only offline copy. Navigation,
source changes and revoked write permissions invalidate stale captures/saves.
Hidden text, form values, scripts, frames and visible access gates are not used
to bypass access restrictions. Offline display requests no remote resources.

### Site-owned gestures

Windows performs a bounded gesture-start check for the target's touch action,
interactive handlers and horizontal scrolling. A site-owned pinch is sent as a
paired native touch stream, not browser-wide ZoomFactor changes. Normal article
history and browser zoom remain available. A visible website-gesture override
handles regions that cannot be classified reliably, such as opaque frames.

Policy and touch commands share the existing single native slot, freshness and
navigation fence. Unknown results recover only from fresh samples after true
native readiness. Physical cursor position/visibility, ordinary mouse input and
the six-value touchscreen path are retained.

## Evidence so far

- Newly reproduced hover/autofocus failures were observed before repair; the
  60-case activation/editor/gate/policy batch then passed.
- The latest complete repaired six-file batch passed **174 tests, zero failures**:
  site gestures, provider-photo page flow, specialized album flow, Reader layout,
  Reader permissions and WebView startup. Other passing scopes overlap and are
  not summed here.
- C++ checks passed: all 19 existing touch-queue regressions, all 10 site-gesture
  groups, plus UNKNOWN-recovery, pending-popup lifecycle and null-JavaScript-reply
  programs. The reply regression exercises actual `MethodResult::Success()`
  with a null pointer, encoded null, valid JSON string and unexpected type.
- The combined native fixture compiled without executing app startup.
- Initial native Release run: real blocking/Reader and site-gesture cases passed
  and completed native/environment disposal with stages `[0,1,2,3,4,5]`.
  Blocking checked 84 URL boundaries; two blocked local script requests never
  reached the server, while two opt-out requests did. A local map-like surface
  reached zoom 2 with unchanged browser zoom and physical cursor state.
- That run is **not an accepted complete run**: HTML hit overlapping guarded
  test helpers, cleanup was unproven, and Markdown/email were fenced. The helper
  was repaired to finish guarded dispatch before inspecting held native ACKs;
  later runs continued diagnosis. No native cleanup success or exit code is
  inferred from the old test process subsequently disappearing.
- A subsequent native access violation was captured twice: a reply optional
  contained a null pointer, and `IsNull()` dereferenced it. The native reply
  boundary now checks the pointer and string variant before using either.
- After that repair, Release completed blocking/Reader, site gestures, HTML
  and Markdown with full disposal proof. Email failed initial readiness:
  its load callback compared public wrapper identity rather than the shared
  platform controller, so scrolling installation was skipped. It now uses the
  same controller-identity helper as file previews. The new identity tests
  plus the scroll-bridge unit/widget suite passed **26 tests, zero failures**.
  Disposal diagnostics now start before document-readiness checks so an early
  assertion does not hide cleanup evidence.
- Debug exposed a separate late-reply use-after-free. The matching-symbol dump
  showed the JavaScript reply callback accessing a destroyed native view. Both
  success and error callbacks now check an independently owned lifetime token
  before touching the view. Native regressions cover live, disposed and destroyed
  owners. The package gesture/disposal rerun passed **39 tests**.
- The live fixture's deferred `cancelPointer` was classified as device input
  rather than test input by Flutter 3.27.4. Sending the same valid cancel event
  through `tester.sendEventToBinding` restored actual DOM cancellation evidence.
  File pan traces retain DOM contact counts and header/body positions. This is
  synthetic-input validation, not hardware gesture or arbitrary-timing proof.
- Final current-source native validation: **two Debug and two Release trials
  passed all five cases**, all disposal stages, semantics restoration and native
  exit code 0. Accepted receipt/report hashes are recorded in
  `build/performance/browser-scroll-native-accepted.json`.
- Final production analysis covered 191 changed/new production paths with zero
  errors, zero warnings and 291 informational lints (not a clean-lint claim).
  Details: `build/performance/browser-scroll-final-analysis-summary.json`.
- The initial normal build stopped after successful Rust compilation because
  two blank Cargo-output lines decoded to null under PowerShell strict mode.
  The parser now ignores null/non-message records while retaining optimized-DLL
  verification. Its regression passed against the original log and malformed/
  empty inputs. Both normal builds subsequently completed and passed verification.

Initial failed-run evidence:
`build/performance/browser-scroll-native-release-20260928-115331-196-fd67daea97264d18b53f396cefd41e01/`.

## Remaining boundaries

- Opaque native Office editors currently support downward-wheel header
  retirement, not an acknowledged reverse/momentum boundary handoff.
- Rotated/free-horizontal PDFs, zoomed-photo boundaries and some zoomed pager
  residuals are not universally covered by the new page adapters.
- Local WebView coast stops when residual travel transfers to the header;
  continuous momentum through that boundary is not implemented.
- Automatic website-gesture classification cannot inspect every cross-origin
  frame or closed shadow tree. The explicit override is available.
- Reader/offline output is text-only. This is not a full webpage archive.
- The supplied news URL could not be inspected through page extraction: it
  ended at an ad-system endpoint. No live-site speedup or Google Maps hardware
  verification is claimed by the isolated fixtures.
- Visual review remains unavailable through the existing image transport;
  no new golden baselines have been approved.

## Verified delivery — 2026-09-28

Normal `lib/main.dart` was built Release first, Debug last. Independent verification
at **14:35:32 UTC** confirmed 4,890 identical build inputs, 1,179 functional assets
and 36 native components across both bundles. Input digest:
`BB1B6B28BA9078DA744954BD8D6065289FF102B13DE3A9A8705AE6D15CFD56F6`.

Executables (relative to the repository):
- `frontend/appflowy_flutter/build/windows/x64/runner/Release/AppFlowy.exe`
  refreshed **14:28:49 UTC**; Release AOT refreshed **14:27:31 UTC**.
- `frontend/appflowy_flutter/build/windows/x64/runner/Debug/AppFlowy.exe`
  refreshed **14:34:24 UTC**; Debug kernel refreshed **14:32:38 UTC**.

Release PID **47272** started through Explorer at **14:36:08 UTC**. At
**14:36:42 UTC**, its executable path, responsive window, Explorer parent,
optimized backend hash and unchanged hashes of all four build artifacts were
verified. No existing user app was closed, and no profiles or workspace data
were reset. This runtime check is not visual or live-site approval.

Receipts:
- `build/performance/browser-scroll-native-accepted.json`
- `build/performance/browser-scroll-bundle-verification.json`
- `build/performance/browser-scroll-release-runtime.json`
