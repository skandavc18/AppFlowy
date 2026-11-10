# Description

This is a guide on how to build the rust SDK for AppFlowy on android.
Compiling the sdk is easy it just needs a few tweaks.
When compiling for android we need the following pre-requisites:

- Android NDK Tools. (v24 has been tested).
- Cargo NDK. (@latest version).

**Getting the tools**
- Install cargo-ndk ```bash cargo install cargo-ndk```.
- [Download](https://developer.android.com/ndk/downloads/) Android NDK version 24.
- When downloading Android NDK you can get the compressed version as a standalone from the site.
    Or you can download it through [Android Studio](https://developer.android.com/studio).
- After downloading the two you need to set the environment variables. For Windows that's a separate process.
    On macOS and Linux the process is similar.
- The variables needed are '$ANDROID_NDK_HOME', this will point to where the NDK is located.
---

**Cargo Config File**
This code needs to be written in ~/.cargo/config, this helps cargo know where to locate the android tools(linker and archiver).
**NB** Keep in mind just replace 'user' with your own user name. Or just point it to the location of where you put the NDK.

```toml
[target.aarch64-linux-android]
ar = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
linker = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang"

[target.armv7-linux-androideabi]
ar = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
linker = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi29-clang"

[target.i686-linux-android]
ar = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
linker = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/i686-linux-android29-clang"

[target.x86_64-linux-android]
ar = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar"
linker = "/home/user/Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/bin/x86_64-linux-android29-clang"
```

**Clang Fix**
 In order to get clang to work properly with version 24 you need to create this file.
 libgcc.a, then add this one line.
 ```
 INPUT(-lunwind)
 ```

**Folder path: 'Android/Sdk/ndk/24.0.8215888/toolchains/llvm/prebuilt/linux-x86_64/lib64/clang/14.0.1/lib/linux'.**
After that you have to copy this file into three different folders namely aarch64, arm, i386 and x86_64.
We have to do this so we Android NDK can find clang on our system, if we used NDK 22 we wouldn't have to do this process.
Though using NDK v22 will not give us a lot of features to work with.
This GitHub [issue](https://github.com/fzyzcjy/flutter_rust_bridge/issues/419) explains the reason why we are doing this.

 ---

 **Android NDK**

 After installing the NDK tools for android you should export the PATH to your config file
 (.vimrc, .zshrc, .profile, .bashrc file), That way it can be found.

 ```vim
 export PATH=/home/sean/Android/Sdk/ndk/24.0.8215888
 ```

 ---

**x86_64 emulators and Waydroid**

The APK only packages `arm64-v8a` unless you pass `abi-filters`. To run on an x86_64 emulator or Waydroid, build the SDK for `x86_64` (with the `dart-ffi` crate type switched to `cdylib`, as `cargo make` does) and select that ABI. Gradle needs JDK 17, and the Android SDK at `ANDROID_HOME` needs NDK `24.0.8215888` with its license accepted: every `flutter` command rewrites `android/local.properties` from `ANDROID_HOME`, so set it in the shell, not only in that file.

In Waydroid, a laptop touchpad arrives as mouse-wheel notches (10 px of finger travel each). `lib/shared/scrolling/waydroid_scroll.dart` detects Waydroid and turns them back into 1:1 scrolling with the desktop release coast; other Android devices are unaffected.

```bash
# frontend/rust-lib (cargo-ndk 3.x; --bindgen points librocksdb-sys at the NDK sysroot)
cargo ndk -t x86_64 --bindgen -o ../appflowy_flutter/android/app/src/main/jniLibs build --features "dart,openssl_vendored" --package=dart-ffi --release

# frontend/appflowy_flutter: fetch the built-in office editor first (see below)
dart run tool/office_editor/fetch_office_editor.dart

# frontend/appflowy_flutter (`flutter run` accepts the same -P flag)
flutter build apk --release --target-platform android-x64 -P abi-filters=x86_64
waydroid app install build/app/outputs/flutter-apk/app-release.apk
```

**Built-in office editor**

Word, Excel and PowerPoint files open in the same bundled editor as on the desktop, and the APK carries it: `android/app/build.gradle` stages `frontend/appflowy_flutter/office_editor` as `assets/office_editor/**` (task `stageOfficeEditorAssets`, run before every `merge*Assets`). That folder is not in git, so fetch it before building:

```bash
# frontend/appflowy_flutter; re-run after pulling a change to the tool. It skips the download when the folder is current.
dart run tool/office_editor/fetch_office_editor.dart
```

Without it the build still succeeds, but prints `Warning: … office_editor is missing` and the APK has no editor: office files then fall back to AppFlowy Cloud's editor or a self-hosted document server, as before.

- The editor adds about 183 MB to the APK (413 MB unpacked). Already-compressed files (`.br`, `.woff2`, `.pptx`, and PNG by default) are stored; scripts, JSON, WASM and fonts stay deflated.
- The first time a document opens, `OfficeEditorBundle.kt` copies the assets into the app's files (`files/office_editor`, excluded from backups) while the editor shows "Preparing the document editor…" with progress. It needs about 480 MB free. Later launches and updates reuse the copy until an APK brings a different `APPFLOWY_BUNDLE.json`/`build-identity.json`.
- The editor is served to the WebView over `http://127.0.0.1`, which `res/xml/network_security_config.xml` allows; every other host keeps Android's no-cleartext default, so a self-hosted document server must use HTTPS.
- To debug, `adb logcat -s AppFlowyOfficeEditor` shows each unpacking (file count, size, time) and any failure. Deleting `files/office_editor` makes the next document unpack it again: `adb shell run-as io.appflowy.appflowy rm -rf files/office_editor` on a debug build, or remove `/data/data/io.appflowy.appflowy/files/office_editor` from a root shell (`sudo waydroid shell` on Waydroid).
