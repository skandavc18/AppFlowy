# Cover image loading: verified test handoff (2026-09-27)

## Execution-owner result

**Final CFE/runtime run: 200 passed, 0 failed, 0 skipped, 0 incomplete, 11 files.**
The author-only notes below describe the original handoff, not the current test
status. No app-native build, app launch, live workspace/data/cache access,
golden update, dependency install or code generation was performed.

Evidence at repository root:

- `build/performance/cover-loading-verified-final-20260927-201959-717.log`
- matching `.events.jsonl` and `.summary.json` (per-file counts and test hashes)
- `build/performance/cover-loading-verified-tests.ps1`: direct Flutter 3.27.4
  SDK Dart + flutter-tools snapshot, `--no-pub --concurrency=1`, expanded output
  and JSON file reporter; exclusive process guard. Final runs add `--timeout=30s`.
- `build/performance/cover-loading-verified-finish.ps1`: scoped CLI analysis and
  history/source-hash/measurement manifest (separate from the passing test run).
- Final manifest:
  `build/performance/cover-loading-verified-analysis-20260927-202434-938.manifest.json`.
  Matching `.log` contains every CLI diagnostic. Analysis completed with exit
  **1: 0 errors, 0 warnings, 115 infos** (112 trailing commas, 2 missing braces,
  1 unnecessary import). No style-only repair loop was attempted. Final test
  hashes were unchanged and the final runner-process list was empty.

| Test file (under `test/`) | Passed | Failed |
| --- | ---: | ---: |
| unit_test/image/cover_image_decode_test.dart | 9 | 0 |
| widget_test/cover_image_loading_performance_test.dart | 27 | 0 |
| widget_test/cover_image_native_quality_test.dart | 11 | 0 |
| unit_test/image/appflowy_network_image_test.dart | 1 | 0 |
| widget_test/document_cover_appearance_test.dart | 15 | 0 |
| widget_test/page_cover_resize_test.dart | 22 | 0 |
| widget_test/page_cover_host_integration_test.dart | 66 | 0 |
| widget_test/page_icon_cover_test.dart | 6 | 0 |
| unit_test/workspace/cover_image_download_test.dart | 7 | 0 |
| unit_test/database/media_thumbnail_test.dart | 33 | 0 |
| features/workspace/application/workspace_cover_codec_test.dart | 3 | 0 |

### Actual red-to-green corrections

1. Ran the original 8+27 cases FIRST: **27 passed / 8 failed**, both suites
   compiled. The eight dependent editor diagnostics were stale, not CFE errors.
   Added missing localization pumps and the next build after async eviction;
   no assertions removed. Original 35 cases then all passed.
2. Existing regressions initially **147 passed / 6 failed**. Legacy pixel
   assertions assumed a full-resolution AssetImage clone. They now verify the
   exact wrapped asset, actual bounded dimensions and retained decoded-image
   clone identity across the icon-only resize. Bounded real-IO turns wait for
   the resized frame (fake-clock `pumpAndSettle` is not a codec completion).
3. **Production root fix in `cover_image_decode.dart`:** native contain of
   1200×800 at 640×224 decoded 337×225 instead of 336×224. Binary floating-point
   `800 * (224 / 800)` exceeded the integer slightly before `ceil()`. Scale is
   now retained as an integer ratio, with exact integer ceiling per axis.
   Crop still rounds fractional 426⅔ upward to 427; no upscaling, caps and
   all fit modes remain. Added an exact unit regression and real-codec test.
4. First native run was interrupted: **7 passed / 1 failed / 1 unfinished**,
   not green. Old fixture streams awaited native IO under a frozen test clock.
   Bounded alternating real-IO turns + pumps fixed shutdown. The owned orphan
   `flutter_tester` PID 48112 was verified and stopped; no app was stopped.
5. Native retry fixture now measures 19ms + 1ms AFTER stream error delivery
   reaches native Image's `errorBuilder`, where the real retry timer starts.
   Production retry delays were not changed. Per-file repair cycles stayed
   below the three-cycle limit.

### Native quality and timing evidence (not application FPS)

`cover_image_native_quality_test.dart` generates temporary quadrant PNGs. Real
`CachedNetworkImageProvider`, native Image/ImageCache and native codecs read
those files. A test binding counts codec calls and delegates the unchanged
decoder API; only cache metadata/transport responses are simulated. No mocked
ImageInfo/codec pixels, engine changes or ScrollAware overrides.

Measured **post-delivery frame-wait** wall times in the final test run:

| Fit | Cold | Disk-warm | Memory-warm |
| --- | ---: | ---: | ---: |
| contain | 72.525ms | 26.198ms | 0.533ms |
| crop | 25.827ms | 29.674ms | 0.443ms |
| stretch | 28.680ms | 27.457ms | 0.412ms |

Cold transport delay is a separate **synthetic 200ms fake-clock gate**. No
frame/decode occurs at 199ms; bytes are supplied at 200ms. Values above begin
after that gate (or after mounting warm paths), not at app startup. Every wait
passed a 2-second safety deadline; sub-millisecond values are observations,
not fragile 5ms test thresholds or a production latency SLA.

- Each cold/disk-warm path: exactly 1 cache stream request, 1 native decode,
  1 placeholder build. Memory-warm: exactly 0 of each.
- Five chunk events: 0 Image widget replacements and 0 extra placeholder
  builds. Zero fade transitions; no unused auxiliary cache-status probes.
- 1200×800 source: contain 336×224; crop/stretch 640×427. Four actual RGBA
  quadrant samples verified after decode. Stretch changes painting fit only.
- Portrait 800×1200 → 640×960; panorama 6000×60 → 4096×41;
  portrait 60×6000 → 41×4096; tiny 2×1 → 2×1.
- One-pixel in-bucket changes reuse the actual ui.Image; crossing the bucket
  makes exactly one new decode/request (768×512 in the fixture).
- Native late source/auth/cache-generation frames cannot replace current blue
  pixels with old quadrants. Old errors do not evict/retry the replacement.
  In-place token mutation changes hashed keys while retaining supplied-profile
  headers, including existing self-hosted routing; no auth routing edits here.
- Invalid real PNG bytes evict the failed decoded entry; same-URL remount
  recovers from valid bytes. Transient retry shares eviction across same-URL
  owners, leaves another URL's Image untouched, and frees/reuses last-owner
  counts. Original widget tests additionally cover callback/disposal policy.

All nine scoped editor files reported no diagnostics after final edits, but
CLI analysis reported the 115 infos above; editor results are not substituted
for CLI counts. The user's previously verified 417 Find tests
were NOT rerun or added to these 200; Find/layout/native sources were untouched
by this execution owner. Combined Debug/Release builds remain a later phase.

## Original author-only handoff (historical)

## Status

**Tests, CLI analysis, terminals, builds and app launches are UNRUN in this pass.**
The Find agent exclusively owns execution. Dart editor formatting and editor
diagnostics are the only automated checks used here; they are not compile or
runtime evidence. No goldens changed or visual approval claimed.

Final editor result: all four production paths, the decode helper suite and the
updated existing appearance suite report no diagnostics. The new widget suite
still reports eight missing-member diagnostics for `FlowyNetworkRetryCounter`
(`reset`, `getRetryCount`, `scopedUrlCount`) after a missing helper closing brace
was repaired in its defining file. Those members are now present at class scope
and the defining file is clear, so the dependent diagnostics appear stale, but
remain **unresolved/unverified** here. Do not treat this as an all-clean analysis
or a passing compile. Stop editor repair loops; the execution owner must verify.

## Source-verified costs

- `lib/shared/appflowy_network_image.dart` previously performed
  `getFileFromCache` on every mount even without an `onImageLoaded` consumer.
  This was an extra metadata lookup, not evidence of a second HTTP download.
- Every image listened to the singleton retry `ChangeNotifier`; one URL's retry
  rebuilt every mounted subscriber. `Future.delayed` retry callbacks were not
  cancellable, had no source/auth/disposal generation guards, and the error
  listener removed files/retried regardless of the configured HTTP status set.
  The default policy was five attempts separated by six seconds.
- `ViewCoverImage` and legacy `DesktopCover` supplied no decode hints for local,
  asset or network images. Tiny thumbnails and hero covers could decode the
  full source. Their local path also synchronously tested file existence while
  building. The modern desktop path already used the supplied `ViewPB` without
  a second backend GET; no backend-fetch fix was necessary or made.
- Installed `cached_network_image` 3.4.1 defaults to **500 ms image fade-in and
  1000 ms placeholder fade-out**. Its progress builder runs on chunks, but the
  cover's builder only returned the same static fallback.
- Installed Flutter 3.27.4 `ResizeImagePolicy.exact` distorts the intrinsic aspect
  when both dimensions are given. Width-only sizing does not bound the other
  dimension or guarantee sharp panorama crops. `ResizeImagePolicy.fit` alone
  can underdecode the cropped axis.

## Authored changes

- New `cover_image_decode.dart`: actual layout constraints × DPR, rounded UP
  into 32px buckets through 256px, 128px through 1024px, then 256px buckets.
  Invalid/unbounded geometry does not invent a screen-sized target. No text-scale
  multiplier, speculative preloads or full-resolution metadata decode.
- A resize-only `CoverImageProvider` uses the codec's intrinsic dimensions
  before decoding. Contain uses the smaller scale, crop the larger; stretch
  retains source aspect during decode and stretches only in painting. Never
  upscale during decode. Each decoded axis is capped at 4096 pixels.
- **API choice:** generic `FlowyNetworkImage` callers still use
  `CachedNetworkImage.memCacheWidth/memCacheHeight` unchanged. Bounded covers
  instead use the public `CachedNetworkImageProvider` inside native `Image`
  with the resize adapter. The package widget has no provider/decoder injection
  hook, so forcing its two public mem-cache dimensions cannot also guarantee
  correct Fit/Crop geometry. No package modification or dependency was added.
- Cover placeholders now disappear at the actual decoded frame with no fade;
  no chunk listener is installed for a static placeholder. Native Image keeps
  Flutter's normal ScrollAware admission. No global velocity bypass, hero
  preload, scroll physics change, native-preview change or fullscreen cap.
- URL-keyed callbacks replace global image subscriptions; legacy notifier API
  remains available. Last-owner removal frees URL counts/listeners. State-owned
  retry timers cancel on rebind/disposal; late errors, probes and eviction
  completions are epoch-guarded. Same-attempt/same-cache eviction is shared.
- Retry only configured `HttpExceptionWithStatus` codes, with the existing
  default `{404}` kept for consumers expecting generated images. Selected
  covers opt into `{408,429,500,502,503,504}`: no automatic retries of missing,
  unauthorized or invalid-image covers. Retry limit/delay defaults unchanged.
- Skip the advisory metadata lookup unless `onImageLoaded` is consumed. Keep
  its historical cache-status meaning for screenshot/preview callers; late
  results cannot report against a replacement source, cache or disposed state.
- Snapshot URL/profile-ID/token/cache dependencies, including in-place protobuf
  mutations. Authenticated cache identities are SHA-256 digests, not raw secrets;
  token changes cannot reuse the old provider's pending result. Scoped cache
  instances are isolated too. Unauthenticated production disk keys remain URLs.
  Supplied-profile auth routing (including self-hosted URLs) is unchanged.
  Retry logs contain only status/attempt; malformed tokens are not logged raw.
- Missing-token `ViewCoverImage` fallback remains a security guard, NOT diagnosed
  as a startup defect. Authenticated entries under the old URL-only cache key
  are not adopted into the new credential namespace; first use/token rotation
  may therefore be cold. No user cache is flushed or migrated.
- Both desktop cover generations use the same decoder. Tiny `ViewCoverThumbnail`
  explicitly uses crop/center rather than inheriting a hero presentation scope.
  Corner clipping, ratio, per-page 96..640 height policy, position, persistence
  and sizing drafts are unchanged. `PageCoverController` is unchanged.

### Pixel budgets, not measurements

For a 6000×4000 source, nominal RGBA is 96,000,000 bytes. At DPR 2:

| Display | Bucket | Crop decode | Nominal RGBA |
| --- | --- | --- | --- |
| 720×200 hero | 1536×512 | 1536×1024 | 6,291,456 bytes |
| 44×32 thumbnail | 96×64 | 96×64 | 24,576 bytes |

These exclude encoded files, decoder scratch memory and GPU/cache overhead.
An extreme panorama/portrait or display above the cap can lose crop detail at
4096px; there is no claim of unlimited-DPI fidelity. Fullscreen originals are
unchanged. Network latency, auth readiness, download sizes and overall app FPS
were not measured, and the user's global jerkiness is not declared solved.

## Validation authored; all execution pending

35 new cases are authored: 8 helper cases and 27 widget cases (including the
nine theme × fit combinations). No case has been executed in this pass.

- `test/unit_test/image/cover_image_decode_test.dart`: actual constraints/DPR,
  independent hero/thumbnail targets, stable one-pixel resize/cache keys,
  encoded aspect for contain/crop/stretch, portrait crop, no tiny-image upscale,
  all-fit 4096 caps, invalid/unbounded input.
- `test/widget_test/cover_image_loading_performance_test.dart`: actual temporary
  PNG bytes through controlled cache streams, native chunk delivery, first-frame
  RGBA and decoded dimensions (not painted backdrops), static placeholder rebuild
  counts, local/asset decoding, all three themes × all three fits at 200% text;
  no unused probe; same-URL subscriptions/no cross-URL rebuild; shared eviction;
  bounded HTTP policy; disposal/late callbacks; source/token/cache replacement;
  in-place token mutation; existing self-hosted auth behavior; missing-token
  guard; metadata failures; pending eviction rebind; thumbnail/hero separation;
  generic public mem-cache options/full-resolution defaults.
- `document_cover_appearance_test.dart`: two existing provider assertions now
  inspect the wrapped original AssetImage, preserving exact source assertions.

### Commands for the execution owner — UNRUN

From `frontend/appflowy_flutter`, serialize these with the Find agent's work:

1. `flutter test --no-pub --concurrency=1 test/unit_test/image/cover_image_decode_test.dart test/widget_test/cover_image_loading_performance_test.dart`
   Suggested log: `build/performance/cover-image-loading-focused.log` at repo root.
2. `flutter test --no-pub --concurrency=1 test/unit_test/image/appflowy_network_image_test.dart test/widget_test/document_cover_appearance_test.dart test/widget_test/page_cover_resize_test.dart test/widget_test/page_cover_host_integration_test.dart test/widget_test/page_icon_cover_test.dart test/unit_test/workspace/cover_image_download_test.dart`
   Suggested log: `build/performance/cover-image-loading-regressions.log`.
3. `flutter analyze --no-pub lib/shared/appflowy_network_image.dart lib/shared/cover_image_decode.dart lib/workspace/presentation/widgets/view_cover/view_cover_image.dart lib/plugins/document/presentation/editor_plugins/header/desktop_cover.dart test/unit_test/image/cover_image_decode_test.dart test/widget_test/cover_image_loading_performance_test.dart test/widget_test/document_cover_appearance_test.dart`
   Suggested log: `build/performance/cover-image-loading-analysis.log`.
4. Once ALL agents' sources are stable, run existing **AF: Build and Verify
   Windows Bundles** (Release first, Debug last). Verify freshly built exe AND
   AOT/kernel against the final source snapshot. Expected binary locations:
   `frontend/appflowy_flutter/build/windows/x64/runner/Release/AppFlowy.exe` and
   `frontend/appflowy_flutter/build/windows/x64/runner/Debug/AppFlowy.exe`.

No suggested log above is claimed to exist or contain passing results. Run a
representative cached/cold cover comparison in the fresh app before claiming
the reported delay or global jerkiness is fixed; never log URLs/tokens/headers.

Untouched: WorkspaceFileView, identity/workspace-design layout, shared Find,
native code, tasks, manifests, dependencies, env files and code generation.