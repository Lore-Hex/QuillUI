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
#   scripts/fetch-upstream.sh telegram
#
# Idempotent: each upstream is `git clone --depth=1` on first run
# and `git fetch + reset --hard FETCH_HEAD` on subsequent runs. CI can
# set QUILLUI_TRUST_UPSTREAM_CACHE=1 after restoring `.upstream` from
# actions/cache; existing checkouts are then reused without a network
# refresh, while cache misses still clone normally.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_DIR="$ROOT_DIR/.upstream"
mkdir -p "$UPSTREAM_DIR"

source "$ROOT_DIR/scripts/quillui-enchanted-source.sh"

quillui_truthy() {
    case "${1:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        *) return 1 ;;
    esac
}

quillui_trust_upstream_cache() {
    quillui_truthy "${QUILLUI_TRUST_UPSTREAM_CACHE:-0}"
}

fetch_repo() {
    local name="$1"
    local url="$2"
    local ref="${3:-}"
    local dest="$UPSTREAM_DIR/$name"

    if [[ -d "$dest/.git" ]]; then
        if quillui_trust_upstream_cache; then
            echo "==> using cached $name (QUILLUI_TRUST_UPSTREAM_CACHE=1)"
            git -C "$dest" reset --hard HEAD >/dev/null
            return
        fi
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

reset_repo_to_commit() {
    local name="$1"
    local commit="$2"
    local dest="$UPSTREAM_DIR/$name"

    if [[ ! -d "$dest/.git" ]]; then
        echo "error: cannot pin missing upstream checkout: $name" >&2
        return 1
    fi

    if git -C "$dest" cat-file -e "$commit^{commit}" 2>/dev/null; then
        echo "==> resetting $name to cached commit $commit"
    else
        echo "==> fetching pinned $name commit $commit"
        git -C "$dest" fetch --depth=1 origin "$commit" >/dev/null
    fi
    git -C "$dest" reset --hard "$commit" >/dev/null
}

apply_generated_source_patch() {
    local name="$1"
    local repo="$2"
    local patch="$3"

    if [[ ! -f "$patch" || ! -d "$repo/.git" ]]; then
        return
    fi

    if git -C "$repo" apply --check "$patch" >/dev/null 2>&1; then
        echo "==> applying $name generated-source patch"
        git -C "$repo" apply "$patch"
    elif git -C "$repo" apply --reverse --check "$patch" >/dev/null 2>&1; then
        echo "==> $name generated-source patch already applied"
    else
        echo "warning: could not apply $name generated-source patch" >&2
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
    # #selector(x) -> Selector("x"), inject the class-body quillPerform
    # dispatch) so the QuillWireGuardConformanceUI target compiles against the
    # QuillAppKit shadow, which has no Objective-C runtime. Self-guarded +
    # idempotent: only runs while un-lowered source is present, so it's safe
    # regardless of the WireGuardKitC.h early-return below and of cached
    # .upstream trees.
    # Linux-only: on macOS the real AppKit handles #selector/@objc, and the
    # injected quillPerform (QuillSelectorDispatching) references a Linux-only
    # shadow type — so leave the source pristine for any macOS consumer.
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

    # Apple Swift 6.1's SwiftPM rejects raw `-default-isolation MainActor`
    # passed through `swiftSettings: .unsafeFlags(...)`; newer toolchains accept
    # the frontend flag only when routed with `-Xfrontend`. Normalize whichever
    # upstream WireGuard manifest was fetched before the macOS CI target build.
    local manifest="$UPSTREAM_DIR/wireguard-apple/Package.swift"
    if [[ -f "$manifest" ]] && grep -q '"-default-isolation"' "$manifest"; then
        echo "==> patching wireguard-apple Package.swift default-isolation flags"
        python3 - "$manifest" <<'PY'
import re
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
replacement = '["-Xfrontend", "-default-isolation", "-Xfrontend", "MainActor"]'
patched = re.sub(
    r'\[\s*"-default-isolation"\s*,\s*"MainActor"\s*\]',
    replacement,
    src,
)
if patched != src:
    open(path, "w", encoding="utf-8").write(patched)
    print("patched WireGuard Package.swift default-isolation flags for SwiftPM frontend compatibility")
PY
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

    # LogViewHelper.swift (UI/) also reads the ringlogger C ring buffer directly
    # (view_lines_from_cursor / open_log) to render the in-app log viewer, so it
    # needs the same explicit `import WireGuardRingLoggerC` under SwiftPM.
    local logviewhelper="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/LogViewHelper.swift"
    if [[ -f "$logviewhelper" ]] && ! grep -q '^import WireGuardRingLoggerC' "$logviewhelper"; then
        echo "==> patching LogViewHelper.swift to import WireGuardRingLoggerC"
        python3 - "$logviewhelper" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
patched = src.replace('import Foundation\n', 'import Foundation\nimport WireGuardRingLoggerC\n', 1)
open(path, "w").write(patched)
print("patched LogViewHelper.swift to import WireGuardRingLoggerC")
PY
    fi

    # ParseError+WireGuardAppError.swift (UI/macOS) extends WireGuardKit's
    # TunnelConfiguration (import WireGuardKit) and its nested ParseError enum
    # (declared in QuillWireGuardUpstreamConfig) — both need explicit imports
    # under SwiftPM (Xcode saw them via one app module). It imports Cocoa, not
    # Foundation, so anchor on that.
    local parseerr="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/ParseError+WireGuardAppError.swift"
    if [[ -f "$parseerr" ]] && ! grep -q '^import QuillWireGuardUpstreamConfig' "$parseerr"; then
        echo "==> patching ParseError+WireGuardAppError.swift imports"
        python3 - "$parseerr" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
patched = src.replace('import Cocoa\n', 'import Cocoa\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\n', 1)
open(path, "w").write(patched)
print("patched ParseError+WireGuardAppError.swift to import WireGuardKit + QuillWireGuardUpstreamConfig")
PY
    fi

    # B-wall: NSTableView+Reuse's `dequeueReusableCell<T: NSView>() { T() }` can't
    # construct a generic class value on Linux without a `required init()` (macOS
    # gets it free via the ObjC runtime). Rather than force `required init()` onto
    # NSView (cascades repo-wide), narrow the cell constraint to NSView &
    # QuillReusableView (a QuillAppKit protocol requiring init()), and make the
    # cell types it dequeues conform with a `required init()`.
    local reuse="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/NSTableView+Reuse.swift"
    if [[ -f "$reuse" ]] && ! grep -q 'QuillReusableView' "$reuse"; then
        echo "==> patching NSTableView+Reuse.swift cell constraint to NSView & QuillReusableView"
        python3 - "$reuse" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('func dequeueReusableCell<T: NSView>() -> T',
                  'func dequeueReusableCell<T: NSView & QuillReusableView>() -> T', 1)
open(path, "w").write(src)
print("patched NSTableView+Reuse.swift cell constraint")
PY
    fi

    # LogViewCell (+ subclasses) conform to QuillReusableView so they can be
    # dequeued: add the conformance + make their init() `required`.
    local logcell="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/View/LogViewCell.swift"
    if [[ -f "$logcell" ]] && ! grep -q 'QuillReusableView' "$logcell"; then
        echo "==> patching LogViewCell.swift to conform to QuillReusableView (required init)"
        python3 - "$logcell" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('class LogViewCell: NSTableCellView {',
                  'class LogViewCell: NSTableCellView, QuillReusableView {', 1)
src = src.replace('    init() {', '    required init() {', 1)             # LogViewCell's own init()
src = src.replace('    override init() {', '    required init() {')       # the two subclasses
open(path, "w").write(src)
print("patched LogViewCell.swift for QuillReusableView")
PY
    fi

    # ZIP subsystem imports: ZipArchive.swift calls the vendored minizip C
    # (import WireGuardMinizipC); ZipImporter/ZipExporter parse/serialize .conf via
    # wg-quick (TunnelConfiguration = WireGuardKit; fromWgQuickConfig/asWgQuickConfig
    # = QuillWireGuardUpstreamConfig). Xcode saw these via one app module; SwiftPM
    # needs explicit imports.
    local ziparch="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/ZipArchive/ZipArchive.swift"
    if [[ -f "$ziparch" ]] && ! grep -q '^import WireGuardMinizipC' "$ziparch"; then
        echo "==> patching ZipArchive.swift to import WireGuardMinizipC"
        python3 - "$ziparch" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Foundation\n', 'import Foundation\nimport WireGuardMinizipC\n', 1)
open(path, "w").write(src)
print("patched ZipArchive.swift to import WireGuardMinizipC")
PY
    fi
    for zf in ZipImporter.swift ZipExporter.swift; do
        local zpath="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/ZipArchive/$zf"
        if [[ -f "$zpath" ]] && ! grep -q '^import QuillWireGuardUpstreamConfig' "$zpath"; then
            echo "==> patching $zf imports (WireGuardKit + QuillWireGuardUpstreamConfig)"
            python3 - "$zpath" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Foundation\n',
                  'import Foundation\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\n', 1)
open(path, "w").write(src)
print("patched imports")
PY
        fi
    done

    # TunnelImporter: routes imported URLs through ZipImporter + the wg-quick parser.
    # (1) imports: TunnelConfiguration (WireGuardKit) + fromWgQuickConfig
    #     (QuillWireGuardUpstreamConfig). (2) it's a nonisolated static func, but its
    #     dispatchGroup.notify(queue: .main) closure calls the @MainActor
    #     ErrorPresenterProtocol.showErrorAlert — legal at runtime (it IS on main), so
    #     wrap that one call in MainActor.assumeIsolated to satisfy the type-checker.
    local timp="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/TunnelImporter.swift"
    if [[ -f "$timp" ]] && ! grep -q '^import QuillWireGuardUpstreamConfig' "$timp"; then
        echo "==> patching TunnelImporter.swift (imports + assumeIsolated showErrorAlert)"
        python3 - "$timp" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Foundation\n',
                  'import Foundation\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\n', 1)
old = '                    errorPresenterType.showErrorAlert(title: alertText.title, message: alertText.message, from: sourceVC, onPresented: completionHandler)\n'
new = ('                    MainActor.assumeIsolated {\n'
       '                        errorPresenterType.showErrorAlert(title: alertText.title, message: alertText.message, from: sourceVC, onPresented: completionHandler)\n'
       '                    }\n')
if old in src:
    src = src.replace(old, new, 1)
open(path, "w").write(src)
print("patched TunnelImporter.swift")
PY
    fi

    # ImportPanelPresenter is a UI presenter (NSOpenPanel) whose static func touches
    # the @MainActor NSViewController.view (sourceVC.view.window). It's nonisolated in
    # the source, so mark the class @MainActor (Apple-faithful — it presents UI on the
    # main thread; its only caller, the @MainActor VC action handleImportTunnelAction,
    # is fine). Same shape as the ErrorPresenter @MainActor patch.
    local ipp="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/ImportPanelPresenter.swift"
    if [[ -f "$ipp" ]] && ! grep -q '@MainActor' "$ipp"; then
        echo "==> patching ImportPanelPresenter.swift @MainActor"
        python3 - "$ipp" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
open(path, "w").write(src.replace('class ImportPanelPresenter {', '@MainActor\nclass ImportPanelPresenter {', 1))
print("patched ImportPanelPresenter @MainActor")
PY
    fi

    # StatusMenu's importTunnelsClicked calls the (now-@MainActor) ImportPanelPresenter
    # inside the StatusMenuWindowDelegate.showManageTunnelsWindow completion closure.
    # That completion presents UI on the main thread, so mark its type @MainActor — the
    # closure then inherits the isolation and the presentImportPanel call type-checks.
    # (AppDelegate, which conforms to StatusMenuWindowDelegate, gets the matching
    # @MainActor completion patch when it lands.)
    local smenu="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/StatusMenu.swift"
    if [[ -f "$smenu" ]] && ! grep -q '@MainActor (NSWindow?)' "$smenu"; then
        echo "==> patching StatusMenu.swift showManageTunnelsWindow completion @MainActor"
        python3 - "$smenu" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('completion: ((NSWindow?) -> Void)?)',
                  'completion: (@MainActor (NSWindow?) -> Void)?)', 1)
open(path, "w").write(src)
print("patched StatusMenu showManageTunnelsWindow completion @MainActor")
PY
    fi

    # TunnelsTracker is a plain (nonisolated) class implementing TunnelsManager's
    # list/activation delegates, but those callbacks touch @MainActor UI:
    # ManageTunnelsRootViewController.tunnelsListVC + .view (the VC is @MainActor) and
    # the @MainActor-patched ErrorPresenter.showErrorAlert. The delegate protocols can't
    # be made @MainActor (that cascades into TunnelsManager's many nonisolated call
    # sites), so wrap the @MainActor work in MainActor.assumeIsolated — these callbacks
    # fire on the main thread (and the conformance target is compile-only). Idempotent.
    local tt="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/TunnelsTracker.swift"
    if [[ -f "$tt" ]] && ! grep -q 'MainActor.assumeIsolated' "$tt"; then
        echo "==> patching TunnelsTracker.swift @MainActor delegate forwards (assumeIsolated)"
        python3 - "$tt" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
for call in [
    'manageTunnelsRootVC?.tunnelsListVC?.tunnelAdded(at: index)',
    'manageTunnelsRootVC?.tunnelsListVC?.tunnelModified(at: index)',
    'manageTunnelsRootVC?.tunnelsListVC?.tunnelMoved(from: oldIndex, to: newIndex)',
    'manageTunnelsRootVC?.tunnelsListVC?.tunnelRemoved(at: index)',
]:
    src = src.replace(call, 'MainActor.assumeIsolated { ' + call + ' }')
block = '''        if let manageTunnelsRootVC = manageTunnelsRootVC, manageTunnelsRootVC.view.window?.isVisible ?? false {
            ErrorPresenter.showErrorAlert(error: error, from: manageTunnelsRootVC)
        } else {
            ErrorPresenter.showErrorAlert(error: error, from: nil)
        }'''
src = src.replace(block, '        MainActor.assumeIsolated {\n' + block + '\n        }')
open(path, "w").write(src)
print("patched TunnelsTracker.swift @MainActor delegate forwards")
PY
    fi

    # AppDelegate conforms to StatusMenuWindowDelegate (whose completion was marked
    # @MainActor in StatusMenu.swift), and references WIREGUARD_GO_VERSION — a constant
    # generated as a C #define by WireGuardKitGo/Makefile that isn't present in the Linux
    # conformance build. (1) match the @MainActor completion in the conformance; (2) inject
    # a Linux-only stub constant so the About-panel string compiles.
    local appdel="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/AppDelegate.swift"
    if [[ -f "$appdel" ]]; then
        python3 - "$appdel" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('func showManageTunnelsWindow(completion: ((NSWindow?) -> Void)?)',
                  'func showManageTunnelsWindow(completion: (@MainActor (NSWindow?) -> Void)?)', 1)
if 'let WIREGUARD_GO_VERSION' not in src:
    needle = 'import ServiceManagement\n'
    src = src.replace(needle, needle + '#if os(Linux)\nlet WIREGUARD_GO_VERSION = "0.0.0"  // generated C #define on macOS; stub for the Linux conformance build\n#endif\n', 1)
open(path, "w").write(src)
print("patched AppDelegate.swift: @MainActor completion + WIREGUARD_GO_VERSION stub")
PY
    fi

    # Application (NSApplication subclass) creates the @MainActor AppDelegate in its
    # nonisolated init() (the shadow's NSApplication is @unchecked Sendable, not @MainActor —
    # making it @MainActor would have a huge blast radius). App startup is on the main
    # thread, so wrap the AppDelegate creation + delegate assignment in MainActor.assumeIsolated.
    local appcls="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/Application.swift"
    if [[ -f "$appcls" ]] && ! grep -q 'MainActor.assumeIsolated' "$appcls"; then
        echo "==> patching Application.swift (assumeIsolated around AppDelegate creation)"
        python3 - "$appcls" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
old = '''        super.init()
        appDelegate = AppDelegate() // Keep a strong reference to the app delegate
        delegate = appDelegate // Set delegate before app.run() gets called in NSApplicationMain()'''
new = '''        super.init()
        MainActor.assumeIsolated {
            appDelegate = AppDelegate() // Keep a strong reference to the app delegate
            delegate = appDelegate // Set delegate before app.run() gets called in NSApplicationMain()
        }'''
assert old in src, "Application.swift init body not found"
open(path, "w").write(src.replace(old, new, 1))
print("patched Application.swift assumeIsolated")
PY
    fi

    # WireGuardKit/DNSResolver: now compiled on Linux (un-excluded in Package.swift). Two
    # Linux ports — (1) widen the lone `#error("Unimplemented")` os-gate in withReresolvedIP
    # to Linux (return self, like macOS); (2) Glibc-vs-Darwin C types: SOCK_DGRAM is
    # `__socket_type` and IPPROTO_UDP is `Int` on Linux, but addrinfo's fields are Int32, so
    # cast (Linux only). WireGuardKit isn't run through the lowering CLI, hence this patch.
    local dnsres="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardKit/DNSResolver.swift"
    if [[ -f "$dnsres" ]] && ! grep -q 'Int32(SOCK_DGRAM.rawValue)' "$dnsres"; then
        echo "==> patching DNSResolver.swift for Linux (os-gate widen + addrinfo C-type casts)"
        python3 - "$dnsres" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('        #elseif os(macOS)\n        return self',
                  '        #elseif os(macOS) || os(Linux)\n        return self', 1)
src = src.replace(
'''        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP''',
'''        hints.ai_family = AF_UNSPEC
        #if os(Linux)
        hints.ai_socktype = Int32(SOCK_DGRAM.rawValue)
        hints.ai_protocol = Int32(IPPROTO_UDP)
        #else
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP
        #endif''', 1)
open(path, "w").write(src)
print("patched DNSResolver.swift for Linux")
PY
    fi

    # WireGuardKit/PacketTunnelSettingsGenerator: now compiled on Linux (un-excluded). Its
    # only `#error("Unimplemented")` is the mtu==0 branch — widen `#elseif os(macOS)` (which
    # sets tunnelOverheadBytes = 80) to include Linux. (NE settings/routes come from the
    # NetworkExtension shim, incl. the tunnelOverheadBytes property added there.)
    local ptsg="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardKit/PacketTunnelSettingsGenerator.swift"
    if [[ -f "$ptsg" ]] && ! grep -q '#elseif os(macOS) || os(Linux)' "$ptsg"; then
        echo "==> patching PacketTunnelSettingsGenerator.swift os-gate for Linux"
        python3 - "$ptsg" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('            #elseif os(macOS)\n            networkSettings.tunnelOverheadBytes = 80',
                  '            #elseif os(macOS) || os(Linux)\n            networkSettings.tunnelOverheadBytes = 80', 1)
open(path, "w").write(src)
print("patched PacketTunnelSettingsGenerator.swift os-gate")
PY
    fi

    # WireGuardKit/WireGuardAdapter: now compiled on Linux (un-excluded) over the
    # WireGuardKitGo stub shim. Three Linux ports: (1) add `import Network` — it uses
    # NWPathMonitor / Network.NWPath but only `import NetworkExtension` (which re-exports
    # Network on Apple, not in our shim); (2) Linux-stub the tunnelFileDescriptor computed
    # property — its utun discovery uses Darwin kernel-control sockets (AF_SYSTEM / ctl_info
    # / sockaddr_ctl / CTLIOCGINFO) that don't exist on Linux (the adapter never runs here);
    # (3) widen the didReceivePathUpdate `#if os(macOS)` (wgBumpSockets) to include Linux,
    # else `#error("Unsupported")`.
    local wgadapter="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardKit/WireGuardAdapter.swift"
    if [[ -f "$wgadapter" ]] && ! grep -q 'no utun kernel-control sockets on Linux' "$wgadapter"; then
        echo "==> patching WireGuardAdapter.swift for Linux (import Network + tunnelFileDescriptor stub + os-gate)"
        python3 - "$wgadapter" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Foundation\nimport NetworkExtension\n',
                  'import Foundation\nimport NetworkExtension\nimport Network\n', 1)
src = src.replace(
'''    private var tunnelFileDescriptor: Int32? {
        var ctlInfo = ctl_info()''',
'''    private var tunnelFileDescriptor: Int32? {
        #if os(Linux)
        return nil // no utun kernel-control sockets on Linux (AF_SYSTEM/ctl_info are Darwin); the adapter never runs here
        #else
        var ctlInfo = ctl_info()''', 1)
src = src.replace(
'''            if addr.sc_id == ctlInfo.ctl_id {
                return fd
            }
        }
        return nil
    }''',
'''            if addr.sc_id == ctlInfo.ctl_id {
                return fd
            }
        }
        return nil
        #endif
    }''', 1)
src = src.replace(
'''        #if os(macOS)
        if case .started(let handle, _) = self.state {
            wgBumpSockets(handle)
        }
        #elseif os(iOS)''',
'''        #if os(macOS) || os(Linux)
        if case .started(let handle, _) = self.state {
            wgBumpSockets(handle)
        }
        #elseif os(iOS)''', 1)
open(path, "w").write(src)
print("patched WireGuardAdapter.swift for Linux")
PY
    fi

    # The NE extension (WireGuardNetworkExtension): missing imports that Apple supplies
    # transitively. PacketTunnelProvider uses WireGuardKit's WireGuardAdapter but imports
    # only Foundation/NetworkExtension/os; ErrorNotifier uses Foundation's FileManager but
    # imports only NetworkExtension. Add the explicit imports so they compile on Linux.
    local ptp="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardNetworkExtension/PacketTunnelProvider.swift"
    if [[ -f "$ptp" ]] && ! grep -q '^import WireGuardKit' "$ptp"; then
        echo "==> patching PacketTunnelProvider.swift to import WireGuardKit"
        python3 - "$ptp" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Foundation\nimport NetworkExtension\nimport os\n',
                  'import Foundation\nimport NetworkExtension\nimport os\nimport WireGuardKit\n', 1)
open(path, "w").write(src)
print("patched PacketTunnelProvider.swift import WireGuardKit")
PY
    fi
    local enotifier="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardNetworkExtension/ErrorNotifier.swift"
    if [[ -f "$enotifier" ]] && ! grep -q '^import Foundation' "$enotifier"; then
        echo "==> patching ErrorNotifier.swift to import Foundation"
        python3 - "$enotifier" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import NetworkExtension\n', 'import Foundation\nimport NetworkExtension\n', 1)
open(path, "w").write(src)
print("patched ErrorNotifier.swift import Foundation")
PY
    fi

    # TunnelListRow is dequeued by TunnelsListTableViewController, so it must conform
    # to QuillReusableView (init() requirement) with a `required init()` (the B-wall
    # protocol, like LogViewCell).
    local tlr="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/View/TunnelListRow.swift"
    if [[ -f "$tlr" ]] && ! grep -q 'QuillReusableView' "$tlr"; then
        echo "==> patching TunnelListRow.swift to conform to QuillReusableView (required init)"
        python3 - "$tlr" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('class TunnelListRow: NSView {', 'class TunnelListRow: NSView, QuillReusableView {', 1)
src = src.replace('    init() {', '    required init() {', 1)
open(path, "w").write(src)
print("patched TunnelListRow.swift for QuillReusableView")
PY
    fi

    # ConfTextColorTheme keys its color map by the highlighter C span types
    # (HighlightSection etc.), so it needs `import WireGuardHighlighterC`.
    local cct="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/View/ConfTextColorTheme.swift"
    if [[ -f "$cct" ]] && ! grep -q '^import WireGuardHighlighterC' "$cct"; then
        echo "==> patching ConfTextColorTheme.swift to import WireGuardHighlighterC"
        python3 - "$cct" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Cocoa\n', 'import Cocoa\nimport WireGuardHighlighterC\n', 1)
open(path, "w").write(src)
print("patched ConfTextColorTheme.swift to import WireGuardHighlighterC")
PY
    fi

    # ConfTextStorage (NSTextStorage subclass) runs the highlighter C
    # (highlight_config / highlight_type / HighlightEnd) over the wg-quick text, so
    # it needs `import WireGuardHighlighterC`.
    local cts="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/View/ConfTextStorage.swift"
    if [[ -f "$cts" ]] && ! grep -q '^import WireGuardHighlighterC' "$cts"; then
        echo "==> patching ConfTextStorage.swift to import WireGuardHighlighterC"
        python3 - "$cts" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Cocoa\n', 'import Cocoa\nimport WireGuardHighlighterC\n', 1)
open(path, "w").write(src)
print("patched ConfTextStorage.swift to import WireGuardHighlighterC")
PY
    fi

    # TunnelEditViewController references TunnelConfiguration/PrivateKey (WireGuardKit)
    # + the wg-quick parser splitToArray (QuillWireGuardUpstreamConfig), so it needs
    # both explicit imports.
    local tevc="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/ViewController/TunnelEditViewController.swift"
    if [[ -f "$tevc" ]] && ! grep -q '^import QuillWireGuardUpstreamConfig' "$tevc"; then
        echo "==> patching TunnelEditViewController.swift imports"
        python3 - "$tevc" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Cocoa\n', 'import Cocoa\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\n', 1)
open(path, "w").write(src)
print("patched TunnelEditViewController.swift to import WireGuardKit + QuillWireGuardUpstreamConfig")
PY
    fi

    # KeyValueRow + KeyValueImageRow (both : EditableKeyValueRow) are dequeued by
    # TunnelDetailTableViewController, so they conform to QuillReusableView with a
    # `required init()` (the B-wall protocol, like LogViewCell/TunnelListRow). The
    # base EditableKeyValueRow has `convenience init()` / `init(hasValueImage:)`
    # (distinct text), so the global `    init() {`→`    required init() {` replace
    # hits exactly the two concrete cells.
    local kvr="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/View/KeyValueRow.swift"
    if [[ -f "$kvr" ]] && ! grep -q 'QuillReusableView' "$kvr"; then
        echo "==> patching KeyValueRow.swift (KeyValueRow + KeyValueImageRow) for QuillReusableView"
        python3 - "$kvr" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('class KeyValueRow: EditableKeyValueRow {',
                  'class KeyValueRow: EditableKeyValueRow, QuillReusableView {', 1)
src = src.replace('class KeyValueImageRow: EditableKeyValueRow {',
                  'class KeyValueImageRow: EditableKeyValueRow, QuillReusableView {', 1)
src = src.replace('    init() {', '    required init() {')   # both concrete cells (exactly 2)
open(path, "w").write(src)
print("patched KeyValueRow.swift for QuillReusableView")
PY
    fi

    # ButtonRow is dequeued by TunnelDetailTableViewController → conform to
    # QuillReusableView (required init()). It already carries a lowered
    # class-body quillPerform (QuillSelectorDispatching), so guard on the
    # class-line conformance specifically (not a bare QuillReusableView grep).
    local btnrow="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/View/ButtonRow.swift"
    if [[ -f "$btnrow" ]] && ! grep -q 'class ButtonRow: NSView, QuillReusableView' "$btnrow"; then
        echo "==> patching ButtonRow.swift for QuillReusableView (required init)"
        python3 - "$btnrow" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('class ButtonRow: NSView {', 'class ButtonRow: NSView, QuillReusableView {', 1)
src = src.replace('    init() {', '    required init() {', 1)
open(path, "w").write(src)
print("patched ButtonRow.swift for QuillReusableView")
PY
    fi

    # TunnelDetailTableViewController references TunnelConfiguration (WireGuardKit).
    local tdvc="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/ViewController/TunnelDetailTableViewController.swift"
    if [[ -f "$tdvc" ]] && ! grep -q '^import WireGuardKit' "$tdvc"; then
        echo "==> patching TunnelDetailTableViewController.swift to import WireGuardKit"
        python3 - "$tdvc" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import Cocoa\n', 'import Cocoa\nimport WireGuardKit\n', 1)
open(path, "w").write(src)
print("patched TunnelDetailTableViewController.swift to import WireGuardKit")
PY
    fi

    # Break the SwiftPM modularity wall for the model layer: the wg-quick parser
    # methods (asWgQuickConfig / init(fromWgQuickConfig:)) live in the
    # QuillWireGuardUpstreamConfig target but are `internal`, so the conformance
    # target can't call them cross-module. Make them `public` (behaviour-neutral).
    local wgquick="$UPSTREAM_DIR/wireguard-apple/Sources/Shared/Model/TunnelConfiguration+WgQuickConfig.swift"
    if [[ -f "$wgquick" ]] && ! grep -q 'public convenience init(fromWgQuickConfig' "$wgquick"; then
        echo "==> patching TunnelConfiguration+WgQuickConfig.swift parser methods to public"
        python3 - "$wgquick" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('    convenience init(fromWgQuickConfig', '    public convenience init(fromWgQuickConfig', 1)
src = src.replace('    func asWgQuickConfig()', '    public func asWgQuickConfig()', 1)
open(path, "w").write(src)
print("patched WgQuickConfig parser methods to public")
PY
    fi

    # NETunnelProviderProtocol+Extension defines PacketTunnelProviderError + the
    # NETunnelProviderProtocol<->TunnelConfiguration bridge. For SwiftPM it needs:
    # Foundation (Bundle — the NE shadow doesn't re-export it), WireGuardKit
    # (TunnelConfiguration), QuillWireGuardUpstreamConfig (the now-public
    # asWgQuickConfig / fromWgQuickConfig), and Glibc on Linux (getuid).
    local neext="$UPSTREAM_DIR/wireguard-apple/Sources/Shared/Model/NETunnelProviderProtocol+Extension.swift"
    if [[ -f "$neext" ]] && ! grep -q '^import WireGuardKit' "$neext"; then
        echo "==> patching NETunnelProviderProtocol+Extension.swift imports"
        python3 - "$neext" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
src = src.replace('import NetworkExtension\n',
                  'import NetworkExtension\nimport Foundation\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\n#if canImport(Glibc)\nimport Glibc\n#endif\n', 1)
open(path, "w").write(src)
print("patched NETunnelProviderProtocol+Extension.swift imports")
PY
    fi

    # FileManager+Extension uses FileManager.containerURL(forSecurityApplicationGroupIdentifier:),
    # which swift-corelibs-foundation lacks (no app groups on Linux). QuillFoundation
    # supplies a (nil-returning) clone, so the file needs `import QuillFoundation`.
    local fmext="$UPSTREAM_DIR/wireguard-apple/Sources/Shared/FileManager+Extension.swift"
    if [[ -f "$fmext" ]] && ! grep -q '^import QuillFoundation' "$fmext"; then
        echo "==> patching FileManager+Extension.swift to import QuillFoundation"
        python3 - "$fmext" <<'PY'
import sys
path = sys.argv[1]
src = open(path).read()
patched = src.replace('import os\n', 'import os\nimport QuillFoundation\n', 1)
open(path, "w").write(patched)
print("patched FileManager+Extension.swift to import QuillFoundation")
PY
    fi

    # Model-layer core (TunnelsManager/TunnelContainer + the UAPI parser). Cross-
    # module visibility for SwiftPM: make splitToArray + the wg-quick parser's
    # ParserState/ParseError public (internal in QuillWireGuardUpstreamConfig),
    # and add imports to the two consumers. NOTE: these run AFTER the lowering
    # loop above, so the added imports survive (lowering re-serializes files and
    # would otherwise drop late-added imports).
    local strconv="$UPSTREAM_DIR/wireguard-apple/Sources/Shared/Model/String+ArrayConversion.swift"
    if [[ -f "$strconv" ]] && ! grep -q 'public func splitToArray' "$strconv"; then
        echo "==> patching String+ArrayConversion.swift: splitToArray -> public"
        python3 - "$strconv" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
open(path, "w").write(src.replace('    func splitToArray(', '    public func splitToArray('))
print("patched splitToArray -> public")
PY
    fi
    local wgq="$UPSTREAM_DIR/wireguard-apple/Sources/Shared/Model/TunnelConfiguration+WgQuickConfig.swift"
    if [[ -f "$wgq" ]] && ! grep -q 'public enum ParseError' "$wgq"; then
        echo "==> patching WgQuickConfig.swift: ParserState/ParseError -> public"
        python3 - "$wgq" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
src = src.replace('    enum ParserState {', '    public enum ParserState {', 1)
src = src.replace('    enum ParseError: Error {', '    public enum ParseError: Error {', 1)
open(path, "w").write(src)
print("patched ParserState/ParseError -> public")
PY
    fi
    local tmgr="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/Tunnel/TunnelsManager.swift"
    if [[ -f "$tmgr" ]] && ! grep -q '^import QuillFoundation' "$tmgr"; then
        echo "==> patching TunnelsManager.swift imports"
        python3 - "$tmgr" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
src = src.replace('import os\n', 'import os\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\nimport QuillFoundation\n#if canImport(Glibc)\nimport Glibc\n#endif\n', 1)
open(path, "w").write(src); print("patched TunnelsManager.swift imports")
PY
    fi
    local uapi="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/Tunnel/TunnelConfiguration+UapiConfig.swift"
    if [[ -f "$uapi" ]] && ! grep -q '^import WireGuardKit' "$uapi"; then
        echo "==> patching TunnelConfiguration+UapiConfig.swift imports"
        python3 - "$uapi" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
src = src.replace('import Foundation\n', 'import Foundation\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\n', 1)
open(path, "w").write(src); print("patched TunnelConfiguration+UapiConfig.swift imports")
PY
    fi

    # TunnelViewModel (config edit/validation VM) uses WireGuardKit types
    # (TunnelConfiguration/IPAddressRange/…) + splitToArray (now public in
    # QuillWireGuardUpstreamConfig). Add both imports.
    local tvm="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/TunnelViewModel.swift"
    if [[ -f "$tvm" ]] && ! grep -q '^import WireGuardKit' "$tvm"; then
        echo "==> patching TunnelViewModel.swift imports"
        python3 - "$tvm" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
src = src.replace('import Foundation\n', 'import Foundation\nimport WireGuardKit\nimport QuillWireGuardUpstreamConfig\n', 1)
open(path, "w").write(src); print("patched TunnelViewModel.swift imports")
PY
    fi

    # ErrorPresenter does NSAlert UI from nonisolated static funcs that touch
    # NSViewController.view, which the QuillAppKit shadow marks @MainActor. The
    # real presenter is effectively main-actor — annotate the protocol + the
    # macOS class @MainActor so it compiles under the shadow's concurrency.
    # (VCs are NSViewController subclasses => already implicitly @MainActor, so
    # only nonisolated helpers like this need the annotation.)
    local epp="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/ErrorPresenterProtocol.swift"
    if [[ -f "$epp" ]] && ! grep -q '@MainActor' "$epp"; then
        echo "==> patching ErrorPresenterProtocol.swift @MainActor"
        python3 - "$epp" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
open(path, "w").write(src.replace('protocol ErrorPresenterProtocol {', '@MainActor\nprotocol ErrorPresenterProtocol {', 1))
print("patched ErrorPresenterProtocol @MainActor")
PY
    fi
    local epm="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/ErrorPresenter.swift"
    if [[ -f "$epm" ]] && ! grep -q '@MainActor' "$epm"; then
        echo "==> patching ErrorPresenter.swift @MainActor"
        python3 - "$epm" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
open(path, "w").write(src.replace('class ErrorPresenter: ErrorPresenterProtocol {', '@MainActor\nclass ErrorPresenter: ErrorPresenterProtocol {', 1))
print("patched ErrorPresenter @MainActor")
PY
    fi

    # The QuillAppKit shadow's NSResponder declares `open func copy(_:)` (the
    # Telegram pasteboard surface), so LogViewController's responder-chain
    # `copy(_:)` is an override on Linux but not on real AppKit. Split the
    # declaration per platform; the original body moves into a helper.
    local lvc="$UPSTREAM_DIR/wireguard-apple/Sources/WireGuardApp/UI/macOS/ViewController/LogViewController.swift"
    if [[ -f "$lvc" ]] && ! grep -q 'quillCopySelectedLogLines' "$lvc"; then
        echo "==> patching LogViewController.swift copy(_:) override split"
        python3 - "$lvc" <<'PY'
import sys
path = sys.argv[1]; src = open(path).read()
# The Linux lowering strips @objc before this patch runs on Linux fetches,
# so match either form of the signature.
needles = [
    '    @objc func copy(_ sender: Any?) {\n',
    '    func copy(_ sender: Any?) {\n',
]
needle = next((n for n in needles if n in src), None)
assert needle is not None, "LogViewController copy(_:) signature not found"
replacement = (
    '    #if os(Linux)\n'
    '    // NSResponder.copy(_:) is nonisolated in the QuillAppKit shadow; the\n'
    '    // responder chain invokes it on the main thread, so bridge into the\n'
    '    // MainActor-isolated view-controller helper.\n'
    '    override func copy(_ sender: Any?) {\n'
    '        MainActor.assumeIsolated { quillCopySelectedLogLines(sender) }\n'
    '    }\n'
    '    #else\n'
    + needle +
    '        quillCopySelectedLogLines(sender)\n'
    '    }\n'
    '    #endif\n'
    '    private func quillCopySelectedLogLines(_ sender: Any?) {\n'
)
open(path, "w").write(src.replace(needle, replacement, 1))
print("patched LogViewController copy(_:) override split")
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

    # Env: StreamWatcher uses URLSessionWebSocketTask (FoundationNetworking on
    # Linux); Router uses UIImage/UIApplication (UIKit — on iOS these arrive
    # transitively via SwiftUI, but the Linux SwiftUI shim does not re-export
    # UIKit). Inject the missing imports after the first `import Foundation`.
    # canImport gates keep the Apple build unaffected. Idempotent.
    local envdir="$UPSTREAM_DIR/icecubes/Packages/Env/Sources/Env"
    if [[ -d "$envdir" ]]; then
        echo "==> patching IceCubes Env for the Linux FoundationNetworking / UIKit imports"
        python3 - "$envdir" <<'PY'
import sys, os, glob

directory = sys.argv[1]
fn_block = (
    "import Foundation\n"
    "#if canImport(FoundationNetworking)\n"
    "import FoundationNetworking\n"
    "#endif"
)
uikit_block = (
    "#if canImport(UIKit)\n"
    "import UIKit\n"
    "#endif"
)
for path in sorted(glob.glob(os.path.join(directory, "*.swift"))):
    src = open(path).read()
    needs_uikit = ("UIImage" in src or "UIApplication" in src) and "import UIKit" not in src
    fn_done = "FoundationNetworking" in src
    lines = src.split("\n")
    out = []
    inserted_uikit = False
    for line in lines:
        stripped = line.strip()
        if stripped == "import OSLog":
            # No OSLog module on Linux; the repo `os` shim provides Logger.
            # (An `@_exported import os` OSLog shim retains os_log symbols that
            # break swift-syntax's link — see #305 — so rewrite, don't shim.)
            out.append("import os")
        elif stripped == "import Foundation" and not fn_done:
            out.append(fn_block)
            fn_done = True
            if needs_uikit:
                out.append(uikit_block)
                inserted_uikit = True
        else:
            out.append(line)
    new = "\n".join(out)
    if new != src:
        open(path, "w").write(new)
        print("patched", os.path.basename(path))
PY
    fi

    # Keep fetched IceCubes source disposable: Swift 6 Linux currently times
    # out on a few very large SwiftUI builder/modifier expressions in StatusKit.
    # This patch only splits those expressions into equivalent AnyView chunks
    # in the generated checkout. The canonical upstream source remains clean.
    apply_generated_source_patch \
        "IceCubes StatusKit Linux type-check" \
        "$UPSTREAM_DIR/icecubes" \
        "$ROOT_DIR/scripts/patches/icecubes-statuskit-linux-typecheck.patch"

    local accountdir="$UPSTREAM_DIR/icecubes/Packages/Account/Sources/Account"
    if [[ -d "$accountdir" ]]; then
        echo "==> lowering IceCubes Account Linux compatibility syntax"
        python3 - "$accountdir" <<'PY'
import glob
import os
import sys

directory = sys.argv[1]
for path in sorted(glob.glob(os.path.join(directory, "**", "*.swift"), recursive=True)):
    src = open(path).read()
    lowered = src.replace("import OSLog", "import os")
    if lowered != src:
        open(path, "w").write(lowered)
        print("patched", os.path.relpath(path, directory))
PY
        "$ROOT_DIR/scripts/lower-objc-interop-for-linux.sh" "$accountdir"
    fi

    local statusdir="$UPSTREAM_DIR/icecubes/Packages/StatusKit/Sources/StatusKit"
    if [[ -d "$statusdir" ]]; then
        echo "==> lowering IceCubes StatusKit Objective-C interop syntax for Linux"
        "$ROOT_DIR/scripts/lower-objc-interop-for-linux.sh" "$statusdir"
    fi
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

    # ReachabilityManager builds an OWSURLSession with a background
    # URLSessionConfiguration. swift-corelibs-foundation marks
    # URLSessionConfiguration.background(withIdentifier:) @available(unavailable)
    # on non-Darwin (background transfers need the OS daemon). Linux-only build,
    # so use .default -- a reachability probe needs no background semantics, and
    # no background-only properties are set on this config, so the swap is total.
    local reach="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Network/ReachabilityManager.swift"
    if [[ -f "$reach" ]] && grep -q 'background(withIdentifier: "SSKReachabilityManagerImpl")' "$reach"; then
        echo "==> patching signal-ios ReachabilityManager.swift background(withIdentifier:) -> .default"
        python3 - "$reach" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
open(path, "w").write(s.replace('.background(withIdentifier: "SSKReachabilityManagerImpl")', '.default'))
PY
    fi

    # ProxiedContentDownloader writes a downloaded asset via
    #   assetData.write(to: NSURL.fileURL(withPath: filePath), options: .atomicWrite)
    # swift-corelibs-foundation has no NSURL.fileURL(withPath:) (only the
    # withPathComponents: [String] form, which also returns URL?), and
    # Data.WritingOptions has no .atomicWrite (the modern spelling is .atomic).
    # Rewrite to URL(fileURLWithPath:) (non-optional, present on corelibs) + .atomic
    # -- same semantics, Linux-only build.
    local proxied="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Network/ProxiedContentDownloader.swift"
    if [[ -f "$proxied" ]] && grep -q 'NSURL.fileURL(withPath:' "$proxied"; then
        echo "==> patching signal-ios ProxiedContentDownloader.swift NSURL.fileURL/atomicWrite"
        python3 - "$proxied" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
s = s.replace("NSURL.fileURL(withPath: filePath)", "URL(fileURLWithPath: filePath)")
s = s.replace(", options: .atomicWrite)", ", options: .atomic)")
open(path, "w").write(s)
PY
    fi

    # GRDBDatabaseStorageAdapter sets two GRDB Configuration knobs that the GRDB
    # version vendored here has removed/auto-managed: `.defaultTransactionKind`
    # ("now automatically managed") and `.automaticMemoryManagement` (no member).
    # Drop both assignments (GRDB uses its managed defaults). Linux-only build;
    # behaviour is GRDB's current default, which is fine for the single-process DB.
    local gdsa="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Storage/Database/GRDBDatabaseStorageAdapter.swift"
    if [[ -f "$gdsa" ]] && grep -q 'configuration.automaticMemoryManagement' "$gdsa"; then
        echo "==> patching signal-ios GRDBDatabaseStorageAdapter.swift GRDB Configuration drift"
        python3 - "$gdsa" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
s = s.replace("        configuration.defaultTransactionKind = .immediate\n", "")
s = s.replace("        configuration.automaticMemoryManagement = false\n", "")
open(path, "w").write(s)
PY
    fi

    # Signal's Yap/GRDB bridge expects the in-memory SDSRecord delegate to learn
    # the inserted GRDB row id immediately after anyInsert(...). SQLite on Linux
    # successfully inserts the row, but without this callback outgoing messages
    # still see `sqliteRowId == nil` and the real send pipeline aborts with
    # "Failed to insert message!". Match the update path by propagating GRDB's
    # last inserted row id from the Linux-patched disposable checkout.
    local sds="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Storage/Database/SDSRecord.swift"
    if [[ -f "$sds" ]] && ! grep -q 'delegate?.updateRowId(transaction.database.lastInsertedRowID)' "$sds"; then
        echo "==> patching signal-ios SDSRecord.swift insert row-id propagation"
        python3 - "$sds" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
needle = "        failIfThrows {\n            try self.insert(transaction.database)\n        }\n"
replacement = "        failIfThrows {\n            try self.insert(transaction.database)\n            delegate?.updateRowId(transaction.database.lastInsertedRowID)\n        }\n"
if needle not in s:
    raise SystemExit("SDSRecord.sdsInsert shape changed")
open(path, "w").write(s.replace(needle, replacement, 1))
PY
    fi

    # swift-corelibs NSAttributedString/NSMutableAttributedString have no
    # parameterless init() (NSAttributedString() binds to init?(coder:),
    # NSMutableAttributedString() needs init(string:)). The extension-override
    # route is illegal (init() is NSObject's, not overridable from an extension),
    # so rewrite the empty constructors to the equivalent (string: "") form across
    # SSK. Idempotent (the rewritten form no longer matches "()"). Skip QuillPort
    # symlinks so the committed port sources aren't touched. Linux-only build.
    echo "==> patching signal-ios empty NS(Mutable)AttributedString() constructors"
    python3 - "$UPSTREAM_DIR/signal-ios/SignalServiceKit" <<'PY'
import sys, os
root = sys.argv[1]
n = 0
for dp, _dirs, files in os.walk(root):
    if "/QuillPort" in dp:
        continue
    for f in files:
        if not f.endswith(".swift"):
            continue
        path = os.path.join(dp, f)
        if os.path.islink(path):
            continue
        src = open(path, encoding="utf-8").read()
        out = src.replace("NSMutableAttributedString()", 'NSMutableAttributedString(string: "")')
        out = out.replace("NSAttributedString()", 'NSAttributedString(string: "")')
        if out != src:
            open(path, "w", encoding="utf-8").write(out)
            n += 1
print(f"  rewrote NS(Mutable)AttributedString() in {n} files")
PY

    # AppVersion logs the locale's country via (locale as NSLocale).countryCode,
    # but swift-corelibs marks NSLocale.countryCode `internal` (Apple's is public)
    # -> "inaccessible due to internal protection level". Use the public Swift
    # Locale.regionCode (the file already uses locale.languageCode). Linux-only.
    local appver="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Util/AppVersion.swift"
    if [[ -f "$appver" ]] && grep -q '(locale as NSLocale).countryCode' "$appver"; then
        echo "==> patching signal-ios AppVersion.swift NSLocale.countryCode -> Locale.regionCode"
        python3 - "$appver" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
open(path, "w").write(s.replace("(locale as NSLocale).countryCode", "locale.regionCode"))
PY
    fi

    # EditableMessageBodyTextStorage: NSTextStorage calls super.init() in its
    # init(db:). swift-corelibs has no parameterless NSTextStorage/NSMutableAttributedString
    # init (the chain's designated init is init(string:)) -> "missing argument
    # 'string'". Rewrite that one super.init() to super.init(string: "") (unique
    # by the preceding `self.db = db`). Linux-only build.
    local emb="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Messages/BodyRanges/EditableMessageBody.swift"
    if [[ -f "$emb" ]] && grep -q 'self.db = db' "$emb"; then
        echo "==> patching signal-ios EditableMessageBody.swift super.init() -> super.init(string:)"
        python3 - "$emb" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
s = s.replace("self.db = db\n        super.init()", 'self.db = db\n        super.init(string: "")')
open(path, "w").write(s)
PY
    fi

    # swift-corelibs has no URL<->CFURL bridge, so `someURL as CFURL` ("URL is not
    # convertible to CFURL") fails. The receivers are our own shims now changed to
    # take URL (CGImageSourceCreateWithURL / CFNetworkCopyProxiesForURL /
    # AudioServicesCreateSystemSoundID / CGImageDestinationCreateWithURL); drop the
    # casts at their call sites.
    echo "==> patching signal-ios drop `as CFURL` at URL-shim call sites"
    python3 - "$UPSTREAM_DIR/signal-ios/SignalServiceKit" <<'PY'
import sys, os
root = sys.argv[1]
subs = [
    ("CGImageSourceCreateWithURL(fileUrl as CFURL", "CGImageSourceCreateWithURL(fileUrl"),
    ("CGImageSourceCreateWithURL(fileUrlForSpritesheet() as CFURL", "CGImageSourceCreateWithURL(fileUrlForSpritesheet()"),
    ("CFNetworkCopyProxiesForURL(chatURL as CFURL", "CFNetworkCopyProxiesForURL(chatURL"),
    ("AudioServicesCreateSystemSoundID(url as CFURL", "AudioServicesCreateSystemSoundID(url"),
    ("CGImageDestinationCreateWithURL(destinationUrl as CFURL", "CGImageDestinationCreateWithURL(destinationUrl"),
    # The CGImageDestination type-id arg: swift-corelibs has no String<->CFString bridge,
    # so `UTType.png.identifier as CFString` fails; the ImageIO shim takes String -> drop it.
    ("UTType.png.identifier as CFString", "UTType.png.identifier"),
    # BadgeAssets: `[kCGImageSourceShouldCache: kCFBooleanFalse]` is [String: CFBoolean?]
    # which doesn't coerce to CFDictionary on swift-corelibs. The dict is only passed to
    # the inert CGImageSourceCreateImageAtIndex (returns nil on Linux), so nil is
    # equivalent. (Two identical occurrences.)
    ("[kCGImageSourceShouldCache: kCFBooleanFalse] as CFDictionary", "nil as CFDictionary?"),
    # AvatarBuilder: a `[cgColor, cgColor] as CFArray` for a CGGradient. swift-corelibs
    # has no [Any?]<->CFArray bridge, and our CGGradient init already takes `colors: Any?`,
    # so drop the coercion and let the array pass through directly. (Unique occurrence.)
    ("] as CFArray", "]"),
    # CGImageSourceCreateWithData now takes Data (not CFData) -- swift-corelibs has no
    # Data<->CFData bridge. Drop `as CFData` at its call sites (QuotedReplyManager sticker
    # parsing, OWSImageSource). The Security SecCertificateCreateWithData(... as CFData)
    # site is intentionally left untouched.
    ("stickerData as CFData", "stickerData"),
    ("CGImageSourceCreateWithData(self.rawValue as CFData", "CGImageSourceCreateWithData(self.rawValue"),
    # QuotedReplyManager sticker options: [String: Bool] doesn't coerce to CFDictionary on
    # swift-corelibs; the inert CGImageSourceCreateWithData ignores options, so nil suffices.
    ("[kCGImageSourceShouldCache: false] as CFDictionary", "nil as CFDictionary?"),
    # DebugLogger: the CF URL key constant kCFURLContentModificationDateKey is absent on
    # swift-corelibs; use the native URLResourceKey case (the call wants [URLResourceKey]).
    ("kCFURLContentModificationDateKey as URLResourceKey", "URLResourceKey.contentModificationDateKey"),
    # DebugLogger: swift-corelibs ProcessInfo has no public init -> use the shared instance.
    ("ProcessInfo()", "ProcessInfo.processInfo"),
    # SignalAccount.shouldUseNicknames probes PersonNameComponentsFormatter's .short style,
    # which is unavailable on swift-corelibs Foundation (no public init / no .style). On
    # Apple .short yields the nickname (so SSK uses nicknames); return that result directly.
    ('''        var nameComponents = PersonNameComponents()
        nameComponents.givenName = "givenName"
        nameComponents.nickname = "nickname"
        let nameFormatter = PersonNameComponentsFormatter()
        nameFormatter.style = .short
        return nameFormatter.string(from: nameComponents) == "nickname"''',
     '''        // PersonNameComponentsFormatter is unavailable on swift-corelibs Foundation.
        // On Apple, .short yields the nickname, so SSK uses nicknames; match that.
        return true'''),
    # UIImage+Attachment / OWSImageSource image-metadata: swift-corelibs CFString isn't
    # Hashable (so [CFString: Any] can't be a dict) and there is no Dictionary<->CFDictionary
    # bridge. Use a native [String: Any] dict and drop the `as CFDictionary` casts; the
    # ImageIO shim's CGImageSourceCopyPropertiesAtIndex now takes Any? and returns [String: Any]?.
    ("[CFString: Any]", "[String: Any]"),
    ("options as CFDictionary", "options"),
    # OutageDetection resolves uptime.signal.org via CFHostCreateWithName. swift-corelibs
    # has no String<->CFString bridge, so `"uptime.signal.org" as CFString` fails; the
    # CFNetwork shim's CFHostCreateWithName takes String -> drop the cast. (The shim also
    # no longer redeclares CFStreamError, so CoreFoundation's is used by both sides.)
    ('"uptime.signal.org" as CFString', '"uptime.signal.org"'),
    # Math+OWS.fuzzyEquals (in `extension CGFloat`): unqualified `abs(self - other)`
    # resolves to a static member on swift-corelibs ("static member 'abs' cannot be used
    # on instance of type 'CGFloat'"). Use FloatingPoint.magnitude (the absolute value),
    # which is unambiguous and identical for CGFloat.
    ("return abs(self - other) < tolerance", "return (self - other).magnitude < tolerance"),
    # LinkValidator.firstLinkPreviewURL: NSTextCheckingResult.url is absent on
    # swift-corelibs ("no member 'url'"). Reconstruct the URL from the matched
    # substring (the link text) via the String<->NSString bridge (which corelibs
    # supports, unlike the CF bridges). Scheme-less bare-domain matches yield a
    # scheme-less URL that isPermittedLinkPreviewUrl already rejects, so behavior
    # is preserved for the https previews SSK actually uses.
    ("guard let parsedUrl = match.url else { return }",
     "guard let parsedUrl = URL(string: (entireMessage.text as NSString).substring(with: match.range)) else { return }"),
    # KeyValueStore.getObject(ofClasses:): NSKeyedUnarchiver.unarchivedObject(ofClasses:)
    # expects [AnyClass] but `classes` is typed [any NSSecureCoding.Type]. On Apple the
    # ObjC metatypes bridge implicitly; swift-corelibs requires an explicit cast. Every
    # NSSecureCoding-conforming archived type is a class, so map each to AnyClass.
    ("NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: $0)",
     "NSKeyedUnarchiver.unarchivedObject(ofClasses: classes.compactMap { $0 as? AnyClass }, from: $0)"),
    # OWSFileSystem.freeSpaceInBytes: the URLResourceKey
    # .volumeAvailableCapacityForImportantUsageKey (and its resource-value property) are
    # absent on swift-corelibs. Fall back to .volumeAvailableCapacityKey /
    # .volumeAvailableCapacity (total available, Int) -- corelibs has these. The guard
    # (>= 0) and UInt64(result) conversion are valid for Int too.
    ("[.volumeAvailableCapacityForImportantUsageKey]", "[.volumeAvailableCapacityKey]"),
    ("resourceValues.volumeAvailableCapacityForImportantUsage", "resourceValues.volumeAvailableCapacity"),
    # OWSFormat: PersonNameComponentsFormatter.localizedString(from:style:options:) is
    # unavailable on swift-corelibs-foundation. Build a simplified display name from the
    # components (given + family) -- HONEST: style nuance (.short/.abbreviated) is lost.
    ('''let value = PersonNameComponentsFormatter.localizedString(
            from: nameComponents,
            style: style,
            options: [],
        )''',
     '''let value = [nameComponents.givenName, nameComponents.familyName].compactMap { $0 }.joined(separator: " ")'''),
    # GRDBSchemaMigrator: expose a public schema-only migration entry that calls
    # the private _runIncrementalMigrations, so the headless smoke exe can run
    # Signal's full schema migration on a plain DatabaseWriter (no SDSDatabaseStorage).
    ('''        return try runIncrementalMigrations(databaseStorage: databaseStorage, runDataMigrations: runDataMigrations)
    }
''',
     '''        return try runIncrementalMigrations(databaseStorage: databaseStorage, runDataMigrations: runDataMigrations)
    }

    public static func quillRunSchemaMigrations(on databaseWriter: some DatabaseWriter) throws {
        _ = try _runIncrementalMigrations(databaseWriter: databaseWriter, runDataMigrations: false)
    }
'''),
    # Bundle.bundleIdPrefix owsFailDebug()s (fatal in debug) when the Info.plist key
    # OWSBundleIDPrefix is missing. A headless QuillOS exe has no Info.plist, and the
    # default "org.whispersystems" is correct -- gate the failDebug out on Linux.
    ('''        } else {
            owsFailDebug("Missing Info.plist entry for OWSBundleIDPrefix")
            return "org.whispersystems"
        }''',
     '''        } else {
            #if !os(Linux)
            owsFailDebug("Missing Info.plist entry for OWSBundleIDPrefix")
            #endif
            // Headless QuillOS has no Info.plist; the default prefix is correct.
            return "org.whispersystems"
        }'''),
    # AttachmentValidationBackfillMigrator.Filter.operator: existential `any
    # SQLSpecificExpressible` can't conform to itself on Swift 6, so the generic GRDB
    # `==` won't coerce. The sole caller passes a concrete Column -> narrow the lhs to
    # Column so `==` instantiates with T==Column (which conforms).
    ('''        let `operator`: (_ lhs: SQLSpecificExpressible, _ rhs: SQLExpressible?) -> SQLExpression''',
     '''        // QuillOS/Linux Swift 6: the existential `any SQLSpecificExpressible` cannot
        // conform to itself, so passing the generic GRDB `==` to a closure typed with an
        // existential lhs is rejected (`type 'any SQLSpecificExpressible' cannot conform
        // to 'SQLSpecificExpressible'`). The sole caller passes a concrete `Column`
        // (line ~318: `columnFilter.operator(Column(columnFilter.column), value)`), so
        // narrow the lhs to `Column`; `==` then instantiates with T == Column, which
        // conforms. Faithful (all column filters use a Column), macOS-unaffected.
        let `operator`: (_ lhs: Column, _ rhs: SQLExpressible?) -> SQLExpression'''),
    # Timer target/selector cluster: swift-corelibs Timer has only block-based
    # init/scheduledTimer + no perform/selector dispatch. Gate each site #if os(Linux)
    # to the block-based timer (NSTimer+OWS proxy is inert -- ObjC-only/dead on Linux).
    ('''        _ = target.perform(selector, with: timer)''',
     '''        #if os(Linux)
        // ObjC selector dispatch (perform) is unavailable on swift-corelibs (no ObjC
        // runtime). weakScheduledTimer/weakTimer are @available(swift, obsoleted: 1) --
        // callable only from ObjC, which is excluded on Linux -- so this proxy is never
        // exercised on QuillOS. Inert.
        _ = (target, selector, timer)
        #else
        _ = target.perform(selector, with: timer)
        #endif'''),
    ('''        return Timer.scheduledTimer(timeInterval: timeInterval, target: proxy, selector: Selector("timerFired(_:)"), userInfo: userInfo, repeats: repeats)''',
     '''        #if os(Linux)
        // corelibs Timer has no target/selector overload; use the block-based timer.
        // proxy is strongly captured to keep it alive (the real Timer would retain it).
        return Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: repeats) { timer in proxy.timerFired(timer) }
        #else
        return Timer.scheduledTimer(timeInterval: timeInterval, target: proxy, selector: Selector("timerFired(_:)"), userInfo: userInfo, repeats: repeats)
        #endif'''),
    ('''        return Timer(timeInterval: timeInterval, target: proxy, selector: Selector("timerFired(_:)"), userInfo: userInfo, repeats: repeats)''',
     '''        #if os(Linux)
        return Timer(timeInterval: timeInterval, repeats: repeats) { timer in proxy.timerFired(timer) }
        #else
        return Timer(timeInterval: timeInterval, target: proxy, selector: Selector("timerFired(_:)"), userInfo: userInfo, repeats: repeats)
        #endif'''),
    ('''        self.timer = Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: Selector("fire"),
            userInfo: userInfo,
            repeats: repeats,
        )''',
     '''        #if os(Linux)
        // swift-corelibs Timer has no target/selector overload (no ObjC dispatch); use
        // the block-based scheduledTimer. self is strongly captured so the timer keeps
        // this WeakTimer alive (matching the original, where the Timer retained the
        // target); the weak `target` check in fire(timer:) is preserved.
        self.timer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: repeats) { timer in
            self.fire(timer: timer)
        }
        #else
        self.timer = Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: Selector("fire"),
            userInfo: userInfo,
            repeats: repeats,
        )
        #endif'''),
    ('''        let timer = Timer(
            timeInterval: StorageServiceManagerImpl.backupDebounceInterval,
            target: self,
            selector: Selector("backupTimerFired(_:)"),
            userInfo: nil,
            repeats: false,
        )''',
     '''        #if os(Linux)
        // corelibs Timer has no target/selector overload; use the block-based timer.
        // self is strongly captured to match the original (Timer retained target: self).
        let timer = Timer(timeInterval: StorageServiceManagerImpl.backupDebounceInterval, repeats: false) { timer in
            self.backupTimerFired(timer)
        }
        #else
        let timer = Timer(
            timeInterval: StorageServiceManagerImpl.backupDebounceInterval,
            target: self,
            selector: Selector("backupTimerFired(_:)"),
            userInfo: nil,
            repeats: false,
        )
        #endif'''),
    # TextCheckingDataItem transit branch: NSTextCheckingKey.airline/.flight are
    # internal on swift-corelibs and data detection is unavailable, so the transit
    # URL-building block is dead on Linux. Gate it #if !os(Linux).
    ('''                if matchUrl == nil {
                    guard
                        let components = match.components,
                        let airline = components[.airline]?.nilIfEmpty,
                        let flight = components[.flight]?.nilIfEmpty
                    else {
                        Logger.warn("Missing components.")
                        return nil
                    }
                    let query = airline + " " + flight
                    guard let urlEncodedQuery = query.encodeURIComponent else {
                        owsFailDebug("Could not URL encode query.")
                        return nil
                    }
                    let urlString = "https://www.google.com/?q=" + urlEncodedQuery
                    guard let transitUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build transitUrl.")
                        return nil
                    }
                    customUrl = transitUrl
                }''',
     '''                #if os(Linux)
                // Transit-info data detection is unavailable on swift-corelibs
                // Foundation: NSDataDetector yields no matches and the .airline/.flight
                // NSTextCheckingKeys are internal there. This branch is dead on Linux,
                // so the lookup URL is skipped; `guard let url = customUrl ?? matchUrl`
                // below then drops the (absent) match. Transit data items are a
                // deferred display feature on QuillOS.
                _ = matchUrl
                #else
                if matchUrl == nil {
                    guard
                        let components = match.components,
                        let airline = components[.airline]?.nilIfEmpty,
                        let flight = components[.flight]?.nilIfEmpty
                    else {
                        Logger.warn("Missing components.")
                        return nil
                    }
                    let query = airline + " " + flight
                    guard let urlEncodedQuery = query.encodeURIComponent else {
                        owsFailDebug("Could not URL encode query.")
                        return nil
                    }
                    let urlString = "https://www.google.com/?q=" + urlEncodedQuery
                    guard let transitUrl = URL(string: urlString) else {
                        owsFailDebug("Couldn't build transitUrl.")
                        return nil
                    }
                    customUrl = transitUrl
                }
                #endif'''),
    # Contact.fullName: PersonNameComponentsFormatter.localizedString(from:style:) is
    # unavailable on swift-corelibs-foundation. Join given+family (the .default style).
    ('''        return PersonNameComponentsFormatter.localizedString(
            from: components,
            style: .default,
        )''',
     '''        // QuillOS/Linux: swift-corelibs-foundation has no PersonNameComponentsFormatter
        // formatting (localizedString is @available(*, unavailable)). The .default style
        // produces "given family", so join the available components to stay faithful.
        return [components.givenName, components.familyName].compactMap { $0 }.joined(separator: " ")'''),
    # OWSUrlSession server-trust delegate: NSURLAuthenticationMethodServerTrust,
    # protectionSpace.serverTrust and URLCredential(trust:) are unavailable on
    # swift-corelibs-foundation. Gate the Darwin cert-pinning block #if !os(Linux);
    # on Linux corelibs URLSession does its own system-trust validation.
    ('''        if
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        {
            if endpoint.securityPolicy.evaluate(serverTrust: serverTrust, domain: challenge.protectionSpace.host) {
                credential = URLCredential(trust: serverTrust)
                disposition = .useCredential
            } else {
                disposition = .cancelAuthenticationChallenge
            }
        } else {
            disposition = .performDefaultHandling
        }''',
     '''        #if os(Linux)
        // Custom server-trust pinning relies on the Darwin Security framework and
        // URLAuthenticationChallenge.serverTrust, which swift-corelibs-foundation
        // marks unavailable. corelibs URLSession performs standard system-trust TLS
        // validation itself, so we defer to default handling here. (Cert pinning is
        // a hardening feature; deferred on QuillOS.)
        disposition = .performDefaultHandling
        #else
        if
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        {
            if endpoint.securityPolicy.evaluate(serverTrust: serverTrust, domain: challenge.protectionSpace.host) {
                credential = URLCredential(trust: serverTrust)
                disposition = .useCredential
            } else {
                disposition = .cancelAuthenticationChallenge
            }
        } else {
            disposition = .performDefaultHandling
        }
        #endif'''),
    # HTTPResponse.parseStringEncoding: no String<->CFString bridge on corelibs.
    # Map common IANA charset names directly to String.Encoding.
    ('''        let encoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
        guard encoding != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))''',
     '''        // swift-corelibs-foundation lacks the String<->CFString toll-free bridge,
        // so map the common IANA charset names directly to String.Encoding.
        switch encodingName.lowercased() {
        case "utf-8": return .utf8
        case "utf-16": return .utf16
        case "iso-8859-1", "latin1": return .isoLatin1
        case "us-ascii", "ascii": return .ascii
        case "windows-1252": return .windowsCP1252
        default: return .utf8
        }'''),
]
n = 0
for dp, _d, fs in os.walk(root):
    if "/QuillPort" in dp:
        continue
    for f in fs:
        if not f.endswith(".swift"):
            continue
        p = os.path.join(dp, f)
        if os.path.islink(p):
            continue
        s = open(p, encoding="utf-8").read()
        o = s
        for a, b in subs:
            s = s.replace(a, b)
        if s != o:
            open(p, "w", encoding="utf-8").write(s)
            n += 1
print("  dropped as-CFURL at", n, "files")
PY

    # MessageProcessingPipelineStage was an `@objc protocol` with `optional func`
    # members on Apple. The lowering pass strips `@objc` (-> plain `public
    # protocol`), which makes `optional` invalid ("'optional' can only be applied
    # to members of an '@objc' protocol"). Model optionality the Swift-native way:
    # drop `optional`, add a default no-op extension, and drop the `?` optional-
    # chaining at the two call sites. Conformers implement only the Resume method,
    # so the Suspend default impl is load-bearing.
    local mps="$UPSTREAM_DIR/signal-ios/SignalServiceKit/Messages/MessagePipelineSupervisor.swift"
    if [[ -f "$mps" ]] && grep -q 'optional func supervisorDid' "$mps"; then
        echo "==> patching signal-ios MessagePipelineSupervisor.swift optional-protocol lowering"
        python3 - "$mps" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
s = s.replace(
    "    optional func supervisorDidSuspendMessageProcessing(_ supervisor: MessagePipelineSupervisor)",
    "    func supervisorDidSuspendMessageProcessing(_ supervisor: MessagePipelineSupervisor)")
s = s.replace(
    "    optional func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor)\n}",
    "    func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor)\n}\n\n"
    "public extension MessageProcessingPipelineStage {\n"
    "    // @objc `optional func` -> Swift-native default no-op impls.\n"
    "    func supervisorDidSuspendMessageProcessing(_ supervisor: MessagePipelineSupervisor) {}\n"
    "    func supervisorDidResumeMessageProcessing(_ supervisor: MessagePipelineSupervisor) {}\n"
    "}")
s = s.replace("supervisorDidSuspendMessageProcessing?(self)",
              "supervisorDidSuspendMessageProcessing(self)")
s = s.replace("supervisorDidResumeMessageProcessing?(self)",
              "supervisorDidResumeMessageProcessing(self)")
open(path, "w").write(s)
print("patched MessagePipelineSupervisor.swift optional-protocol lowering")
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

patch_netnewswire() {
    local articles_table="$UPSTREAM_DIR/netnewswire/Modules/ArticlesDatabase/Sources/ArticlesDatabase/ArticlesTable.swift"
    if [[ ! -f "$articles_table" ]]; then
        echo "==> netnewswire ArticlesTable.swift not found; skipping Linux lowering"
    elif grep -q "QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch" "$articles_table"; then
        echo "==> netnewswire ArticlesTable.swift already patched for Linux"
    else
        echo "==> patching netnewswire ArticlesTable.swift for Linux selector/word-enumeration lowering"
        python3 - "$articles_table" <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()

old_observer = '		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)'
new_observer = '''#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		_ = NotificationCenter.default.addObserver(forName: .lowMemory, object: nil, queue: nil) { [weak self] _ in
			self?.emptyCaches()
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)
#endif'''
if old_observer not in src:
    raise SystemExit("ArticlesTable observer pattern not found")
src = src.replace(old_observer, new_observer, 1)

old_method = '''	@objc func handleLowMemory(_ notification: Notification) {
		emptyCaches()
	}
'''
new_method = '''#if !os(Linux)
	@objc func handleLowMemory(_ notification: Notification) {
		emptyCaches()
	}
#endif
'''
if old_method not in src:
    raise SystemExit("ArticlesTable low-memory selector method not found")
src = src.replace(old_method, new_method, 1)

old_search = '''	func sqliteSearchString(with searchString: String) -> String {
		var s = ""
		searchString.enumerateSubstrings(in: searchString.startIndex..<searchString.endIndex, options: .byWords) { (word, _, _, _) in
			guard let word else {
				return
			}
			s += word
			if word != "AND" && word != "OR" {
				s += "*"
			}
			s += " "
		}
		return s
	}
'''
new_search = '''	func sqliteSearchString(with searchString: String) -> String {
		var s = ""
#if os(Linux)
		let words = searchString.split { character in
			!(character.isLetter || character.isNumber || character == "_")
		}
		for wordSubstring in words {
			let word = String(wordSubstring)
			s += word
			if word != "AND" && word != "OR" {
				s += "*"
			}
			s += " "
		}
#else
		searchString.enumerateSubstrings(in: searchString.startIndex..<searchString.endIndex, options: .byWords) { (word, _, _, _) in
			guard let word else {
				return
			}
			s += word
			if word != "AND" && word != "OR" {
				s += "*"
			}
			s += " "
		}
#endif
		return s
	}
'''
if old_search not in src:
    raise SystemExit("ArticlesTable search tokenizer pattern not found")
src = src.replace(old_search, new_search, 1)

open(path, "w").write(src)
print("patched NetNewsWire ArticlesTable.swift selector + word-tokenizer lowering")
PY
    fi

    local error_log_database="$UPSTREAM_DIR/netnewswire/Modules/ErrorLog/Sources/ErrorLog/ErrorLogDatabase.swift"
    if [[ ! -f "$error_log_database" ]]; then
        echo "==> netnewswire ErrorLogDatabase.swift not found; skipping Linux lowering"
    elif grep -q "QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch" "$error_log_database"; then
        echo "==> netnewswire ErrorLogDatabase.swift already patched for Linux"
    else
        echo "==> patching netnewswire ErrorLogDatabase.swift for Linux selector lowering"
        python3 - "$error_log_database" <<'PY'
import sys

path = sys.argv[1]
src = open(path).read()

old_observer = '			NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidEncounterError(_:)), name: .appDidEncounterError, object: nil)'
new_observer = '''#if os(Linux)
			// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
			_ = NotificationCenter.default.addObserver(forName: .appDidEncounterError, object: nil, queue: nil) { [weak self] notification in
				self?.handleAppDidEncounterError(notification)
			}
#else
			NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidEncounterError(_:)), name: .appDidEncounterError, object: nil)
#endif'''
if old_observer not in src:
    raise SystemExit("ErrorLogDatabase observer pattern not found")
src = src.replace(old_observer, new_observer, 1)

old_method = '	@objc nonisolated func handleAppDidEncounterError(_ notification: Notification) {'
new_method = '''#if !os(Linux)
	@objc
#endif
	nonisolated func handleAppDidEncounterError(_ notification: Notification) {'''
if old_method not in src:
    raise SystemExit("ErrorLogDatabase selector method not found")
src = src.replace(old_method, new_method, 1)

open(path, "w").write(src)
print("patched NetNewsWire ErrorLogDatabase.swift selector lowering")
PY
    fi

    local account_dir="$UPSTREAM_DIR/netnewswire/Modules/Account/Sources/Account"
    if [[ ! -d "$account_dir" ]]; then
        echo "==> netnewswire Account source not found; skipping Linux lowering"
    else
        echo "==> patching netnewswire Account for Linux FoundationNetworking/selector/CloudKit lowering"
        python3 - "$account_dir" <<'PY'
from pathlib import Path
import re
import sys

account_dir = Path(sys.argv[1])

for path in account_dir.rglob("*.swift"):
    src = path.read_text()
    if "import Foundation" in src and "import FoundationNetworking" not in src:
        src = src.replace(
            "import Foundation",
            "import Foundation\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif",
            1,
        )
    path.write_text(src)

cloudkit = account_dir / "CloudKitLinuxUnavailable.swift"
cloudkit.write_text(
"""// QuillUI Linux lowering: CloudKit is unavailable on Linux.

import Foundation
import Articles
import RSCore
import RSWeb
import Secrets

public typealias CloudKitStatsProgressHandler = @MainActor @Sendable (CloudKitStats) -> Void

public struct CloudKitStats: Sendable {
    public static let empty = CloudKitStats(statusCount: 0, starredStatusCount: 0, unreadStatusCount: 0, readStatusCount: 0, staleStatusCount: 0, articleCount: 0, starredArticleCount: 0, unreadArticleCount: 0, readArticleCount: 0)

    public let statusCount: Int
    public let starredStatusCount: Int
    public let unreadStatusCount: Int
    public let readStatusCount: Int
    public let staleStatusCount: Int
    public let articleCount: Int
    public let starredArticleCount: Int
    public let unreadArticleCount: Int
    public let readArticleCount: Int

    public func cleanUpPlan(syncUnreadContent: Bool) -> CloudKitCleanUpPlan {
        CloudKitCleanUpPlan(staleStatusCount: staleStatusCount, readContentCount: readArticleCount, unreadContentCount: syncUnreadContent ? 0 : unreadArticleCount)
    }
}

public struct CloudKitCleanUpPlan: Sendable {
    public let staleStatusCount: Int
    public let readContentCount: Int
    public let unreadContentCount: Int

    public var totalCount: Int { readContentCount + unreadContentCount }
    public var isEmpty: Bool { totalCount == 0 }
}

public enum CloudKitCleanUpPhase: Sendable {
    case deletingStaleStatus
    case deletingReadContent
    case deletingUnreadContent
    case completed
}

public struct CloudKitCleanUpProgress: Sendable {
    public let phase: CloudKitCleanUpPhase
    public let staleStatusDeleted: Int
    public let readContentDeleted: Int
    public let unreadContentDeleted: Int

    public var totalDeleted: Int { readContentDeleted + unreadContentDeleted }
}

public enum CloudKitStatsError: LocalizedError {
    case noiCloudAccount

    public var errorDescription: String? {
        NSLocalizedString("No iCloud account found.", comment: "CloudKit stats error")
    }
}

@MainActor final class CloudKitAccountDelegate: AccountDelegate {
    weak var account: Account?
    let behaviors: AccountBehaviors = []
    let isOPMLImportInProgress = false
    var progressInfo = ProgressInfo()
    let server: String? = nil
    var credentials: Credentials?
    var accountSettings: AccountSettings?

    init(dataFolder: String) {}

    func receiveRemoteNotification(userInfo: [AnyHashable: Any]) async {}
    func refreshAll() async throws { throw AccountError.invalidParameter }
    func syncArticleStatus() async throws -> Bool { false }
    func sendArticleStatus() async throws { throw AccountError.invalidParameter }
    func refreshArticleStatus() async throws { throw AccountError.invalidParameter }
    func importOPML(opmlFile: URL) async throws { throw AccountError.invalidParameter }
    func createFolder(name: String) async throws -> Folder { throw AccountError.invalidParameter }
    func renameFolder(with folder: Folder, to name: String) async throws { throw AccountError.invalidParameter }
    func removeFolder(with folder: Folder) async throws { throw AccountError.invalidParameter }
    func createFeed(url: String, name: String?, container: Container, validateFeed: Bool) async throws -> Feed { throw AccountError.invalidParameter }
    func renameFeed(with feed: Feed, to name: String) async throws { throw AccountError.invalidParameter }
    func addFeed(feed: Feed, container: Container) async throws { throw AccountError.invalidParameter }
    func removeFeed(feed: Feed, container: Container) async throws { throw AccountError.invalidParameter }
    func moveFeed(feed: Feed, sourceContainer: Container, destinationContainer: Container) async throws { throw AccountError.invalidParameter }
    func restoreFeed(feed: Feed, container: Container) async throws { throw AccountError.invalidParameter }
    func restoreFolder(folder: Folder) async throws { throw AccountError.invalidParameter }
    func markArticles(articles: Set<Article>, statusKey: ArticleStatus.Key, flag: Bool) async throws { throw AccountError.invalidParameter }
    func accountDidInitialize() {}
    func accountWillBeDeleted() {}
    static func validateCredentials(credentials: Credentials, endpoint: URL?) async throws -> Credentials? { nil }
    func vacuumDatabases() async {}
    func suspendNetwork() {}
    func resume() {}

    func fetchCloudKitStats(progress: @escaping CloudKitStatsProgressHandler) async throws -> CloudKitStats {
        throw AccountError.invalidParameter
    }

    func cleanUpCloudKit(dryRun: Bool, progress: @escaping @MainActor @Sendable (CloudKitCleanUpProgress) -> Void) async throws {
        throw AccountError.invalidParameter
    }
}
"""
)

observer_pattern = re.compile(
    r"(?P<indent>[ \t]*)NotificationCenter\.default\.addObserver\(self, selector: #selector\((?P<method>[A-Za-z0-9_]+)\(_:\)\), name: (?P<name>[^,]+), object: (?P<object>[^\n]+?)\)"
)

for path in account_dir.rglob("*.swift"):
    if path.name == "CloudKitLinuxUnavailable.swift" or "/CloudKit/" in path.as_posix():
        continue
    src = path.read_text()

    def replace_observer(match):
        indent = match.group("indent")
        method = match.group("method")
        name = match.group("name")
        obj = match.group("object")
        original = match.group(0).strip()
        return (
            f"{indent}#if os(Linux)\n"
            f"{indent}// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.\n"
            f"{indent}_ = NotificationCenter.default.addObserver(forName: {name}, object: {obj}, queue: nil) {{ [weak self] notification in\n"
            f"{indent}\tTask {{ @MainActor in\n"
            f"{indent}\t\tself?.{method}(notification)\n"
            f"{indent}\t}}\n"
            f"{indent}}}\n"
            f"{indent}#else\n"
            f"{indent}{original}\n"
            f"{indent}#endif"
        )

    src = observer_pattern.sub(replace_observer, src)
    src = src.replace("@objc nonisolated final class", "nonisolated final class")
    src = src.replace("@objc nonisolated func", "#if !os(Linux)\n\t@objc\n#endif\n\tnonisolated func")
    src = src.replace("@objc func", "#if !os(Linux)\n\t@objc\n#endif\n\tfunc")
    src = src.replace(
        "saveQueue.add(self, #selector(saveToDiskIfNeeded))",
        "saveQueue.add { [weak self] in\n\t\t\t\t\tself?.saveToDiskIfNeeded()\n\t\t\t\t}",
    )
    path.write_text(src)

print("patched NetNewsWire Account Linux lowering")
PY
    fi

    local shared_dir="$UPSTREAM_DIR/netnewswire/Shared"
    if [[ -d "$shared_dir" ]] && grep -rqE 'NSSortDescriptor\(key:|sortDescriptor(\?)?\.key' "$shared_dir" 2>/dev/null; then
        echo "==> lowering netnewswire Shared Foundation compatibility"
        ( cd "$ROOT_DIR" && swift run quill-lower-foundation "$shared_dir" )
    fi

    local netnewswire_dir="$UPSTREAM_DIR/netnewswire"
    if [[ -d "$netnewswire_dir" ]] && grep -rq 'Bundle.main.bundleIdentifier!' "$netnewswire_dir" 2>/dev/null; then
        echo "==> lowering netnewswire forced bundle identifiers for Linux test runners"
        python3 - "$netnewswire_dir" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
fallback = '(Bundle.main.bundleIdentifier ?? "com.ranchero.NetNewsWire")'
for path in root.rglob("*.swift"):
    src = path.read_text()
    patched = src.replace("Bundle.main.bundleIdentifier!", fallback)
    if patched != src:
        path.write_text(patched)
PY
    fi

    local article_string_formatter="$shared_dir/Extensions/ArticleStringFormatter.swift"
    if [[ -f "$article_string_formatter" ]] && grep -q '#selector(handleAppDidGoToBackground' "$article_string_formatter"; then
        echo "==> lowering netnewswire Shared ArticleStringFormatter selector observers"
        python3 - "$article_string_formatter" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_init = '''	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidGoToBackground(_:)), name: .appDidGoToBackground, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)
	}
'''
new_init = '''	init() {
#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		_ = NotificationCenter.default.addObserver(forName: .appDidGoToBackground, object: nil, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.handleAppDidGoToBackground(notification)
			}
		}
		_ = NotificationCenter.default.addObserver(forName: .lowMemory, object: nil, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.handleLowMemory(notification)
			}
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(handleAppDidGoToBackground(_:)), name: .appDidGoToBackground, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)
#endif
	}
'''
if old_init not in src:
    raise SystemExit("ArticleStringFormatter selector observer pattern not found")
src = src.replace(old_init, new_init, 1)

src = src.replace(
    "\t@objc func handleAppDidGoToBackground(_ notification: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc handleAppDidGoToBackground(_ notification: Notification) {",
    1,
)
src = src.replace(
    "\t@objc func handleLowMemory(_ notification: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc handleLowMemory(_ notification: Notification) {",
    1,
)
src = src.replace("return NSAttributedString()", 'return NSAttributedString(string: "")')

path.write_text(src)
print("patched ArticleStringFormatter selector observer lowering")
PY
    fi

    local default_feeds_importer="$shared_dir/Importers/DefaultFeedsImporter.swift"
    if [[ -f "$default_feeds_importer" ]] && grep -q 'Bundle.main.url(forResource: "DefaultFeeds"' "$default_feeds_importer"; then
        echo "==> lowering netnewswire Shared DefaultFeedsImporter resource lookup"
        python3 - "$default_feeds_importer" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()
src = src.replace(
    'let defaultFeedsURL = Bundle.main.url(forResource: "DefaultFeeds", withExtension: "opml")!',
    '''#if os(Linux)
\t\tguard let defaultFeedsURL = Bundle.module.url(forResource: "DefaultFeeds", withExtension: "opml") else {
\t\t\treturn
\t\t}
#else
\t\tlet defaultFeedsURL = Bundle.main.url(forResource: "DefaultFeeds", withExtension: "opml")!
#endif''',
    1,
)
path.write_text(src)
print("patched DefaultFeedsImporter Bundle.module lookup")
PY
    fi

    local extension_containers_file="$shared_dir/ShareExtension/ExtensionContainersFile.swift"
    if [[ -f "$extension_containers_file" ]] && grep -q '#selector(markAsDirty' "$extension_containers_file" && grep -q 'as! String' "$extension_containers_file"; then
        echo "==> lowering netnewswire Shared ExtensionContainersFile selectors and app-group lookup"
        python3 - "$extension_containers_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_file_path = '''	private static var filePath: String = {
		let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as! String
		let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
		return containerURL!.appendingPathComponent("extension_containers.plist").path
	}()
'''
new_file_path = '''	private static var filePath: String = {
		let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? "group.com.ranchero.NetNewsWire"
		let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
		return containerURL!.appendingPathComponent("extension_containers.plist").path
	}()
'''
if old_file_path not in src:
    raise SystemExit("ExtensionContainersFile filePath pattern not found")
src = src.replace(old_file_path, new_file_path, 1)

old_observers = '''		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .UserDidAddAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .UserDidDeleteAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .AccountStateDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .ChildrenDidChange, object: nil)
'''
new_observers = '''#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		for name in [Notification.Name.UserDidAddAccount, .UserDidDeleteAccount, .AccountStateDidChange, .ChildrenDidChange] {
			_ = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
				Task { @MainActor in
					self?.markAsDirty()
				}
			}
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .UserDidAddAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .UserDidDeleteAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .AccountStateDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .ChildrenDidChange, object: nil)
#endif
'''
if old_observers not in src:
    raise SystemExit("ExtensionContainersFile observer pattern not found")
src = src.replace(old_observers, new_observers, 1)

src = src.replace(
    "\t@objc func markAsDirty() {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc markAsDirty() {",
    1,
)
src = src.replace(
    "\t\tsaveQueue.add(self, #selector(saveToDiskIfNeeded))",
    "#if os(Linux)\n\t\tsaveQueue.add { [weak self] in\n\t\t\tself?.saveToDiskIfNeeded()\n\t\t}\n#else\n\t\tsaveQueue.add(self, #selector(saveToDiskIfNeeded))\n#endif",
    1,
)
src = src.replace(
    "\t@objc func saveToDiskIfNeeded() {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc saveToDiskIfNeeded() {",
    1,
)

path.write_text(src)
print("patched ExtensionContainersFile selector/app-group lowering")
PY
    fi

    local extension_feed_add_request_file="$shared_dir/ShareExtension/ExtensionFeedAddRequestFile.swift"
    if [[ -f "$extension_feed_add_request_file" ]] && grep -q 'as! String' "$extension_feed_add_request_file"; then
        echo "==> lowering netnewswire Shared ExtensionFeedAddRequestFile app-group lookup"
        python3 - "$extension_feed_add_request_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()
old_file_path = '''	private static let filePath: String = {
		let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as! String
		let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
		return containerURL!.appendingPathComponent("extension_feed_add_request.plist").path
	}()
'''
new_file_path = '''	private static let filePath: String = {
		let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String ?? "group.com.ranchero.NetNewsWire"
		let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
		return containerURL!.appendingPathComponent("extension_feed_add_request.plist").path
	}()
'''
if old_file_path not in src:
    raise SystemExit("ExtensionFeedAddRequestFile filePath pattern not found")
src = src.replace(old_file_path, new_file_path, 1)
path.write_text(src)
print("patched ExtensionFeedAddRequestFile app-group lowering")
PY
    fi

    local smart_feed="$shared_dir/SmartFeeds/SmartFeed.swift"
    if [[ -f "$smart_feed" ]] && grep -q '#selector(unreadCountDidChange' "$smart_feed"; then
        echo "==> lowering netnewswire Shared SmartFeed selector observers"
        python3 - "$smart_feed" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_init = '''	init(delegate: SmartFeedDelegate) {
		self.delegate = delegate
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
		queueFetchUnreadCounts() // Fetch unread count at startup
	}
'''
new_init = '''	init(delegate: SmartFeedDelegate) {
		self.delegate = delegate
#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		_ = NotificationCenter.default.addObserver(forName: .UnreadCountDidChange, object: nil, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.unreadCountDidChange(notification)
			}
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: nil)
#endif
		queueFetchUnreadCounts() // Fetch unread count at startup
	}
'''
if old_init not in src:
    raise SystemExit("SmartFeed selector observer pattern not found")
src = src.replace(old_init, new_init, 1)

src = src.replace(
    "\t@objc func unreadCountDidChange(_ note: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc unreadCountDidChange(_ note: Notification) {",
    1,
)
src = src.replace(
    "\t@objc func fetchUnreadCounts() {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc fetchUnreadCounts() {",
    1,
)
src = src.replace(
    "\t\tCoalescingQueue.standard.add(self, #selector(fetchUnreadCounts))",
    "#if os(Linux)\n\t\tCoalescingQueue.standard.add { [weak self] in\n\t\t\tself?.fetchUnreadCounts()\n\t\t}\n#else\n\t\tCoalescingQueue.standard.add(self, #selector(fetchUnreadCounts))\n#endif",
    1,
)

path.write_text(src)
print("patched SmartFeed selector observer lowering")
PY
    fi

    local unread_feed="$shared_dir/SmartFeeds/UnreadFeed.swift"
    if [[ -f "$unread_feed" ]] && grep -q '#selector(unreadCountDidChange' "$unread_feed"; then
        echo "==> lowering netnewswire Shared UnreadFeed selector observer"
        python3 - "$unread_feed" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_init = '''	init() {

		self.unreadCount = appDelegate.unreadCount
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: appDelegate)
	}
'''
new_init = '''	init() {

		self.unreadCount = appDelegate.unreadCount
#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		_ = NotificationCenter.default.addObserver(forName: .UnreadCountDidChange, object: appDelegate, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.unreadCountDidChange(notification)
			}
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(unreadCountDidChange(_:)), name: .UnreadCountDidChange, object: appDelegate)
#endif
	}
'''
if old_init not in src:
    raise SystemExit("UnreadFeed selector observer pattern not found")
src = src.replace(old_init, new_init, 1)
src = src.replace(
    "\t@objc func unreadCountDidChange(_ note: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc unreadCountDidChange(_ note: Notification) {",
    1,
)

path.write_text(src)
print("patched UnreadFeed selector observer lowering")
PY
    fi

    local smart_feed_pasteboard_writer="$shared_dir/SmartFeeds/SmartFeedPasteboardWriter.swift"
    if [[ -f "$smart_feed_pasteboard_writer" ]] && grep -q '@MainActor @objc final class SmartFeedPasteboardWriter' "$smart_feed_pasteboard_writer"; then
        echo "==> lowering netnewswire Shared SmartFeedPasteboardWriter ObjC attribute"
        python3 - "$smart_feed_pasteboard_writer" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()
src = src.replace(
    "@MainActor @objc final class SmartFeedPasteboardWriter",
    "@MainActor final class SmartFeedPasteboardWriter",
    1,
)
path.write_text(src)
print("patched SmartFeedPasteboardWriter ObjC lowering")
PY
    fi

    local icon_image_cache="$shared_dir/IconImageCache.swift"
    if [[ -f "$icon_image_cache" ]] && grep -q '#selector(handleLowMemory' "$icon_image_cache"; then
        echo "==> lowering netnewswire Shared IconImageCache selector observer"
        python3 - "$icon_image_cache" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_init = '''	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)
	}
'''
new_init = '''	init() {
#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		_ = NotificationCenter.default.addObserver(forName: .lowMemory, object: nil, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.handleLowMemory(notification)
			}
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(handleLowMemory(_:)), name: .lowMemory, object: nil)
#endif
	}
'''
if old_init not in src:
    raise SystemExit("IconImageCache observer pattern not found")
src = src.replace(old_init, new_init, 1)
src = src.replace(
    "\t@objc func handleLowMemory(_ notification: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc handleLowMemory(_ notification: Notification) {",
    1,
)

path.write_text(src)
print("patched IconImageCache selector observer lowering")
PY
    fi

    local rsimage_extensions="$shared_dir/Extensions/RSImage+Extensions.swift"
    if [[ -f "$rsimage_extensions" ]] && ! grep -q '#else[[:space:]]*$' "$rsimage_extensions"; then
        echo "==> lowering netnewswire Shared RSImage app icon fallback"
        python3 - "$rsimage_extensions" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()
needle = '''		return nil
		#endif
'''
replacement = '''		return nil
		#else
		return nil
		#endif
'''
if needle not in src:
    raise SystemExit("RSImage app icon fallback pattern not found")
src = src.replace(needle, replacement, 1)
path.write_text(src)
print("patched RSImage Linux app icon fallback")
PY
    fi

    local dinosaurs_view_model="$shared_dir/Dinosaurs/DinosaursViewModel.swift"
    if [[ -f "$dinosaurs_view_model" ]] && grep -q '^@Observable$' "$dinosaurs_view_model"; then
        echo "==> lowering netnewswire Shared DinosaursViewModel Observation macro"
        python3 - "$dinosaurs_view_model" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()
src = src.replace("@Observable\n@MainActor final class DinosaursViewModel", "@MainActor final class DinosaursViewModel", 1)
path.write_text(src)
print("patched DinosaursViewModel @Observable lowering")
PY
    fi

    local current_activity_view_model="$shared_dir/CurrentActivity/CurrentActivityViewModel.swift"
    if [[ -f "$current_activity_view_model" ]] && grep -q '#selector(handleActivityDidChange' "$current_activity_view_model"; then
        echo "==> lowering netnewswire Shared CurrentActivityViewModel selector timers"
        python3 - "$current_activity_view_model" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_start = '''	func start() {
		if !isObserving {
			NotificationCenter.default.addObserver(self, selector: #selector(handleActivityDidChange(_:)), name: .activityDidChange, object: nil)
			isObserving = true
		}
		scheduleUpdate()
	}
'''
new_start = '''	func start() {
		if !isObserving {
#if os(Linux)
			// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
			_ = NotificationCenter.default.addObserver(forName: .activityDidChange, object: nil, queue: nil) { [weak self] notification in
				Task { @MainActor in
					self?.handleActivityDidChange(notification)
				}
			}
#else
			NotificationCenter.default.addObserver(self, selector: #selector(handleActivityDidChange(_:)), name: .activityDidChange, object: nil)
#endif
			isObserving = true
		}
		scheduleUpdate()
	}
'''
if old_start not in src:
    raise SystemExit("CurrentActivityViewModel start observer pattern not found")
src = src.replace(old_start, new_start, 1)

old_schedule = '''		updateTimer = Timer.scheduledTimer(timeInterval: Self.updateInterval, target: self, selector: #selector(update), userInfo: nil, repeats: true)
		update()
'''
new_schedule = '''#if os(Linux)
		updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
			Task { @MainActor in
				self?.update()
			}
		}
#else
		updateTimer = Timer.scheduledTimer(timeInterval: Self.updateInterval, target: self, selector: #selector(update), userInfo: nil, repeats: true)
#endif
		update()
'''
if old_schedule not in src:
    raise SystemExit("CurrentActivityViewModel timer selector pattern not found")
src = src.replace(old_schedule, new_schedule, 1)
src = src.replace("private var updateTimer: Timer?", "private var updateTimer: Foundation.Timer?", 1)
src = src.replace("Timer.scheduledTimer", "Foundation.Timer.scheduledTimer")

src = src.replace(
    "\t@objc func handleActivityDidChange(_ notification: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc handleActivityDidChange(_ notification: Notification) {",
    1,
)
src = src.replace(
    "\t@objc func update() {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc update() {",
    1,
)

path.write_text(src)
print("patched CurrentActivityViewModel selector/timer lowering")
PY
    fi

    local account_refresh_timer="$shared_dir/Timer/AccountRefreshTimer.swift"
    if [[ -f "$account_refresh_timer" ]] && grep -q '#selector(timedRefresh' "$account_refresh_timer" && ! grep -q 'Foundation.Timer?' "$account_refresh_timer"; then
        echo "==> lowering netnewswire Shared AccountRefreshTimer selector timer"
        python3 - "$account_refresh_timer" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_timer = '''		let timer = Timer(fireAt: nextRefreshTime, interval: 0, target: self, selector: #selector(timedRefresh(_:)), userInfo: nil, repeats: false)
		RunLoop.main.add(timer, forMode: .common)
		internalTimer = timer
'''
new_timer = '''#if os(Linux)
		let timer = Timer(fire: nextRefreshTime, interval: 0, repeats: false) { [weak self] timer in
			Task { @MainActor in
				self?.timedRefresh(timer)
			}
		}
#else
		let timer = Timer(fireAt: nextRefreshTime, interval: 0, target: self, selector: #selector(timedRefresh(_:)), userInfo: nil, repeats: false)
#endif
		RunLoop.main.add(timer, forMode: .common)
		internalTimer = timer
'''
if old_timer not in src:
    raise SystemExit("AccountRefreshTimer selector timer pattern not found")
src = src.replace(old_timer, new_timer, 1)
src = src.replace("private var internalTimer: Timer?", "private var internalTimer: Foundation.Timer?", 1)
src = src.replace("Timer(fire:", "Foundation.Timer(fire:")
src = src.replace(
    "\t@objc func timedRefresh(_ sender: Timer?) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc timedRefresh(_ sender: Foundation.Timer?) {",
    1,
)

path.write_text(src)
print("patched AccountRefreshTimer selector timer lowering")
PY
    fi

    local article_status_sync_timer="$shared_dir/Timer/ArticleStatusSyncTimer.swift"
    if [[ -f "$article_status_sync_timer" ]] && grep -q '#selector' "$article_status_sync_timer" && ! grep -q 'Foundation.Timer?' "$article_status_sync_timer"; then
        echo "==> lowering netnewswire Shared ArticleStatusSyncTimer selectors"
        python3 - "$article_status_sync_timer" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_init = '''	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(handleAccountDidQueueArticleStatuses(_:)), name: .AccountDidQueueArticleStatuses, object: nil)
	}
'''
new_init = '''	init() {
#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		_ = NotificationCenter.default.addObserver(forName: .AccountDidQueueArticleStatuses, object: nil, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.handleAccountDidQueueArticleStatuses(notification)
			}
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(handleAccountDidQueueArticleStatuses(_:)), name: .AccountDidQueueArticleStatuses, object: nil)
#endif
	}
'''
if old_init not in src:
    raise SystemExit("ArticleStatusSyncTimer observer pattern not found")
src = src.replace(old_init, new_init, 1)

old_timer = '''		let timer = Timer(fireAt: nextRefreshTime, interval: 0, target: self, selector: #selector(timedRefresh(_:)), userInfo: nil, repeats: false)
		RunLoop.main.add(timer, forMode: .common)
		internalTimer = timer
'''
new_timer = '''#if os(Linux)
		let timer = Timer(fire: nextRefreshTime, interval: 0, repeats: false) { [weak self] timer in
			Task { @MainActor in
				self?.timedRefresh(timer)
			}
		}
#else
		let timer = Timer(fireAt: nextRefreshTime, interval: 0, target: self, selector: #selector(timedRefresh(_:)), userInfo: nil, repeats: false)
#endif
		RunLoop.main.add(timer, forMode: .common)
		internalTimer = timer
'''
if old_timer not in src:
    raise SystemExit("ArticleStatusSyncTimer selector timer pattern not found")
src = src.replace(old_timer, new_timer, 1)
src = src.replace("private var internalTimer: Timer?", "private var internalTimer: Foundation.Timer?", 1)
src = src.replace("Timer(fire:", "Foundation.Timer(fire:")
src = src.replace(
    "\t@objc func timedRefresh(_ sender: Timer?) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc timedRefresh(_ sender: Foundation.Timer?) {",
    1,
)
src = src.replace(
    "\t@objc func handleAccountDidQueueArticleStatuses(_ notification: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc handleAccountDidQueueArticleStatuses(_ notification: Notification) {",
    1,
)

path.write_text(src)
print("patched ArticleStatusSyncTimer selector/timer lowering")
PY
    fi

    local user_notification_manager="$shared_dir/UserNotifications/UserNotificationManager.swift"
    if [[ -f "$user_notification_manager" ]] && grep -q '#selector(accountDidDownloadArticles' "$user_notification_manager"; then
        echo "==> lowering netnewswire Shared UserNotificationManager selectors"
        python3 - "$user_notification_manager" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old_observers = '''		NotificationCenter.default.addObserver(self, selector: #selector(accountDidDownloadArticles(_:)), name: .AccountDidDownloadArticles, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
'''
new_observers = '''#if os(Linux)
		// QuillUI Linux lowering: swift-corelibs has no ObjC selector dispatch.
		_ = NotificationCenter.default.addObserver(forName: .AccountDidDownloadArticles, object: nil, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.accountDidDownloadArticles(notification)
			}
		}
		_ = NotificationCenter.default.addObserver(forName: .StatusesDidChange, object: nil, queue: nil) { [weak self] notification in
			Task { @MainActor in
				self?.statusesDidChange(notification)
			}
		}
#else
		NotificationCenter.default.addObserver(self, selector: #selector(accountDidDownloadArticles(_:)), name: .AccountDidDownloadArticles, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(statusesDidChange(_:)), name: .StatusesDidChange, object: nil)
#endif
'''
if old_observers not in src:
    raise SystemExit("UserNotificationManager observer pattern not found")
src = src.replace(old_observers, new_observers, 1)
src = src.replace(
    "\t@objc func accountDidDownloadArticles(_ note: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc accountDidDownloadArticles(_ note: Notification) {",
    1,
)
src = src.replace(
    "\t@objc func statusesDidChange(_ note: Notification) {",
    "#if !os(Linux)\n\t@objc\n#endif\n\tfunc statusesDidChange(_ note: Notification) {",
    1,
)
path.write_text(src)
print("patched UserNotificationManager selector lowering")
PY
    fi

    local article_sorter="$shared_dir/Timeline/ArticleSorter.swift"
    if [[ -f "$article_sorter" ]] && grep -qE 'feedNameFor: \(Article\) -> String|\.sorted \{' "$article_sorter"; then
        echo "==> lowering netnewswire Shared ArticleSorter for Swift 6 Linux"
        python3 - "$article_sorter" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()
src = src.replace(
    "feedNameFor: (Article) -> String = { $0.sortableFeedName }",
    "feedNameFor: @MainActor (Article) -> String = { $0.sortableFeedName }",
)
src = src.replace(
    "feedNameFor: (Article) -> String) -> [Article]",
    "feedNameFor: @MainActor (Article) -> String) -> [Article]",
)
src = src.replace(".sorted { lhs, rhs in", ".sorted(by: { lhs, rhs in")
src = src.replace(
    """\t\t\t\tcase .orderedSame: lhs.feedID < rhs.feedID
\t\t\t\t}
\t\t\t}
\t\t\t.flatMap""",
    """\t\t\t\tcase .orderedSame: lhs.feedID < rhs.feedID
\t\t\t\t}
\t\t\t})
\t\t\t.flatMap""",
)
src = src.replace("articles.sorted { article1, article2 in", "articles.sorted(by: { article1, article2 in")
src = src.replace(
    """\t\t\t} else {
\t\t\t\tarticle1.logicalDatePublished < article2.logicalDatePublished
\t\t\t}
\t\t}""",
    """\t\t\t} else {
\t\t\t\tarticle1.logicalDatePublished < article2.logicalDatePublished
\t\t\t}
\t\t})""",
)
path.write_text(src)
print("patched ArticleSorter actor/default-closure and sorted(by:) lowering")
PY
    fi
}

want=("$@")
patch_solderscope() {
    # SolderScope compiles on Linux through two disposable-checkout fixes:
    # 1. `import os.log` is lowered to `import os`, which pure-Swift shims cannot
    #    express as a clang submodule.
    # 2. The Linux CoreImage/CoreVideo bridge needs frozen camera frames
    #    materialized to CGImage; otherwise a frozen CIImage can later draw black
    #    when its backing capture storage changes.
    if [[ "$(uname -s)" == "Linux" ]]; then
        local dir="$UPSTREAM_DIR/solderscope/SolderScope"
        if [[ -d "$dir" ]] && grep -rqE 'import os\.log' "$dir" 2>/dev/null; then
            echo "==> lowering solderscope for Linux (import os.log)"
            ( cd "$ROOT_DIR" && swift run quill-lower-appkit "$dir" )
        fi
        local microscope="$dir/Renderer/MicroscopeView.swift"
        if [[ -f "$microscope" ]]; then
            python3 - "$microscope" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
new = text
replacements = [
    (
        """            if isFrozen && frozenFrame == nil {
                frozenFrame = currentFrame
            } else if !isFrozen {
                frozenFrame = nil
            }
""",
        """            if isFrozen && frozenFrame == nil {
                frozenFrame = materializedFrame(from: currentFrame)
                needsDisplay = true
            } else if !isFrozen {
                frozenFrame = nil
                needsDisplay = true
            }
""",
    ),
    (
        """    private var frozenFrame: CIImage?
""",
        """    private var frozenFrame: QuillFoundation.CGImage?
""",
    ),
    (
        """        (isFrozen ? frozenFrame : currentFrame)?.extent.size
""",
        """        if isFrozen, let frozenFrame {
            return CGSize(width: frozenFrame.width, height: frozenFrame.height)
        }
        return currentFrame?.extent.size
""",
    ),
    (
        """            if frozenFrame == nil {
                frozenFrame = image
            }
""",
        """            if frozenFrame == nil {
                frozenFrame = materializedFrame(from: image)
                needsDisplay = true
            }
""",
    ),
    (
        """    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
""",
        """    override var isFlipped: Bool { true }

    private func materializedFrame(from image: CIImage?) -> QuillFoundation.CGImage? {
        guard let image,
              let ciContext = ciContext else { return nil }
        return ciContext.createCGImage(image, from: image.extent)
    }

    override func draw(_ dirtyRect: NSRect) {
""",
    ),
    (
        """        // Get the frame to display
        let frameToDisplay = isFrozen ? frozenFrame : currentFrame
        guard let ciImage = frameToDisplay else { return }

        // Convert CIImage to CGImage for reliable rendering
        let imageExtent = ciImage.extent
        guard let cgImage = ciContext.createCGImage(ciImage, from: imageExtent) else { return }
""",
        """        // Get the frame to display
        let cgImage: QuillFoundation.CGImage
        if isFrozen {
            guard let frozenFrame else { return }
            cgImage = frozenFrame
        } else {
            guard let ciImage = currentFrame,
                  let renderedImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            cgImage = renderedImage
        }
""",
    ),
]
patched_markers = [
    "frozenFrame = materializedFrame(from: currentFrame)",
    "private var frozenFrame: QuillFoundation.CGImage?",
    "private func materializedFrame(from image: CIImage?) -> QuillFoundation.CGImage?",
]
if all(marker in new for marker in patched_markers):
    raise SystemExit(0)
for old, replacement in replacements:
    if old not in new:
        raise SystemExit(f"patch_solderscope: expected MicroscopeView snippet not found in {path}: {old.splitlines()[0]}")
    new = new.replace(old, replacement, 1)
if new != text:
    path.write_text(new)
    print(f"patch_solderscope: materialized frozen frames in {path}")
PY
        fi
    fi
}

patch_euclid() {
    # Euclid's example app is UIKit + SceneKit with a small RealityKit tab.
    # Linux has no ObjC runtime, so lower its selector glue in the disposable
    # checkout. Also instantiate the UIViewController subclasses through their
    # explicit nib initializer; adding a broad UIViewController.init() changes
    # UIKit semantics and cascades through other conformance targets.
    if [[ "$(uname -s)" == "Linux" ]]; then
        local example="$UPSTREAM_DIR/euclid/Example"
        [[ -d "$example" ]] || return 0
        python3 - "$example" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
replacements = {
    "RealityKitViewController.swift": [
        ("@objc private func handlePinch", "private func handlePinch"),
        ("@objc private func handleRotate", "private func handleRotate"),
        ("@objc private func handlePan", "private func handlePan"),
        ("#selector(handlePinch(_:))", 'Selector("handlePinch(_:)")'),
        ("#selector(handleRotate(_:))", 'Selector("handleRotate(_:)")'),
        ("#selector(handlePan(_:))", 'Selector("handlePan(_:)")'),
    ],
    "SceneDelegate.swift": [
        ("SceneKitViewController()", "SceneKitViewController(nibName: nil, bundle: nil)"),
        ("RealityKitViewController()", "RealityKitViewController(nibName: nil, bundle: nil)"),
    ],
}
changed = 0
for name, edits in replacements.items():
    path = root / name
    if not path.exists():
        continue
    text = path.read_text()
    new = text
    for old, replacement in edits:
        new = new.replace(old, replacement)
    if new != text:
        path.write_text(new)
        changed += 1
print(f"patch_euclid: lowered selector/init glue in {changed} file(s)")
PY
    fi
}

patch_shapescript() {
    # ShapeScript's macOS viewer is an AppKit/NSDocument app and uses target-
    # action selectors plus Interface Builder attributes. Linux has no ObjC
    # runtime, so lower only the disposable Viewer/Mac checkout through the same
    # AppKit pass used by WireGuard/SolderScope. Shared/ and CLI stay source-
    # unchanged; the Mac target is the only slice with @IB*/#selector usage.
    if [[ "$(uname -s)" == "Linux" ]]; then
        local mac_viewer="$UPSTREAM_DIR/shapescript/Viewer/Mac"
        if [[ -d "$mac_viewer" ]] && grep -rqE '#selector|@objc|@IBAction|@IBOutlet|@IB' "$mac_viewer" 2>/dev/null; then
            echo "==> lowering shapescript Viewer/Mac for Linux"
            ( cd "$ROOT_DIR" && swift run quill-lower-appkit "$mac_viewer" )
        fi
        [[ -d "$mac_viewer" ]] || return 0
        python3 - "$mac_viewer" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
replacements = {
    "AppDelegate.swift": [
        ("files.sorted(by: { $0.path < $1.path })", "files.map({ $0 as URL }).sorted(by: { ($0.path ?? \"\") < ($1.path ?? \"\") })"),
        ("files.sorted(by: { ($0.path ?? \"\") < ($1.path ?? \"\") })", "files.map({ $0 as URL }).sorted(by: { ($0.path ?? \"\") < ($1.path ?? \"\") })"),
    ],
    "DocumentViewController.swift": [
        ("NSColor.red", "NSColor(red: 1, green: 0, blue: 0, alpha: 1)"),
        ("scnView.gestureRecognizers.insert(clickGesture, at: 0)", "scnView.addGestureRecognizer(clickGesture)"),
        ("errorTextView.gestureRecognizers.insert(clickGesture2, at: 0)", "errorTextView.addGestureRecognizer(clickGesture2)"),
        ("scnView.layer?.backgroundColor", "scnView.layer.backgroundColor"),
    ],
    "Utilities.swift": [
        ("func dismissOpenSavePanel() {", "@MainActor func dismissOpenSavePanel() {"),
    ],
}
changed = 0
for name, edits in replacements.items():
    path = root / name
    if not path.exists():
        continue
    text = path.read_text()
    new = text
    for old, replacement in edits:
        new = new.replace(old, replacement)
    if new != text:
        path.write_text(new)
        changed += 1
shared = root.parent / "Shared" / "DocumentViewController+View.swift"
if shared.exists():
    text = shared.read_text()
    new = text.replace(
        """renderTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            self.scnView.rendersContinuously = false
            self.renderTimer = nil
        }""",
        """scnView.rendersContinuously = false
        renderTimer = nil""",
    ).replace(
        "material.emission.contents = OSColor.red",
        "material.emission.contents = OSColor(red: 1, green: 0, blue: 0, alpha: 1)",
    )
    if new != text:
        shared.write_text(new)
        changed += 1
print(f"patch_shapescript: applied Linux viewer glue in {changed} file(s)")
PY
    fi
}

patch_libsignal() {
    # libsignal's LibSignalClient ships "testing endpoints" (FakeChat / OTP /
    # comparable-backup test helpers) gated `#if !os(iOS) || targetEnvironment(simulator)`
    # -- compiled for macOS/simulator test builds, EXCLUDED on iOS device builds
    # "to save on code size". On Linux `!os(iOS)` is true, so they would compile
    # and reference `signal_testing_*` FFI symbols that are ABSENT from the release
    # libsignal_ffi.a (cargo build -p libsignal-ffi --release), breaking any
    # downstream executable/test link (undefined symbol at ld time). QuillOS links
    # the release .a, so narrow the gate to ALSO exclude Linux (behave like a device
    # build). Idempotent + self-guarded: only rewrites the un-narrowed gate.
    local dir="$UPSTREAM_DIR/libsignal/swift/Sources/LibSignalClient"
    [[ -d "$dir" ]] || return 0
    python3 - "$dir" <<'PYLS'
import sys, os
root = sys.argv[1]
old = "#if !os(iOS) || targetEnvironment(simulator)"
new = "#if (!os(iOS) || targetEnvironment(simulator)) && !os(Linux)"
n = 0
for f in ("ChatServiceTypes.swift", "ComparableBackup.swift", "Net.swift", "ChatConnection+Fake.swift"):
    p = os.path.join(root, f)
    if not os.path.exists(p):
        continue
    src = open(p).read()
    if old in src:
        open(p, "w").write(src.replace(old, new))
        n += 1
print(f"patch_libsignal: narrowed testing-endpoint gate on Linux in {n} file(s)")
PYLS
}

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
            if [[ -d "$ROOT_DIR/vendor/apps/enchanted/Enchanted" ]] && ! quillui_truthy "${QUILLUI_REFRESH_VENDORED_SOURCE:-0}"; then
                echo "==> using vendored enchanted source at vendor/apps/enchanted"
            else
                fetch_repo enchanted https://github.com/gluonfield/enchanted.git
            fi
            ;;
        netnewswire)
            fetch_repo netnewswire https://github.com/Ranchero-Software/NetNewsWire.git
            # PINNED to NNW main as of 2026-06-08: the Linux Account/Shared
            # module train (merged 2026-06-09) compiles against this tree;
            # upstream HEAD has since drifted its RSDatabase wrapper API
            # (DatabaseResult lost tableExists/executeStatements/...), which
            # turned the Linux CI lane red. Advance the pin together with
            # the slice, not implicitly via HEAD-tracking fetches.
            reset_repo_to_commit netnewswire 7fc1e65308583fb014818c342ecbb1560e8461db
            patch_netnewswire
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
        telegram)
            fetch_repo telegram-swift https://github.com/overtake/TelegramSwift.git master
            ;;
        solderscope)
            # First community-requested conformance app (MIT): real macOS
            # SwiftUI USB-microscope viewer, compiled unmodified on Linux.
            fetch_repo solderscope https://github.com/rjwalters/SolderScope.git
            patch_solderscope
            ;;
        euclid)
            # nicklockwood/Euclid (MIT): pure-Swift 3D geometry/CSG library.
            # The library core is platform-independent (SceneKit/RealityKit/
            # AppKit interop files are all canImport-gated upstream), so the
            # `Euclid` target can go green on Linux ahead of any SCN surface.
            # Example/ is a real UIKit + SceneKit (+ one RealityKit screen)
            # demo app — the warm-up SceneKit conformance driver.
            fetch_repo euclid https://github.com/nicklockwood/Euclid.git
            patch_euclid
            ;;
        lrucache)
            # nicklockwood/LRUCache (MIT): single-file pure-Swift dependency
            # of ShapeScript.
            fetch_repo lrucache https://github.com/nicklockwood/LRUCache.git
            ;;
        svgpath)
            # nicklockwood/SVGPath (MIT): SVG path parser dependency of
            # ShapeScript (CoreGraphics/SwiftUI extensions canImport-gated).
            fetch_repo svgpath https://github.com/nicklockwood/SVGPath.git
            ;;
        shapescript)
            # nicklockwood/ShapeScript (MIT): real shipped macOS app whose
            # entire viewport is SceneKit — the flagship SceneKit conformance
            # target. Core language lib + CLI already support Linux upstream;
            # Viewer/Mac is an NSDocument-based AppKit app (also feeds the
            # AppKit-reimplementation conformance ladder). Upstream pins
            # Euclid 0.8.x via SwiftPM; we build it against .upstream/euclid
            # instead (HEAD == 0.8.14 today), so fetch euclid/lrucache/svgpath
            # alongside — or just use the `scenekit` meta-arm.
            fetch_repo shapescript https://github.com/nicklockwood/ShapeScript.git
            patch_shapescript
            ;;
        scenekit)
            # Meta-arm: everything the SceneKit conformance campaign needs.
            # See docs/scenekit-conformance.md.
            fetch_repo euclid https://github.com/nicklockwood/Euclid.git
            patch_euclid
            fetch_repo lrucache https://github.com/nicklockwood/LRUCache.git
            fetch_repo svgpath https://github.com/nicklockwood/SVGPath.git
            fetch_repo shapescript https://github.com/nicklockwood/ShapeScript.git
            patch_shapescript
            ;;
        *)
            echo "unknown upstream: $name" >&2
            exit 64
            ;;
    esac
done
