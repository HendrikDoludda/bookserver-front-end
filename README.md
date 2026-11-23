# bookserver

[![CI](https://github.com/HendrikDoludda/bookserver-front-end/actions/workflows/ci.yml/badge.svg)](https://github.com/HendrikDoludda/bookserver-front-end/actions/workflows/ci.yml)

Native front-end for the bookserver, built with [Flutter](https://docs.flutter.dev/).
One Dart codebase targets **iOS, Android, macOS, Windows and Linux**.

## Download

The app reads from a bookserver, so start the server first:
[bookserver-back-end](https://github.com/HendrikDoludda/bookserver-back-end) has its downloads
and how to start it. Then open the app and enter `http://localhost:8080`. Type the `http://`:
without it, the app tries `https://`.

- **macOS 12 or newer**, Apple Silicon or Intel:
  [bookserver-macos.zip](https://github.com/HendrikDoludda/bookserver-front-end/releases/download/desktop-builds/bookserver-macos.zip).
  Double-click the zip and drag `bookserver.app` into Applications. The app isn't signed by an
  identified developer, so macOS refuses the first start: click *Done*, open System Settings →
  Privacy & Security, click *Open Anyway* next to bookserver and confirm. When it asks for the
  keychain, where it keeps the login, enter your Mac password and click *Always Allow*.
- **Windows 10 or 11**, 64-bit:
  [bookserver-windows-x64.zip](https://github.com/HendrikDoludda/bookserver-front-end/releases/download/desktop-builds/bookserver-windows-x64.zip).
  Right-click the zip → *Extract All*, then open `bookserver.exe` in that folder. If SmartScreen
  says "Windows protected your PC", click *More info* → *Run anyway*.
- **Linux**, 64-bit, Ubuntu 22.04, Debian 12 or newer:
  [bookserver-linux-x64.tar.gz](https://github.com/HendrikDoludda/bookserver-front-end/releases/download/desktop-builds/bookserver-linux-x64.tar.gz).
  Extract it and run `bookserver/bookserver`. It needs GTK 3 and libsecret, which the Ubuntu and
  Debian desktops already have; step 4 of [linux.md](docs/run-deploy/linux.md) installs them
  elsewhere.

These are unsigned preview builds, made as [github.md](docs/run-deploy/github.md) says.

| | |
|---|---|
| App ID (iOS bundle ID / Android `applicationId`) | `com.hendrikdoludda.bookserver` |
| Dart package name | `bookserver` (imports look like `package:bookserver/...`) |
| Flutter / Dart at project setup | 3.50.0 stable / 3.14.0 |

- Setting up a machine and running the app: [docs/run-deploy/local.md](docs/run-deploy/local.md)
- Commands for development: [docs/commands.md](docs/commands.md)
- Where the code lives and the rules it follows: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

Flutter compiles the Dart code, but each platform is still built by its own native
toolchain: Xcode for iOS and macOS, the Android SDK for Android, Visual Studio for Windows,
CMake and clang for Linux. Editing works in VS Code
with the *Flutter* extension (it installs *Dart* too), or in Android Studio with the
Flutter plugin.

> Prefer an Apple Silicon Mac: Flutter is deprecating Intel Macs, and a future
> version will no longer build on them.

## Project layout

```
lib/                    your Dart code; main.dart is the entry point
test/                   tests (flutter_test)
assets/                 files bundled into the app, such as the built-in English texts
docs/                   architecture, commands, and how to run the app
pubspec.yaml            name, version, dependencies, assets
pubspec.lock            exact resolved versions. Committed, so everyone builds the same thing
analysis_options.yaml   lint rules (flutter_lints)
android/ ios/           native host projects that wrap the Flutter app,
macos/ windows/ linux/  one per platform
docker/                 the Linux build, run in a container
.github/                CI and the desktop builds for download
```

The native folders are generated. You only edit them for platform configuration:
permissions, app icons, signing, entitlements and minimum OS versions. `build/` and
`.dart_tool/` are generated output and are git-ignored.

`version: 1.0.0+1` in `pubspec.yaml` means `<version name>+<build number>`. It becomes
`CFBundleShortVersionString` / `CFBundleVersion` on Apple and `versionName` /
`versionCode` on Android. Increase the build number for every store upload.

## License

Copyright © 2026 Hendrik Doludda. Licensed under the [MIT License](LICENSE).
