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

scripts/linux-swift-test.sh --scratch-path .build-linux
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

GENERATED_APP_SMOKE_ROWS=()
while IFS="$tab" read -r product backend; do
  [[ -n "$product" ]] || continue
  [[ -n "$backend" ]] || continue
  GENERATED_APP_SMOKE_ROWS+=("$product"$'\t'"$backend")
done < <(quillui_backend_generated_app_matrix)

BACKEND_SMOKE_ROWS=()
BACKEND_SMOKE_PRODUCTS=()
while IFS="$tab" read -r product backend; do
  [[ -n "$product" ]] || continue
  [[ -n "$backend" ]] || continue
  BACKEND_SMOKE_ROWS+=("$product"$'\t'"$backend")
  BACKEND_SMOKE_PRODUCTS+=("$product")
done < <(quillui_backend_smoke_matrix)

if (( ${#APP_PRODUCTS[@]} == 0 )); then
  echo "No backend app products listed by scripts/quillui-backend-products.sh backend-apps" >&2
  exit 1
fi

if (( ${#APP_SMOKE_ROWS[@]} == 0 )); then
  echo "No backend app smoke rows listed by scripts/quillui-backend-products.sh app-matrix" >&2
  exit 1
fi

if (( ${#GENERATED_APP_SMOKE_ROWS[@]} == 0 )); then
  echo "No generated app smoke rows listed by scripts/quillui-backend-products.sh generated-app-matrix" >&2
  exit 1
fi

if (( ${#BACKEND_SMOKE_ROWS[@]} == 0 )); then
  echo "No backend launch smoke rows listed by scripts/quillui-backend-products.sh smoke-matrix" >&2
  exit 1
fi

ALL_BUILD_ROWS=("${APP_SMOKE_ROWS[@]}" "${BACKEND_SMOKE_ROWS[@]}")

for row in "${ALL_BUILD_ROWS[@]}"; do
  IFS="$tab" read -r product build_backend <<< "$row"
  [[ -n "$product" && -n "$build_backend" ]] || continue
  build_backend="$(quillui_validate_requested_backend_for_product "$product" "$build_backend")"
  QUILLUI_LINUX_BACKEND="$build_backend" swift build --scratch-path .build-linux --product "$product"
  quillui_record_backend_product_build "$ROOT_DIR/.build-linux" "$product" "$build_backend"
done

SMOKE_SECONDS="${QUILLUI_BACKEND_SMOKE_SECONDS:-${QUILLUI_SMOKE_SECONDS:-6}}"
generated_app_smoke_count=0

run_executable_smoke() {
  local product="$1"
  local executable="$2"
  local requested_backend="${3:-}"
  local smoke_label="$product"
  local effective_backend="$requested_backend"

  if [[ ! -x "$executable" ]]; then
    echo "Built executable is missing or not executable: $executable" >&2
    exit 1
  fi

  if [[ -z "$effective_backend" ]]; then
    effective_backend="$(quillui_requested_backend_for_product "$product")"
  fi
  if [[ -n "$effective_backend" ]]; then
    smoke_label="$smoke_label ($effective_backend requested)"
  fi
  local -a app_environment=()
  quillui_append_backend_launch_environment app_environment "$product" "" "$effective_backend"

  set +e
  timeout "${SMOKE_SECONDS}s" xvfb-run -a env "${app_environment[@]}" "$executable"
  local smoke_status=$?
  set -e

  if [[ "$smoke_status" != "124" ]]; then
    echo "$smoke_label backend headless smoke failed with exit code $smoke_status" >&2
    exit "$smoke_status"
  fi
}

run_smoke() {
  local product="$1"
  local requested_backend="${2:-}"
  local executable
  local bin_path

  if [[ -z "$requested_backend" ]]; then
    requested_backend="$(quillui_requested_backend_for_product "$product")"
  fi
  requested_backend="$(quillui_validate_requested_backend_for_product "$product" "$requested_backend")"

  QUILLUI_LINUX_BACKEND="$requested_backend" swift build --scratch-path .build-linux --product "$product"
  quillui_record_backend_product_build "$ROOT_DIR/.build-linux" "$product" "$requested_backend"
  bin_path="$(QUILLUI_LINUX_BACKEND="$requested_backend" swift build --scratch-path .build-linux --show-bin-path)"
  executable="$bin_path/$product"

  run_executable_smoke "$product" "$executable" "$requested_backend"
}

for row in "${APP_SMOKE_ROWS[@]}"; do
  IFS="$tab" read -r product backend <<< "$row"
  run_smoke "$product" "$backend"
done

for row in "${BACKEND_SMOKE_ROWS[@]}"; do
  IFS="$tab" read -r product backend <<< "$row"
  run_smoke "$product" "$backend"
done

if [[ "${QUILLUI_SKIP_QUILL_CHAT_BUILD:-0}" != "1" && -d "$QUILL_CHAT_APP_DIR" ]]; then
  for row in "${GENERATED_APP_SMOKE_ROWS[@]}"; do
    IFS="$tab" read -r product backend <<< "$row"
    generated_work_root="$QUILL_CHAT_WORK_ROOT-$backend"

    QUILLUI_QUILL_CHAT_BUILD_WORKDIR="$generated_work_root" \
      QUILLUI_QUILL_CHAT_PRODUCT_NAME="$product" \
      QUILLUI_QUILL_CHAT_BACKEND_FACADE="$backend" \
      scripts/build-quill-chat-linux.sh

    if [[ "$backend" == "qt" ]]; then
      QUILL_CHAT_BIN_DIR="$(QUILLUI_LINUX_BACKEND=qt swift build \
        --package-path "$generated_work_root/package" \
        --scratch-path "$generated_work_root/.build-check" \
        --show-bin-path)"
    else
      QUILL_CHAT_BIN_DIR="$(swift build \
        --package-path "$generated_work_root/package" \
        --scratch-path "$generated_work_root/.build-check" \
        --show-bin-path)"
    fi

    run_executable_smoke "$product" "$QUILL_CHAT_BIN_DIR/$product" "$backend"
    generated_app_smoke_count=$((generated_app_smoke_count + 1))
  done
fi

cat <<MSG

Linux backend build completed.
Headless backend smoke completed for ${#APP_SMOKE_ROWS[@]} app/backend rows, ${#BACKEND_SMOKE_ROWS[@]} backend launch fixture/backend rows, and $generated_app_smoke_count generated app/backend rows; products stayed running for $SMOKE_SECONDS seconds under Xvfb.
Run an app in a graphical session with:

  swift run ${APP_PRODUCTS[0]}

MSG
