#!/bin/bash
# Builds the SwiftUI desktop widget into a self-contained .app bundle using only
# the Command Line Tools (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Claude 用量"
BUNDLE_ID="com.local.claude-usage-widget"
EXEC_NAME="ClaudeUsage"
VERSION="1.0.0"

BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
RES_DIR="$APP/Contents/Resources"

echo "→ cleaning"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "→ compiling Swift sources"
swiftc -swift-version 5 -O \
    -target arm64-apple-macos13.0 \
    Sources/*.swift \
    -o "$MACOS_DIR/$EXEC_NAME"

echo "→ writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP/Contents/PkgInfo"

echo "→ code signing"
SIGN_KC="$HOME/Library/Keychains/afterglow-codesign.keychain-db"
SIGN_ID="Afterglow Local Signing"
if security find-certificate -c "$SIGN_ID" "$SIGN_KC" >/dev/null 2>&1; then
    security unlock-keychain -p "afterglow-signing" "$SIGN_KC" 2>/dev/null || true
    if codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KC" "$APP" 2>/dev/null; then
        echo "  signed with stable identity: $SIGN_ID (keychain grant will persist across rebuilds)"
    else
        echo "  stable signing failed → ad-hoc"; codesign --force --sign - "$APP" 2>/dev/null || true
    fi
else
    echo "  no stable identity yet — run ./setup-signing.sh once to avoid repeat keychain prompts; using ad-hoc"
    codesign --force --sign - "$APP" 2>/dev/null || true
fi

echo "✓ built: $APP"
