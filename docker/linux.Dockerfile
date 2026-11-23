# The Linux release build, on any machine with Docker — docs/run-deploy/linux.md.
# The oldest Ubuntu still supported: a Linux binary needs a glibc at least as new as the one it was built with.
FROM ubuntu:22.04 AS build

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
        ca-certificates curl git unzip xz-utils zip \
        clang cmake ninja-build pkg-config \
        libgtk-3-dev liblzma-dev libsecret-1-dev libstdc++-12-dev \
    && rm -rf /var/lib/apt/lists/*

# The same Flutter as every other build of the app: the Stack line in CLAUDE.md.
ARG FLUTTER_VERSION=3.50.0
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:$PATH"
RUN flutter config --no-analytics --no-cli-animations && flutter precache --linux

WORKDIR /app
# The packages first, so a change to the app's code reuses this layer.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build linux --release

# Only the bundle leaves the build: `docker build --output <folder>` writes it there.
FROM scratch
COPY --from=build /app/build/linux/x64/release/bundle /
