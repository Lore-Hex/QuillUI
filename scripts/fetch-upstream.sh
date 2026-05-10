#!/usr/bin/env bash
# Fetch the upstream open-source apps that QuillUI builds against.
# These checkouts live under `.upstream/` (gitignored) and are
# referenced by the Package.swift target list. Without them the
# manifest skips the matching targets; with them, the per-app
# targets become available.
#
# Usage:
#   scripts/fetch-upstream.sh              # fetch every upstream
#   scripts/fetch-upstream.sh enchanted    # fetch a specific one
#   scripts/fetch-upstream.sh enchanted netnewswire
#
# Idempotent: each upstream is `git clone --depth=1` on first run
# and `git fetch + reset --hard FETCH_HEAD` on subsequent runs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="$ROOT_DIR/.upstream"
mkdir -p "$UPSTREAM_DIR"

fetch_repo() {
    local name="$1"
    local url="$2"
    local ref="${3:-}"
    local dest="$UPSTREAM_DIR/$name"

    if [[ -d "$dest/.git" ]]; then
        echo "==> updating $name"
        if [[ -n "$ref" ]]; then
            git -C "$dest" fetch --depth=1 origin "$ref" >/dev/null
        else
            git -C "$dest" fetch --depth=1 origin >/dev/null
        fi
        git -C "$dest" reset --hard FETCH_HEAD >/dev/null
    else
        echo "==> cloning $name from $url"
        if [[ -n "$ref" ]]; then
            git clone --depth=1 --branch "$ref" "$url" "$dest" >/dev/null
        else
            git clone --depth=1 "$url" "$dest" >/dev/null
        fi
    fi
}

patch_codeeditsymbols() {
    # CodeEditSymbols 0.2.3's Package.swift is missing a `resources:`
    # declaration for `Symbols.xcassets`, so `Bundle.module` lookup
    # crashes at runtime. The patch is conservative: only add the
    # line when it's still missing.
    local manifest="$UPSTREAM_DIR/codeeditsymbols/Package.swift"
    if [[ ! -f "$manifest" ]]; then
        return
    fi
    if grep -q "Symbols.xcassets" "$manifest"; then
        echo "==> codeeditsymbols Package.swift already patched"
        return
    fi
    echo "==> patching codeeditsymbols Package.swift to declare Symbols.xcassets"
    # Insert `resources: [.process("Symbols.xcassets")]` into the
    # `CodeEditSymbols` target. We anchor on the target declaration
    # and add a `resources:` line if not present.
    python3 - "$manifest" <<'PY'
import re
import sys

path = sys.argv[1]
src = open(path).read()

# Find the `.target(name: "CodeEditSymbols", ... )` block. The body
# is everything between the opening `(` and the matching `)`, which
# we locate by paren-counting since the upstream layout has nested
# brackets in `dependencies: []`.
needle = '.target(\n            name: "CodeEditSymbols"'
i = src.find(needle)
if i < 0:
    needle = '.target('
    i = src.find(needle)
    if i < 0:
        print("warning: could not find CodeEditSymbols target", file=sys.stderr)
        sys.exit(0)

start = src.index("(", i)
depth = 0
end = -1
for j in range(start, len(src)):
    c = src[j]
    if c == "(":
        depth += 1
    elif c == ")":
        depth -= 1
        if depth == 0:
            end = j
            break
if end < 0:
    print("warning: could not parse CodeEditSymbols target body", file=sys.stderr)
    sys.exit(0)

body = src[start + 1:end]
if "Symbols.xcassets" in body:
    sys.exit(0)
patched_body = body.rstrip().rstrip(",") + ",\n            resources: [.process(\"Symbols.xcassets\")]\n        "
src = src[: start + 1] + patched_body + src[end:]
open(path, "w").write(src)
print("patched CodeEditSymbols target with Symbols.xcassets resource")
PY
}

want=("$@")
if [[ ${#want[@]} -eq 0 ]]; then
    want=(enchanted netnewswire wireguard codeedit codeeditsymbols)
fi

for name in "${want[@]}"; do
    case "$name" in
        enchanted)
            fetch_repo enchanted https://github.com/gluonfield/enchanted.git
            ;;
        netnewswire)
            fetch_repo netnewswire https://github.com/Ranchero-Software/NetNewsWire.git
            ;;
        wireguard)
            fetch_repo wireguard-apple https://github.com/WireGuard/wireguard-apple.git
            ;;
        codeedit)
            fetch_repo codeedit https://github.com/CodeEditApp/CodeEdit.git
            ;;
        codeeditsymbols)
            fetch_repo codeeditsymbols https://github.com/CodeEditApp/CodeEditSymbols.git
            patch_codeeditsymbols
            ;;
        *)
            echo "unknown upstream: $name" >&2
            exit 64
            ;;
    esac
done
