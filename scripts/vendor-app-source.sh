#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
DRY_RUN=0
APP_NAME=""
SOURCE_DIR=""

usage() {
  cat <<'USAGE'
Usage: scripts/vendor-app-source.sh [OPTIONS] APP [SOURCE_DIR]

Copy an upstream app checkout into vendor/apps/APP so local and CI builds can
use pinned source without cloning on every run.

When SOURCE_DIR is omitted, the script reads from .upstream/APP.

Options:
  --source PATH, --from PATH
                        Source checkout to copy. Equivalent to SOURCE_DIR.
  --dry-run             Print the copy that would be performed.
  -h, --help            Show this help.

Environment:
  QUILLUI_VENDOR_FORCE=1
                        Re-copy source even when the clean checkout
                        fingerprint matches the already-vendored tree.
USAGE
}

fail_usage() {
  echo "$1" >&2
  echo >&2
  usage >&2
  exit 64
}

validate_app_name() {
  local name="$1"

  if [[ ! "$name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    fail_usage "APP must be a simple vendored app source name, got: $name"
  fi
}

truthy_flag() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

git_source_identity() {
  local source="$1"
  local commit
  local source_root
  local status
  local top_level

  command -v git >/dev/null 2>&1 || return 1
  git -C "$source" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  top_level="$(git -C "$source" rev-parse --show-toplevel 2>/dev/null || true)"
  source_root="$(cd "$source" >/dev/null && pwd)"
  [[ "$top_level" == "$source_root" ]] || return 1
  status="$(git -C "$source" status --porcelain --untracked-files=no 2>/dev/null || true)"
  [[ -z "$status" ]] || return 1
  commit="$(git -C "$source" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$commit" ]] || return 1

  printf 'git:%s' "$commit"
}

content_source_identity() {
  local source="$1"

  python3 - "$source" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
excluded_dirs = {
    ".artifacts",
    ".git",
    ".qa",
    ".build",
    ".swiftpm",
    "DerivedData",
    "node_modules",
    "test-results",
    "xcuserdata",
}
excluded_files = {".DS_Store", ".quillui-vendor-source-fingerprint"}
digest = hashlib.sha256()
digest.update(b"quillui-app-source-tree/v1\0")

for path in sorted(root.rglob("*")):
    try:
        relative = path.relative_to(root)
    except ValueError:
        continue
    if any(part in excluded_dirs or part.startswith(".build-") for part in relative.parts):
        continue
    if not path.is_file() or path.name in excluded_files:
        continue
    data = path.read_bytes()
    digest.update(str(relative).encode("utf-8"))
    digest.update(b"\0")
    digest.update(str(len(data)).encode("utf-8"))
    digest.update(b":")
    digest.update(data)
    digest.update(b"\0")

print("tree:" + digest.hexdigest())
PY
}

vendored_app_source_metadata() {
  local app_name="$1"
  local source="$2"
  shift 2

  local source_identity
  source_identity="$(git_source_identity "$source" || content_source_identity "$source")" || return 1

  printf 'quillui-app-source-vendor/v1\n'
  printf 'app=%s\n' "$app_name"
  printf 'source=%s\n' "$source_identity"
  for exclude in "$@"; do
    printf 'exclude=%s\n' "$exclude"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source|--from)
      [[ $# -ge 2 ]] || fail_usage "$1 requires a path."
      SOURCE_DIR="$2"
      shift 2
      ;;
    --source=*|--from=*)
      SOURCE_DIR="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail_usage "Unsupported option: $1"
      ;;
    *)
      if [[ -z "$APP_NAME" ]]; then
        APP_NAME="$1"
      elif [[ -z "$SOURCE_DIR" ]]; then
        SOURCE_DIR="$1"
      else
        fail_usage "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$APP_NAME" ]] || fail_usage "APP is required."
validate_app_name "$APP_NAME"

if [[ -z "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$ROOT_DIR/.upstream/$APP_NAME"
fi

case "$SOURCE_DIR" in
  /*) ;;
  *) SOURCE_DIR="$ROOT_DIR/$SOURCE_DIR" ;;
esac

if [[ ! -d "$SOURCE_DIR" ]]; then
  cat >&2 <<MSG
Upstream app source was not found at:
  $SOURCE_DIR

Run scripts/fetch-upstream.sh $APP_NAME, pass an explicit SOURCE_DIR, or add
the checkout manually before vendoring it.
MSG
  exit 66
fi

DEST_DIR="$ROOT_DIR/vendor/apps/$APP_NAME"
METADATA_FILE="$DEST_DIR/.quillui-vendor-source-fingerprint"
PRESERVED_VENDOR_NOTE=""
if [[ "$(cd "$SOURCE_DIR" >/dev/null && pwd)" == "$DEST_DIR" ]]; then
  echo "Source is already the vendored app directory: vendor/apps/$APP_NAME" >&2
  exit 65
fi

RSYNC_EXCLUDES=(
  --exclude '.artifacts'
  --exclude '.git'
  --exclude '.qa'
  --exclude '.build'
  --exclude '.build-*'
  --exclude '.swiftpm'
  --exclude 'DerivedData'
  --exclude 'node_modules'
  --exclude 'test-results'
  --exclude 'xcuserdata'
  --exclude '.DS_Store'
)

remote_url=""
commit_sha=""
if git_identity="$(git_source_identity "$SOURCE_DIR")"; then
  remote_url="$(git -C "$SOURCE_DIR" config --get remote.origin.url 2>/dev/null || true)"
  commit_sha="${git_identity#git:}"
fi

if [[ "$DRY_RUN" == "1" ]]; then
  echo "would vendor $APP_NAME source from $SOURCE_DIR to vendor/apps/$APP_NAME"
  exit 0
fi

metadata=""
if metadata="$(vendored_app_source_metadata "$APP_NAME" "$SOURCE_DIR" "${RSYNC_EXCLUDES[@]}")"; then
  if ! truthy_flag "${QUILLUI_VENDOR_FORCE:-0}" \
    && [[ -d "$DEST_DIR" ]] \
    && [[ -f "$METADATA_FILE" ]] \
    && [[ "$(cat "$METADATA_FILE")" == "$metadata" ]]; then
    echo "already vendored $APP_NAME source -> vendor/apps/$APP_NAME"
    exit 0
  fi
fi

if [[ -f "$DEST_DIR/QUILLUI_VENDOR.md" ]]; then
  PRESERVED_VENDOR_NOTE="$(mktemp "${TMPDIR:-/tmp}/quillui-vendor-note.XXXXXX")"
  cp "$DEST_DIR/QUILLUI_VENDOR.md" "$PRESERVED_VENDOR_NOTE"
fi

mkdir -p "$ROOT_DIR/vendor/apps"
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --delete-excluded \
    "${RSYNC_EXCLUDES[@]}" \
    "$SOURCE_DIR/" "$DEST_DIR/"
else
  rm -rf "$DEST_DIR"
  mkdir -p "$DEST_DIR"
  cp -a "$SOURCE_DIR"/. "$DEST_DIR"/
  find "$DEST_DIR" \
    \( -name .artifacts -o -name .git -o -name .qa -o -name .build -o -name '.build-*' -o -name .swiftpm -o -name DerivedData -o -name node_modules -o -name test-results -o -name xcuserdata -o -name .DS_Store \) \
    -prune -exec rm -rf {} +
fi

if [[ -n "$PRESERVED_VENDOR_NOTE" ]]; then
  cp "$PRESERVED_VENDOR_NOTE" "$DEST_DIR/QUILLUI_VENDOR.md"
  rm -f "$PRESERVED_VENDOR_NOTE"
else
  cat > "$DEST_DIR/QUILLUI_VENDOR.md" <<EOF
# Vendored $APP_NAME Source

- Upstream: ${remote_url:-unknown}
- Commit: ${commit_sha:-unknown}

QuillUI vendors this upstream app source tree so generic compatibility
lowering and Linux build tooling can run without cloning the app on every CI or
local build. Keep the app source pristine; compatibility work belongs in
QuillUI, QuillKit, QuillData, or reusable lowering and package-generation
tooling.
EOF
fi

if [[ -n "$metadata" ]]; then
  printf '%s\n' "$metadata" > "$METADATA_FILE"
fi

echo "vendored $APP_NAME source -> vendor/apps/$APP_NAME"
