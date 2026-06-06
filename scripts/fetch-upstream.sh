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

patch_wireguard_apple() {
    # Lower the macOS UI's AppKit target-action for Linux (strip @objc,
    # #selector(x) -> Selector("x"), generate the QuillActionDispatching
    # dispatch) so the QuillWireGuardConformanceUI target compiles against the
    # QuillAppKit shadow, which has no Objective-C runtime. Self-guarded +
    # idempotent: only runs while un-lowered source is present, so it's safe
    # regardless of the WireGuardKitC.h early-return below and of cached
    # .upstream trees.
    # Linux-only: on macOS the real AppKit handles #selector/@objc, and the
    # generated QuillActionDispatching extension references a Linux-only shadow
    # type — so leave the source pristine for any macOS consumer.
    # Lower the WHOLE app (WireGuardApp: UI/macOS + Tunnel/ + …) AND its Shared/
    # helpers (Logging/Logger.swift = wg_log, etc.), not just UI/macOS, so model
    # files also compile in the Linux conformance targets — toward the
    # single-app-module convergence. The guard includes `import os.log` so Shared/
    # (no @objc but `import os.log` in Logger.swift) is covered; it goes false
    # after lowering, keeping this idempotent on cached trees. The Shared/Model
    # parser files (in the core QuillWireGuardUpstreamConfig target) have NO
    # lowering triggers, so that target is unaffected. The CLI is recursive +
    # idempotent.
    if [[ "$(uname -s)" == "Linux" ]]; then
        for sub in WireGuardApp Shared; do
            local subdir="$UPSTREAM_DIR/wireguard-apple/Sources/$sub"
            if [[ -d "$subdir" ]] && grep -rqE '#selector|@objc|import os\.log' "$subdir" 2>/dev/null; then
                echo "==> lowering wireguard-apple Sources/$sub for Linux"
                ( cd "$ROOT_DIR" && swift run quill-lower-appkit "$subdir" )
            fi
        done
    fi

    # `WireGuardKitC.h` uses `u_int32_t` / `u_char` / `u_int16_t`
    # / `sockaddr_ctl` from <sys/types.h> + <sys/kern_control.h>
    # but doesn't include them. macOS 15+ enforces strict
    # modular header imports — without explicit includes the
    # build fails with `declaration of 'u_int32_t' must be
    # imported from module 'DarwinFoundation.unsigned_types.u_int32_t'`.
    # Add the explicit `#include <sys/types.h>` so the modular
    # check sees them through the right module.
    local header="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardKitC/WireGuardKitC.h"
    if [[ ! -f "$header" ]]; then
        return
    fi
    if grep -q '^#include <sys/types.h>' "$header"; then
        echo "==> wireguard-apple WireGuardKitC.h already patched"
        return
    fi
    echo "==> patching wireguard-apple WireGuardKitC.h to include <sys/types.h>"
    python3 - "$header" <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()
# Insert `#include <sys/types.h>` just after the copyright
# comment block / before the first other include. Idempotent
# because we already checked for the presence in the calling
# shell.
patched = src.replace(
    '#include "key.h"',
    '#include <sys/types.h>\n#include "key.h"',
    1,
)
if patched == src:
    # No anchor — prepend.
    patched = '#include <sys/types.h>\n' + src
open(path, "w").write(patched)
print("patched WireGuardKitC.h to explicitly include <sys/types.h>")
PY

    # The Shared/Model wg-quick parser extends WireGuardKit's
    # TunnelConfiguration but imports only Foundation — upstream's
    # Xcode build puts it in the WireGuardKit module via target
    # membership, but SwiftPM compiles it as its own target, so it
    # needs an explicit `import WireGuardKit`. Same shape as the
    # header patch above: a Linux/SwiftPM compat add, no logic change.
    local parser="$UPSTREAM_DIR/wireguard-apple/Sources/Shared/Model/TunnelConfiguration+WgQuickConfig.swift"
    if [[ -f "$parser" ]] && ! grep -q '^import WireGuardKit' "$parser"; then
        echo "==> patching TunnelConfiguration+WgQuickConfig.swift to import WireGuardKit"
        python3 - "$parser" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
patched = src.replace('import Foundation\n', 'import Foundation\nimport WireGuardKit\n', 1)
open(path, "w").write(patched)
print("patched TunnelConfiguration+WgQuickConfig.swift to import WireGuardKit")
PY
    fi

    # Logger.swift (Shared/Logging) calls the ringlogger C ring buffer
    # (open_log / write_msg_to_log / write_log_to_file / close_log) from
    # Sources/Shared/Logging/ringlogger.c, built as the WireGuardRingLoggerC C
    # target. Upstream's Xcode build sees the C funcs via same-target membership;
    # SwiftPM needs an explicit `import WireGuardRingLoggerC`. Same shape as the
    # parser patch above.
    local logger="$UPSTREAM_DIR/wireguard-apple/Sources/Shared/Logging/Logger.swift"
    if [[ -f "$logger" ]] && ! grep -q '^import WireGuardRingLoggerC' "$logger"; then
        echo "==> patching Logger.swift to import WireGuardRingLoggerC"
        python3 - "$logger" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
patched = src.replace('import Foundation\n', 'import Foundation\nimport WireGuardRingLoggerC\n', 1)
open(path, "w").write(patched)
print("patched Logger.swift to import WireGuardRingLoggerC")
PY
    fi
}

patch_icecubes() {
    # NetworkClient files `import Foundation` and use URLRequest / URLSession /
    # HTTPURLResponse, which live in the FoundationNetworking module on Linux
    # (swift-corelibs-foundation). Add a conditional `import FoundationNetworking`
    # after the first `import Foundation`; canImport is false on macOS so the
    # Apple build is unaffected. Idempotent.
    local dir="$UPSTREAM_DIR/icecubes/Packages/NetworkClient/Sources/NetworkClient"
    if [[ ! -d "$dir" ]]; then
        return
    fi
    echo "==> patching IceCubes NetworkClient for the Linux FoundationNetworking split"
    python3 - "$dir" <<'PY'
import sys, os, glob

directory = sys.argv[1]
addition = (
    "import Foundation\n"
    "#if canImport(FoundationNetworking)\n"
    "import FoundationNetworking\n"
    "#endif"
)
for path in sorted(glob.glob(os.path.join(directory, "*.swift"))):
    src = open(path).read()
    lines = src.split("\n")
    out = []
    fn_done = "FoundationNetworking" in src
    for line in lines:
        stripped = line.strip()
        if stripped == "import OSLog":
            # Linux: the repo `os` shim provides Logger; there is no OSLog
            # module, and an `@_exported import os` shim retains os_log symbols
            # that break swift-syntax's link. Rewrite to the plain os import.
            out.append("import os")
        elif stripped == "import Foundation" and not fn_done:
            out.append(addition)
            fn_done = True
        else:
            out.append(line)
    new = "\n".join(out)
    if new != src:
        open(path, "w").write(new)
        print("patched", os.path.basename(path))
PY
}

patch_signal_ios() {
    # GRDBSchemaMigrator.swift calls NSCoder.decodeTopLevelObject(of:forKey:),
    # which swift-corelibs-foundation has renamed to decodeObject(of:forKey:)
    # (same signature; corelibs makes the old spelling a hard error, not a mere
    # deprecation). SSK builds Linux-only here, so the rename is safe. The `try`
    # on the now-non-throwing call is a harmless warning. (Placed before the
    # TSMutex block, which has early returns that would otherwise skip this.)
    local mig="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Storage/Database/GRDBSchemaMigrator.swift"
    if [[ -f "$mig" ]] && grep -q 'decodeTopLevelObject(' "$mig"; then
        echo "==> patching signal-ios GRDBSchemaMigrator.swift decodeTopLevelObject -> decodeObject"
        python3 - "$mig" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
open(path, "w").write(src.replace("decodeTopLevelObject(", "decodeObject("))
PY
    fi

    # Signal's SignalServiceKit/Concurrency/TSMutex.swift does
    # `internal import os.lock` for os_unfair_lock. The `os` framework's clang
    # `lock` submodule does not exist on Linux, and QuillUI's `os` is a Swift
    # module (which cannot expose a clang submodule). Swap the import to
    # QuillUI's COSUnfairLock C shim on non-Apple platforms. TSMutex's logic is
    # untouched — only the import line is conditionalized.
    local f="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Concurrency/TSMutex.swift"
    if [[ ! -f "$f" ]]; then
        return
    fi
    if grep -q 'COSUnfairLock' "$f"; then
        echo "==> signal-ios TSMutex.swift already patched"
        return
    fi
    echo "==> patching signal-ios TSMutex.swift os.lock import for Linux"
    python3 - "$f" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
patched = src.replace(
    "internal import os.lock",
    "#if canImport(Darwin)\n"
    "internal import os.lock\n"
    "#else\n"
    // `public` (not `internal`): TSMutex's `withLock`/`lock` are `@inlinable`, and
    // an @inlinable function may only reference public/usableFromInline symbols.
    // An `internal import` makes the COSUnfairLock C functions internal -> the
    // @inlinable methods can't call os_unfair_lock_lock. `public import` exposes them.
    "public import COSUnfairLock\n"
    "#endif",
    1,
)
open(path, "w").write(patched)
print("patched TSMutex.swift os.lock import for Linux")
PY
}

want=("$@")
if [[ ${#want[@]} -eq 0 ]]; then
    # Default set excludes codeedit/codeeditsymbols. CodeEditSymbols
    # 0.2.3 pulls in a SwiftLintPlugin prebuild command that SwiftPM
    # 6 rejects ("a prebuild command cannot use executables built
    # from source"). Until the upstream is patched or replaced,
    # the CodeEdit work has to be opt-in via:
    #   scripts/fetch-upstream.sh codeedit codeeditsymbols
    want=(enchanted netnewswire wireguard icecubes)
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
            patch_wireguard_apple
            ;;
        icecubes)
            fetch_repo icecubes https://github.com/Dimillian/IceCubesApp.git
            patch_icecubes
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
