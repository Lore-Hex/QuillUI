#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/quillui-linux-backend-smoke-lib.sh"

quillui_install_linux_backend_smoke_packages

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
done < <(quillui_backend_app_products)

APP_SMOKE_ROWS=()
tab="$(printf '\t')"
while IFS="$tab" read -r product backend; do
  [[ -n "$product" ]] || continue
  [[ -n "$backend" ]] || continue
  APP_SMOKE_ROWS+=("$product"$'\t'"$backend")
done < <(quillui_backend_app_matrix)

BACKEND_SMOKE_PRODUCTS=()
while IFS= read -r product; do
  [[ -n "$product" ]] && BACKEND_SMOKE_PRODUCTS+=("$product")
done < <(quillui_backend_smoke_products)

if (( ${#APP_PRODUCTS[@]} == 0 )); then
  echo "No backend app products listed by scripts/quillui-backend-products.sh backend-apps" >&2
  exit 1
fi

if (( ${#APP_SMOKE_ROWS[@]} == 0 )); then
  echo "No backend app smoke rows listed by scripts/quillui-backend-products.sh app-matrix" >&2
  exit 1
fi

if (( ${#BACKEND_SMOKE_PRODUCTS[@]} == 0 )); then
  echo "No backend launch smoke products listed by scripts/quillui-backend-products.sh smoke-products" >&2
  exit 1
fi

ALL_PRODUCTS=("${APP_PRODUCTS[@]}" "${BACKEND_SMOKE_PRODUCTS[@]}")

for product in "${ALL_PRODUCTS[@]}"; do
  swift build --scratch-path .build-linux --product "$product"
done
BIN_PATH="$(swift build --scratch-path .build-linux --show-bin-path)"

SMOKE_SECONDS="${QUILLUI_BACKEND_SMOKE_SECONDS:-${QUILLUI_SMOKE_SECONDS:-6}}"

run_smoke() {
  local product="$1"
  local requested_backend="${2:-}"
  local smoke_label="$product"
  local executable="$BIN_PATH/$product"
  if [[ -z "$executable" ]]; then
    echo "Could not find built executable for $product" >&2
    exit 1
  fi
  if [[ ! -x "$executable" ]]; then
    echo "Built executable is missing or not executable: $executable" >&2
    exit 1
  fi

  local -a app_environment=(GTK_A11Y=none)
  if [[ -z "$requested_backend" ]]; then
    requested_backend="$(quillui_requested_backend_for_product "$product")"
  fi
  if [[ -n "$requested_backend" ]]; then
    smoke_label="$product ($requested_backend requested)"
    app_environment+=(QUILLUI_BACKEND="$requested_backend")
  fi

  set +e
  timeout "${SMOKE_SECONDS}s" xvfb-run -a env "${app_environment[@]}" "$executable"
  local smoke_status=$?
  set -e

  if [[ "$smoke_status" != "124" ]]; then
    echo "$smoke_label backend headless smoke failed with exit code $smoke_status" >&2
    exit "$smoke_status"
  fi
}

for row in "${APP_SMOKE_ROWS[@]}"; do
  IFS="$tab" read -r product backend <<< "$row"
  run_smoke "$product" "$backend"
done

for product in "${BACKEND_SMOKE_PRODUCTS[@]}"; do
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
  timeout "${SMOKE_SECONDS}s" xvfb-run -a env GTK_A11Y=none QUILLUI_BACKEND=gtk "$QUILL_CHAT_EXECUTABLE"
  quill_chat_smoke_status=$?
  set -e

  if [[ "$quill_chat_smoke_status" != "124" ]]; then
    echo "quill-chat-linux backend headless smoke failed with exit code $quill_chat_smoke_status" >&2
    exit "$quill_chat_smoke_status"
  fi
fi

cat <<MSG

Linux backend build completed.
Headless backend smoke completed for ${#APP_SMOKE_ROWS[@]} app/backend rows and ${#BACKEND_SMOKE_PRODUCTS[@]} backend launch fixtures; products stayed running for $SMOKE_SECONDS seconds under Xvfb.
Run an app in a graphical session with:

  swift run ${APP_PRODUCTS[0]}

MSG
