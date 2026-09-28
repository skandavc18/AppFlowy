# Find, file headers, icons and warm chrome

## Implemented behavior

- Page-scoped Ctrl+F works from page/header controls without requiring an editor click, including secondary-pane controls. Explicit sidebar navigation opens the existing workspace command palette; modal-route and hidden-view ownership guards remain.
- Dashboard, canvas, loaded AI-chat messages, CSV and notebook text use model-backed local Find with native text highlighting and reveal. Existing document, PDF, image/OCR, source, spreadsheet and collection search engines remain in use.
- The shared Find/Replace bar is capped at 420px, preserves native field/controller/IME state, uses a restrained entrance and replacement-row disclosure, and respects both accessibility motion flags. Replace uses existing editable model transactions rather than altering rendered text or read-only data.
- Database Find materializes distant lazy rows, reveals the matching column and verifies actual native word rectangles. Placeholder expansion can trigger a guarded re-seek. Filters, column visibility, dirty cell drafts and composition are preserved; unavailable or clipped text is reported rather than represented as an exact reveal.
- Workspace search has an explicit **Page contents** option, contextual snippets and subtle word highlighting. Reads are bounded, debounced and authorized before and after materialization; snippets clear on access/source/query/workspace invalidation and popup disposal.
- PDF/file actions share a horizontally scrollable row. PDF reading-mode updates retain the viewer; page-turn raster lookup now agrees with the capped high-DPI rendering budget. Current PDF matches reveal without a surprise zoom.
- Standalone files use a consistent vertical page identity: icon and decoration controls, title, metadata, then hover-revealed actions. Default no-cover top spacing and icon size remain 44px and 56px.
- Short file panes scroll only the retained identity header, reserving up to 120px (40% of a short pane) for the viewer. The 320×260 regression retains a 104px viewer without shrinking text/icons or remounting the renderer.
- Page icons resize continuously from 16 to 320 logical pixels, with fractional drag preview, cancellation, keyboard adjustments and reset. Only `page_icon_size` metadata changes; writes merge fresh metadata and respect locks, access and source identity. Unrelated and legacy covers survive.
- Sidebar/titlebar share warm cream in standard light (`#F6F0E5`) and Paper (`#F0E6D4`), and warm charcoal in dark (`#27231F`). Neutral hover uses a low-alpha wash without doubling the background and Ink layers. Native image/status/brand semantics remain distinct.
- The default icon inventory now has 379 semantic names: 221 use explicit illustrations and 158 intentional utility gradients. There are 125 additional original illustrations; saved picker identities and custom artwork remain intact.
- Windows popup-webview trackpad input preserves original timestamps, rejects stale queued tails, fences navigation and waits for the shared environment before first creation. Chromium retains native wheel/trackpad scrolling; wheel gain was not guessed or reduced.

## Deliberate coverage limits

- Chat searches **loaded messages**, not unfetched history.
- Book/PDF Find searches the **current reader content**, not a new whole-book cross-chapter index.
- Workspace content scanning is bounded and reports partial coverage. It does not index PDF/Office/binary interiors, remote/provider sources or dashboard/canvas configurations; current-surface Find remains separate.
- Database, PDF, chat and other read-only projections do not gain unsafe replacement. Replacements are offered only on supported editable models.
- Caption controls owned by the native window package, immersive photo controls, semantic status/data colors, brands and custom user artwork are not blanket recolored.
- This does not establish that all cold-site network/GPU/JavaScript startup costs or every scroll stutter are eliminated.

## Verification evidence

Paths beginning `build/performance/` below are relative to the repository unless explicitly marked as application-relative.

| Check | Result | Evidence |
| --- | --- | --- |
| Original 38 local Find suites | 635 passed | `build/performance/final-all-find-verified.log` |
| Seven-suite icon/legacy-hover matrix | 62 passed; 4,548 actual glyph renders | `build/performance/final-icon-hover-matrix-verified.log` |
| Light/dark/Paper component fixtures | 3 passed | `build/performance/find-chrome-visual-capture.log` |
| Broader 104-file application selection, latest complete result per file | 2,517 passed; 1 sidebar golden comparison unapproved | `build/performance/final-remaining-app-regressions-manifest.json` |
| Post-short-header Find recheck, six existing files | 62 passed; already included in the 635 Find cases | `build/performance/final-post-header-find-regressions.log` |
| Changed production Dart analysis | 115 paths, no issues | `build/performance/final-production-analysis.log` |
| Windows webview package Dart tests | 22 passed | `build/performance/final-remaining-package-dart.log` |
| Production native trackpad queue/serializer tests | 19 passed | `build/performance/final-remaining-native-queue.log` |
| Installed WebView2 Debug fixture | Passed, original 30ms/5ms intervals and stale cancellation | `build/performance/popup-webview-native-verification-2.log` |
| WebView2 structured report | One native creation; successful navigation recovery | Application-relative `build/performance/large_page_popup_webview_scrolling.json` |

The disjoint application selections contain **3,217 passing test bodies across
150 files**, plus one failing/unapproved golden comparison. Rechecks of the same
files are not added again. With 22 package tests, 19 native policy tests and the
one installed-WebView2 scenario, there are **3,259 passing selected checks**.
This is not an all-workspace test run. Setup/teardown/loader events and the 4,548
glyph renders inside their tests are not additional test bodies.

The short-pane follow-up is the one reviewed production change after the frozen
104-file manifest baseline. Its before/after hashes, 384 passing focused
header/media/neighbour cases, and unchanged golden hashes are recorded in
`build/performance/remaining-short-pane-verification.json`. The old baseline was
not silently rebased. The post-header Find check and 115-path production analysis
then passed. Test-only informational style lints remain; clean production
analysis is not a claim of clean whole-workspace/test analysis.

The retired `document_image_test.dart` rewrite suite and other unselected visual
suites were not run. The selected sidebar golden assertion was retained and
failed with a 68.14% pixel difference against the old baseline. No generated
reference was approved as a substitute for reviewing that change. Both normal
Release/Debug bundles are now built and independently verified below.

### Visual review

The three fresh component PNGs and `find-chrome-review.html` are under application-relative `build/performance/`. They render production controls with synthetic data and bundled fonts; they are not whole-app screenshots. Layout, hit areas, state retention, hover and resize/cancel assertions passed.

**Visual sign-off is blocked:** the direct image channel and one fresh integrated-browser capture returned attachment placeholders rather than viewable images. No unseen image was approved and no golden baseline was changed.

### Completed Windows builds and launch

Both normal `lib/main.dart` bundles were built through
`tool/build_windows_bundles.ps1`, **Release first, Debug last**, replacing the
temporary integration-test executable. The independent verification at
**2026-09-27T04:47:52.9563346Z** rehashed all **4,850 current build inputs** and
confirmed **1,179 functional assets / 36 native components** match across modes.
Input SHA-256:
`192F4A9C45B9C3ED49FA4F8EC3830A5B013A5B644EAE94E7DFE6E3FE8FE327B9`.

| Normal artifact | Modified UTC | Bytes |
| --- | --- | ---: |
| Release `AppFlowy.exe` | `2026-09-27T04:41:47.1698123Z` | 132,096 |
| Release `data/app.so` | `2026-09-27T04:39:26.0495066Z` | 52,265,888 |
| Debug `AppFlowy.exe` | `2026-09-27T04:46:10.9798671Z` | 1,116,672 |
| Debug `data/flutter_assets/kernel_blob.bin` | `2026-09-27T04:44:12.3770125Z` | 192,033,128 |

All four artifacts are nonempty and newer than their own build starts and the
latest changed application source. Executables:

- `C:\AppFlowy\frontend\appflowy_flutter\build\windows\x64\runner\Release\AppFlowy.exe`
- `C:\AppFlowy\frontend\appflowy_flutter\build\windows\x64\runner\Debug\AppFlowy.exe`

Fresh Debug **PID 5560** was launched through Explorer at
`2026-09-27T04:47:53.9139924Z`. At `2026-09-27T04:48:26.0631867Z` its window was
present and responsive, its parent was Explorer, and its loaded `dart_ffi.dll`
matched the verified optimized backend:
`EA61459C507D35F69C0F8F79E57FB9266EC599B5D053DC98ED983AB0036F64B3`.
No existing app was closed, no OS input was injected, and no workspace/profile
was reset. This is process/runtime verification, not full live UI approval.

Evidence under repository-root `build/performance/`:
`find-chrome-windows-build.log`, `find-chrome-bundle-verification.json`, and
`find-chrome-debug-runtime.json`. The normal build's own manifest is
application-relative `build/performance/windows-bundles.json`.

Further detail: `icon-coverage-audit.md`, `hover-effects-audit.md`, and `popup-webview-scrolling.md`.
