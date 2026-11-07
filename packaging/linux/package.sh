#!/usr/bin/env bash
# SPDX-FileCopyrightText: Copyright 2026 Eden Mali Project
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Package a built Eden (Eden Mali) tree into a relocatable tar.xz for Linux.
# The tarball bundles the binary, the Qt6 runtime libraries and the Qt plugins
# it needs, so it can run on any distro that provides the remaining system
# libraries (FFmpeg, Vulkan, X11/Wayland, glibc).
#
# Usage: packaging/linux/package.sh
# Env:   BUILD_DIR (default: <repo>/build)
#        DIST_DIR  (default: <repo>/artifacts)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD="${BUILD_DIR:-$ROOT/build}"
DIST="${DIST_DIR:-$ROOT/artifacts}"
ARCH="$(uname -m)"

VERSION="$(git -C "$ROOT" describe --tags --always 2>/dev/null || echo dev)"
VERSION="$(echo "$VERSION" | sed 's/^v//')"
PKG="EdenMali-${VERSION}-linux-${ARCH}"
OUT="$DIST/$PKG"

echo ">> Packaging $PKG"

rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib" "$OUT/plugins" "$OUT/share/applications"

# --- binaries -------------------------------------------------------------
for exe in eden eden-cli; do
    if [ -x "$BUILD/bin/$exe" ]; then
        install -m 0755 "$BUILD/bin/$exe" "$OUT/bin/$exe"
    else
        echo "warning: $BUILD/bin/$exe not found, skipping"
    fi
done

if [ ! -x "$OUT/bin/eden" ]; then
    echo "error: eden binary was not built" >&2
    exit 1
fi

# --- Qt6 runtime ----------------------------------------------------------
qtpaths_bin="$(command -v qtpaths6 || command -v qtpaths || true)"
if [ -z "$qtpaths_bin" ]; then
    echo "error: qtpaths6 not found, install qt6-base-dev" >&2
    exit 1
fi

QT_LIBS="$("$qtpaths_bin" --query QT_INSTALL_LIBS)"
QT_PLUGINS="$("$qtpaths_bin" --query QT_INSTALL_PLUGINS)"

cp -a "$QT_LIBS"/libQt6*.so* "$OUT/lib/" 2>/dev/null || true

for plugin_dir in \
    platforms \
    platforminputcontexts \
    platformthemes \
    xcbglintegrations \
    egldeviceintegrations \
    wayland-shell-integration \
    wayland-decoration-client \
    wayland-graphics-integration-client \
    imageformats \
    iconengines \
    networkinformation \
    tls; do
    if [ -d "$QT_PLUGINS/$plugin_dir" ]; then
        cp -a "$QT_PLUGINS/$plugin_dir" "$OUT/plugins/"
    fi
done

# --- desktop entry and launcher ------------------------------------------
if [ -f "$ROOT/dist/dev.eden_emu.eden.svg" ]; then
    install -m 0644 "$ROOT/dist/dev.eden_emu.eden.svg" "$OUT/share/"
fi
if [ -f "$ROOT/dist/dev.eden_emu.eden.desktop" ]; then
    sed -e 's|^Exec=.*|Exec=eden-mali %f|' \
        -e 's|^TryExec=.*|TryExec=eden-mali|' \
        "$ROOT/dist/dev.eden_emu.eden.desktop" > "$OUT/share/applications/eden-mali.desktop"
fi

cat > "$OUT/bin/eden-mali" <<'LAUNCHER'
#!/bin/sh
# Wrapper that points Eden Mali at the bundled Qt runtime.
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QT_PLUGIN_PATH="$HERE/../plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$HERE/../plugins/platforms"
exec "$HERE/eden" "$@"
LAUNCHER
chmod 0755 "$OUT/bin/eden-mali"

# --- rpath ---------------------------------------------------------------
for bin in "$OUT"/bin/eden "$OUT"/bin/eden-cli; do
    [ -f "$bin" ] || continue
    patchelf --set-rpath '$ORIGIN/../lib' "$bin"
done

# --- docs ----------------------------------------------------------------
for doc in LICENSE.txt README.md; do
    [ -f "$ROOT/$doc" ] && install -m 0644 "$ROOT/$doc" "$OUT/"
done

# --- archive -------------------------------------------------------------
mkdir -p "$DIST"
tar -C "$DIST" -cJf "$DIST/$PKG.tar.xz" "$PKG"
sha256sum "$DIST/$PKG.tar.xz" > "$DIST/$PKG.tar.xz.sha256"

echo ">> Created $DIST/$PKG.tar.xz"
du -h "$DIST/$PKG.tar.xz"
