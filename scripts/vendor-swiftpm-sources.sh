#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null && pwd)"
source "$ROOT_DIR/scripts/quillui-vendored-source.sh"
SCRATCH_PATH="$ROOT_DIR/.build"
RESOLVE=1
DRY_RUN=0
SLIM=1
HYDRATE_MISSING=0
CHECK_VENDORED=0
ALLOW_UNKNOWN_PACKAGE_RESOLVED_PINS=0
PACKAGES=()
PACKAGE_RESOLVED_FILES=()
APP_NAMES=()

usage() {
  cat <<'USAGE'
Usage: scripts/vendor-swiftpm-sources.sh [OPTIONS] [PACKAGE...]

Copy selected SwiftPM checkout sources into third_party/ so Package.swift can
use path dependencies instead of repeatedly creating remote working copies.

Default package set: OpenCombine, GRDB.swift, swift-syntax, swift-crypto,
swift-asn1, swift-protobuf, SwiftSoup

Options:
  --all                  Vendor every known SwiftPM package when its checkout exists.
  --app NAME             Add Package.resolved files discovered under a vendored or
                         upstream app checkout resolved by scripts/quillui-vendored-source.sh.
  --package-resolved PATH
                         Add packages pinned by an Xcode/SwiftPM Package.resolved.
                         Repeatable. The script vendors matching existing checkouts
                         or reports already-vendored packages.
                         Known dev-only pins are skipped by default. Set
                         QUILLUI_VENDOR_INCLUDE_DEV_PACKAGES=1 to include them.
  --scratch-path PATH    SwiftPM scratch path whose checkouts/ directory is used.
                         Defaults to .build.
  --no-resolve           Do not run swift package resolve before copying.
  --hydrate-missing      Clone missing Package.resolved pins at their exact
                         revisions into scratch checkouts before copying.
  --check-vendored       Only verify that selected packages already exist under
                         third_party/ with Package.swift files.
  --full                 Copy full checkouts instead of the default slim source copy.
  --dry-run              Print the copies that would be performed.
  --list                 Print known package names.
  -h, --help             Show this help.

Environment:
  QUILLUI_VENDOR_FORCE=1  Re-copy sources even when the clean checkout
                          fingerprint matches the already-vendored tree.
USAGE
}

known_packages() {
  cat <<'PACKAGES'
OpenCombine
GRDB.swift
swift-syntax
swift-crypto
swift-asn1
swift-protobuf
SwiftSoup
ActivityIndicatorView
Alamofire
AsyncAlgorithms
KeyboardShortcuts
Magnet
MarkdownUI
NetworkImage
OllamaKit
Sauce
Sparkle
Splash
SwiftCMark
SwiftLintPlugin
SwiftSnapshotTesting
SwiftUIIntrospect
Vortex
WrappingHStack
JavaScriptKit
trusted-router-swift
AboutWindow
AnyCodable
CodeEditKit
CodeEditLanguages
CodeEditSourceEditor
CodeEditSymbols
CodeEditTextView
CollectionConcurrencyKit
ConcurrencyPlus
FSEventsWrapper
JSONRPC
LanguageClient
LanguageServerProtocol
LogStream
ProcessEnv
Queue
Rearrange
Semaphore
SwiftTerm
SwiftTreeSitter
TextFormation
TextStory
WelcomeWindow
ZIPFoundation
swift-collections
swift-glob
tree-sitter
PACKAGES
}

default_packages() {
  cat <<'PACKAGES'
OpenCombine
GRDB.swift
swift-syntax
swift-crypto
swift-asn1
swift-protobuf
SwiftSoup
PACKAGES
}

fail_usage() {
  echo "$1" >&2
  echo >&2
  usage >&2
  exit 64
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
  local status

  command -v git >/dev/null 2>&1 || return 1
  git -C "$source" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  status="$(git -C "$source" status --porcelain --untracked-files=no 2>/dev/null || true)"
  [[ -z "$status" ]] || return 1
  commit="$(git -C "$source" rev-parse HEAD 2>/dev/null || true)"
  [[ -n "$commit" ]] || return 1

  printf 'git:%s' "$commit"
}

vendored_source_metadata() {
  local package="$1"
  local source="$2"
  local slim="$3"
  shift 3

  local source_identity
  source_identity="$(git_source_identity "$source")" || return 1

  printf 'quillui-swiftpm-vendor/v1\n'
  printf 'package=%s\n' "$package"
  printf 'slim=%s\n' "$slim"
  printf 'source=%s\n' "$source_identity"
  for exclude in "$@"; do
    printf 'exclude=%s\n' "$exclude"
  done
}

add_package() {
  local package="$1"
  local existing

  [[ -n "$package" ]] || return 0
  if [[ ${#PACKAGES[@]} -gt 0 ]]; then
    for existing in "${PACKAGES[@]}"; do
      [[ "$existing" != "$package" ]] || return 0
    done
  fi
  PACKAGES+=("$package")
}

add_package_resolved_file() {
  local resolved_file="$1"
  local existing

  [[ -n "$resolved_file" ]] || return 0
  if [[ ${#PACKAGE_RESOLVED_FILES[@]} -gt 0 ]]; then
    for existing in "${PACKAGE_RESOLVED_FILES[@]}"; do
      [[ "$existing" != "$resolved_file" ]] || return 0
    done
  fi
  PACKAGE_RESOLVED_FILES+=("$resolved_file")
}

validate_app_name() {
  local app_name="$1"

  if [[ ! "$app_name" =~ ^[A-Za-z0-9_.-]+$ ]]; then
    fail_usage "--app must be a simple vendored app source name, got: $app_name"
  fi
}

add_package_resolved_files_for_app() {
  local app_name="$1"
  local checkout_dir
  local resolved_file
  local found=0

  validate_app_name "$app_name"
  if ! checkout_dir="$(quillui_resolve_app_checkout_dir "$ROOT_DIR" "$app_name")"; then
    fail_usage "--app source was not found for '$app_name'. Expected vendor/apps/$app_name or .upstream/$app_name."
  fi

  while IFS= read -r resolved_file; do
    [[ -n "$resolved_file" ]] || continue
    add_package_resolved_file "$resolved_file"
    found=1
  done < <(find "$checkout_dir" \
    \( -name .git -o -name .build -o -name DerivedData \) -prune \
    -o -name Package.resolved -type f -print | sort)

  if [[ "$found" == "0" ]]; then
    echo "warning: no Package.resolved found under --app $app_name source: $checkout_dir" >&2
  fi
}

read_package_resolved_names() {
  local resolved_file="$1"

  python3 - "$resolved_file" <<'PY'
import json
import os
import sys
from pathlib import Path

include_dev_packages = os.environ.get("QUILLUI_VENDOR_INCLUDE_DEV_PACKAGES", "").lower() in {
    "1",
    "true",
    "yes",
    "on",
}
dev_only = {
    "swift-snapshot-testing",
    "swiftlintplugin",
}
shim_only = {
    "sparkle",
}
canonical = {
    "activityindicatorview": "ActivityIndicatorView",
    "aboutwindow": "AboutWindow",
    "alamofire": "Alamofire",
    "anycodable": "AnyCodable",
    "codeeditkit": "CodeEditKit",
    "codeeditlanguages": "CodeEditLanguages",
    "codeeditsourceeditor": "CodeEditSourceEditor",
    "codeeditsymbols": "CodeEditSymbols",
    "codeedittextview": "CodeEditTextView",
    "collectionconcurrencykit": "CollectionConcurrencyKit",
    "concurrencyplus": "ConcurrencyPlus",
    "fseventswrapper": "FSEventsWrapper",
    "grdb.swift": "GRDB.swift",
    "jsonrpc": "JSONRPC",
    "keyboardshortcuts": "KeyboardShortcuts",
    "languageclient": "LanguageClient",
    "languageserverprotocol": "LanguageServerProtocol",
    "logstream": "LogStream",
    "magnet": "Magnet",
    "networkimage": "NetworkImage",
    "ollamakit": "OllamaKit",
    "processenv": "ProcessEnv",
    "queue": "Queue",
    "rearrange": "Rearrange",
    "sauce": "Sauce",
    "semaphore": "Semaphore",
    "sparkle": "Sparkle",
    "splash": "Splash",
    "swift-async-algorithms": "AsyncAlgorithms",
    "swift-cmark": "SwiftCMark",
    "swift-collections": "swift-collections",
    "swift-glob": "swift-glob",
    "swift-markdown-ui": "MarkdownUI",
    "swift-snapshot-testing": "SwiftSnapshotTesting",
    "swift-syntax": "swift-syntax",
    "swiftlintplugin": "SwiftLintPlugin",
    "swiftterm": "SwiftTerm",
    "swifttreesitter": "SwiftTreeSitter",
    "swiftui-introspect": "SwiftUIIntrospect",
    "textformation": "TextFormation",
    "textstory": "TextStory",
    "tree-sitter": "tree-sitter",
    "vortex": "Vortex",
    "welcomewindow": "WelcomeWindow",
    "wrappinghstack": "WrappingHStack",
    "zipfoundation": "ZIPFoundation",
}

path = Path(sys.argv[1])
data = json.loads(path.read_text())
names = []
for pin in data.get("pins", []):
    identity = str(pin.get("identity", "")).lower()
    location = str(pin.get("location", "")).rstrip("/")
    basename = location.rsplit("/", 1)[-1]
    if basename.endswith(".git"):
        basename = basename[:-4]
    key = identity or basename.lower()
    if not include_dev_packages and key in dev_only:
        continue
    if key in shim_only:
        continue
    names.append(canonical.get(key, basename))

for name in sorted(dict.fromkeys(name for name in names if name)):
    print(name)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      while IFS= read -r package; do
        add_package "$package"
      done < <(known_packages)
      shift
      ;;
    --app)
      [[ $# -ge 2 ]] || fail_usage "--app requires a value."
      APP_NAMES+=("$2")
      shift 2
      ;;
    --app=*)
      APP_NAMES+=("${1#--app=}")
      shift
      ;;
    --package-resolved)
      [[ $# -ge 2 ]] || fail_usage "--package-resolved requires a value."
      add_package_resolved_file "$2"
      shift 2
      ;;
    --package-resolved=*)
      add_package_resolved_file "${1#--package-resolved=}"
      shift
      ;;
    --scratch-path)
      [[ $# -ge 2 ]] || fail_usage "--scratch-path requires a value."
      SCRATCH_PATH="$2"
      shift 2
      ;;
    --scratch-path=*)
      SCRATCH_PATH="${1#--scratch-path=}"
      shift
      ;;
    --no-resolve)
      RESOLVE=0
      shift
      ;;
    --hydrate-missing)
      HYDRATE_MISSING=1
      shift
      ;;
    --check-vendored)
      CHECK_VENDORED=1
      shift
      ;;
    --full)
      SLIM=0
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --list)
      known_packages
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      fail_usage "Unsupported option: $1"
      ;;
    *)
      add_package "$1"
      shift
      ;;
  esac
done

if [[ ${#APP_NAMES[@]} -gt 0 ]]; then
  for app_name in "${APP_NAMES[@]}"; do
    add_package_resolved_files_for_app "$app_name"
  done
fi

if [[ ${#PACKAGE_RESOLVED_FILES[@]} -gt 0 ]]; then
  ALLOW_UNKNOWN_PACKAGE_RESOLVED_PINS=1
  for resolved_file in "${PACKAGE_RESOLVED_FILES[@]}"; do
    case "$resolved_file" in
      /*) ;;
      *) resolved_file="$ROOT_DIR/$resolved_file" ;;
    esac
    [[ -f "$resolved_file" ]] || fail_usage "Package.resolved was not found: $resolved_file"
    while IFS= read -r package; do
      add_package "$package"
    done < <(read_package_resolved_names "$resolved_file")
  done
fi

if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  while IFS= read -r package; do
    add_package "$package"
  done < <(default_packages)
fi

case "$SCRATCH_PATH" in
  /*) ;;
  *) SCRATCH_PATH="$ROOT_DIR/$SCRATCH_PATH" ;;
esac

hydrate_missing_package_checkouts() {
  local hydrate_args=(
    "python3"
    "$ROOT_DIR/scripts/hydrate-swiftpm-checkouts-from-resolved.py"
    "--root-dir" "$ROOT_DIR"
    "--scratch-path" "$SCRATCH_PATH"
  )
  local resolved_file

  for resolved_file in "${PACKAGE_RESOLVED_FILES[@]}"; do
    hydrate_args+=("--package-resolved" "$resolved_file")
  done
  [[ "$DRY_RUN" == "0" ]] || hydrate_args+=("--dry-run")
  "${hydrate_args[@]}"
}

if [[ "$HYDRATE_MISSING" == "1" && ${#PACKAGE_RESOLVED_FILES[@]} -gt 0 ]]; then
  hydrate_missing_package_checkouts
fi

check_vendored_packages() {
  local package
  local status=0

  for package in "${PACKAGES[@]}"; do
    if [[ "$ALLOW_UNKNOWN_PACKAGE_RESOLVED_PINS" != "1" ]] && ! known_packages | grep -qx "$package"; then
      echo "error: unknown SwiftPM package '$package'. Use --list to see known packages." >&2
      return 64
    fi
    if [[ ! -f "$ROOT_DIR/third_party/$package/Package.swift" ]]; then
      echo "missing vendored $package -> third_party/$package" >&2
      status=1
    fi
  done

  if [[ "$status" == "0" ]]; then
    audit_vendored_package_manifests || status=$?
  fi

  if [[ "$status" == "0" ]]; then
    echo "vendored SwiftPM package sources are present"
  fi
  return "$status"
}

audit_vendored_package_manifests() {
  python3 - "$ROOT_DIR" "${PACKAGES[@]}" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
packages = sys.argv[2:]
status = 0

for package in packages:
    package_dir = root / "third_party" / package
    for manifest in sorted(package_dir.glob("Package*.swift")):
        for line_number, line in enumerate(manifest.read_text().splitlines(), 1):
            stripped = line.strip()
            if not stripped or stripped.startswith("//"):
                continue
            has_remote_dependency = ".package(url:" in stripped or (
                "url:" in stripped and "github.com" in stripped
            )
            if not has_remote_dependency:
                continue
            relative = manifest.relative_to(root)
            print(
                f"remote package dependency remains in {relative}:{line_number}: {stripped}",
                file=sys.stderr,
            )
            status = 1

sys.exit(status)
PY
}

if [[ "$CHECK_VENDORED" == "1" ]]; then
  check_vendored_packages
  exit $?
fi

if [[ "$RESOLVE" == "1" && "$DRY_RUN" != "1" ]]; then
  "$ROOT_DIR/scripts/swiftpm-preserve-package-resolved.sh" \
    swift package resolve \
    --package-path "$ROOT_DIR" \
    --scratch-path "$SCRATCH_PATH"
fi

sync_vendored_source_tree() {
  local source="$1"
  local destination="$2"
  shift 2

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --delete-excluded "$@" "$source/" "$destination/"
    return
  fi

  python3 - "$source" "$destination" "$@" <<'PY'
import fnmatch
import shutil
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
raw_args = sys.argv[3:]
patterns = []
index = 0
while index < len(raw_args):
    if raw_args[index] == "--exclude" and index + 1 < len(raw_args):
        patterns.append(raw_args[index + 1].rstrip("/"))
        index += 2
    else:
        index += 1

def ignored(path: Path) -> bool:
    relative = path.relative_to(source)
    rel = relative.as_posix()
    name = path.name
    for pattern in patterns:
        if fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(rel, pattern):
            return True
        if any(fnmatch.fnmatch(part, pattern) for part in relative.parts):
            return True
    return False

if destination.exists():
    shutil.rmtree(destination)
destination.parent.mkdir(parents=True, exist_ok=True)
destination.mkdir(parents=True, exist_ok=True)

for path in source.rglob("*"):
    if ignored(path):
        continue
    relative = path.relative_to(source)
    target = destination / relative
    if path.is_dir():
        target.mkdir(parents=True, exist_ok=True)
    elif path.is_symlink():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(path.readlink())
    elif path.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
PY
}

vendor_one() {
  local package="$1"
  local source="$SCRATCH_PATH/checkouts/$package"
  local destination="$ROOT_DIR/third_party/$package"
  local metadata_file="$destination/.quillui-vendor-source-fingerprint"
  local metadata=""
  local checkout
  local checkout_name
  local normalized_package
  local normalized_checkout
  local checkout_names=("$package")
  local rsync_excludes=(
    --exclude '.git'
    --exclude '.build'
    --exclude '.build-*'
    --exclude '.swiftpm'
    --exclude 'Package.resolved'
    --exclude 'DerivedData'
    --exclude 'xcuserdata'
    --exclude '.DS_Store'
  )

  if [[ "$ALLOW_UNKNOWN_PACKAGE_RESOLVED_PINS" != "1" ]] && ! known_packages | grep -qx "$package"; then
    echo "error: unknown SwiftPM package '$package'. Use --list to see known packages." >&2
    return 64
  fi

  case "$package" in
    AsyncAlgorithms) checkout_names+=("swift-async-algorithms") ;;
    MarkdownUI) checkout_names+=("swift-markdown-ui") ;;
    SwiftCMark) checkout_names+=("swift-cmark") ;;
    SwiftLintPlugin) checkout_names+=("SwiftLintPlugin" "swiftlintplugin") ;;
    SwiftSnapshotTesting) checkout_names+=("swift-snapshot-testing") ;;
    SwiftUIIntrospect) checkout_names+=("SwiftUI-Introspect" "swiftui-introspect") ;;
  esac
  for checkout_name in "${checkout_names[@]}"; do
    if [[ -d "$SCRATCH_PATH/checkouts/$checkout_name" ]]; then
      source="$SCRATCH_PATH/checkouts/$checkout_name"
      break
    fi
  done

  if [[ ! -d "$source" ]]; then
    normalized_package="$(printf '%s' "$package" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.]+//g')"
    shopt -s nullglob
    for checkout in "$SCRATCH_PATH/checkouts"/*; do
      normalized_checkout="$(basename "$checkout" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9.]+//g')"
      if [[ "$normalized_checkout" == "$normalized_package" ]]; then
        source="$checkout"
        break
      fi
    done
    shopt -u nullglob
  fi

  if [[ ! -d "$source" ]]; then
    if [[ -f "$destination/Package.swift" ]]; then
      echo "already vendored $package -> third_party/$package"
      return 0
    fi
    echo "warning: no checkout found for $package at $source; skipping" >&2
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "would vendor $package -> third_party/$package"
    return 0
  fi

  if [[ "$SLIM" == "1" ]]; then
    rsync_excludes+=(
      --exclude '.github'
      --exclude '.vscode'
      --exclude '.idea'
      --exclude 'Tests'
      --exclude 'test'
      --exclude 'docs'
      --exclude 'Docs'
      --exclude 'Documentation'
      --exclude '*.docc'
      --exclude 'Examples'
      --exclude 'Example'
      --exclude '*Example*'
      --exclude 'Assets'
      --exclude 'Images'
      --exclude 'Demo'
      --exclude 'Demos'
      --exclude 'Playground'
      --exclude 'Playgrounds'
      --exclude 'Sandbox'
      --exclude '*Tests'
      --exclude 'TestApplication'
      --exclude 'TestAppHelper'
      --exclude 'UITests'
      --exclude 'TerminalApp'
      --exclude 'Benchmarks'
      --exclude 'Benchmark'
      --exclude 'bench'
      --exclude 'Performance'
      --exclude 'FuzzTesting'
      --exclude 'fuzz'
      --exclude 'man'
      --exclude 'tools'
      --exclude 'wrappers'
      --exclude 'PluginExamples'
      --exclude 'Reference'
      --exclude 'Carthage'
      --exclude '*.xcodeproj'
      --exclude '*.xcworkspace'
      --exclude 'Makefile'
    )
  fi

  if metadata="$(vendored_source_metadata "$package" "$source" "$SLIM" "${rsync_excludes[@]}")"; then
    if ! truthy_flag "${QUILLUI_VENDOR_FORCE:-0}" \
      && [[ -f "$destination/Package.swift" ]] \
      && [[ -f "$metadata_file" ]] \
      && [[ "$(cat "$metadata_file")" == "$metadata" ]]; then
      echo "already vendored $package -> third_party/$package"
      return 0
    fi
  fi

  mkdir -p "$ROOT_DIR/third_party"
  sync_vendored_source_tree "$source" "$destination" "${rsync_excludes[@]}"
  if [[ -n "$metadata" ]]; then
    printf '%s\n' "$metadata" > "$metadata_file"
  fi
  chmod -R u+w "$destination"
  echo "vendored $package -> third_party/$package"
}

patch_swift_crypto_manifest() {
  local manifest="$ROOT_DIR/third_party/swift-crypto/Package.swift"

  [[ -f "$manifest" && -d "$ROOT_DIR/third_party/swift-asn1" ]] || return 0
  chmod u+w "$manifest"

  python3 - "$manifest" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

old = '''// Switch between local and remote dependencies depending on an environment variable
if ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.2.0")
    ]
} else {
    package.dependencies += [
        .package(path: "../swift-asn1")
    ]
}
'''
previous = '''// QuillUI vendors swift-crypto next to swift-asn1, so prefer the local
// sibling when present. Keep the upstream SWIFTCI_USE_LOCAL_DEPS override too.
let swiftASN1LocalPath = "../swift-asn1"
if FileManager.default.fileExists(atPath: swiftASN1LocalPath)
    || ProcessInfo.processInfo.environment["SWIFTCI_USE_LOCAL_DEPS"] != nil
{
    package.dependencies += [
        .package(path: swiftASN1LocalPath)
    ]
} else {
    package.dependencies += [
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.2.0")
    ]
}
'''
new = '''// QuillUI vendors swift-crypto next to swift-asn1, so keep the
// transitive dependency local as well.
package.dependencies += [
    .package(path: "../swift-asn1")
]
'''

if old in text:
    path.write_text(text.replace(old, new, 1))
elif previous in text:
    path.write_text(text.replace(previous, new, 1))
elif ".package(path: \"../swift-asn1\")" not in text:
    raise SystemExit("swift-crypto Package.swift dependency switch was not recognized")
PY
}

patch_swift_tree_sitter_manifest() {
  local manifest="$ROOT_DIR/third_party/SwiftTreeSitter/Package.swift"

  [[ -f "$manifest" && -d "$ROOT_DIR/third_party/tree-sitter" ]] || return 0
  chmod u+w "$manifest"

  python3 - "$manifest" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
old = '.package(path: "../tree-sitter")'
new = '.package(name: "TreeSitter", path: "../tree-sitter")'
if old in text:
    path.write_text(text.replace(old, new, 1))
elif new not in text:
    raise SystemExit("SwiftTreeSitter Package.swift tree-sitter dependency was not recognized")
PY
}

patch_vendored_transitive_manifests() {
  python3 - "$ROOT_DIR" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])

def balanced_call_end(text: str, open_paren: int) -> int:
    depth = 0
    in_string = False
    escaped = False
    index = open_paren
    while index < len(text):
        char = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        else:
            if char == '"':
                in_string = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    return index + 1
        index += 1
    raise SystemExit("unterminated Package.swift call while patching vendored manifest")

def remove_named_call(text: str, call: str, name: str) -> str:
    marker = f".{call}("
    index = 0
    while True:
        index = text.find(marker, index)
        if index < 0:
            return text
        open_paren = text.find("(", index)
        end = balanced_call_end(text, open_paren)
        block = text[index:end]
        if f'name: "{name}"' not in block:
            index = end
            continue
        start = text.rfind("\n", 0, index) + 1
        while start > 0 and text[start - 1] in " \t":
            start -= 1
        if end < len(text) and text[end] == ",":
            end += 1
        if end < len(text) and text[end] == "\n":
            end += 1
        return text[:start] + text[end:]

def replace_or_verify(text: str, old: str, new: str, required: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if required in text:
        return text
    raise SystemExit(f"{label} dependency block was not recognized")

def patch_file(relative_path: str, callback, required_dirs: tuple[str, ...] = ()) -> None:
    if any(not (root / item).is_dir() for item in required_dirs):
        return
    path = root / relative_path
    if not path.is_file():
        return
    os.chmod(path, path.stat().st_mode | 0o200)
    original = path.read_text()
    patched = callback(original)
    if patched != original:
        path.write_text(patched)

def patch_ollamakit(text: str) -> str:
    text = replace_or_verify(
        text,
        '''    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.8.1")),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", .upToNextMajor(from: "1.3.0"))
    ],
''',
        '''    dependencies: [
        .package(path: "../Alamofire")
    ],
''',
        '.package(path: "../Alamofire")',
        "OllamaKit Package.swift",
    )
    text = remove_named_call(text, "testTarget", "OllamaKitTests")
    if "swift-docc-plugin" in text or "OllamaKitTests" in text:
        raise SystemExit("OllamaKit Package.swift still contains remote docs or stale tests")
    return text

def patch_markdownui(text: str) -> str:
    text = replace_or_verify(
        text,
        '''  dependencies: [
    .package(url: "https://github.com/gonzalezreal/NetworkImage", from: "6.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.10.0"),
    .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.4.0"),
  ],
''',
        '''  dependencies: [
    .package(path: "../NetworkImage"),
    .package(name: "swift-cmark", path: "../SwiftCMark"),
  ],
''',
        '.package(name: "swift-cmark", path: "../SwiftCMark")',
        "MarkdownUI Package.swift",
    )
    text = remove_named_call(text, "testTarget", "MarkdownUITests")
    if "swift-snapshot-testing" in text or "MarkdownUITests" in text:
        raise SystemExit("MarkdownUI Package.swift still contains remote snapshot tests")
    return text

def patch_magnet(text: str) -> str:
    text = replace_or_verify(
        text,
        '.package(url: "https://github.com/Clipy/Sauce", .upToNextMinor(from: "2.4.0"))',
        '.package(path: "../Sauce")',
        '.package(path: "../Sauce")',
        "Magnet Package.swift",
    )
    text = remove_named_call(text, "testTarget", "MagnetTests")
    if "MagnetTests" in text:
        raise SystemExit("Magnet Package.swift still contains stale tests")
    return text

def patch_grdb(text: str) -> str:
    old = '''// SPI_BUILDER also enables the `make docs-localhost` command.
if ProcessInfo.processInfo.environment["SPI_BUILDER"] == "1" {
    dependencies.append(.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"))
}
'''
    new = '''// QuillUI vendors GRDB for offline Linux runtime builds. Do not pull the
// documentation-only Swift-DocC plugin even when SPI_BUILDER leaks into CI.
'''
    if old in text:
        text = text.replace(old, new, 1)
    if "swift-docc-plugin" in text:
        raise SystemExit("GRDB Package.swift still contains remote docs dependency")
    return text

def patch_async_algorithms(text: str) -> str:
    dependency_replacements = {
        '''if Context.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
  package.dependencies += [
    .package(
      url: "https://github.com/apple/swift-collections.git",
      from: "1.5.0",
      traits: [.trait(name: "UnstableContainersPreview", condition: .when(traits: ["UnstableAsyncStreaming"]))]
    )
  ]
} else {
  package.dependencies += [
    .package(path: "../swift-collections")
  ]
}
''': '''package.dependencies += [
  .package(path: "../swift-collections")
]
''',
        '''if Context.environment["SWIFTCI_USE_LOCAL_DEPS"] == nil {
  package.dependencies += [
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
  ]
} else {
  package.dependencies += [
    .package(path: "../swift-collections")
  ]
}
''': '''package.dependencies += [
  .package(path: "../swift-collections")
]
''',
        '''  dependencies: [
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.4"),
    .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
  ],
''': '''  dependencies: [
    .package(path: "../swift-collections"),
  ],
''',
    }
    for old, new in dependency_replacements.items():
        if old in text:
            text = text.replace(old, new, 1)
            break
    if '.package(path: "../swift-collections")' not in text or "swift-docc-plugin" in text:
        raise SystemExit("AsyncAlgorithms Package.swift dependency block was not recognized")
    text = text.replace('    .library(name: "AsyncStreaming", targets: ["AsyncStreaming"]),\n', "")
    traits_start = text.find("  traits: [")
    targets_start = text.find("  targets: [")
    if 0 <= traits_start < targets_start:
        text = text[:traits_start] + text[targets_start:]
    text = remove_named_call(text, "target", "AsyncStreaming")
    text = remove_named_call(text, "testTarget", "AsyncAlgorithmsTests")
    text = remove_named_call(text, "testTarget", "AsyncStreamingTests")
    if "AsyncStreaming" in text or "AsyncAlgorithmsTests" in text:
        raise SystemExit("AsyncAlgorithms Package.swift still contains unbuildable slim-tree targets")
    return text

def patch_zipfoundation_legacy(text: str) -> str:
    old_platform_block = '''#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
let dependencies: [Package.Dependency] = []
#else
let dependencies: [Package.Dependency] = [.package(url: "https://github.com/IBM-Swift/CZlib.git", .exact("0.1.2"))]
#endif
'''
    old_compression_block = '''#if canImport(Compression)
let dependencies: [Package.Dependency] = []
#else
let dependencies: [Package.Dependency] = [.package(url: "https://github.com/IBM-Swift/CZlib.git", .exact("0.1.2"))]
#endif
'''
    new_target_block = '''#if canImport(Compression)
let targets: [Target] = [
    .target(name: "ZIPFoundation"),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
#else
let targets: [Target] = [
    .systemLibrary(name: "CZLib", pkgConfig: "zlib"),
    .target(name: "ZIPFoundation", dependencies: ["CZLib"]),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
#endif
'''
    if old_platform_block in text:
        text = text.replace(old_platform_block, new_target_block, 1)
    elif old_compression_block in text:
        text = text.replace(old_compression_block, new_target_block, 1)
    elif '.systemLibrary(name: "CZLib", pkgConfig: "zlib")' not in text:
        raise SystemExit("ZIPFoundation Package@swift-4 legacy manifest was not recognized")
    text = text.replace("\n\tdependencies: dependencies,\n    targets: [\n        .target(name: \"ZIPFoundation\"),\n\t\t.testTarget(name: \"ZIPFoundationTests\", dependencies: [\"ZIPFoundation\"])\n    ]", "\n    targets: targets")
    text = text.replace("\n\tdependencies: dependencies,\n    targets: [\n        .target(name: \"ZIPFoundation\"),\n\t\t.testTarget(name: \"ZIPFoundationTests\", dependencies: [\"ZIPFoundation\"])\n    ],", "\n    targets: targets,")
    if "IBM-Swift/CZlib" in text or "dependencies: dependencies" in text:
        raise SystemExit("ZIPFoundation legacy Package.swift still contains remote CZlib")
    return text

patch_file("third_party/OllamaKit/Package.swift", patch_ollamakit, ("third_party/Alamofire",))
patch_file("third_party/MarkdownUI/Package.swift", patch_markdownui, ("third_party/NetworkImage", "third_party/SwiftCMark"))
patch_file("third_party/Magnet/Package.swift", patch_magnet, ("third_party/Sauce",))
patch_file("third_party/GRDB.swift/Package.swift", patch_grdb)
for manifest in (
    "third_party/AsyncAlgorithms/Package.swift",
    "third_party/AsyncAlgorithms/Package@swift-5.8.swift",
    "third_party/AsyncAlgorithms/Package@swift-5.7.swift",
):
    patch_file(manifest, patch_async_algorithms, ("third_party/swift-collections",))
for manifest in (
    "third_party/ZIPFoundation/Package@swift-4.0.swift",
    "third_party/ZIPFoundation/Package@swift-4.1.swift",
    "third_party/ZIPFoundation/Package@swift-4.2.swift",
):
    patch_file(manifest, patch_zipfoundation_legacy)
PY
}

for package in "${PACKAGES[@]}"; do
  vendor_one "$package"
done

patch_swift_crypto_manifest
patch_swift_tree_sitter_manifest
patch_vendored_transitive_manifests
