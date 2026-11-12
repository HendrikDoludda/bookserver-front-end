# bookserver

Native front-end for the bookserver, built with [Flutter](https://docs.flutter.dev/).
One Dart codebase targets **iOS, Android and macOS**.

| | |
|---|---|
| App ID (iOS bundle ID / Android `applicationId`) | `com.hendrikdoludda.bookserver` |
| Dart package name | `bookserver` (imports look like `package:bookserver/...`) |
| Flutter / Dart at project setup | 3.50.0 stable / 3.14.0 |

## One-time machine setup (macOS)

Flutter compiles your Dart code, but each platform is still built by its own native
toolchain. You need Flutter plus the native tools for every platform you build.

1. **Flutter SDK** (this includes Dart, so don't install Dart separately):
   ```sh
   git clone https://github.com/flutter/flutter.git -b stable ~/develop/flutter
   echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> ~/.zshrc   # then open a new terminal
   flutter --version   # the first run downloads the Dart SDK
   ```
2. **Xcode** (for iOS and macOS) from the App Store, then:
   ```sh
   sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'
   brew install cocoapods   # still needed for plugins that don't support Swift Package Manager yet
   ```
3. **Android Studio** (for Android). Open it once and let it install the Android SDK,
   then run `flutter doctor --android-licenses`. Flutter uses the JDK bundled with
   Android Studio. Create an emulator under *Device Manager*.
4. **Editor:** VS Code with the *Flutter* extension (it also installs *Dart*), or
   Android Studio with the Flutter plugin.
5. **Check everything** with `flutter doctor`. Every platform you build for should show ✓.

> Prefer an Apple Silicon Mac: Flutter is deprecating Intel Macs, and a future
> version will no longer build on them.

## Run it

```sh
flutter pub get          # fetch packages (pubspec.yaml -> pubspec.lock)
flutter devices          # list simulators, emulators, phones and this Mac
flutter run -d macos     # or -d <device id from `flutter devices`>
```

- **iOS Simulator:** `open -a Simulator` first.
- **Android emulator:** `flutter emulators` to list them, then `flutter emulators --launch <id>`.
- **A real iPhone:** open `ios/Runner.xcworkspace` in Xcode once and pick your Team
  under *Signing & Capabilities*.

While `flutter run` is active, press `r` for **hot reload** (applies code changes and
keeps app state), `R` for **hot restart** (resets state), `q` to quit. In VS Code, F5
starts the app and saving a file triggers hot reload.

## Everyday commands

| Command | What it does |
|---|---|
| `flutter pub add <package>` | Add a dependency (find packages on [pub.dev](https://pub.dev)) |
| `flutter analyze` | Static analysis plus the lint rules in `analysis_options.yaml` |
| `dart format .` | Format code in the standard Dart style |
| `flutter test` | Run the tests in `test/` |
| `flutter build ipa` / `appbundle` / `macos` | Release builds for App Store / Play Store / Mac (code signing must be set up first) |
| `flutter upgrade` | Update the Flutter SDK. Do this deliberately, as a team |

## Project layout

```
lib/                    your Dart code; main.dart is the entry point
test/                   tests (flutter_test)
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
- **Plain `http://`** (for example a local dev server) is blocked by default on
  iOS/macOS (App Transport Security) and Android (cleartext traffic). Use `https://`,
  or add a debug-only exception.
- **Android emulator to your Mac:** inside the emulator, `localhost` is the emulator
  itself. Your Mac is `10.0.2.2`.
