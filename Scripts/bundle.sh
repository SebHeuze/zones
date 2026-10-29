#!/usr/bin/env bash
# Assembles a notarisable-shaped Zones.app menu-bar agent from the SwiftPM
# release build and ad-hoc code-signs it so the Accessibility (TCC) grant
# persists across rebuilds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Zones.app"
BIN_NAME="ZonesApp"

# Version metadata. Overridable so Scripts/release.sh can stamp a real release;
# the defaults keep a plain `./Scripts/bundle.sh` working for local dev.
ZONES_VERSION="${ZONES_VERSION:-0.1.0}"
ZONES_BUILD="${ZONES_BUILD:-1}"

# Build a universal (arm64 + x86_64) binary so releases run on both Apple Silicon
# and Intel Macs — macOS 14 still supports 2018-era Intel hardware. Override with
# ZONES_ARCHS="arm64" for a faster single-arch local build.
ZONES_ARCHS="${ZONES_ARCHS:-arm64 x86_64}"
ARCH_FLAGS=()
for arch in $ZONES_ARCHS; do ARCH_FLAGS+=(--arch "$arch"); done

echo "==> Building release binary (version $ZONES_VERSION, build $ZONES_BUILD, archs: $ZONES_ARCHS)"
swift build -c release --package-path "$ROOT" "${ARCH_FLAGS[@]}"
BIN_PATH="$(swift build -c release --package-path "$ROOT" "${ARCH_FLAGS[@]}" --show-bin-path)/$BIN_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/Zones"

echo "==> Installing app icon"
# Resources/AppIcon.icns is committed; regenerate it with Scripts/make-icon.sh.
ICON_SRC="$ROOT/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "!! $ICON_SRC missing — run Scripts/make-icon.sh to generate it." >&2
    exit 1
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Zones</string>
    <key>CFBundleDisplayName</key>
    <string>Zones</string>
    <key>CFBundleIdentifier</key>
    <string>co.uk.vindraper.zones</string>
    <key>CFBundleExecutable</key>
    <string>Zones</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${ZONES_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${ZONES_BUILD}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Prefer the stable self-signed dev identity (see Scripts/create-signing-cert.sh)
# so the Accessibility (TCC) grant survives rebuilds. Fall back to ad-hoc, which
# changes the cdhash every build and forces a re-grant each time.
IDENTITY="${ZONES_SIGN_IDENTITY:-Zones Dev}"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "==> Code-signing with '$IDENTITY'"
    SIGN_ID="$IDENTITY"
else
    echo "==> '$IDENTITY' not found — ad-hoc signing (TCC grant won't persist across rebuilds)"
    echo "    Run Scripts/create-signing-cert.sh once to fix this."
    SIGN_ID="-"
fi

# Sign with the hardened runtime (required for notarisation). There are no
# nested frameworks or helpers, so a single signature on the app is enough and
# no library-validation exception is needed.
echo "==> Signing app"
codesign --force --options runtime --sign "$SIGN_ID" "$APP"

echo "==> Done: $APP"
echo "    Launch with: open \"$APP\""
echo "    First run will prompt for Accessibility permission."
