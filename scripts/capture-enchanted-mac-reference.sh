#!/usr/bin/env bash
set -euo pipefail

# Capture the canonical macOS parity reference from the GENUINE upstream
# Enchanted app (gluonfield / AugustDev "Enchanted by Freysa"), built straight
# from the vendored or local upstream Enchanted.xcodeproj.
#
# IMPORTANT: the reference MUST be the real Mac app, NOT `swift run
# quill-enchanted` (our own QuillUI port). Screenshotting our own port and
# calling it the "reference" makes the parity gate circular and blind to every
# place the port diverges from the real app. See issue #134.

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must be run on macOS (it builds + screenshots the real Enchanted.app)."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/quillui-enchanted-source.sh"

FIXTURE_DIR="$ROOT_DIR/Tests/Fixtures/Enchanted"
FIXTURE_PATH="$FIXTURE_DIR/macos-reference.png"
UPSTREAM_ROOT="$(quillui_resolve_enchanted_checkout_dir "$ROOT_DIR")"
UPSTREAM_PROJ="$UPSTREAM_ROOT/Enchanted.xcodeproj"
DD="${ENCHANTED_DERIVED_DATA:-/tmp/enchanted-mac-reference-dd}"

mkdir -p "$FIXTURE_DIR"

if [[ ! -d "$UPSTREAM_PROJ" ]]; then
  echo "Upstream Enchanted project not found at $UPSTREAM_PROJ — run scripts/fetch-upstream.sh first."
  exit 1
fi

# 1. Build the genuine upstream app (unsigned Debug, macOS).
echo "Building the genuine upstream Enchanted.app (this resolves SPM deps on first run)..."
xcodebuild \
  -project "$UPSTREAM_PROJ" \
  -scheme Enchanted \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build

APP="$DD/Build/Products/Debug/Enchanted.app"
if [[ ! -d "$APP" ]]; then
  echo "Build did not produce $APP"
  exit 1
fi

# 2. Launch it and bring its window on-screen.
#    NOTE: macOS may restore the window onto a different Mission Control Space.
#    `screencapture -l <windowid>` only succeeds once the window is on the
#    CURRENT space and rendered. If this script reports a wallpaper/black grab,
#    click the Enchanted window once (or run from the Space it opens on) and
#    re-run. Clearing saved state helps it open on the current Space.
killall Enchanted 2>/dev/null || true
sleep 1
BID="$(defaults read "$APP/Contents/Info" CFBundleIdentifier 2>/dev/null || echo subj.Enchanted)"
rm -rf "$HOME/Library/Saved Application State/$BID.savedState" 2>/dev/null || true
open "$APP"
echo "Waiting for Enchanted to launch + render the empty-conversation view..."
sleep 12

# 3. Find the main window id (owner name contains "Enchanted", real height).
WINDOW_ID="$(/usr/bin/swift - <<'EOT'
import AppKit
import Quartz
let opt = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
let wl = (CGWindowListCopyWindowInfo(opt, kCGNullWindowID) as? [[String: Any]]) ?? []
for w in wl where (w[kCGWindowOwnerName as String] as? String ?? "").contains("Enchanted") {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    if ((b["Height"] as? Double) ?? 0) > 200 {
        print(w[kCGWindowNumber as String] as? Int ?? 0); break
    }
}
EOT
)"

if [[ -z "$WINDOW_ID" ]]; then
  echo "Could not find a real Enchanted window. Is the app showing its main window?"
  exit 1
fi
echo "Found Enchanted window id: $WINDOW_ID"

# 4. Capture the window's own surface (-l is unoccluded by other windows).
screencapture -l "$WINDOW_ID" -o "$FIXTURE_PATH"

if [[ ! -f "$FIXTURE_PATH" ]]; then
  echo "screencapture produced no file (window likely on another Space — see NOTE above)."
  exit 1
fi

# 5. Report the captured size. Eyeball the PNG to confirm it shows the app
#    (a light UI), not the desktop wallpaper — a wallpaper grab means the
#    window was on another Space (see NOTE above); re-run after focusing it.
echo "Captured $(sips -g pixelWidth -g pixelHeight "$FIXTURE_PATH" 2>/dev/null | awk '/pixel/{print $2}' | paste -sd x -)"

# 6. Keep it committable (<200KB).
if command -v pngquant &>/dev/null; then
  pngquant --force --ext .png --quality 60-85 "$FIXTURE_PATH" || true
fi
echo "Reference captured to $FIXTURE_PATH ($(du -k "$FIXTURE_PATH" | cut -f1)KB)"
echo "Done. This is the GENUINE upstream Enchanted macOS app — use it as the parity ground truth."
