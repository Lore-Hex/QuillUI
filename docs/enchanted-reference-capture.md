# Enchanted macOS Reference Capture

This document describes how to regenerate the canonical macOS reference screenshot for the Enchanted app. This reference is used by the visual verifier to ensure Linux backends (GTK/Qt) maintain parity with the macOS appearance.

## Acceptance Criteria for Reference
- **Size**: Exactly 2228x1498 pixels.
- **DPI**: 144 DPI (Retina 2x).
- **Mode**: Captured with `QUILLUI_ENCHANTED_REFERENCE_MODE=1` to ensure deterministic content (e.g., specific prompt cards, fixed model).
- **Content**: Empty state of Enchanted with no active conversation.

## Regeneration Procedure

1. **Host**: Must be run on a macOS machine with a Retina display.
2. **Command**: Run the following script from the repo root:
   ```bash
   ./scripts/capture-enchanted-mac-reference.sh
   ```
3. **What it does**:
   - Launches `quill-enchanted` with the `QUILLUI_ENCHANTED_REFERENCE_MODE=1` environment variable.
   - The app automatically resizes its window to the reference size (1114x749 points).
   - The script finds the window ID and uses `screencapture -l` to capture it.
   - It then crops the macOS title bar (56 pixels) to get the final 2228x1498 content.
   - It optimizes the PNG to keep it under 200KB.

## Troubleshooting

### Window not found
If the script fails to find the window, ensure that no other instances of `quill-enchanted` are running and that the app has finished launching. The script waits 15 seconds by default.

### Incorrect size
If the captured size is not 2228x1498, it might be because:
- You are not on a Retina display (you'll get 1x pixels).
- The macOS title bar height is different on your system.
- The window size restoration feature of macOS interfered (the script tries to avoid this by using a different window title "Enchanted Reference" in reference mode).

### Determinism
The `QUILLUI_ENCHANTED_REFERENCE_MODE=1` flag is critical. It forces the app into a state where:
- The prompt cards are fixed and not shuffled.
- The model list is deterministic.
- Any other random or environment-dependent UI elements are pinned.

## Verifying the Reference
You can run the verifier locally (requires ImageMagick) to check the reference:
```bash
./scripts/verify-backend-screenshot.py Tests/Fixtures/Enchanted/macos-reference.png quill-enchanted-mac-reference
```
