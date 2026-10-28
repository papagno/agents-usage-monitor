#!/bin/zsh
# Builds a release binary and wraps it in FuelGauge.app. Pass --install to copy it to
# /Applications and launch it.
#
# Optional environment:
#   VERSION        marketing version, e.g. 0.1.0 (default 0.0.0 for local builds)
#   BUILD_NUMBER   build number (default: the number of commits)
#   SIGN_IDENTITY  codesigning identity (default "-", ad-hoc); anything else also enables
#                  the hardened runtime and a secure timestamp, which notarization requires
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
BUNDLE_ID="com.effectivebits.FuelGauge"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/FuelGauge.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/FuelGauge" "$APP/Contents/MacOS/FuelGauge"
# ditto keeps the framework's symlinks, which codesign requires.
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Fuel Gauge</string>
    <key>CFBundleDisplayName</key><string>Fuel Gauge</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>FuelGauge</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Francesco Papagno. GPL-3.0-or-later.</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://github.com/papagno/fuel-gauge/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key><string>lRKgp01JFmEEcfpbuSnPS8ARl4BVn+VB8H1k1UAM018=</string>
</dict>
</plist>
PLIST

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGN=(codesign --force --sign -)
else
    SIGN=(codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY")
fi
# Sparkle's helpers are signed inside out, then the framework, then the app
# (https://sparkle-project.org/documentation/sandboxing/#code-signing).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP"
echo "Built $APP ($VERSION, build $BUILD_NUMBER)"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
    rm -rf "/Applications/FuelGauge.app"
    cp -R "$APP" /Applications/
    open "/Applications/FuelGauge.app"
    echo "Installed and launched /Applications/FuelGauge.app"
fi
