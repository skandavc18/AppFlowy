# AppFlowy Project Guidelines

## UI Theming

- Every UI change must support AppFlowy's paper mode as well as standard light and dark themes.
- In paper mode, preserve the established warm-tinted surfaces instead of introducing hard-coded white or cool-grey backgrounds.
- Reuse `PaperTheme.isEnabled(context)` and `EditorSurfaceStyle` surface helpers from `frontend/appflowy_flutter/lib/shared/` rather than duplicating paper-mode color checks.
- Verify new or changed surfaces, hover states, overlays, editors, previews, and menus remain visually coherent in paper mode.

## Windows Builds

- When building the Windows desktop app, always build and verify both Debug and Release bundles.
- Report both executable paths, and do not consider the build complete unless both executables exist and were refreshed by the current build.
