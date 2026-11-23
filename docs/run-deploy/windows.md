# Windows

## Commands
| Key | Command |
|---|---|
| `flutter-sdk` | `git clone https://github.com/flutter/flutter.git -b 3.50.0 C:\src\flutter` |
| `developer-mode` | `start ms-settings:developers` |
| `doctor` | `flutter doctor` |
| `clone` | `git clone PASTE_REPOSITORY_URL bookserver-front-end` |
| `build-windows` | `flutter build windows --release` |
| `run-windows` | `.\build\windows\x64\runner\Release\bookserver.exe` |
| `zip-windows` | `Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath bookserver-windows.zip` |

The commands run in PowerShell, on the Windows PC.

## Deploy
1. Install Git for Windows, and Visual Studio 2022 (Community is enough) with the workload "Desktop development with C++".
2. Install Flutter — [`flutter-sdk`](#commands) — and add `C:\src\flutter\bin` to your Path (Settings → System → About → Advanced system settings → Environment Variables); then open a new PowerShell.
3. Turn on Developer Mode, which Flutter needs to link the app's plugins — [`developer-mode`](#commands).
4. Check that "Windows Version" and "Visual Studio" show ✓ — [`doctor`](#commands). Android and Chrome may show ✗; this build doesn't need them.
5. Get the app — [`clone`](#commands), with the frontend repository's address from GitHub — and `cd bookserver-front-end`.
6. Build — [`build-windows`](#commands). The app is the folder `build\windows\x64\runner\Release`: `bookserver.exe`, its DLLs and its `data` folder, which stay together.
7. Start it — [`run-windows`](#commands). Connect it to `http://localhost:8080` when the server runs on the PC; any other server needs its `https://` address: your `tailscale serve` address ([tailscale.md](../../../bookserver_backend/docs/run-deploy/tailscale.md)), with Tailscale on the PC.
8. For another PC, zip the folder — [`zip-windows`](#commands). That PC may also need Microsoft's Visual C++ Redistributable (x64).
