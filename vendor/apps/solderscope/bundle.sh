#!/bin/bash
set -e

# Build the executable
echo "Building SolderScope..."
swift build -c release

# Set up paths
APP_NAME="SolderScope"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean and create bundle structure
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
cp "SolderScope/Metadata/Info.plist" "$CONTENTS_DIR/"

# Copy entitlements if they exist
if [ -f "SolderScope/Metadata/SolderScope.entitlements" ]; then
    cp "SolderScope/Metadata/SolderScope.entitlements" "$CONTENTS_DIR/"
fi

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Copy icon if it exists
if [ -f "SolderScope/Metadata/AppIcon.icns" ]; then
    cp "SolderScope/Metadata/AppIcon.icns" "$RESOURCES_DIR/"
fi

echo "Bundle created at: $BUNDLE_DIR"

# Create DMG
echo ""
echo "Creating DMG..."

DMG_NAME="$APP_NAME-v0.1.0"
DMG_DIR="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"

# Clean up any previous DMG artifacts
rm -rf "$DMG_DIR"
rm -f "$DMG_PATH"

# Create DMG staging directory
mkdir -p "$DMG_DIR"
cp -r "$BUNDLE_DIR" "$DMG_DIR/"

# Create Applications symlink
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG using hdiutil
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

# Clean up staging directory
rm -rf "$DMG_DIR"

echo ""
echo "DMG created at: $DMG_PATH"
echo ""
echo "To install:"
echo "  1. Open the DMG: open \"$DMG_PATH\""
echo "  2. Drag SolderScope to Applications"
echo ""
echo "Or install directly:"
echo "  cp -r \"$BUNDLE_DIR\" /Applications/"
