#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
# SwiftPM embeds its resource fallback location. Build in an anonymous path so
# this generated literal cannot expose the builder's account or clone location.
BUILD_ROOT="$(mktemp -d /tmp/node-remote-build.XXXXXX)"
trap 'rm -rf "$BUILD_ROOT"' EXIT
cp "$PROJECT_ROOT/Package.swift" "$BUILD_ROOT/Package.swift"
cp -R "$PROJECT_ROOT/Sources" "$BUILD_ROOT/Sources"
swift build --package-path "$BUILD_ROOT" --scratch-path "$BUILD_ROOT/.build" -c release \
  -Xswiftc -file-prefix-map -Xswiftc "$PROJECT_ROOT=." \
  -Xswiftc -file-prefix-map -Xswiftc "$BUILD_ROOT=." \
  -Xswiftc -debug-prefix-map -Xswiftc "$PROJECT_ROOT=." \
  -Xswiftc -debug-prefix-map -Xswiftc "$BUILD_ROOT=." \
  -Xcc "-ffile-prefix-map=$PROJECT_ROOT=." \
  -Xcc "-ffile-prefix-map=$BUILD_ROOT=."
# Assemble and sign outside the project: synced folders (iCloud Drive) tag bundles with
# Finder/File Provider metadata that codesign rejects.
APP="$BUILD_ROOT/Node Remote.app"
DEST="$PROJECT_ROOT/dist/Node Remote.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_ROOT/.build/release/NodeRemote" "$APP/Contents/MacOS/NodeRemote"
cp -R "$BUILD_ROOT/.build/release/NodeRemote_NodeRemote.bundle" "$APP/Contents/Resources/"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
strip -S "$APP/Contents/MacOS/NodeRemote"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NodeRemote</string>
<key>CFBundleIdentifier</key><string>br.local.NodeRemote</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Node Remote</string>
<key>CFBundleDisplayName</key><string>Node Remote</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>Encontrar e controlar sua TV LG ou Samsung na mesma rede Wi-Fi.</string>
<key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
<key>CFBundleLocalizations</key><array><string>pt-BR</string></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
codesign --force --deep --sign - --identifier br.local.NodeRemote "$APP"
mkdir -p "$PROJECT_ROOT/dist"
rm -rf "$DEST"
ditto "$APP" "$DEST"
# The copy in a synced folder gets the same metadata again; it is not part of the signature.
xattr -cr "$DEST" || true
printf 'App created at %s\n' "$DEST"
