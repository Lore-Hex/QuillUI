#!/usr/bin/env bash
set -euo pipefail

# Assert macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must be run on macOS."
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/Tests/Fixtures/Enchanted"
FIXTURE_PATH="$FIXTURE_DIR/macos-reference.png"

mkdir -p "$FIXTURE_DIR"

# Launch app in deterministic mode
echo "Launching quill-enchanted in reference mode..."
killall quill-enchanted 2>/dev/null || true

# We use a custom window title to avoid system state restoration of window size
QUILLUI_ENCHANTED_REFERENCE_MODE=1 swift run quill-enchanted > enchanted-capture.log 2>&1 &
APP_PID=$!

# Wait for app to launch and window to appear
echo "Waiting for Enchanted to launch..."
sleep 15

# Find window ID
echo "Finding Enchanted window..."
WINDOW_ID=$(swift - <<EOT
import AppKit
import Quartz

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    exit(1)
}

for window in windowListInfo {
    let ownerName = window[kCGWindowOwnerName as String] as? String ?? "Unknown"
    let windowID = window[kCGWindowNumber as String] as? Int ?? 0
    
    if ownerName == "quill-enchanted" || ownerName == "Enchanted" || ownerName == "Enchanted Reference" {
        print("\(windowID)")
        exit(0)
    }
}
exit(1)
EOT
)

if [[ -z "$WINDOW_ID" ]]; then
  echo "Could not find Enchanted window. Check enchanted-capture.log"
  kill "$APP_PID" 2>/dev/null || true
  exit 1
fi

echo "Found Enchanted window ID: $WINDOW_ID"

# Capture window
# -o to not capture shadow
screencapture -l "$WINDOW_ID" -o "$FIXTURE_PATH"

# Kill the app
kill "$APP_PID" 2>/dev/null || true

# Validate and crop if needed
ACTUAL_WIDTH=$(sips -g pixelWidth "$FIXTURE_PATH" | awk '/pixelWidth/ {print $2}')
ACTUAL_HEIGHT=$(sips -g pixelHeight "$FIXTURE_PATH" | awk '/pixelHeight/ {print $2}')

echo "Captured screenshot: ${ACTUAL_WIDTH}x${ACTUAL_HEIGHT}"

# macOS screencapture -l includes the title bar (28pt = 56px on Retina)
# If we requested 1114x721pt, we get 2228x1554px total if it adds 28pt title bar.
# 1554 - 56 = 1498.
if [[ "$ACTUAL_WIDTH" == "2228" && "$ACTUAL_HEIGHT" == "1554" ]]; then
  echo "Detected title bar. Cropping to 2228x1498..."
  swift - "$FIXTURE_PATH" "$FIXTURE_PATH" 0 56 2228 1498 <<EOT
import AppKit
let args = CommandLine.arguments
let inputPath = args[1]
let outputPath = args[2]
let x = Double(args[3])!, y = Double(args[4])!, w = Double(args[5])!, h = Double(args[6])!
guard let image = NSImage(contentsOfFile: inputPath) else { exit(1) }
var imageRect = NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
guard let cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil) else { exit(1) }
guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else { exit(1) }
let bitmapRep = NSBitmapImageRep(cgImage: cropped)
guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { exit(1) }
try? pngData.write(to: URL(fileURLWithPath: outputPath))
EOT
  ACTUAL_HEIGHT=1498
fi

if [[ "$ACTUAL_WIDTH" != "2228" || "$ACTUAL_HEIGHT" != "1498" ]]; then
  echo "Warning: Screenshot size is ${ACTUAL_WIDTH}x${ACTUAL_HEIGHT}, expected 2228x1498."
fi

# Optimize PNG to get it < 200KB
if command -v pngquant &>/dev/null; then
  echo "Optimizing PNG with pngquant..."
  pngquant --force --ext .png --quality 60-80 "$FIXTURE_PATH"
elif command -v optipng &>/dev/null; then
  echo "Optimizing PNG with optipng..."
  optipng -o2 "$FIXTURE_PATH"
else
  echo "No PNG optimization tools found. Using sips..."
  sips -s format png "$FIXTURE_PATH" --out "$FIXTURE_PATH"
fi

# Final check
FILE_SIZE=$(du -k "$FIXTURE_PATH" | cut -f1)
echo "Final fixture size: ${FILE_SIZE}KB"
if (( FILE_SIZE > 200 )); then
  echo "Warning: Fixture size is ${FILE_SIZE}KB, which is over the 200KB target."
fi

echo "Reference captured to $FIXTURE_PATH"
