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
