# Scrolling, search-result and cover-loading regressions

## Current status

The source fixes below have focused test evidence and six accepted native
performance trials (three Release, three Debug). Both refreshed normal app
bundles are independently verified; the user-selected Release build is open
and responsive. Remaining format/performance limits are listed below.

The user clarified that Ctrl+F accepts the full word, but results disappear after extending the query. No hard 3–4-character input cap was reproduced.

## Shared search and frame work

- Closed Find no longer retains dashboard provider subscriptions or publishes empty refreshes in response to unrelated events. Unsupported cards do not create embed-search wrappers; cheap activity/query checks precede model lookup.
- Stable text and membership are indexed from model changes, separately from geometry. Native-highlight observation is one-shot on relevant layout, paint, configuration and scroll changes, not a recurring application-frame scan.
- Per-generation native range membership is indexed instead of repeatedly scanning complete match lists. Late typed previews and inserted document nodes explicitly notify the observer; access revocation still clears matches immediately.
- Latest-query recovery runs once after an occupied shared read slot becomes available. It does not release unfinished native work, increase deadlines or require another keystroke. Authorized bounded database snapshots can be re-matched until invalidation; document prefix searches reuse their source generation. Ctrl+P title timeout is reported as incomplete coverage.

Measured operation evidence, not global FPS:

| Check | Before | After |
| --- | ---: | ---: |
| Document checks for 1,000 actual occurrences | 500,500 | 1,000 |
| Snapshot scans for that range query | 2,004 | 3 |
| Open-empty embed authorization calls | 4 | 0 |
| Closed embed unrelated-event Find notifications | 2 | 0 |
| Counted scan work during 120 stable active frames | Not completed in the failing baseline | 0 |

**417 distinct tests across 26 files passed**, including incremental native typing, queued recovery, authority invalidation, exact word boxes, late model updates and retained field/controller state. See `build/performance/scroll-search-handoff.md` for exact logs, per-file counts and limitations. This does not claim every shared content-search mode was changed or certify live application FPS.

## Cover loading

- Cover-specific decoding is DPR-aware, bucketed and aspect-preserving, with no decode upscaling and a 4096px per-axis cap. One-pixel changes inside a bucket reuse the decoded image. Contain, crop and stretch retain their distinct painting semantics.
- Static cover placeholders no longer rebuild on download chunks or wait for the package's 500ms/1000ms fades. Unused advisory cache probes are skipped.
- Retry notifications are scoped by URL, with cancellable timers and source/auth/cache-generation guards. A failed image does not rebuild every other image. Authenticated cache identity is isolated without exposing tokens or flushing user caches.
- Appearance defaults, per-page height, position, legacy covers and missing-token protection remain.

**200 tests across 11 files passed**, using real PNG bytes and native decoding/cache behavior. Controlled memory-warm post-delivery waits were 0.41–0.53ms; cold/disk-warm observations were 25.8–72.5ms. These are fixture observations after byte availability, not network latency or app-startup promises. See `doc/cover-image-loading-performance.md` for full evidence and diagnostic counts.

## Page flow and controls

- Workspace files use a natural unpinned header and bounded retained renderer, rather than independently scrolling header/body areas. Main content explicitly participates through the existing nested coordinator or a renderer-local consumption adapter.
- Finite-width responsive publishers use `FileActionBand`; actual controls, not merely a wide containing box, align physically right. Notebook no longer relies on the 620px compatibility shell. Standalone options remain persistent while onscreen; cover decorations remain separate.
- Supported paths include text/code/notebook, continuous unrotated PDF, archive listings, fitted-photo wheel/vertical trackpad, cloud-folder identity, provider-file text/code dialogs, audited album walls/playlists, and bookmark grid/shelf/feed/timeline.
- Provider dialogs retain a pinned route-safe Close outside the retiring header and reject stale materialization results. Existing renderer/cache/controller and source/access ownership remains.
- Native PDF movement cancels the old pdfrx viewport-resize animation before applying residual scroll, preventing that animation from overwriting the next movement.
- Fitted-photo state tolerates only sub-1e-9 translation noise on an otherwise exact identity matrix; genuine zoom/rotation/pan is not snapped away.
- Copy feedback expands native reveal requests to its real padded bounds. Late completion does not pull a fully retired toolbar back onscreen. There is no recurring observer, new ticker or focus request for feedback.

**1,014 distinct tests across 28 files passed**, including 106 fullscreen cases, 36 right-alignment matrix cases, 12 photo-pan cases and 25 provider-file cases. Exact native header/residual/reverse geometry, clipping, saved drafts and pending action locks remain asserted. The short-pane settling helper waits on idle scroll positions, not unrelated pending-copy spinners. See `build/performance/page-flow-final-blockers-20260927.md`.

These counts are separate scopes and may overlap; they are not summed into a fabricated unique total. Source analyses reported no errors/warnings in their scopes, but informational style lints remain.

## Accepted native performance evidence

All six revision-3 fixtures passed with complete six-window/six-cover reports,
equal semantics-handle counts, complete cleanup, zero remaining transient
callbacks and native process exit 0. Receipt/report hashes were independently
checked against the current fixture. Exact accepted paths and hashes:
`build/performance/scroll-search-native-accepted.json`.

All **36 timed scroll windows** recorded zero foreground-read and hidden-tab-read
deltas. The following values are milliseconds and are **medians of three trial
p95 values**, not pooled/global percentiles. N is cards per tab (two retained
tabs); each tab also contains the 1,000-occurrence editor.

| Mode | N | Find | Build p95 | Raster p95 | Total-span p95 |
| --- | ---: | --- | ---: | ---: | ---: |
| Release | 10 | Active | 12.771 | 2.180 | 14.902 |
| Release | 10 | Closed | 0.348 | 1.039 | 2.250 |
| Release | 50 | Active | 11.945 | 1.758 | 13.875 |
| Release | 50 | Closed | 0.834 | 1.108 | 2.757 |
| Release | 100 | Active | 11.990 | 1.901 | 14.215 |
| Release | 100 | Closed | 1.873 | 1.561 | 3.941 |
| Debug | 10 | Active | 27.573 | 1.789 | 29.148 |
| Debug | 10 | Closed | 1.795 | 1.443 | 3.955 |
| Debug | 50 | Active | 25.405 | 1.876 | 27.736 |
| Debug | 50 | Closed | 2.806 | 1.266 | 4.564 |
| Debug | 100 | Active | 27.118 | 2.101 | 29.851 |
| Debug | 100 | Closed | 4.527 | 1.422 | 6.708 |

Release active windows delivered 99–100 of 100 scheduled inputs; Debug active
windows delivered only 54–61, skipping late slots rather than replaying a burst.
Closed-Find windows delivered all 100 inputs in both modes. These demand-driven
engine timings/frame counts are not monitor-presentation FPS. **Active Find
remains costly, particularly in Debug**; there is no historical application-FPS
baseline or guarantee of stutter-free behavior on every page.

At the recorded DPR 1.25, the paired native cover probes decoded the same
3000×2000 source to 512×342 with the cover policy: estimated RGBA storage fell
from **24,000,000 to 700,416 bytes (97.0816%)**. This is decoded-image storage,
not whole-process memory. For cold unique keys with no injected byte delay:

| Mode | Median source-to-decoded, plain → cover | Median source-to-first-UI post-frame, plain → cover |
| --- | --- | --- |
| Release | 81.281 → 39.820 ms | 83.256 → 41.666 ms |
| Debug | 322.420 → 52.144 ms | 344.301 → 57.724 ms |

These are same-build decoder-policy comparisons, not previous-app speedups.
Plain decoding preceded optimized decoding in these probes; process/codec cache
warm-up and order effects remain, especially in Debug. Warm-remount timings were
variable (the optimized Release remount was slower in two of three pairs).
The separately injected 80ms byte-delay cases are not included in the table.
Failed earlier fixture receipts are excluded from all reported accepted results.

Final analysis covered **173 current production Dart paths**, with **0 errors,
0 warnings and 210 informational lints**. This is not a clean-lint claim.
Evidence: `build/performance/scroll-search-final-analysis-summary.json` and
the corresponding production-analysis log.

## Boundaries still explicit

- Whole-page handoff for rotated, facing, page-break and horizontal PDFs is not established by the continuous-PDF adapter.
- Native Office and HTML/Markdown/mail WebViews do not yet expose the exact body-consumption protocol needed for safe reverse/momentum handoff. A parent scroll wrapper alone is not claimed to fix those formats.
- Zoomed-photo boundary-to-header handoff, every specialized album mode, populated playlist playback and every provider-native renderer have not been exhaustively verified.
- No new visual/golden approval was performed. The existing image transport limitation remains; no unseen reference was approved.
- The isolated `integration_test/performance/scroll_search_performance_test.dart` measures current-build synthetic engine work and paired decoder policies, not historical whole-app FPS. Its six accepted runs do not certify all live pages or native Office/WebView integration.

## Verified delivery — 2026-09-28

Both normal `lib/main.dart` bundles were rebuilt **Release first, Debug last**.
Independent verification at **01:31:32.6257165 UTC** rehashed **4,870 current
inputs**, matching SHA256
`A50B1D2AD065BDEB6FB5CC7FCA2DDEB2C4BA2DF7A4DFFC940799827F5605BD24`.
Parity passed for **1,179 functional assets and 36 native components**,
including the same optimized Rust backend in both bundles.

Executables:

- Release: `C:\AppFlowy\frontend\appflowy_flutter\build\windows\x64\runner\Release\AppFlowy.exe`
- Debug: `C:\AppFlowy\frontend\appflowy_flutter\build\windows\x64\runner\Debug\AppFlowy.exe`

All four artifacts are nonempty and newer than both their own build start and
the latest changed application source:

| Artifact | Bytes | Modified UTC, 2026-09-28 |
| --- | ---: | --- |
| Release `AppFlowy.exe` | 132,096 | 01:27:38.0941973 |
| Release `data/app.so` | 52,577,184 | 01:26:47.0872849 |
| Debug `AppFlowy.exe` | 1,116,672 | 01:30:18.4990433 |
| Debug `data/flutter_assets/kernel_blob.bin` | 192,616,048 | 01:29:18.1983258 |

The user explicitly selected **Release** for reopening. Fresh normal Release
PID **42948** started at **01:31:39.9229030 UTC** through Explorer, without
launch flags, a profile override, workspace reset or force-closing another app.
At **01:31:58.2823699 UTC**, its window existed and was responsive, its parent
was Explorer, all four artifact hashes remained unchanged, and its loaded
`dart_ffi.dll` file matched the verified optimized backend SHA256
`69E1E81233EF067EB1D2CD8DB6E55542983CF6A75C7616562A87E52939DAAE66`.
This is launch/identity evidence, not full visual or live-page FPS approval.

Records:

- `build/performance/scroll-search-normal-windows-build.log`
- `build/performance/scroll-search-bundle-verification.json`
- `build/performance/scroll-search-release-runtime.json`

No application source changed after these builds. The temporary performance
fixture is not the delivered AppFlowy target.
