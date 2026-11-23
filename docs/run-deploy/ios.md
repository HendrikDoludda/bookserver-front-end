# iOS

## Commands
| Key | Command |
|---|---|
| `devices` | `flutter devices` |
| `run-ios-release` | `flutter run --release -d PASTE_DEVICE_ID` |
| `build-ios-unsigned` | `flutter build ios --release --no-codesign` |

## Deploy
1. On a Mac where Xcode has your personal Apple ID (Xcode → Settings → Accounts): its team, "… (Personal Team)", is the one the project names. Set up Flutter and Xcode there as [local.md](local.md)'s steps 1 and 2 say, and get the app's code.
2. Connect the iPhone by USB and tap "Trust This Computer"; on iOS 16 or newer, turn on Developer Mode (Settings → Privacy & Security → Developer Mode) and let it restart.
3. If an earlier build signed by another team is on the phone, delete it first: the phone keeps one signer per app, and you sign in once more afterwards.
4. Find the phone's id — [`devices`](#commands) — and install a release build — [`run-ios-release`](#commands) with that id. The first time, Xcode registers the phone with your team and makes your certificate. The app stays on the phone after you quit with `q`.
5. The first time, the phone won't open an app from an unknown developer: Settings → General → VPN & Device Management → your Apple ID → Trust.
6. A release build needs the server's `https://` address: connect it to your `tailscale serve` address ([tailscale.md](../../../bookserver_backend/docs/run-deploy/tailscale.md)), with the Tailscale app on the phone.
7. A free team's signature lasts 7 days; then the app won't open until you repeat step 4, which keeps the stored session. A free team signs at most 3 apps per device.
8. An iPad works the same way, with iPadOS 15 or newer.
9. On a Mac without your personal team, a build only shows that the app compiles for a device — [`build-ios-unsigned`](#commands); it can't be installed.
