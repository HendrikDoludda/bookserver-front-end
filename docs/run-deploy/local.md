# Local

## Commands
| Key | Command |
|---|---|
| `flutter-sdk` | `git clone https://github.com/flutter/flutter.git -b stable ~/develop/flutter` |
| `flutter-path` | `echo 'export PATH="$HOME/develop/flutter/bin:$PATH"' >> ~/.zshrc` |
| `xcode` | `sudo sh -c 'xcode-select -s /Applications/Xcode.app/Contents/Developer && xcodebuild -runFirstLaunch'` |
| `cocoapods` | `brew install cocoapods` |
| `android-licenses` | `flutter doctor --android-licenses` |
| `doctor` | `flutter doctor` |
| `run-macos` | `flutter run -d macos` |
| `simulator` | `open -a Simulator` |
| `emulators` | `flutter emulators` |
| `emulator` | `flutter emulators --launch PASTE_EMULATOR_ID` |
| `devices` | `flutter devices` |
| `run-device` | `flutter run -d PASTE_DEVICE_ID` |

## Run
1. Install the Flutter SDK, which brings Dart — [`flutter-sdk`](#commands), then [`flutter-path`](#commands) and open a new terminal.
2. For iOS and macOS: install Xcode from the App Store, then [`xcode`](#commands) and [`cocoapods`](#commands).
3. For Android: install Android Studio and open it once, so it installs the Android SDK; accept the licenses — [`android-licenses`](#commands) — and create an emulator under *Device Manager*.
4. Check that each platform you build for shows ✓ — [`doctor`](#commands).
5. Run the app on this Mac — [`run-macos`](#commands). While it runs, `r` reloads changed code and keeps the app's state, `R` restarts the app, `q` quits.
6. Or in the iOS simulator — [`simulator`](#commands) — or an Android emulator — [`emulators`](#commands), then [`emulator`](#commands) with an id from that list — and then [`run-device`](#commands) with an id from [`devices`](#commands).
7. A real iPhone needs your signing team once: open `ios/Runner.xcworkspace` in Xcode and pick the team under *Signing & Capabilities*.
