# GitHub

## Deploy
1. Push the commit the downloads should be built from to `main`.
2. On GitHub, open the repository's Actions tab → *Desktop builds* → *Run workflow* on `main`. It runs CI and builds macOS, Windows and Linux.
3. When every job is green, the `desktop-builds` pre-release holds the three new files and the README's download links serve them. A failed job leaves the previous files in place.
