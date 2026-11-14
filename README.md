# bookserver

Native front-end for the bookserver, built with [Flutter](https://docs.flutter.dev/).
One Dart codebase targets **iOS, Android and macOS**.

| | |
|---|---|
| App ID (iOS bundle ID / Android `applicationId`) | `com.hendrikdoludda.bookserver` |
| Dart package name | `bookserver` (imports look like `package:bookserver/...`) |
| Flutter / Dart at project setup | 3.50.0 stable / 3.14.0 |

- Setting up a machine and running the app: [docs/run-deploy/local.md](docs/run-deploy/local.md)
- Commands for development: [docs/commands.md](docs/commands.md)
- Where the code lives and the rules it follows: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

Flutter compiles the Dart code, but each platform is still built by its own native
toolchain: Xcode for iOS and macOS, the Android SDK for Android. Editing works in VS Code
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
android/ ios/ macos/    native host projects that wrap the Flutter app
```

The native folders are generated. You only edit them for platform configuration:
permissions, app icons, signing, entitlements and minimum OS versions. `build/` and
`.dart_tool/` are generated output and are git-ignored.

`version: 1.0.0+1` in `pubspec.yaml` means `<version name>+<build number>`. It becomes
`CFBundleShortVersionString` / `CFBundleVersion` on Apple and `versionName` /
`versionCode` on Android. Increase the build number for every store upload.

## Before the first API call to the bookserver

The generated project can't reach the network in every build yet:

- **Android release builds:** the `INTERNET` permission is only in the debug and
  profile manifests. Add `<uses-permission android:name="android.permission.INTERNET"/>`
  to `android/app/src/main/AndroidManifest.xml`. Without it, release builds can't
  reach the network and show no clear error.
- **macOS (debug and release):** the app is sandboxed without outgoing-network
  permission. Add the `com.apple.security.network.client` key set to `true` to both
  `macos/Runner/DebugProfile.entitlements` and `macos/Runner/Release.entitlements`.
- **Android emulator to your Mac:** inside the emulator, `localhost` is the emulator
  itself. Your Mac is `10.0.2.2`.
