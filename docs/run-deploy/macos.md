# macOS

## Commands
| Key | Command |
|---|---|
| `build-macos` | `flutter build macos --release` |
| `zip-macos` | `ditto -c -k --sequesterRsrc --keepParent build/macos/Build/Products/Release/bookserver.app bookserver-macos.zip` |
| `unquarantine` | `xattr -dr com.apple.quarantine /Applications/bookserver.app` |

## Deploy
1. Build — [`build-macos`](#commands). The app is `build/macos/Build/Products/Release/bookserver.app`; drag it into Applications.
2. The first start of a new build asks for the keychain, where the session is kept: enter your Mac password and click Always Allow.
3. For another Mac, zip it — [`zip-macos`](#commands), which keeps the app's signature intact — copy `bookserver-macos.zip` over, double-click it there and drag `bookserver.app` into Applications.
4. That Mac won't open an app from another computer that isn't signed by a known developer: clear its quarantine there — [`unquarantine`](#commands) — until 73's signing task.
5. A release build takes only the server's `https://` address: connect it to your `tailscale serve` address ([tailscale.md](../../../bookserver_backend/docs/run-deploy/tailscale.md)), with Tailscale on that Mac.
