#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_NAME="${QUILLCHATKIT_IOS_SDK:-iphonesimulator}"
TARGET_TRIPLE="${QUILLCHATKIT_IOS_TARGET_TRIPLE:-arm64-apple-ios14.0-simulator}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "check-quillchatkit-ios.sh requires Xcode's xcrun and the iPhoneSimulator SDK." >&2
  exit 69
fi

SDK_PATH="$(xcrun --sdk "$SDK_NAME" --show-sdk-path)"

cd "$ROOT_DIR"
swift build \
  --disable-automatic-resolution \
  --sdk "$SDK_PATH" \
  --target QuillChatKit \
  -Xswiftc -target \
  -Xswiftc "$TARGET_TRIPLE"
