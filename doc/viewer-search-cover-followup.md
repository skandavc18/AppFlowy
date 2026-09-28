# Viewer, search, folder and cover follow-up

## Implemented changes

1. Fullscreen PDF, photo and archive routes expose a persistent X outside overflowing controls. Workspace photos have a fullscreen entry using the existing image renderer and shared themed chrome. PDF search reports whole-document progress and does not prematurely choose a result while later pages are being scanned; search already traversed all pages.
2. The database collection's Tables control remains available when its rail is hidden.
3. Find maps native text spans correctly, observes late rendering, excludes hidden children, and searches visible authorized default dashboard page/database previews. Nested document queries remain independent and embedded projections remain read-only.
4. Ctrl+P title search includes authorized cached workspace pages independently of delayed backend results, rejects stale generations, and uses a subtle theme-aware scrim and reduced-motion-aware transition.
5. Archive search protects native text-entry shortcuts and Enter focus, displays count/scope, filters recursively and restores the browsed path when cleared. Existing path matching already included filenames; it was not replaced with an incorrect filename-only diagnosis.
6. Standalone file controls stay visible below the title, aligned right. Photo/fullscreen controls use the shared UI styling rather than a separate black-overlay design. Short file panes retain a scrollable header and usable viewer space.
7. Folder/file identity appears in all seven folder presentations, with proper default monochrome/Vivid icons and saved custom artwork taking precedence.
8. Page covers resize through guarded metadata-only writes with drag cancellation, keyboard controls and reset. Document, folder, dashboard, collection, database and standalone-file headers are integrated.
9. Native WebView measurement exposed an intermittent shutdown crash. The symbolized fault was static compositor destruction during DLL process detach. Platform-thread shared ownership now releases compositor, graphics, dispatcher and runtime resources in a defined lifetime. Asynchronous texture unregistration retains its resources through completion.
10. Folder headers and lazy listings scroll together. Audited generic collection contents, external listings and album Grid/Masonry/Timeline use the shared whole-page header path; Columns retains coordinated directory scrolling.
11. Appearance settings provide device-local cover defaults: rounded/square corners, aspect ratio, Fit/Fill-Crop/Stretch, vertical position and reset, with a live preview. Existing images and per-page height overrides are preserved. English locale source and generated language assets were synchronized normally.

## Verified evidence

- **1,429 passed, 0 failed, 0 skipped** across 57 selected application test files: repository-root `build/performance/followup-remaining-full57-20260927-131725-193.summary.json` and matching log/events.
- **26 WebView package Dart tests passed**, including shared asynchronous disposal acknowledgements and existing input/gesture behavior: `build/performance/cadence-native/package-disposal-input-verified.log`.
- Native cadence observer, texture retirement, platform resource ownership and **19 input-queue cases** passed: `build/performance/cadence-native/observer-and-queue.log`.
- **Three Release and three Debug native trials passed**, each with success=true, native quiescence, disposal stages 0–5 and process exit 0. Application-relative manifests: `build/performance/cadence-baseline_release_20260927_154209-manifest.json` and `cadence-baseline_debug_20260927_163450-manifest.json`.
- Consolidated native metrics: repository-root `build/performance/followup-native-verified.json`. These are callback/capture measurements, not monitor presentation counters.
- Final analysis covered **152 changed production Dart files**, with **0 errors, 0 warnings and 138 informational lints**. This is not a completely clean lint claim. Evidence: `build/performance/followup-final-analysis-summary.json` and `followup-final-production-analysis.log`.
- Formatter processed the documented follow-up application/test files through the editor. No golden baseline was updated or approved.

## Explicit limitations

- **No general WebView scrolling-FPS improvement is established.** The native crash is repaired and repeated clean exits are verified. No frame-rate cap, wheel gain, vsync flag or scrolling engine was changed. Site/device-specific poor frame rate remains unresolved without a representative reproducible case; invalid earlier trials are not used to manufacture a speedup.
- Dashboard Find covers visible authorized typed content. Unloaded, collapsed or clipped bodies, custom/provider content, media and canvas-painted labels are not claimed as universally searchable.
- Specialized multi-pane readers, native database workbenches and unaudited collection modes retain their existing scrolling behavior. Workspace-root covers use their real workspace metadata and follow appearance defaults, but do not use synthetic page IDs for per-page height writes.
- Existing golden comparisons remain unapproved: the image transport returned placeholders during visual review. Passing numeric geometry/theme tests is not full visual approval.
- Historical tests/builds from the previous delivery are not added to these follow-up totals.

## Normal application delivery — verified

Normal `lib/main.dart` **Release then Debug** builds completed, replacing the
cadence fixture executables. Independent verification at
`2026-09-27T11:48:10.2412206Z` rehashed **4,865 current inputs**, checked all four
fresh executable/runtime artifacts, and confirmed parity of **1,179 functional
assets and 36 native components**. Input SHA-256:
`6C8391B4C42305A0473BF69EE22266C11A6B60D2B6B8D0F39AA1FF4B3ED382AF`.

| Artifact | Modified UTC | Bytes |
| --- | --- | ---: |
| Release `AppFlowy.exe` | `2026-09-27T11:42:27.7887640Z` | 132,096 |
| Release `data/app.so` | `2026-09-27T11:41:30.4163079Z` | 52,462,496 |
| Debug `AppFlowy.exe` | `2026-09-27T11:46:35.9863763Z` | 1,116,672 |
| Debug `data/flutter_assets/kernel_blob.bin` | `2026-09-27T11:45:02.2860031Z` | 192,416,856 |

Both executables:

- `C:\AppFlowy\frontend\appflowy_flutter\build\windows\x64\runner\Debug\AppFlowy.exe`
- `C:\AppFlowy\frontend\appflowy_flutter\build\windows\x64\runner\Release\AppFlowy.exe`

Fresh normal Debug **PID 8024** launched through Explorer at
`2026-09-27T11:48:10.6549032Z`. At `2026-09-27T11:48:40.8352136Z`, its window was
present and responsive, with the verified optimized backend and current repaired
WebView plugin loaded. This is a runtime startup check, not full visual approval
or evidence that arbitrary live-site scrolling became faster.

Evidence under repository-root `build/performance/`:
`followup-normal-windows-build.log`, `followup-bundle-verification.json`, and
`followup-debug-runtime.json`. The build's own manifest is application-relative
`build/performance/windows-bundles.json`. The app is left open; no new app source
was edited after these builds. The explicit limitations above remain.
