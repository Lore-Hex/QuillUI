#!/usr/bin/env bash
set -euo pipefail

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
swift build --scratch-path .build-linux --product quill-enchanted
swift build --scratch-path .build-linux --product quill-enchanted-upstream-slice
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

run_smoke quill-enchanted
run_smoke quill-enchanted-upstream-slice

cat <<MSG

Linux GTK build completed.
Headless GTK smoke completed; both apps stayed running for $SMOKE_SECONDS seconds under Xvfb.
Run the app in a graphical session with:

  swift run quill-enchanted

MSG
