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
    # `extension ButtonRow: QuillActionDispatching`, so guard on the class-line
    # conformance specifically (not a bare QuillReusableView grep).
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
