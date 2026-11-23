# Linux

## Commands
| Key | Command |
|---|---|
| `build-linux` | `docker build -f docker/linux.Dockerfile --output build/linux-docker .` |
| `pack-linux` | `tar -czf build/bookserver-linux.tar.gz -C build/linux-docker .` |
| `unpack-linux` | `mkdir -p ~/bookserver && tar -xzf bookserver-linux.tar.gz -C ~/bookserver` |
| `runtime-libraries` | `sudo apt install libgtk-3-0 libsecret-1-0 gnome-keyring` |
| `run-linux` | `~/bookserver/bookserver` |

## Deploy
1. On the Mac, start Docker Desktop: Docker is the Linux build machine.
2. Build, in the frontend folder — [`build-linux`](#commands). The first build downloads about 2–3 GB; later ones reuse it. The bundle is `build/linux-docker/`: `bookserver`, `lib/` and `data/`, which stay together. It runs on 64-bit Intel and AMD Linux from Ubuntu 22.04 and Debian 12 on; on an Apple Silicon Mac, add `--platform linux/amd64` for those.
3. Pack it — [`pack-linux`](#commands) — and copy `build/bookserver-linux.tar.gz` to the Linux machine; unpack it there — [`unpack-linux`](#commands).
4. On the Linux machine (Ubuntu or Debian), install what the app needs at run time — [`runtime-libraries`](#commands). The session is kept in the desktop's keyring (GNOME Keyring; on KDE, KWallet's Secret Service): without one, the app works but asks for the login at every start.
5. Start it — [`run-linux`](#commands). Connect it to `http://localhost:8080` when the server runs on that machine; any other server needs its `https://` address: your `tailscale serve` address ([tailscale.md](../../../bookserver_backend/docs/run-deploy/tailscale.md)), with Tailscale on that machine.
