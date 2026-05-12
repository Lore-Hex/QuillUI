#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

install_packages() {
  if [[ "${QUILLUI_SKIP_APT:-0}" == "1" ]]; then
    return
  fi

  local packages=(
    clang
    git
    libgtk-4-dev
    libsqlite3-dev
    pkg-config
    xvfb
  )
  local missing=()

  for package in "${packages[@]}"; do
    if ! dpkg -s "$package" >/dev/null 2>&1; then
      missing+=("$package")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    sudo apt-get update
    sudo apt-get install -y "${missing[@]}"
  fi
}

install_packages

if ! command -v swift >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Swift is not installed in this Linux environment.
Install Swift with Swiftly first:

  curl -O "https://download.swift.org/swiftly/linux/swiftly-1.1.1-$(uname -m).tar.gz"
  tar -zxf "swiftly-1.1.1-$(uname -m).tar.gz"
  ./swiftly init

Then open a new shell or source Swiftly's env file and re-run this script.
MSG
  exit 1
fi

scripts/patch-swiftopenui-gtk-css.sh .build-linux

swift test --scratch-path .build-linux
scripts/generated-enchanted-core-check.sh
scripts/generated-enchanted-chat-components-check.sh
scripts/generated-enchanted-macos-chat-check.sh
scripts/generated-enchanted-full-source-check.sh

QUILL_CHAT_APP_DIR="${QUILL_CHAT_DIR:-$ROOT_DIR/../quill/clients/quill-chat}/Enchanted"
QUILL_CHAT_WORK_ROOT="${QUILLUI_QUILL_CHAT_BUILD_WORKDIR:-$ROOT_DIR/.build/quill-chat-linux}"
if [[ "${QUILLUI_SKIP_QUILL_CHAT_BUILD:-0}" != "1" && -d "$QUILL_CHAT_APP_DIR" ]]; then
  QUILLUI_QUILL_CHAT_BUILD_WORKDIR="$QUILL_CHAT_WORK_ROOT" scripts/build-quill-chat-linux.sh
elif [[ "${QUILLUI_SKIP_QUILL_CHAT_BUILD:-0}" != "1" ]]; then
  echo "Skipping local Quill Chat Linux app build; source not found at $QUILL_CHAT_APP_DIR"
fi

APP_PRODUCTS=()
while IFS= read -r product; do
  [[ -n "$product" ]] && APP_PRODUCTS+=("$product")
done < <(scripts/linux-gtk-app-products.sh)

if (( ${#APP_PRODUCTS[@]} == 0 )); then
  echo "No GTK app products listed by scripts/linux-gtk-app-products.sh" >&2
  exit 1
fi

for product in "${APP_PRODUCTS[@]}"; do
  swift build --scratch-path .build-linux --product "$product"
done
BIN_PATH="$(swift build --scratch-path .build-linux --show-bin-path)"

SMOKE_SECONDS="${QUILLUI_SMOKE_SECONDS:-6}"

run_smoke() {
  local product="$1"
  local executable="$BIN_PATH/$product"
  if [[ -z "$executable" ]]; then
    echo "Could not find built executable for $product" >&2
    exit 1
  fi
  if [[ ! -x "$executable" ]]; then
    echo "Built executable is missing or not executable: $executable" >&2
    exit 1
  fi

  set +e
  GTK_A11Y=none timeout "${SMOKE_SECONDS}s" xvfb-run -a "$executable"
  local smoke_status=$?
  set -e

  if [[ "$smoke_status" != "124" ]]; then
    echo "$product GTK headless smoke failed with exit code $smoke_status" >&2
    exit "$smoke_status"
  fi
}

for product in "${APP_PRODUCTS[@]}"; do
  run_smoke "$product"
done

if [[ "${QUILLUI_SKIP_QUILL_CHAT_BUILD:-0}" != "1" && -d "$QUILL_CHAT_APP_DIR" ]]; then
  QUILL_CHAT_BIN_DIR="$(swift build \
    --package-path "$QUILL_CHAT_WORK_ROOT/package" \
    --scratch-path "$QUILL_CHAT_WORK_ROOT/.build-check" \
    --show-bin-path)"
  QUILL_CHAT_EXECUTABLE="$QUILL_CHAT_BIN_DIR/quill-chat-linux"
  if [[ ! -x "$QUILL_CHAT_EXECUTABLE" ]]; then
    echo "Built Quill Chat executable is missing or not executable: $QUILL_CHAT_EXECUTABLE" >&2
    exit 1
  fi

  set +e
  GTK_A11Y=none timeout "${SMOKE_SECONDS}s" xvfb-run -a "$QUILL_CHAT_EXECUTABLE"
  quill_chat_smoke_status=$?
  set -e

  if [[ "$quill_chat_smoke_status" != "124" ]]; then
    echo "quill-chat-linux GTK headless smoke failed with exit code $quill_chat_smoke_status" >&2
    exit "$quill_chat_smoke_status"
  fi
fi

cat <<MSG

Linux GTK build completed.
Headless GTK smoke completed for ${#APP_PRODUCTS[@]} app products; GTK apps stayed running for $SMOKE_SECONDS seconds under Xvfb.
Run an app in a graphical session with:

  swift run ${APP_PRODUCTS[0]}

MSG
