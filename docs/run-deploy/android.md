# Android

## Commands
| Key | Command |
|---|---|
| `release-key` | `mkdir -p ~/keys && "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool" -genkeypair -v -keystore ~/keys/bookserver-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias bookserver` |
| `key-properties` | `touch android/key.properties && open -e android/key.properties` |
| `build-apk` | `flutter build apk --release` |
| `apk-signer` | `~/Library/Android/sdk/build-tools/36.0.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk` |
| `install-apk` | `~/Library/Android/sdk/platform-tools/adb install -r build/app/outputs/flutter-apk/app-release.apk` |

## Deploy
1. Once, ever: create your release key — [`release-key`](#commands). It asks for a password and your name. Keep the password in your password manager and a copy of `~/keys/bookserver-release.jks` in your backup: without both, no later APK installs over this one.
2. Once on each machine that builds releases: create `android/key.properties`, which git ignores — [`key-properties`](#commands) — with four lines: `storeFile=` and the full path of the `.jks` file, `storePassword=` and the password, `keyAlias=bookserver`, `keyPassword=` and the same password.
3. Before handing out a newer APK, raise the build number after `+` in `pubspec.yaml`'s `version` (`1.0.0+1` → `1.0.0+2`): Android refuses one lower than the installed app's.
4. Build — [`build-apk`](#commands). The APK is `build/app/outputs/flutter-apk/app-release.apk`, one file for every phone. Without `android/key.properties` the build stops and says so.
5. To see which key signed it — [`apk-signer`](#commands): `Signer #1 certificate DN` is the name from step 1.
6. Install it on a phone connected by USB, with USB debugging on — [`install-apk`](#commands) — or copy the APK onto the phone and open it there, allowing the app you open it with to install apps.
7. A release build needs the server's `https://` address: connect it to your `tailscale serve` address ([tailscale.md](../../../bookserver_backend/docs/run-deploy/tailscale.md)), with the Tailscale app on the phone.
