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

### Need Help?

- New to GitHub? Follow [these](https://docs.appflowy.io/docs/documentation/software-contributions/submitting-code/setting-up-your-repositories) steps to get started
- Stuck Somewhere? Join our [Discord](https://discord.gg/9Q2xaN37tV), we're there to help you!
- Find out more about the [community initiatives](https://docs.appflowy.io/docs/appflowy/community).
