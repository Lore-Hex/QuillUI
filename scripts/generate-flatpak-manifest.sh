#!/usr/bin/env bash
set -euo pipefail

ARTIFACT_DIR="${QUILLUI_FLATPAK_ARTIFACT_DIR:-}"
OUTPUT_PATH="${QUILLUI_FLATPAK_MANIFEST_PATH:-}"
RUNTIME="${QUILLUI_FLATPAK_RUNTIME:-org.gnome.Platform}"
RUNTIME_VERSION="${QUILLUI_FLATPAK_RUNTIME_VERSION:-48}"
SDK="${QUILLUI_FLATPAK_SDK:-org.gnome.Sdk}"
DEFAULT_FINISH_ARGS=1
FINISH_ARGS=()

usage() {
  cat <<MSG
Usage: $(basename "$0") --artifact-dir PATH [--output PATH]

Generates a Flatpak manifest from a package-swiftui-linux-app.sh artifact.

Options:
  --artifact-dir PATH       Packaged app artifact directory.
  --output PATH             Manifest output path. Defaults to ARTIFACT_DIR/metadata/APP_ID.flatpak.json.
  --runtime ID              Flatpak runtime. Defaults to org.gnome.Platform.
  --runtime-version VALUE   Runtime version. Defaults to 48.
  --sdk ID                  Flatpak SDK. Defaults to org.gnome.Sdk.
  --finish-arg ARG          Append a finish-arg.
  --no-default-finish-args  Do not include QuillUI's default desktop/network args.
  -h, --help                Show this help.

Environment aliases:
  QUILLUI_FLATPAK_ARTIFACT_DIR
  QUILLUI_FLATPAK_MANIFEST_PATH
  QUILLUI_FLATPAK_RUNTIME
  QUILLUI_FLATPAK_RUNTIME_VERSION
  QUILLUI_FLATPAK_SDK
MSG
}

metadata_value() {
  local key="$1"
  local file="$2"
  awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir)
      ARTIFACT_DIR="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2
      ;;
    --runtime)
      RUNTIME="${2:-}"
      shift 2
      ;;
    --runtime-version)
      RUNTIME_VERSION="${2:-}"
      shift 2
      ;;
    --sdk)
      SDK="${2:-}"
      shift 2
      ;;
    --finish-arg)
      FINISH_ARGS+=("${2:-}")
      shift 2
      ;;
    --no-default-finish-args)
      DEFAULT_FINISH_ARGS=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

if [[ -z "$ARTIFACT_DIR" ]]; then
  usage >&2
  exit 64
fi

if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "Artifact directory was not found: $ARTIFACT_DIR" >&2
  exit 66
fi

ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
METADATA_FILE="$ARTIFACT_DIR/metadata/quillui-release.env"

if [[ ! -f "$METADATA_FILE" ]]; then
  echo "Packaged app metadata file was not found: $METADATA_FILE" >&2
  exit 66
fi

APP_ID="$(metadata_value app_id "$METADATA_FILE")"
PRODUCT_NAME="$(metadata_value product "$METADATA_FILE")"
DISPLAY_NAME="$(metadata_value display_name "$METADATA_FILE")"
SUMMARY="$(metadata_value summary "$METADATA_FILE")"

if [[ -z "$APP_ID" || -z "$PRODUCT_NAME" ]]; then
  echo "Packaged app metadata must contain app_id and product values." >&2
  exit 65
fi

if [[ ! "$PRODUCT_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Flatpak command product name must be a simple executable name: $PRODUCT_NAME" >&2
  exit 64
fi

for path in \
  "$ARTIFACT_DIR/run" \
  "$ARTIFACT_DIR/bin/$PRODUCT_NAME" \
  "$ARTIFACT_DIR/share/applications/$APP_ID.desktop" \
  "$ARTIFACT_DIR/share/metainfo/$APP_ID.metainfo.xml"
do
  if [[ ! -e "$path" ]]; then
    echo "Packaged app artifact is missing required Flatpak input: $path" >&2
    exit 66
  fi
done

if [[ "$DEFAULT_FINISH_ARGS" == "1" ]]; then
  EXISTING_FINISH_ARGS=()
  if ((${#FINISH_ARGS[@]} > 0)); then
    EXISTING_FINISH_ARGS=("${FINISH_ARGS[@]}")
  fi
  FINISH_ARGS=(
    "--share=ipc"
    "--socket=wayland"
    "--socket=fallback-x11"
    "--device=dri"
    "--share=network"
  )
  if ((${#EXISTING_FINISH_ARGS[@]} > 0)); then
    FINISH_ARGS+=("${EXISTING_FINISH_ARGS[@]}")
  fi
fi

if [[ -z "$OUTPUT_PATH" ]]; then
  OUTPUT_PATH="$ARTIFACT_DIR/metadata/$APP_ID.flatpak.json"
fi
mkdir -p "$(dirname "$OUTPUT_PATH")"

export QUILLUI_FLATPAK_ARTIFACT_ABS="$ARTIFACT_DIR"
export QUILLUI_FLATPAK_OUTPUT_PATH="$OUTPUT_PATH"
export QUILLUI_FLATPAK_APP_ID="$APP_ID"
export QUILLUI_FLATPAK_PRODUCT_NAME="$PRODUCT_NAME"
export QUILLUI_FLATPAK_DISPLAY_NAME="$DISPLAY_NAME"
export QUILLUI_FLATPAK_SUMMARY="$SUMMARY"
export QUILLUI_FLATPAK_RUNTIME_ID="$RUNTIME"
export QUILLUI_FLATPAK_RUNTIME_VERSION_VALUE="$RUNTIME_VERSION"
export QUILLUI_FLATPAK_SDK_ID="$SDK"

PYTHON_ARGS=("-")
if ((${#FINISH_ARGS[@]} > 0)); then
  PYTHON_ARGS+=("${FINISH_ARGS[@]}")
fi

python3 "${PYTHON_ARGS[@]}" <<'PY'
import json
import os
import sys

finish_args = sys.argv[1:]
artifact_dir = os.environ["QUILLUI_FLATPAK_ARTIFACT_ABS"]
output_path = os.environ["QUILLUI_FLATPAK_OUTPUT_PATH"]
app_id = os.environ["QUILLUI_FLATPAK_APP_ID"]
product_name = os.environ["QUILLUI_FLATPAK_PRODUCT_NAME"]
display_name = os.environ.get("QUILLUI_FLATPAK_DISPLAY_NAME") or product_name
summary = os.environ.get("QUILLUI_FLATPAK_SUMMARY") or "Apple Swift app running on Linux through QuillUI."

wrapper = "\n".join([
    f"cat > /app/bin/{product_name} <<'EOF'",
    "#!/bin/sh",
    'exec /app/lib/quillui-app/run "$@"',
    "EOF",
    f"chmod 755 /app/bin/{product_name}",
])

manifest = {
    "app-id": app_id,
    "runtime": os.environ["QUILLUI_FLATPAK_RUNTIME_ID"],
    "runtime-version": os.environ["QUILLUI_FLATPAK_RUNTIME_VERSION_VALUE"],
    "sdk": os.environ["QUILLUI_FLATPAK_SDK_ID"],
    "command": product_name,
    "finish-args": finish_args,
    "modules": [
        {
            "name": product_name,
            "buildsystem": "simple",
            "sources": [
                {
                    "type": "dir",
                    "path": artifact_dir,
                }
            ],
            "build-commands": [
                "mkdir -p /app/lib/quillui-app /app/bin /app/share/applications /app/share/metainfo /app/share/icons",
                "cp -a bin metadata run share /app/lib/quillui-app/",
                "if [ -d lib ]; then cp -a lib /app/lib/quillui-app/; fi",
                f"install -Dm644 share/applications/{app_id}.desktop /app/share/applications/{app_id}.desktop",
                f"install -Dm644 share/metainfo/{app_id}.metainfo.xml /app/share/metainfo/{app_id}.metainfo.xml",
                "if [ -d share/icons ]; then cp -a share/icons/* /app/share/icons/; fi",
                wrapper,
            ],
        }
    ],
    "x-quillui": {
        "artifact-dir": artifact_dir,
        "display-name": display_name,
        "summary": summary,
    },
}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY

printf 'Flatpak manifest written: %s\n' "$OUTPUT_PATH"
