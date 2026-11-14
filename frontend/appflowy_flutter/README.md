<h1 align="center" style="margin:0"> AppFlowy_Flutter</h1>
<div align="center">
  <img src="https://img.shields.io/badge/Flutter-v3.13.19-blue"/>
  <img src="https://img.shields.io/badge/Rust-v1.70-orange"/>
</div>

> Documentation for Contributors

This Repository contains the codebase for the frontend of the application, currently we use Flutter as our frontend framework.

### Platforms Supported Using Flutter 💻

- Linux
- macOS
- Windows
  > We are actively working on support for Android & iOS!

_Additionally, we are working on a Web version built with Tauri!_

### Am I Eligible to Contribute?

Yes! You are eligible to contribute, check out the ways in which you can [contribute to AppFlowy](https://docs.appflowy.io/docs/documentation/software-contributions/contributing-to-appflowy). Some of the ways in which you can contribute are:

- Non-Coding Contributions
  - Documentation
  - Feature Requests and Feedbacks
  - Report Bugs
  - Improve Translations
- Coding Contributions

To contribute to `AppFlowy_Flutter` codebase specifically (coding contribution) we suggest you to have basic knowledge of Flutter. In case you are new to Flutter, we suggest you learn the basics, and then contribute afterwards. To get started with Flutter read [here](https://flutter.dev/docs/get-started/codelab).

### What OS should I use for development?

We support all OS for Development i.e. Linux, MacOS and Windows. However, most of us promote macOS and Linux over Windows. We have detailed [docs](https://docs.appflowy.io/docs/documentation/appflowy/from-source/environment-setup) on how to setup `AppFlowy_Flutter` on your local system respectively per operating system.

### Getting Started ❇

We have detailed documentation on how to [get started](https://docs.appflowy.io/docs/documentation/software-contributions/contributing-to-appflowy) with the project, and make your first contribution. However, we do have some specific picks for you:

- [Code Architecture](https://appflowy.gitbook.io/docs/essential-documentation/contribute-to-appflowy/architecture/frontend/frontend/codemap)
- [Styleguide & Conventions](https://docs.appflowy.io/docs/documentation/software-contributions/conventions/naming-conventions)
- [Making Your First PR](https://docs.appflowy.io/docs/documentation/software-contributions/submitting-code/submitting-your-first-pull-request)
- [All AppFlowy Documentation](https://docs.appflowy.io/docs/documentation/appflowy) - Contribution guide, build and run, debugging, testing, localization, etc.

### Account menu

Click the avatar beside your name in the sidebar for **Change profile picture**
or **Log out**. Logging out asks for confirmation before returning to sign-in.

When account settings sync is enabled, workflow files, installed extension
sources and assets, and extension data also follow the account, sealed with its
AppFlowy password. Folder sync carries those same folders. Incoming files reload
the running stores, so they do not require restarting AppFlowy.

Logging out stops workflow clocks, webhooks, extension actions and their file
watchers, disables workflow background startup, and clears local automation
files and extension choices. It does not delete the synced copies: signing back
in restores them instead of syncing the local logout cleanup as a deletion.
Bundled extensions remain part of the application; their account data and
choices are reset. If sign-out is rejected, local data is kept and automation
resumes.

### Background workflows on Linux

In **Workflows > Background**, enable **Keep running after closing the window**
to keep enabled workflows and their webhook listener running without a window.
The notification-area menu can reopen AppFlowy, pause/resume workflows, or quit.
**Start when I sign in** creates an XDG autostart entry that launches AppFlowy
hidden with `--background`; disabling background mode also disables this entry.

Linux needs `libayatana-appindicator3` (or `libappindicator3`) and a desktop
notification area supporting StatusNotifier/AppIndicator. GNOME may need its
AppIndicator extension enabled. If the tray cannot start, AppFlowy stays visible,
turns background mode back off, and shows an error instead of hiding an
unreachable window. Autostart is stored in
`$XDG_CONFIG_HOME/autostart/io.appflowy.appflowy-background.desktop`
(`~/.config/autostart` by default).

The opt-in native regression test closes the real Linux window and verifies a
scheduled workflow still runs, then checks reopening and XDG autostart. Run it
on a desktop with a working notification area and no other AppFlowy instance:

```sh
test_config="$(mktemp -d)"
XDG_CONFIG_HOME="$test_config" flutter test -d linux \
  integration_test/desktop/workflow_background_native_test.dart \
  --dart-define=WORKFLOW_BACKGROUND_NATIVE_TEST=true \
  --dart-define=WORKFLOW_BACKGROUND_TEST_CONFIG="$test_config"
```

The test uses in-memory workflows and only changes autostart inside
`test_config`; remove that temporary directory after the run.

### Native Markdown and HTML previews

Linux renders Markdown and simplified HTML without a web view. Text blocks use
measured heights at the current width and text scale, so scrolling and dragging
the scrollbar do not change the document's length. Long documents and lists
remain lazily mounted. Images and tables retain their natural layout; loading
an image can still reflow the document.

Regression coverage: `flutter test test/unit_test/file/native_markup_preview_test.dart`.

### Linux display refresh rate

Flutter's Linux embedder (3.27.4, and still on Flutter's main branch) starts the
engine's frames on a fixed 60 Hz timer, and GTK 3 paints the OpenGL-drawn
Flutter view at 60 Hz as well. The runner's `linux/display_vsync.cc` lifts both
caps before the engine starts, so frames follow the display (120 Hz on a 120 Hz
screen). It gives the engine a vsync callback by wrapping
`FlutterEngineInitialize` in the procedure table `FlEngine` keeps, and gives each
GTK frame the monitor's refresh interval.

This relies on the engine's private layout, which is checked at startup against
`linux/third_party/flutter_embedder/embedder.h` from the pinned engine revision.
On any mismatch it logs a warning and stays at 60 Hz. When upgrading Flutter,
replace that header with `shell/platform/embedder/embedder.h` from the new
engine revision and check the startup log. Set `APPFLOWY_DISPLAY_VSYNC=0` to turn
it off, or run with `G_MESSAGES_DEBUG=all` to see the intervals in use.

Embedded web views (the office editor) are offscreen GTK windows, which WebKit
would hold to 60 Hz. The `appflowy_linux_webview` plugin turns off WebKit's
`PreferPageRenderingUpdatesNear60FPS`, so pages render at the display's rate
(`APPFLOWY_DISPLAY_VSYNC=0` keeps it on). WebKit composites a page's next frame
only after the last one has been drawn, so the plugin takes each frame as soon
as WebKit hands it over rather than when the offscreen window paints, and copies
it into its own image after telling WebKit it has been drawn. Only the image's
changed rows are uploaded to an `FlTextureGL`; GDK never paints the offscreen
window.

On a computer with an NVIDIA GPU, WebKit would draw pages with NVIDIA's EGL,
which leaves a sync file open in the web process for every frame; once a
process started from the desktop reaches its limit of 1024 open files, the page
stops drawing and documents stop scrolling. Since frames reach the view in
shared memory, the plugin gives the web processes Mesa's EGL wherever Mesa
drives a GPU (the integrated one on a laptop, which also leaves the NVIDIA GPU
asleep), and otherwise raises their open-file limit. An EGL vendor chosen with
`__EGL_VENDOR_LIBRARY_FILENAMES` or `__EGL_VENDOR_LIBRARY_DIRS` is kept.

### Google Maps

With a Google Maps key in Settings > Maps (a Maps Demo Key is enough), maps and
place searches use Google. On every platform, searches ask Places API (New) and
Geocoding API v4, then the legacy Geocoding API, then OpenStreetMap
(`lib/shared/maps/map_geocoder.dart`).

The app draws its maps itself from map tiles, with its own pins on top
(`lib/shared/maps/app_map_view.dart`). Google serves tiles to a renderer like
this only through its Map Tiles API, which a Demo Key does not include, so with
a Demo Key those tiles come from OpenStreetMap. On Linux the map is Google's own
instead: the Maps JavaScript API, which a Demo Key does include, running in the
`appflowy_linux_webview` plugin (`lib/shared/maps/google/`). The plugin draws
the page into a Flutter texture, so the app's search box, controls and hover
cards sit on top of it; it passes the page the wheel and trackpad; and it
carries the page's messages back to the app.

Windows, macOS, Android and iOS do not have Google's map yet, so with a Demo Key
their maps use OpenStreetMap (a key with billing and the Map Tiles API enabled
draws Google's tiles there). They all have web views in this app
(`flutter_inappwebview`: WebView2 on Windows, WKWebView on macOS and iOS, the
system WebView on Android), which already show a pasted Google Maps link as
Google's embedded map, so it is possible, just not built. Each needs building
and testing on its own system: Flutter builds Windows apps only on Windows and
macOS apps only on a Mac, and the parts most likely to break (input, the app's
controls over the web view, and the page reporting back to the app) need the
real machine. Android builds on Linux, so it is the easiest place to start.

The map reaches its page only through `GoogleMapsPages`
(`lib/shared/maps/google/google_maps_pages.dart`), so porting leaves the map
logic alone. It needs:

- a `GoogleMapsPages` that opens the page in `flutter_inappwebview`;
- the page's `post()` to also send through
  `window.flutter_inappwebview.callHandler`;
- wheel and trackpad handling for those web views, or Google's own gestures.

Regression coverage: `flutter test test/widget_test/google_map_surface_test.dart test/unit_test/shared/map_geocoder_fallback_test.dart`.

### Your own AppFlowy Cloud

An AppFlowy Cloud deployment can be used in two ways. Both are offered on the
first screen and in Settings > Account & App > Sync between computers, which
replaced the old "Cloud server" setting.

- **Sync through it**, like Google Drive, OneDrive or Box ("Sync with
  self-hosted AppFlowy Cloud"). The workspace stays on each computer, and the
  sync engine keeps it in step through a folder on the server, sealed with the
  AppFlowy password. Setting it up asks for the server's address first, then an
  account there (sign in, or create one), then the sync folder
  (`lib/workspace/application/sync/self_hosted_cloud.dart`,
  `lib/workspace/presentation/settings/pages/backup/self_hosted_cloud_dialogs.dart`).
  The server needs the sync folders API (`/api/sync-folders`) from
  [skandavc18/AppFlowy-Cloud](https://github.com/skandavc18/AppFlowy-Cloud);
  AppFlowy's hosted service does not have it. Only the tokens the server's
  GoTrue issues are kept, in the same store as other services' tokens (the
  keyring on Linux, DPAPI on Windows, otherwise for the session); the password
  is never stored.
- **Work on it** ("Work on an AppFlowy server"). AppFlowy restarts on the
  server's own sign in, and the server then holds the workspace, with live
  co-editing, sharing and AI. Pick AppFlowy Cloud, or type your own server's
  address; the web address for shared and published pages defaults to the
  server's (`lib/workspace/presentation/settings/pages/backup/appflowy_server.dart`).
  Each server has its own data folder, so the pages kept on this computer come
  back after Leave.

Regression coverage: `flutter test test/unit_test/workspace/self_hosted_cloud_test.dart test/unit_test/workspace/sync_test.dart test/widget_test/self_hosted_cloud_dialogs_test.dart`
(against a stand-in server, `test/unit_test/workspace/self_hosted_cloud_stand_in.dart`),
and `integration_test/desktop/settings/sign_in_page_settings_test.dart` for the
first screen (on Linux, run it under `dbus-run-session` while AppFlowy is open).

### Need Help?

- New to GitHub? Follow [these](https://docs.appflowy.io/docs/documentation/software-contributions/submitting-code/setting-up-your-repositories) steps to get started
- Stuck Somewhere? Join our [Discord](https://discord.gg/9Q2xaN37tV), we're there to help you!
- Find out more about the [community initiatives](https://docs.appflowy.io/docs/appflowy/community).
