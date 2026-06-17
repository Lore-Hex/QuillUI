#!/usr/bin/env bash
#
# QuillSignal upstream-prepare pipeline step: symlink the committed ObjC-port
# Swift files into the SignalServiceKit source tree.
#
# The faithful Swift ports of Signal's ObjC core-model classes (TSInteraction,
# TSMessage, the TS*/OWS* subclasses, ...) live and are version-controlled in
# Sources/SignalServiceKitObjCPort/. SwiftPM compiles the SignalServiceKit
# *library* from the .upstream/ tree (gitignored/disposable), so each port must
# appear UNDER that tree to be compiled into the SAME module as the upstream
# Swift that subclasses it. This step symlinks every committed port into
# <SSK>/QuillPort/ using a RELATIVE path, so the link resolves both on the host
# and inside the build container (where the repo is mounted at a different
# absolute path -- an absolute symlink silently fails to compile there).
#
# Idempotent (rm + re-create each link). Run after fetching .upstream, alongside
# quill-signal-inject-foundation.sh and quill-signal-strip-tests.sh.
#
# Usage: scripts/quill-signal-link-ports.sh [SSK_ROOT]
#   SSK_ROOT defaults to .upstream/signal-ios/SignalServiceKit
#
set -euo pipefail

ROOT="${1:-.upstream/signal-ios/SignalServiceKit}"
PORT_SRC_DIR="Sources/SignalServiceKitObjCPort"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$ROOT" ]; then
    echo "error: SSK root not found: $ROOT" >&2
    exit 1
fi
if [ ! -d "$PORT_SRC_DIR" ]; then
    echo "error: port source dir not found: $PORT_SRC_DIR" >&2
    exit 1
fi

QUILLPORT_DIR="$ROOT/QuillPort"
mkdir -p "$QUILLPORT_DIR"

# Relative path from QuillPort/ back to the repo root, then into the port dir.
# QuillPort -> SignalServiceKit -> signal-ios -> .upstream -> <repo root>.
REL_PREFIX="../../../../$PORT_SRC_DIR"

linked=0
for f in "$PORT_SRC_DIR"/*.swift; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    link="$QUILLPORT_DIR/$base"
    rm -f "$link"
    ln -s "$REL_PREFIX/$base" "$link"
    linked=$((linked + 1))
done

"$SCRIPT_DIR/quill-signal-fix-ssk-concurrency.sh" "$ROOT"

MAIN_THREAD_UTILS="$ROOT/Debugging/OWSSwiftUtils.swift"
if [ -f "$MAIN_THREAD_UTILS" ]; then
python3 - "$MAIN_THREAD_UTILS" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
helper_needle = '''public func assertOnQueue(_ queue: DispatchQueue) {
    dispatchPrecondition(condition: .onQueue(queue))
}
'''
helper_replacement = '''public func assertOnQueue(_ queue: DispatchQueue) {
    dispatchPrecondition(condition: .onQueue(queue))
}

#if os(Linux)
@usableFromInline let quillSignalLinuxMainDispatchQueueKey = DispatchSpecificKey<Bool>()
@usableFromInline let quillSignalLinuxMainDispatchQueueInstalled: Bool = {
    DispatchQueue.main.setSpecific(key: quillSignalLinuxMainDispatchQueueKey, value: true)
    return true
}()

@usableFromInline
func quillSignalIsMainDispatchContext() -> Bool {
    _ = quillSignalLinuxMainDispatchQueueInstalled
    return Thread.isMainThread || DispatchQueue.getSpecific(key: quillSignalLinuxMainDispatchQueueKey) == true
}

@usableFromInline
func quillSignalIsMainThreadCompatible() -> Bool {
    if quillSignalIsMainDispatchContext() {
        return true
    }
    return ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DEMO"] == "real-conversation"
}
#endif
'''
if "quillSignalLinuxMainDispatchQueueKey" not in text:
    if helper_needle not in text:
        raise SystemExit(f"error: main-thread helper insertion point not found in {path}")
    text = text.replace(helper_needle, helper_replacement)
else:
    if "func quillSignalIsMainDispatchContext()" not in text:
        text = text.replace(
            "@usableFromInline\n"
            "func quillSignalIsMainThreadCompatible() -> Bool {\n",
            "@usableFromInline\n"
            "func quillSignalIsMainDispatchContext() -> Bool {\n"
            "    _ = quillSignalLinuxMainDispatchQueueInstalled\n"
            "    return Thread.isMainThread || DispatchQueue.getSpecific(key: quillSignalLinuxMainDispatchQueueKey) == true\n"
            "}\n"
            "\n"
            "@usableFromInline\n"
            "func quillSignalIsMainThreadCompatible() -> Bool {\n",
        )
    text = text.replace(
        "_ = quillSignalLinuxMainDispatchQueueInstalled\n"
        "    if Thread.isMainThread || DispatchQueue.getSpecific(key: quillSignalLinuxMainDispatchQueueKey) == true {\n"
        "        return true\n"
        "    }\n"
        "    return ProcessInfo.processInfo.environment[\"SIGNAL_UI_RENDER_DEMO\"] == \"real-conversation\"",
        "if quillSignalIsMainDispatchContext() {\n"
        "        return true\n"
        "    }\n"
        "    return ProcessInfo.processInfo.environment[\"SIGNAL_UI_RENDER_DEMO\"] == \"real-conversation\"",
    )

assert_main_needle = '''@inlinable
public func AssertIsOnMainThread(
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if !Thread.isMainThread {
        owsFailDebug("Must be on main thread.", logger: logger, file: file, function: function, line: line)
    }
}
'''
assert_main_replacement = '''@inlinable
public func AssertIsOnMainThread(
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
#if os(Linux)
    if !quillSignalIsMainThreadCompatible() {
        owsFailDebug("Must be on main thread.", logger: logger, file: file, function: function, line: line)
    }
#else
    if !Thread.isMainThread {
        owsFailDebug("Must be on main thread.", logger: logger, file: file, function: function, line: line)
    }
#endif
}
'''
if "if !quillSignalIsMainThreadCompatible()" not in text:
    if assert_main_needle not in text:
        raise SystemExit(f"error: AssertIsOnMainThread hook not found in {path}")
    text = text.replace(assert_main_needle, assert_main_replacement)

assert_not_main_needle = '''@inlinable
public func AssertNotOnMainThread(
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
    if Thread.isMainThread {
        owsFailDebug("Must be off main thread.", logger: logger, file: file, function: function, line: line)
    }
}
'''
assert_not_main_replacement = '''@inlinable
public func AssertNotOnMainThread(
    logger: PrefixedLogger = .empty(),
    file: String = #fileID,
    function: String = #function,
    line: Int = #line,
) {
#if os(Linux)
    if quillSignalIsMainThreadCompatible() {
        owsFailDebug("Must be off main thread.", logger: logger, file: file, function: function, line: line)
    }
#else
    if Thread.isMainThread {
        owsFailDebug("Must be off main thread.", logger: logger, file: file, function: function, line: line)
    }
#endif
}
'''
if "if quillSignalIsMainThreadCompatible()" not in text:
    if assert_not_main_needle not in text:
        raise SystemExit(f"error: AssertNotOnMainThread hook not found in {path}")
    text = text.replace(assert_not_main_needle, assert_not_main_replacement)

path.write_text(text)
PY
fi

THREADING="$ROOT/Concurrency/Threading.swift"
if [ -f "$THREADING" ]; then
python3 - "$THREADING" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
async_needle = '''public func DispatchMainThreadSafe(_ block: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.async(execute: block)
    }
}
'''
async_replacement = '''public func DispatchMainThreadSafe(_ block: @escaping @MainActor () -> Void) {
#if os(Linux)
    if quillSignalIsMainThreadCompatible() {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.async(execute: block)
    }
#else
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.async(execute: block)
    }
#endif
}
'''
if "quillSignalIsMainThreadCompatible()" not in text and "quillSignalIsMainDispatchContext()" not in text:
    if async_needle not in text:
        raise SystemExit(f"error: DispatchMainThreadSafe hook not found in {path}")
    text = text.replace(async_needle, async_replacement)
text = text.replace("if quillSignalIsMainThreadCompatible() {\n        MainActor.assumeIsolated(block)", "if quillSignalIsMainDispatchContext() {\n        MainActor.assumeIsolated(block)")

sync_needle = '''public func DispatchSyncMainThreadSafe(_ block: @escaping @MainActor () -> Void) {
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync(execute: block)
    }
}
'''
sync_replacement = '''public func DispatchSyncMainThreadSafe(_ block: @escaping @MainActor () -> Void) {
#if os(Linux)
    if quillSignalIsMainThreadCompatible() {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync(execute: block)
    }
#else
    if Thread.isMainThread {
        MainActor.assumeIsolated(block)
    } else {
        DispatchQueue.main.sync(execute: block)
    }
#endif
}
'''
if "DispatchSyncMainThreadSafe" in text and "#if os(Linux)" not in text[text.find("public func DispatchSyncMainThreadSafe"):text.find("public func DispatchSyncMainThreadSafe") + 250]:
    if sync_needle not in text:
        raise SystemExit(f"error: DispatchSyncMainThreadSafe hook not found in {path}")
    text = text.replace(sync_needle, sync_replacement)
text = text.replace("if quillSignalIsMainThreadCompatible() {\n        MainActor.assumeIsolated(block)", "if quillSignalIsMainDispatchContext() {\n        MainActor.assumeIsolated(block)")

path.write_text(text)
PY
fi

DB_CHANGE_OBSERVER="$ROOT/Storage/Database/Snapshots/DatabaseChangeObserver.swift"
if [ -f "$DB_CHANGE_OBSERVER" ]; then
python3 - "$DB_CHANGE_OBSERVER" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = '''            assert(appReadiness.isAppReady)
            appReadiness.runNowOrWhenAppWillBecomeReady(append)
'''
replacement = '''#if os(Linux)
            if ProcessInfo.processInfo.environment["SIGNAL_UI_RENDER_DEMO"] == "real-conversation" {
                append()
                return
            }
#endif
            assert(appReadiness.isAppReady)
            appReadiness.runNowOrWhenAppWillBecomeReady(append)
'''
if "SIGNAL_UI_RENDER_DEMO\"] == \"real-conversation\"" not in text:
    if needle not in text:
        raise SystemExit(f"error: DatabaseChangeObserver readiness hook not found in {path}")
    text = text.replace(needle, replacement)
path.write_text(text)
PY
fi

APP_VERSION="$ROOT/Util/AppVersion.swift"
if [ -f "$APP_VERSION" ]; then
python3 - "$APP_VERSION" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = '''private extension Bundle {
    func string(forInfoDictionaryKey key: String) -> String {
        guard let result = object(forInfoDictionaryKey: key) as? String else {
            owsFail("Couldn't fetch string from \\(key)")
        }
        if result.isEmpty {
            owsFail("String is unexpectedly empty")
        }
        return result
    }
}
'''
replacement = '''private extension Bundle {
    func string(forInfoDictionaryKey key: String) -> String {
        guard let result = object(forInfoDictionaryKey: key) as? String else {
#if os(Linux)
            switch key {
            case "CFBundleShortVersionString":
                return "0.0.0"
            case "CFBundleVersion":
                return "1"
            default:
                break
            }
#endif
            owsFail("Couldn't fetch string from \\(key)")
        }
        if result.isEmpty {
            owsFail("String is unexpectedly empty")
        }
        return result
    }
}
'''
if "#if os(Linux)\n            switch key {" not in text:
    if needle not in text:
        raise SystemExit(f"error: AppVersion bundle-version hook not found in {path}")
    path.write_text(text.replace(needle, replacement))
PY
fi

CERTIFICATES="$ROOT/Security/Certificates.swift"
if [ -f "$CERTIFICATES" ]; then
python3 - "$CERTIFICATES" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
needle = '''    private static func dataFromCertificateFile(_ name: String, extension: String) -> Data {
        let bundle = Bundle(for: SignalServiceKitBundleAnchor.self)
        guard let url = bundle.url(forResource: name, withExtension: `extension`) else {
            owsFail("missing X.509 certificate in SignalServiceKit \\(name).\\(`extension`)")
        }

        do {
            let data = try Data(contentsOf: url)
            owsPrecondition(!data.isEmpty)
            return data
        } catch {
            owsFail("error reading X.509 certificate in SignalServiceKit \\(name).\\(`extension`): \\(error)")
        }
    }
'''
replacement = '''    private static func dataFromCertificateFile(_ name: String, extension: String) -> Data {
        let bundle = Bundle(for: SignalServiceKitBundleAnchor.self)
        guard let url = bundle.url(forResource: name, withExtension: `extension`) else {
#if os(Linux)
            let relativePath = ".upstream/signal-ios/SignalServiceKit/Resources/Certificates/\\(name).\\(`extension`)"
            let candidates = [
                FileManager.default.currentDirectoryPath + "/" + relativePath,
                relativePath,
            ]
            for path in candidates {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: path))
                    owsPrecondition(!data.isEmpty)
                    return data
                } catch {
                    owsFail("error reading X.509 certificate in SignalServiceKit \\(name).\\(`extension`): \\(error)")
                }
            }
#endif
            owsFail("missing X.509 certificate in SignalServiceKit \\(name).\\(`extension`)")
        }

        do {
            let data = try Data(contentsOf: url)
            owsPrecondition(!data.isEmpty)
            return data
        } catch {
            owsFail("error reading X.509 certificate in SignalServiceKit \\(name).\\(`extension`): \\(error)")
        }
    }
'''
if "Resources/Certificates/\\(name)" not in text:
    if needle not in text:
        raise SystemExit(f"error: Certificates Linux resource hook not found in {path}")
    path.write_text(text.replace(needle, replacement))
PY
fi

BACKGROUND_TASK="$ROOT/Util/OWSBackgroundTask.swift"
if [ -f "$BACKGROUND_TASK" ]; then
python3 - "$BACKGROUND_TASK" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
shared_needle = '''public class OWSBackgroundTaskManager {
    public static let shared = {
        if Thread.isMainThread {
            return OWSBackgroundTaskManager()
        } else {
            return DispatchQueue.main.sync {
                OWSBackgroundTaskManager()
            }
        }
    }()
'''
shared_replacement = '''public class OWSBackgroundTaskManager {
    public static let shared = {
#if os(Linux)
        return OWSBackgroundTaskManager()
#else
        if Thread.isMainThread {
            return OWSBackgroundTaskManager()
        } else {
            return DispatchQueue.main.sync {
                OWSBackgroundTaskManager()
            }
        }
#endif
    }()
'''
if "#if os(Linux)\n        return OWSBackgroundTaskManager()" not in text:
    if shared_needle not in text:
        raise SystemExit(f"error: OWSBackgroundTaskManager.shared hook not found in {path}")
    text = text.replace(shared_needle, shared_replacement)

init_needle = '''    private init() {
        AssertIsOnMainThread()
        SwiftSingletons.register(self)
    }
'''
init_replacement = '''    private init() {
#if !os(Linux)
        AssertIsOnMainThread()
#endif
        SwiftSingletons.register(self)
    }
'''
if "#if !os(Linux)\n        AssertIsOnMainThread()" not in text:
    if init_needle not in text:
        raise SystemExit(f"error: OWSBackgroundTaskManager init hook not found in {path}")
    text = text.replace(init_needle, init_replacement)

path.write_text(text)
PY
fi

echo "quill-signal-link-ports: linked $linked port file(s) into $QUILLPORT_DIR"
