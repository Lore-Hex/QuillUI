# Reproducible build image for the Signal-iOS → QuillUI Linux port.
# Bakes the apt deps SignalServiceKit + QuillUI's GTK shims + the C shims
# (GRDBSQLite→sqlite3.h, CommonCrypto→openssl/evp.h) need, so builds don't
# depend on a flaky per-run `apt-get` (which intermittently left libsqlite3-dev
# / libssl-dev uninstalled and broke GRDBSQLite / CommonCrypto).
#
# Build once:
#   docker build -t quillui-signal-build -f docker/quillui-signal-build.Dockerfile docker
# Use:
#   docker run --rm -v <worktree>:/qui -v qui-build:/qui/.build quillui-signal-build \
#     bash -c 'cd /qui; QUILLUI_LINUX_BACKEND=gtk swift build --disable-index-store --target SignalServiceKit'
FROM swift:6.2-noble

RUN set -eux; \
    for i in 1 2 3 4 5; do apt-get update && break || sleep 5; done; \
    apt-get install -y --no-install-recommends \
        libgtk-4-dev \
        libgdk-pixbuf-2.0-dev \
        libcairo2-dev \
        libsqlite3-dev \
        libssl-dev \
        pkg-config \
        clang \
        protobuf-compiler \
        cmake \
        git \
        python3 \
        perl \
        ripgrep \
        xvfb \
        dbus-x11 \
        fonts-dejavu-core \
        fonts-noto-color-emoji \
        imagemagick \
        x11-apps \
        ca-certificates; \
    test -f /usr/include/sqlite3.h; \
    test -f /usr/include/openssl/evp.h; \
    rm -rf /var/lib/apt/lists/*
