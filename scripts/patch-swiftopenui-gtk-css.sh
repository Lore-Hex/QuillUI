#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRATCH_PATH="${1:-$ROOT_DIR/.build-linux}"
PACKAGE_PATH="${QUILLUI_SWIFT_PACKAGE_PATH:-$ROOT_DIR}"
SWIFTOPENUI_ROOT="${QUILLUI_SWIFTOPENUI_ROOT:-$PACKAGE_PATH/third_party/SwiftOpenUI}"
SWIFTOPENUI_MANIFEST="$SWIFTOPENUI_ROOT/Package.swift"
RENDERER="$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/Rendering/GTKRenderer.swift"
DESCRIPTOR_TREE="$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/Rendering/GTK4DescriptorTree.swift"
GTK_BACKEND="$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/Rendering/GTK4Backend.swift"
GTK_VIEW_HOST="$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/Rendering/GTKViewHost.swift"
NAVIGATION="$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/Rendering/GTKNavigation.swift"
GTK_SHIM="$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/CGTK/shim.h"
NAVIGATION_DESTINATION="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Navigation/NavigationDestination.swift"
TOOLBAR_MODIFIER="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Modifiers/ToolbarModifier.swift"
LAYOUT="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Layout/Layout.swift"
STATE="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/State/State.swift"
OBSERVABLE_OBJECT="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/State/ObservableObject.swift"
BINDABLE="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/State/Bindable.swift"
ENVIRONMENT="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Environment/Environment.swift"
CONTROL_STYLE_MODIFIERS="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Modifiers/ControlStyleModifiers.swift"
CONFIRMATION_DIALOG_MODIFIER="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Modifiers/ConfirmationDialogModifier.swift"
ON_CHANGE_MODIFIER="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Modifiers/OnChangeModifier.swift"
FRAME_MODIFIER="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Modifiers/FrameModifier.swift"
SYMBOLS="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"
SYMBOL_CODEPOINTS="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUISymbols/MaterialSymbolsCodepoints.swift"
SCROLL_VIEW="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Views/ScrollView.swift"
SCROLL_VIEW_READER="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Views/ScrollViewReader.swift"

LOCALIZATION="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Localization.swift"

MENU_VIEW="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Views/Menu.swift"

SWIFT_DEPENDENCIES_MAIN_QUEUE="$SCRATCH_PATH/checkouts/swift-dependencies/Sources/Dependencies/DependencyValues/MainQueue.swift"
SWIFT_DEPENDENCIES_MAIN_RUN_LOOP="$SCRATCH_PATH/checkouts/swift-dependencies/Sources/Dependencies/DependencyValues/MainRunLoop.swift"
SWIFT_DEPENDENCIES_SOURCE_DIR="$SCRATCH_PATH/checkouts/swift-dependencies/Sources/Dependencies"
SWIFT_SHARING_SOURCE_DIR="$SCRATCH_PATH/checkouts/swift-sharing/Sources/Sharing"
SWIFT_SHARING_PASSTHROUGH_RELAY="$SCRATCH_PATH/checkouts/swift-sharing/Sources/Sharing/Internal/PassthroughRelay.swift"
SWIFT_SHARING_APP_STORAGE_KEY="$SCRATCH_PATH/checkouts/swift-sharing/Sources/Sharing/SharedKeys/AppStorageKey.swift"
SWIFT_SHARING_FILE_STORAGE_KEY="$SCRATCH_PATH/checkouts/swift-sharing/Sources/Sharing/SharedKeys/FileStorageKey.swift"
COMBINE_SCHEDULERS_SOURCE_DIR="$SCRATCH_PATH/checkouts/combine-schedulers/Sources/CombineSchedulers"
CUSTOM_DUMP_SOURCE_DIR="$SCRATCH_PATH/checkouts/swift-custom-dump/Sources/CustomDump"
SWIFT_PERCEPTION_SOURCE_DIR="$SCRATCH_PATH/checkouts/swift-perception/Sources"
XCTEST_DYNAMIC_OVERLAY_SOURCE_DIR="$SCRATCH_PATH/checkouts/xctest-dynamic-overlay/Sources/IssueReporting"
GRDB_SOURCE_DIR="$SCRATCH_PATH/checkouts/GRDB.swift/GRDB"
VENDORED_GRDB_SOURCE_DIR="$PACKAGE_PATH/third_party/GRDB.swift/GRDB"
SQLITE_DATA_SOURCE_DIR="$SCRATCH_PATH/checkouts/sqlite-data/Sources/SQLiteData"

# Resolve unconditionally so $SCRATCH_PATH/checkouts/ is populated BEFORE the
# patches below run against it (OpenCombine/GRDB/swift-dependencies/etc.). The
# subsequent `swift test --scratch-path "$SCRATCH_PATH"` REUSES these patched
# checkouts; if we skip the resolve, the build re-resolves them UNPATCHED and
# fails with `missing required module 'COpenCombineHelpers'`. Do NOT gate this
# on SwiftOpenUI-file presence — SwiftOpenUI is now vendored in-tree
# (third_party/SwiftOpenUI) so such a gate is always true and silently disables
# the resolve in the real build. Only the hermetic patcher unit-test (which sets
# up its own stub checkouts and has no real package to resolve) opts out.
if [[ "${QUILLUI_SKIP_PACKAGE_RESOLVE:-0}" != "1" ]]; then
  swift package resolve --package-path "$PACKAGE_PATH" --scratch-path "$SCRATCH_PATH" >/dev/null
fi

if [[ ! -f "$SWIFTOPENUI_MANIFEST" ]]; then
  echo "SwiftOpenUI manifest was not found at $SWIFTOPENUI_MANIFEST" >&2
  exit 1
fi

if [[ ! -f "$RENDERER" ]]; then
  echo "SwiftOpenUI GTK renderer was not found at $RENDERER" >&2
  exit 1
fi

if [[ ! -f "$DESCRIPTOR_TREE" ]]; then
  echo "SwiftOpenUI GTK descriptor tree was not found at $DESCRIPTOR_TREE" >&2
  exit 1
fi

if [[ ! -f "$GTK_BACKEND" ]]; then
  echo "SwiftOpenUI GTK backend was not found at $GTK_BACKEND" >&2
  exit 1
fi

if [[ ! -f "$GTK_VIEW_HOST" ]]; then
  echo "SwiftOpenUI GTK view host was not found at $GTK_VIEW_HOST" >&2
  exit 1
fi

if [[ ! -f "$NAVIGATION" ]]; then
  echo "SwiftOpenUI GTK navigation renderer was not found at $NAVIGATION" >&2
  exit 1
fi

if [[ ! -f "$NAVIGATION_DESTINATION" ]]; then
  echo "SwiftOpenUI navigation destination source was not found at $NAVIGATION_DESTINATION" >&2
  exit 1
fi

if [[ ! -f "$TOOLBAR_MODIFIER" ]]; then
  echo "SwiftOpenUI toolbar modifier was not found at $TOOLBAR_MODIFIER" >&2
  exit 1
fi

if [[ ! -f "$LAYOUT" ]]; then
  echo "SwiftOpenUI layout helpers were not found at $LAYOUT" >&2
  exit 1
fi

if [[ ! -f "$FRAME_MODIFIER" ]]; then
  echo "SwiftOpenUI frame modifier source was not found at $FRAME_MODIFIER" >&2
  exit 1
fi

if [[ ! -f "$SYMBOLS" ]]; then
  echo "SwiftOpenUI symbol compatibility map was not found at $SYMBOLS" >&2
  exit 1
fi

if [[ ! -f "$SCROLL_VIEW_READER" ]]; then
  echo "SwiftOpenUI ScrollViewReader source was not found at $SCROLL_VIEW_READER" >&2
  exit 1
fi


if [[ ! -f "$SCROLL_VIEW" ]]; then
  echo "SwiftOpenUI ScrollView source was not found at $SCROLL_VIEW" >&2
  exit 1
fi

if [[ ! -f "$LOCALIZATION" ]]; then
  echo "SwiftOpenUI localization source was not found at $LOCALIZATION" >&2
  exit 1
fi

chmod u+w "$SWIFTOPENUI_MANIFEST" "$RENDERER" "$DESCRIPTOR_TREE" "$GTK_BACKEND" "$GTK_VIEW_HOST" "$NAVIGATION" "$NAVIGATION_DESTINATION" "$TOOLBAR_MODIFIER" "$LAYOUT" "$SYMBOLS" "$SCROLL_VIEW" "$SCROLL_VIEW_READER" "$LOCALIZATION"

chmod u+w "$SWIFTOPENUI_MANIFEST" "$RENDERER" "$DESCRIPTOR_TREE" "$GTK_BACKEND" "$GTK_VIEW_HOST" "$NAVIGATION" "$TOOLBAR_MODIFIER" "$LAYOUT" "$SYMBOLS" "$SCROLL_VIEW_READER"
if [[ -f "$MENU_VIEW" ]]; then
  chmod u+w "$MENU_VIEW"
fi

if [[ -f "$GTK_SHIM" ]]; then
  chmod u+w "$GTK_SHIM"
fi
if [[ -f "$STATE" ]]; then
  chmod u+w "$STATE"
fi
if [[ -f "$OBSERVABLE_OBJECT" ]]; then
  chmod u+w "$OBSERVABLE_OBJECT"
fi
if [[ -f "$BINDABLE" ]]; then
  chmod u+w "$BINDABLE"
fi
if [[ -f "$CONTROL_STYLE_MODIFIERS" ]]; then
  chmod u+w "$CONTROL_STYLE_MODIFIERS"
fi
if [[ -f "$CONFIRMATION_DIALOG_MODIFIER" ]]; then
  chmod u+w "$CONFIRMATION_DIALOG_MODIFIER"
fi
if [[ -f "$ON_CHANGE_MODIFIER" ]]; then
  chmod u+w "$ON_CHANGE_MODIFIER"
fi
chmod u+w "$FRAME_MODIFIER"

if [[ -f "$OBSERVABLE_OBJECT" && -f "$BINDABLE" ]]; then
  python3 - "$OBSERVABLE_OBJECT" "$BINDABLE" <<'PY'
import sys
from pathlib import Path

observable_path = Path(sys.argv[1])
bindable_path = Path(sys.argv[2])

original_observable = observable_path.read_text()
observable = original_observable
if "environmentObservableObjectGeneration" not in observable:
    observable = observable.replace(
        """    private func objectDidChange() {
        let liveHosts: [AnyViewHost]
""",
        """    func objectDidChange() {
        let liveHosts: [AnyViewHost]
""",
        1,
    )
    observable = observable.replace(
        """func wireEnvironmentObservableObjectRead(_ object: AnyObject, host: AnyViewHost?) {
    guard let observable = object as? any ObservableObject else { return }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    storage.addHost(host)
}

// MARK: - @ObservedObject
""",
        """func wireEnvironmentObservableObjectRead(_ object: AnyObject, host: AnyViewHost?) {
    guard let observable = object as? any ObservableObject else { return }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    storage.addHost(host)
}

func environmentObservableObjectGeneration(_ object: AnyObject) -> UInt64? {
    guard let observable = object as? any ObservableObject else { return nil }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    return storage.generation
}

func notifyEnvironmentObservableObjectMutation(
    _ object: AnyObject,
    ifGenerationMatches expectedGeneration: UInt64?
) {
    guard let expectedGeneration,
          let observable = object as? any ObservableObject else { return }
    let storage = EnvironmentObservableObjectDependencyRegistry.shared.storage(for: observable)
    guard storage.generation == expectedGeneration else { return }
    storage.objectDidChange()
}

// MARK: - @ObservedObject
""",
        1,
    )
elif "private func objectDidChange()" in observable:
    observable = observable.replace(
        "    private func objectDidChange() {",
        "    func objectDidChange() {",
        1,
    )
if observable != original_observable:
    observable_path.write_text(observable)

original_bindable = bindable_path.read_text()
bindable = original_bindable
if "notifyEnvironmentObservableObjectMutation(" not in bindable:
    bindable = bindable.replace(
        """            get: { object[keyPath: keyPath] },
            set: { object[keyPath: keyPath] = $0 },
            quillUIIdentity: BindingIdentity(
""",
        """            get: { object[keyPath: keyPath] },
            set: {
                let generation = environmentObservableObjectGeneration(object)
                object[keyPath: keyPath] = $0
                notifyEnvironmentObservableObjectMutation(
                    object,
                    ifGenerationMatches: generation
                )
            },
            quillUIIdentity: BindingIdentity(
""",
        1,
    )
if bindable != original_bindable:
    bindable_path.write_text(bindable)
PY
fi

python3 - "$ON_CHANGE_MODIFIER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.exists():
    raise SystemExit("SwiftOpenUI OnChange modifier source was not found")
original = path.read_text()
text = original

if "private struct OnChangeStorageKey: Hashable" not in text:
    old_storage = """/// Global storage for previous onChange values, keyed by render-pass counter.
/// Backends call `onChangeCheckAndFire` during rendering.
/// Not per-host — shared across all hosts in the process.
private var _onChangePreviousValues: [Int: Any] = [:]
"""
    new_storage = """private struct OnChangeStorageKey: Hashable {
    let namespace: String
    let index: Int
}

/// Global storage for previous onChange values, keyed by backend-provided
/// render namespace plus render-pass counter. Backends call
/// `onChangeCheckAndFire` during rendering.
private var _onChangePreviousValues: [OnChangeStorageKey: Any] = [:]
"""
    if old_storage not in text:
        raise SystemExit("SwiftOpenUI OnChange storage shape was not recognized")
    text = text.replace(old_storage, new_storage, 1)

if "namespace: String = \"default\"" not in text:
    old_single = """@discardableResult
public func onChangeCheckAndFire<V: Equatable>(value: V, action: (V) -> Void) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1

    if let previous = _onChangePreviousValues[key] as? V {
        if previous != value {
            action(value)
        }
    }
    // Store current value for next render pass
    _onChangePreviousValues[key] = value

    return key
}
"""
    new_single = """@discardableResult
public func onChangeCheckAndFire<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    action: (V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(value)
        }
    }
    // Store current value for next render pass
    _onChangePreviousValues[storageKey] = value

    return key
}
"""
    if old_single not in text:
        raise SystemExit("SwiftOpenUI OnChange single-argument shape was not recognized")
    text = text.replace(old_single, new_single, 1)

if "public func onChangeCheckAndFireTwoArg<V: Equatable>(\n    namespace: String = \"default\"," not in text:
    old_two_arg = """@discardableResult
public func onChangeCheckAndFireTwoArg<V: Equatable>(
    value: V,
    action: (V, V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1

    if let previous = _onChangePreviousValues[key] as? V {
        if previous != value {
            action(previous, value)
        }
    }
    _onChangePreviousValues[key] = value

    return key
}
"""
    new_two_arg = """@discardableResult
public func onChangeCheckAndFireTwoArg<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    action: (V, V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(previous, value)
        }
    }
    _onChangePreviousValues[storageKey] = value

    return key
}
"""
    if old_two_arg not in text:
        raise SystemExit("SwiftOpenUI OnChange two-argument shape was not recognized")
    text = text.replace(old_two_arg, new_two_arg, 1)

if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

transparent_primary_action = '''    if let multi = view as? any TransparentMultiChildView {
        for child in multi.children {
            if let action = gtkPrimaryTapAction(inAny: child, depth: depth + 1) {
                return action
            }
        }
        return nil
    }

'''
if transparent_primary_action not in text:
    marker = '''    let mirror = Mirror(reflecting: view)
'''
    function_start = text.find("private func gtkPrimaryTapAction<V: View>")
    marker_offset = text.find(marker, function_start)
    if function_start < 0 or marker_offset < 0:
        raise SystemExit("SwiftOpenUI transparent primary-action traversal shape was not recognized")
    text = text[:marker_offset] + transparent_primary_action + text[marker_offset:]

test_helper = '''func gtkTestActivatePrimaryTapAction<V: View>(in view: V) -> Bool {
    guard let action = gtkPrimaryTapAction(in: view) else { return false }
    action()
    return true
}

'''
if test_helper not in text:
    marker = "private func gtkScheduleListRowTapAction("
    function_start = text.find("private func gtkPrimaryTapAction<V: View>")
    marker_offset = text.find(marker, function_start)
    if function_start < 0 or marker_offset < 0:
        raise SystemExit("SwiftOpenUI primary-action test helper insertion point was not recognized")
    text = text[:marker_offset] + test_helper + text[marker_offset:]

if text != original:
    path.write_text(text)
PY

python3 - \
    "$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/App/App.swift" \
    "$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/App/WindowSizing.swift" \
    "$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/Rendering/GTK4Backend.swift" \
    "$SWIFTOPENUI_ROOT/Sources/Backend/GTK4/Rendering/GTKRenderer.swift" <<'PY'
from pathlib import Path
import sys


def replace_once(text, old, new, marker, label):
    if marker in text:
        return text
    if old not in text:
        raise SystemExit(f"SwiftOpenUI {label} shape was not recognized")
    return text.replace(old, new, 1)


app_path, sizing_path, backend_path, renderer_path = map(Path, sys.argv[1:])

original = app_path.read_text()
text = original
text = replace_once(
    text,
    '''    public let quillHidesTitleBar: Bool
    /// Type key used by SwiftUI's value-based `WindowGroup(for:)` API.
''',
    '''    public let quillHidesTitleBar: Bool
    /// Rebuilds the startup window content from the original ViewBuilder.
    /// SwiftUI reevaluates a WindowGroup builder when app-level state changes;
    /// retaining only the first value would freeze derived environment values.
    public let quillContentFactory: () -> Content
    /// Type key used by SwiftUI's value-based `WindowGroup(for:)` API.
''',
    "public let quillContentFactory: () -> Content",
    "deferred WindowGroup property",
)
text = replace_once(
    text,
    '''    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content())
    }

    public init(@ViewBuilder content: () -> Content) {
        self.init(title: "", content: content())
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        self.init(title: id, content: content(), launchesAtStartup: true)
    }
''',
    '''    public init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(
            title: title,
            content: content(),
            quillContentFactory: content
        )
    }

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.init(
            title: "",
            content: content(),
            quillContentFactory: content
        )
    }

    public init(id: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(
            title: id,
            content: content(),
            launchesAtStartup: true,
            quillContentFactory: content
        )
    }
''',
    "public init(_ title: String, @ViewBuilder content: @escaping () -> Content)",
    "deferred WindowGroup startup initializers",
)
text = replace_once(
    text,
    '''            launchesAtStartup: false,
            quillValueTypeKey: quillOpenWindowValueTypeKey(for: valueType),
''',
    '''            launchesAtStartup: false,
            quillContentFactory: { content(.constant(nil)) },
            quillValueTypeKey: quillOpenWindowValueTypeKey(for: valueType),
''',
    "quillContentFactory: { content(.constant(nil)) },\n            quillValueTypeKey: quillOpenWindowValueTypeKey(for: valueType)",
    "deferred value WindowGroup factory",
)
text = replace_once(
    text,
    '''            launchesAtStartup: false,
            quillValueTypeKey: quillOpenWindowValueTypeKey(id: id, for: valueType),
''',
    '''            launchesAtStartup: false,
            quillContentFactory: { content(.constant(nil)) },
            quillValueTypeKey: quillOpenWindowValueTypeKey(id: id, for: valueType),
''',
    "quillContentFactory: { content(.constant(nil)) },\n            quillValueTypeKey: quillOpenWindowValueTypeKey(id: id, for: valueType)",
    "deferred ID value WindowGroup factory",
)
text = replace_once(
    text,
    '''        launchesAtStartup: Bool = true,
        quillHidesTitleBar: Bool = false,
        quillValueTypeKey: String? = nil,
''',
    '''        launchesAtStartup: Bool = true,
        quillHidesTitleBar: Bool = false,
        quillContentFactory: (() -> Content)? = nil,
        quillValueTypeKey: String? = nil,
''',
    "quillContentFactory: (() -> Content)? = nil",
    "deferred WindowGroup internal initializer",
)
text = replace_once(
    text,
    '''        self.launchesAtStartup = launchesAtStartup
        self.quillHidesTitleBar = quillHidesTitleBar
        self.quillValueTypeKey = quillValueTypeKey
''',
    '''        self.launchesAtStartup = launchesAtStartup
        self.quillHidesTitleBar = quillHidesTitleBar
        self.quillContentFactory = quillContentFactory ?? { content }
        self.quillValueTypeKey = quillValueTypeKey
''',
    "self.quillContentFactory = quillContentFactory ?? { content }",
    "deferred WindowGroup factory storage",
)
if text != original:
    app_path.write_text(text)

original = sizing_path.read_text()
text = original
factory_argument = "            quillContentFactory: quillContentFactory,\n"
if text.count(factory_argument) < 6:
    anchor = "            quillValueTypeKey: quillValueTypeKey,\n"
    if text.count(anchor) != 6:
        raise SystemExit("SwiftOpenUI WindowGroup sizing-copy shape was not recognized")
    text = text.replace(anchor, factory_argument + anchor)
if text != original:
    sizing_path.write_text(text)

original = backend_path.read_text()
text = original
text = replace_once(
    text,
    '''                    content: self.quillContent(forPresentedValue: value),
                    dismissesWindow: true,
''',
    '''                    content: self.quillContent(forPresentedValue: value),
                    contentFactory: {
                        self.quillContent(forPresentedValue: value)
                    },
                    dismissesWindow: true,
''',
    "contentFactory: {\n                        self.quillContent(forPresentedValue: value)",
    "GTK value-window deferred content",
)
text = replace_once(
    text,
    "        gtkCreateWindow(app: app, content: content, appStateSource: appStateSource)\n",
    '''        gtkCreateWindow(
            app: app,
            content: content,
            contentFactory: quillContentFactory,
            appStateSource: appStateSource
        )
''',
    "contentFactory: quillContentFactory",
    "GTK startup-window deferred content",
)
text = replace_once(
    text,
    '''        app: OpaquePointer?,
        content renderedContent: Content,
        dismissesWindow: Bool = false,
''',
    '''        app: OpaquePointer?,
        content renderedContent: Content,
        contentFactory: @escaping () -> Content,
        dismissesWindow: Bool = false,
''',
    "contentFactory: @escaping () -> Content",
    "GTK deferred content parameter",
)
root_call = "gtkRenderWindowRootView(renderedContent, appStateSource: appStateSource)"
if "contentProvider: contentFactory" not in text:
    if text.count(root_call) != 2:
        raise SystemExit("SwiftOpenUI GTK WindowGroup root-render shape was not recognized")
    text = text.replace(
        root_call,
        '''gtkRenderWindowRootView(
                    renderedContent,
                    appStateSource: appStateSource,
                    contentProvider: contentFactory
                )''',
    )
if text != original:
    backend_path.write_text(text)

original = renderer_path.read_text()
text = original
text = replace_once(
    text,
    '''func gtkRenderWindowRootView<V: View>(_ view: V, appStateSource: Any? = nil) -> OpaquePointer {
    let host = GTKViewHost(buildBody: {
        MainActor.assumeIsolated { gtkRenderView(view) }
    })
    host.describeBody = {
        MainActor.assumeIsolated { gtkDescribeView(view) }
    }
''',
    '''func gtkRenderWindowRootView<V: View>(
    _ view: V,
    appStateSource: Any? = nil,
    contentProvider: (() -> V)? = nil
) -> OpaquePointer {
    let buildContent = contentProvider ?? { view }
    let host = GTKViewHost(buildBody: {
        gtkAssumeMainActorIsolated { gtkRenderView(buildContent()) }
    })
    host.describeBody = {
        gtkAssumeMainActorIsolated { gtkDescribeView(buildContent()) }
    }
''',
    "contentProvider: (() -> V)? = nil",
    "GTK root deferred content provider",
)
if text != original:
    renderer_path.write_text(text)
PY

python3 - "$ON_CHANGE_MODIFIER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

def replace_once(old: str, new: str, label: str) -> None:
    global text
    if old not in text:
        raise SystemExit(f"SwiftOpenUI {label} shape was not recognized")
    text = text.replace(old, new, 1)

if "public init(content: Content, value: V, action: @escaping (V) -> Void)" not in text:
    replace_once(
        """    public let action: (V) -> Void

    public var body: Never { fatalError() }
}""",
        """    public let action: (V) -> Void

    public init(content: Content, value: V, action: @escaping (V) -> Void) {
        self.content = content
        self.value = value
        self.action = action
    }

    public var body: Never { fatalError() }
}""",
        "OnChangeView public initializer",
    )

if "public init(content: Content, value: V, action: @escaping (V, V) -> Void)" not in text:
    replace_once(
        """    public let action: (V, V) -> Void

    public var body: Never { fatalError() }
}""",
        """    public let action: (V, V) -> Void

    public init(content: Content, value: V, action: @escaping (V, V) -> Void) {
        self.content = content
        self.value = value
        self.action = action
    }

    public var body: Never { fatalError() }
}""",
        "OnChangeTwoArgView public initializer",
    )

if "public struct InitialOnChangeView" not in text:
    initial_types = r'''
/// `onChange(of:initial:)` is a distinct primitive so adding the newer SwiftUI
/// overload does not change the stored layout of the original public view type.
public struct InitialOnChangeView<Content: View, V: Equatable>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: V
    public let initial: Bool
    public let action: (V) -> Void

    public init(content: Content, value: V, initial: Bool, action: @escaping (V) -> Void) {
        self.content = content
        self.value = value
        self.initial = initial
        self.action = action
    }

    public var body: Never { fatalError() }
}

public struct InitialOnChangeTwoArgView<Content: View, V: Equatable>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let value: V
    public let initial: Bool
    public let action: (V, V) -> Void

    public init(content: Content, value: V, initial: Bool, action: @escaping (V, V) -> Void) {
        self.content = content
        self.value = value
        self.initial = initial
        self.action = action
    }

    public var body: Never { fatalError() }
}
'''
    marker = "\n\nextension View {"
    if marker not in text:
        raise SystemExit("SwiftOpenUI initial OnChange type insertion shape was not recognized")
    text = text.replace(marker, "\n" + initial_types + marker, 1)

if "_ action: @escaping () -> Void\n    ) -> InitialOnChangeView" not in text:
    single_marker = """    public func onChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> OnChangeView<Self, V> {
        OnChangeView(content: self, value: value, action: action)
    }
"""
    initial_single_overloads = r'''

    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping () -> Void
    ) -> InitialOnChangeView<Self, V> {
        InitialOnChangeView(content: self, value: value, initial: initial) { _ in action() }
    }

    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping (V) -> Void
    ) -> InitialOnChangeView<Self, V> {
        InitialOnChangeView(content: self, value: value, initial: initial, action: action)
    }
'''
    if single_marker not in text:
        raise SystemExit("SwiftOpenUI initial OnChange single-argument overload shape was not recognized")
    text = text.replace(single_marker, single_marker + initial_single_overloads, 1)

if "_ action: @escaping (V, V) -> Void\n    ) -> InitialOnChangeTwoArgView" not in text:
    two_arg_marker = """    public func onChange<V: Equatable>(
        of value: V,
        _ action: @escaping (V, V) -> Void
    ) -> OnChangeTwoArgView<Self, V> {
        OnChangeTwoArgView(content: self, value: value, action: action)
    }
"""
    initial_two_arg_overload = r'''

    public func onChange<V: Equatable>(
        of value: V,
        initial: Bool,
        _ action: @escaping (V, V) -> Void
    ) -> InitialOnChangeTwoArgView<Self, V> {
        InitialOnChangeTwoArgView(content: self, value: value, initial: initial, action: action)
    }
'''
    if two_arg_marker not in text:
        raise SystemExit("SwiftOpenUI initial OnChange two-argument overload shape was not recognized")
    text = text.replace(two_arg_marker, two_arg_marker + initial_two_arg_overload, 1)

if "value: V,\n    initial: Bool,\n    action: (V) -> Void" not in text:
    old_single_tracking = """@discardableResult
public func onChangeCheckAndFire<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    action: (V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(value)
        }
    }
    // Store current value for next render pass
    _onChangePreviousValues[storageKey] = value

    return key
}
"""
    new_single_tracking = """@discardableResult
public func onChangeCheckAndFire<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    action: (V) -> Void
) -> Int {
    onChangeCheckAndFire(
        namespace: namespace,
        value: value,
        initial: false,
        action: action
    )
}

@discardableResult
public func onChangeCheckAndFire<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    initial: Bool,
    action: (V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(value)
        }
    } else if initial {
        action(value)
    }
    // Store current value for next render pass
    _onChangePreviousValues[storageKey] = value

    return key
}
"""
    replace_once(old_single_tracking, new_single_tracking, "initial OnChange tracking")

if "value: V,\n    initial: Bool,\n    action: (V, V) -> Void" not in text:
    old_two_arg_tracking = """@discardableResult
public func onChangeCheckAndFireTwoArg<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    action: (V, V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(previous, value)
        }
    }
    _onChangePreviousValues[storageKey] = value

    return key
}
"""
    new_two_arg_tracking = """@discardableResult
public func onChangeCheckAndFireTwoArg<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    action: (V, V) -> Void
) -> Int {
    onChangeCheckAndFireTwoArg(
        namespace: namespace,
        value: value,
        initial: false,
        action: action
    )
}

@discardableResult
public func onChangeCheckAndFireTwoArg<V: Equatable>(
    namespace: String = \"default\",
    value: V,
    initial: Bool,
    action: (V, V) -> Void
) -> Int {
    let key = _onChangeCounter
    _onChangeCounter += 1
    let storageKey = OnChangeStorageKey(namespace: namespace, index: key)

    if let previous = _onChangePreviousValues[storageKey] as? V {
        if previous != value {
            action(previous, value)
        }
    } else if initial {
        action(value, value)
    }
    _onChangePreviousValues[storageKey] = value

    return key
}
"""
    replace_once(old_two_arg_tracking, new_two_arg_tracking, "initial two-argument OnChange tracking")

if text != original:
    path.write_text(text)
PY

python3 - "$FRAME_MODIFIER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

if "public struct ContainerRelativeFrameView" not in text:
    container_type = r'''
/// A frame whose size is derived from the nearest container's proposal.
///
/// SwiftUI uses this primitive for paged media, galleries, and other views
/// whose item width is a fraction of a scroll viewport. Keeping the division
/// metadata intact lets each backend resolve the size after its native parent
/// has received a real allocation.
public struct ContainerRelativeFrameView<Content: View>: View, PrimitiveView {
    public typealias Body = Never

    public let content: Content
    public let axes: Axis
    public let count: Int
    public let span: Int
    public let spacing: Double
    public let alignment: Alignment

    public init(
        content: Content,
        axes: Axis,
        count: Int,
        span: Int,
        spacing: Double,
        alignment: Alignment
    ) {
        self.content = content
        self.axes = axes
        self.count = count
        self.span = span
        self.spacing = spacing
        self.alignment = alignment
    }

    public var body: Never { fatalError("ContainerRelativeFrameView is a primitive view") }

    /// Resolve one axis using SwiftUI's count/span/spacing division.
    public func resolvedLength(in containerLength: Double) -> Double {
        let resolvedCount = max(1, count)
        let resolvedSpan = min(max(1, span), resolvedCount)
        let resolvedSpacing = max(0, spacing)
        let available = max(0, containerLength - Double(resolvedCount - 1) * resolvedSpacing)
        let itemLength = available / Double(resolvedCount)
        return itemLength * Double(resolvedSpan) + Double(resolvedSpan - 1) * resolvedSpacing
    }
}
'''
    marker = "\n\nextension View {"
    if marker not in text:
        raise SystemExit("SwiftOpenUI container-relative frame type insertion shape was not recognized")
    text = text.replace(marker, "\n" + container_type + marker, 1)

if "public func containerRelativeFrame(" not in text:
    methods = r'''

    /// Size this view relative to the nearest container on the selected axes.
    public func containerRelativeFrame(
        _ axes: Axis,
        alignment: Alignment = .center
    ) -> ContainerRelativeFrameView<Self> {
        ContainerRelativeFrameView(
            content: self,
            axes: axes,
            count: 1,
            span: 1,
            spacing: 0,
            alignment: alignment
        )
    }

    /// Divide the nearest container into equally sized slots and occupy a span.
    public func containerRelativeFrame(
        _ axes: Axis,
        count: Int,
        span: Int,
        spacing: Double,
        alignment: Alignment = .center
    ) -> ContainerRelativeFrameView<Self> {
        ContainerRelativeFrameView(
            content: self,
            axes: axes,
            count: count,
            span: span,
            spacing: spacing,
            alignment: alignment
        )
    }
'''
    close = "\n}\n"
    if not text.endswith(close):
        raise SystemExit("SwiftOpenUI container-relative frame method insertion shape was not recognized")
    text = text[: -len(close)] + methods + close

if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

old_single = """extension OnChangeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFire(value: value, action: action)
        return gtkRenderView(content)
    }
}
"""
new_single = """extension OnChangeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFire(
            namespace: gtkStateIdentityNamespace(),
            value: value,
            action: action
        )
        return gtkRenderView(content)
    }
}
"""
if old_single in text:
    text = text.replace(old_single, new_single, 1)
elif new_single not in text:
    raise SystemExit("SwiftOpenUI GTK OnChange single-argument renderer shape was not recognized")

old_two_arg = """extension OnChangeTwoArgView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFireTwoArg(value: value, action: action)
        return gtkRenderView(content)
    }
}
"""
new_two_arg = """extension OnChangeTwoArgView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFireTwoArg(
            namespace: gtkStateIdentityNamespace(),
            value: value,
            action: action
        )
        return gtkRenderView(content)
    }
}
"""
if old_two_arg in text:
    text = text.replace(old_two_arg, new_two_arg, 1)
elif new_two_arg not in text:
    raise SystemExit("SwiftOpenUI GTK OnChange two-argument renderer shape was not recognized")

if "extension InitialOnChangeView: GTKRenderable" not in text:
    initial_renderers = r'''

extension InitialOnChangeView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFire(
            namespace: gtkStateIdentityNamespace(),
            value: value,
            initial: initial,
            action: action
        )
        return gtkRenderView(content)
    }
}

extension InitialOnChangeTwoArgView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        onChangeCheckAndFireTwoArg(
            namespace: gtkStateIdentityNamespace(),
            value: value,
            initial: initial,
            action: action
        )
        return gtkRenderView(content)
    }
}
'''
    if new_two_arg not in text:
        raise SystemExit("SwiftOpenUI GTK initial OnChange renderer insertion shape was not recognized")
    text = text.replace(new_two_arg, new_two_arg + initial_renderers, 1)

if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

if "private final class GTKContainerRelativeFrameContext" not in text:
    helpers = r'''private final class GTKContainerRelativeFrameContext {
    let axes: Axis
    let count: Int
    let span: Int
    let spacing: Double
    var requestedWidth: gint = -1
    var requestedHeight: gint = -1

    init(axes: Axis, count: Int, span: Int, spacing: Double) {
        self.axes = axes
        self.count = count
        self.span = span
        self.spacing = spacing
    }

    func resolvedLength(in containerLength: gint) -> gint {
        let resolvedCount = max(1, count)
        let resolvedSpan = min(max(1, span), resolvedCount)
        let resolvedSpacing = max(0, spacing)
        let available = max(
            0,
            Double(containerLength) - Double(resolvedCount - 1) * resolvedSpacing
        )
        let itemLength = available / Double(resolvedCount)
        return max(
            1,
            gint((itemLength * Double(resolvedSpan) + Double(resolvedSpan - 1) * resolvedSpacing).rounded())
        )
    }
}

private func gtkContainerRelativeExtent(
    from widget: UnsafeMutablePointer<GtkWidget>,
    horizontal: Bool
) -> gint? {
    var current = gtk_widget_get_parent(widget)
    var outermostAllocatedExtent: gint?
    var depth = 0

    while let node = current, depth < 160 {
        let extent = horizontal ? gtk_widget_get_width(node) : gtk_widget_get_height(node)
        if extent > 1 {
            outermostAllocatedExtent = extent
            if gtkHasLayoutMarker(node, key: gtkSwiftScrollViewMarker) {
                return extent
            }
        }
        current = gtk_widget_get_parent(node)
        depth += 1
    }

    return outermostAllocatedExtent
}

private let gtkContainerRelativeFrameTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget, let userData else { return 0 }
    let context = Unmanaged<GTKContainerRelativeFrameContext>
        .fromOpaque(userData)
        .takeUnretainedValue()

    var width = context.requestedWidth
    var height = context.requestedHeight
    var changed = false

    if context.axes.contains(.horizontal),
       let containerWidth = gtkContainerRelativeExtent(from: widget, horizontal: true) {
        let resolvedWidth = context.resolvedLength(in: containerWidth)
        if resolvedWidth != context.requestedWidth {
            context.requestedWidth = resolvedWidth
            width = resolvedWidth
            changed = true
        }
    }

    if context.axes.contains(.vertical),
       let containerHeight = gtkContainerRelativeExtent(from: widget, horizontal: false) {
        let resolvedHeight = context.resolvedLength(in: containerHeight)
        if resolvedHeight != context.requestedHeight {
            context.requestedHeight = resolvedHeight
            height = resolvedHeight
            changed = true
        }
    }

    if changed {
        gtk_widget_set_size_request(
            widget,
            context.axes.contains(.horizontal) ? width : -1,
            context.axes.contains(.vertical) ? height : -1
        )
        gtk_widget_queue_resize(widget)
    }

    return 1
}

private func gtkInstallContainerRelativeFrameSizing(
    on widget: UnsafeMutablePointer<GtkWidget>,
    axes: Axis,
    count: Int,
    span: Int,
    spacing: Double
) {
    let context = GTKContainerRelativeFrameContext(
        axes: axes,
        count: count,
        span: span,
        spacing: spacing
    )
    let contextPointer = Unmanaged.passRetained(context).toOpaque()
    _ = gtk_widget_add_tick_callback(
        widget,
        gtkContainerRelativeFrameTickCallback,
        contextPointer,
        { userData in
            Unmanaged<GTKContainerRelativeFrameContext>.fromOpaque(userData!).release()
        }
    )
}

'''
    marker = "private final class GTKRowWidthContext"
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTK container-relative sizing helper insertion shape was not recognized")
    text = text.replace(marker, helpers + marker, 1)

if "extension ContainerRelativeFrameView: GTKRenderable" not in text:
    renderer = r'''extension ContainerRelativeFrameView: GTKRenderable, GTKDescribable {
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .frame,
            typeName: "ContainerRelativeFrameView",
            props: .frame(GTK4FrameDescriptor(
                width: nil,
                height: nil,
                minWidth: nil,
                minHeight: nil,
                maxWidth: axes.contains(.horizontal) ? .infinity : nil,
                maxHeight: axes.contains(.vertical) ? .infinity : nil,
                alignment: gtkAlignmentDescriptor(alignment)
            )),
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let framedContent = content.frame(
            maxWidth: axes.contains(.horizontal) ? .infinity : nil,
            maxHeight: axes.contains(.vertical) ? .infinity : nil,
            alignment: alignment
        )
        let child = widgetFromOpaque(gtkRenderView(framedContent))
        if gtkIsEmptyViewWidget(child) {
            return opaqueFromWidget(child)
        }

        let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        if axes.contains(.horizontal) {
            gtk_widget_set_hexpand(wrapper, 0)
            gtk_widget_set_hexpand(child, 1)
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        }
        if axes.contains(.vertical) {
            gtk_widget_set_vexpand(wrapper, 0)
            gtk_widget_set_vexpand(child, 1)
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        }
        if !axes.contains(.horizontal), gtk_widget_get_hexpand(child) != 0 {
            gtk_widget_set_hexpand(wrapper, 1)
            gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
        }
        if !axes.contains(.vertical), gtk_widget_get_vexpand(child) != 0 {
            gtk_widget_set_vexpand(wrapper, 1)
            gtk_widget_set_valign(wrapper, GTK_ALIGN_FILL)
        }

        gtk_widget_set_size_request(
            wrapper,
            axes.contains(.horizontal) ? 1 : -1,
            axes.contains(.vertical) ? 1 : -1
        )
        gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)
        gtk_box_append(boxPointer(wrapper), child)
        gtkInstallContainerRelativeFrameSizing(
            on: wrapper,
            axes: axes,
            count: count,
            span: span,
            spacing: spacing
        )
        return opaqueFromWidget(wrapper)
    }
}

'''
    marker = "private func gtkMeasureWidgetNaturalSize"
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTK container-relative renderer insertion shape was not recognized")
    text = text.replace(marker, renderer + marker, 1)

scroll_start = text.find("extension ScrollView: GTKRenderable, GTKDescribable")
scroll_end = text.find("// MARK: - Image GTK extension", scroll_start)
if scroll_start < 0 or scroll_end < 0:
    raise SystemExit("SwiftOpenUI GTK ScrollView container-relative patch region was not recognized")
scroll = text[scroll_start:scroll_end]

if "horizontalContentWantsViewportHeight" not in scroll:
    old = """        let child = widgetFromOpaque(gtkRenderView(content))
        if axes.contains(.vertical) {
"""
    new = """        let child = widgetFromOpaque(gtkRenderView(content))
        let horizontalContentWantsViewportHeight =
            axes.contains(.horizontal)
            && !axes.contains(.vertical)
            && gtkHasVerticalFillIntent(child)
        if axes.contains(.vertical) {
"""
    if old not in scroll:
        raise SystemExit("SwiftOpenUI GTK horizontal ScrollView fill-intent insertion shape was not recognized")
    scroll = scroll.replace(old, new, 1)

    old = """            gtk_widget_set_vexpand(child, 0)
            gtk_widget_set_valign(child, GTK_ALIGN_START)
"""
    new = """            gtk_widget_set_vexpand(child, 0)
            gtk_widget_set_valign(
                child,
                horizontalContentWantsViewportHeight ? GTK_ALIGN_FILL : GTK_ALIGN_START
            )
"""
    if old not in scroll:
        raise SystemExit("SwiftOpenUI GTK horizontal ScrollView child alignment shape was not recognized")
    scroll = scroll.replace(old, new, 1)

    old = """            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: false
"""
    new = """            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: horizontalContentWantsViewportHeight
"""
    if old not in scroll:
        raise SystemExit("SwiftOpenUI GTK horizontal ScrollView cross-axis fill shape was not recognized")
    scroll = scroll.replace(old, new, 1)

    old = "        let scrollerWantsVerticalFill = axes.contains(.vertical)\n"
    new = """        let scrollerWantsVerticalFill =
            axes.contains(.vertical) || horizontalContentWantsViewportHeight
"""
    if old not in scroll:
        raise SystemExit("SwiftOpenUI GTK horizontal ScrollView expansion shape was not recognized")
    scroll = scroll.replace(old, new, 1)

    text = text[:scroll_start] + scroll + text[scroll_end:]

overlay_start = text.find("extension OverlayView: GTKRenderable")
overlay_end = text.find("/// Convert SwiftOpenUI Alignment", overlay_start)
if overlay_start < 0 or overlay_end < 0:
    raise SystemExit("SwiftOpenUI GTK Overlay layout marker patch region was not recognized")
overlay = text[overlay_start:overlay_end]
if "Overlay does not participate in its parent's size" not in overlay:
    marker = """        if gtk_widget_get_vexpand(baseWidget) != 0 {
            gtk_widget_set_vexpand(container, 1)
            gtk_widget_set_valign(baseWidget, GTK_ALIGN_FILL)
        }
"""
    replacement = marker + """        // Overlay does not participate in its parent's size. Preserve the
        // base view's layout intent so outer frames and ScrollViews still see
        // a filling shape through one or more decorative overlays.
        gtkPropagateSingleChildLayoutMarkers(from: [baseWidget], to: container)
"""
    if marker not in overlay:
        raise SystemExit("SwiftOpenUI GTK Overlay layout marker insertion shape was not recognized")
    overlay = overlay.replace(marker, replacement, 1)
    text = text[:overlay_start] + overlay + text[overlay_end:]

if text != original:
    path.write_text(text)
PY

python3 - "$SWIFTOPENUI_MANIFEST" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

if "import Foundation" not in text:
    if "import PackageDescription\n" not in text:
        raise SystemExit("SwiftOpenUI manifest PackageDescription import was not recognized")
    text = text.replace("import PackageDescription\n", "import PackageDescription\nimport Foundation\n", 1)

helpers = """#if os(Linux)
func swiftOpenUIPkgConfigArguments(_ name: String, _ arguments: [String]) -> [String] {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["pkg-config"] + arguments + [name]
    process.standardOutput = output
    process.standardError = Pipe()

    do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }
        return String(decoding: data, as: UTF8.self)
            .split(whereSeparator: { $0 == " " || $0 == "\\n" || $0 == "\\t" })
            .map(String.init)
    } catch {
        return []
    }
}

func swiftOpenUIPkgConfigIncludeFlags(_ name: String) -> [String] {
    swiftOpenUIPkgConfigArguments(name, ["--cflags-only-I"])
}

func swiftOpenUIPkgConfigSwiftImporterFlags(_ name: String) -> [String] {
    swiftOpenUIPkgConfigIncludeFlags(name).flatMap { ["-Xcc", $0] }
}

func swiftOpenUIPkgConfigLinkerFlags(_ name: String) -> [String] {
    swiftOpenUIPkgConfigArguments(name, ["--libs-only-L", "--libs-only-l"])
}

let swiftOpenUIGTKSwiftImporterFlags: [String] = swiftOpenUIPkgConfigSwiftImporterFlags("gtk4")
let swiftOpenUIGTKLinkerFlags: [String] = swiftOpenUIPkgConfigLinkerFlags("gtk4")
#else
let swiftOpenUIGTKSwiftImporterFlags: [String] = []
let swiftOpenUIGTKLinkerFlags: [String] = []
#endif

"""

if "func swiftOpenUIPkgConfigArguments(" not in text:
    text = text.replace("import Foundation\n", "import Foundation\n\n" + helpers, 1)

text = text.replace('        pkgConfig: "gtk4",\n', '')

replacements = [
    (
        """    .target(
        name: "CGTKBridge",
        dependencies: ["CGTK"],
        path: "Sources/Backend/GTK4/CGTKBridge"
    ),
""",
        """    .target(
        name: "CGTKBridge",
        dependencies: ["CGTK"],
        path: "Sources/Backend/GTK4/CGTKBridge",
        swiftSettings: [
            .unsafeFlags(swiftOpenUIGTKSwiftImporterFlags),
        ]
    ),
""",
    ),
    (
        """        path: "Sources/Backend/GTK4/Rendering",
        linkerSettings: [
""",
        """        path: "Sources/Backend/GTK4/Rendering",
        swiftSettings: [
            .unsafeFlags(swiftOpenUIGTKSwiftImporterFlags),
        ],
        linkerSettings: [
            .unsafeFlags(swiftOpenUIGTKLinkerFlags),
""",
    ),
    (
        """    .testTarget(
        name: "GTK4RenderTests",
        dependencies: ["SwiftOpenUI", "BackendGTK4", "CGTK", "CGTKBridge"],
        path: "Tests/BackendTests/GTK4Tests"
    ),
""",
        """    .testTarget(
        name: "GTK4RenderTests",
        dependencies: ["SwiftOpenUI", "BackendGTK4", "CGTK", "CGTKBridge"],
        path: "Tests/BackendTests/GTK4Tests",
        swiftSettings: [
            .unsafeFlags(swiftOpenUIGTKSwiftImporterFlags),
        ]
    ),
""",
    ),
    (
        """    .testTarget(
        name: "GTKLayoutParityTests",
        dependencies: ["SwiftOpenUI", "BackendGTK4", "CGTK", "CGTKBridge", "LayoutParityShared"],
        path: "Tests/LayoutParityTests/GTKComparison"
    ),
""",
        """    .testTarget(
        name: "GTKLayoutParityTests",
        dependencies: ["SwiftOpenUI", "BackendGTK4", "CGTK", "CGTKBridge", "LayoutParityShared"],
        path: "Tests/LayoutParityTests/GTKComparison",
        swiftSettings: [
            .unsafeFlags(swiftOpenUIGTKSwiftImporterFlags),
        ]
    ),
""",
    ),
]

for old, new in replacements:
    if old in text:
        text = text.replace(old, new, 1)

if 'pkgConfig: "gtk4"' in text:
    raise SystemExit("SwiftOpenUI manifest CGTK pkgConfig removal did not apply")
if text.count(".unsafeFlags(swiftOpenUIGTKSwiftImporterFlags)") < 4:
    raise SystemExit("SwiftOpenUI manifest GTK importer flag patch did not apply")
if ".unsafeFlags(swiftOpenUIGTKLinkerFlags)" not in text:
    raise SystemExit("SwiftOpenUI manifest GTK linker flag patch did not apply")

if text != original:
    path.write_text(text)
PY

if [[ -f "$MENU_VIEW" ]]; then
  python3 - "$MENU_VIEW" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

old_menu = """public struct Menu: View {
    public typealias Body = Never

    public let title: String
    public let elements: [MenuElement]

    public init(_ title: String, @MenuBuilder content: () -> [MenuElement]) {
        self.title = quillResolveLocalizedString(title)
        self.elements = content()
    }

    public var body: Never { fatalError("Menu is a primitive view") }
}
"""
new_menu = """public struct Menu: View {
    public typealias Body = Never

    public let title: String
    public let elements: [MenuElement]
    public let labelView: AnyView?

    public init(_ title: String, @MenuBuilder content: () -> [MenuElement]) {
        self.init(title, elements: content())
    }

    public init(_ title: String, elements: [MenuElement], labelView: AnyView? = nil) {
        self.title = quillResolveLocalizedString(title)
        self.elements = elements
        self.labelView = labelView
    }

    public var body: Never { fatalError("Menu is a primitive view") }
}
"""

if "public let labelView: AnyView?" not in text:
    if old_menu not in text:
        raise SystemExit("SwiftOpenUI Menu shape was not recognized")
    text = text.replace(old_menu, new_menu, 1)

if "public let labelView: AnyView?" not in text or "labelView: AnyView? = nil" not in text:
    raise SystemExit("SwiftOpenUI Menu label storage patch did not apply")

if text != original:
    path.write_text(text)
PY
fi

if [[ -f "$CONTROL_STYLE_MODIFIERS" ]]; then
  python3 - "$CONTROL_STYLE_MODIFIERS" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
needle = """    /// Filled/prominent background.
    case borderedProminent
"""
replacement = """    /// Filled/prominent background.
    case borderedProminent
    /// QuillPaint macOS default button chrome.
    case quillPaintMacDefault
    /// QuillPaint macOS bordered button chrome.
    case quillPaintMacBordered
    /// QuillPaint macOS sidebar/list-row chrome.
    case quillPaintMacListRow(isSelected: Bool, drawsIdleBackground: Bool)
"""
if "case quillPaintMacDefault" not in text:
    if needle not in text:
        raise SystemExit("SwiftOpenUI ButtonStyleType shape was not recognized")
    text = text.replace(needle, replacement, 1)
elif "case quillPaintMacListRow" not in text:
    text = text.replace(
        "    /// QuillPaint macOS bordered button chrome.\n    case quillPaintMacBordered\n",
        "    /// QuillPaint macOS bordered button chrome.\n    case quillPaintMacBordered\n"
        "    /// QuillPaint macOS sidebar/list-row chrome.\n"
        "    case quillPaintMacListRow(isSelected: Bool, drawsIdleBackground: Bool)\n",
        1,
    )
if text != original:
    path.write_text(text)
PY
fi

if [[ -f "$CONFIRMATION_DIALOG_MODIFIER" ]]; then
  python3 - "$CONFIRMATION_DIALOG_MODIFIER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

helpers = r"""
private protocol SwiftOpenUIButtonRepresentable {
    var swiftOpenUIButtonLabel: String { get }
    var swiftOpenUIButtonAction: () -> Void { get }
}

extension Button: SwiftOpenUIButtonRepresentable {
    fileprivate var swiftOpenUIButtonLabel: String { swiftOpenUITextLabel(from: label) }
    fileprivate var swiftOpenUIButtonAction: () -> Void { action }
}

private protocol SwiftOpenUIDisabledRepresentable {
    var swiftOpenUIDisabledContent: any View { get }
    var swiftOpenUIIsDisabled: Bool { get }
}

extension DisabledView: SwiftOpenUIDisabledRepresentable {
    fileprivate var swiftOpenUIDisabledContent: any View { content }
    fileprivate var swiftOpenUIIsDisabled: Bool { isDisabled }
}

private protocol SwiftOpenUIKeyboardShortcutRepresentable {
    var swiftOpenUIShortcutContent: any View { get }
}

extension KeyboardShortcutView: SwiftOpenUIKeyboardShortcutRepresentable {
    fileprivate var swiftOpenUIShortcutContent: any View { content }
}

private func swiftOpenUITextLabel(from view: any View) -> String {
    if let text = view as? Text {
        return text.content
    }

    if let label = view as? any AnyLabelView {
        return label.title
    }

    if let multi = view as? MultiChildView {
        for child in multi.children {
            let label = swiftOpenUITextLabel(from: child)
            if !label.isEmpty {
                return label
            }
        }
    }

    return ""
}

private func swiftOpenUIMenuElements(from view: any View) -> [MenuElement] {
    if let button = view as? any SwiftOpenUIButtonRepresentable {
        return [.item(label: button.swiftOpenUIButtonLabel, action: button.swiftOpenUIButtonAction)]
    }

    if let disabled = view as? any SwiftOpenUIDisabledRepresentable {
        return disabled.swiftOpenUIIsDisabled ? [] : swiftOpenUIMenuElements(from: disabled.swiftOpenUIDisabledContent)
    }

    if let shortcut = view as? any SwiftOpenUIKeyboardShortcutRepresentable {
        return swiftOpenUIMenuElements(from: shortcut.swiftOpenUIShortcutContent)
    }

    if let multi = view as? MultiChildView {
        return multi.children.flatMap(swiftOpenUIMenuElements)
    }

    return []
}

private func swiftOpenUIConfirmationDialogButtons(from view: any View) -> [AlertButton] {
    swiftOpenUIMenuElements(from: view).flatMap { element in
        switch element {
        case .item(let label, let action):
            return [AlertButton(label, action: action)]
        case .divider:
            return []
        case .submenu(_, let children):
            return children.flatMap { child -> [AlertButton] in
                switch child {
                case .item(let label, let action):
                    return [AlertButton(label, action: action)]
                case .divider:
                    return []
                case .submenu:
                    return []
                }
            }
        }
    }
}

"""

if "swiftOpenUIConfirmationDialogButtons" not in text:
    marker = "\nextension View {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI ConfirmationDialog extension marker was not recognized")
    text = text.replace(marker, "\n" + helpers + marker, 1)

old = """    /// SwiftUI-shaped builder overload with a message view.
    public func confirmationDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> ConfirmationDialogView<Self> {
        _ = actions()
        _ = message()
        return ConfirmationDialogView(
            content: self,
            title: title,
            isPresented: isPresented,
            titleVisibility: .automatic,
            message: "",
            buttons: [],
            participatesInDismissalInterception: false
        )
    }
"""
new = """    /// SwiftUI-shaped builder overload with a message view.
    public func confirmationDialog<Actions: View, Message: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder message: () -> Message
    ) -> ConfirmationDialogView<Self> {
        let actionView = actions()
        let messageView = message()
        return ConfirmationDialogView(
            content: self,
            title: title,
            isPresented: isPresented,
            titleVisibility: .automatic,
            message: swiftOpenUITextLabel(from: messageView),
            buttons: swiftOpenUIConfirmationDialogButtons(from: actionView),
            participatesInDismissalInterception: false
        )
    }
"""

if old in text:
    text = text.replace(old, new, 1)
elif (
    "buttons: swiftOpenUIConfirmationDialogButtons(from: actionView)" not in text
    and "buttons: swiftOpenUIConfirmationDialogButtons(from: actions())" not in text
):
    raise SystemExit("SwiftOpenUI confirmationDialog builder overload shape was not recognized")

if text != original:
    path.write_text(text)
PY
fi

if [[ -f "$GTK_SHIM" ]]; then
python3 - "$GTK_SHIM" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
accessibility_helpers = """
// --- Accessibility shims ---

static inline void
gtk_swift_accessible_update_label(GtkWidget *widget, const char *label) {
    gtk_accessible_update_property(
        GTK_ACCESSIBLE(widget),
        GTK_ACCESSIBLE_PROPERTY_LABEL,
        label ? label : "",
        -1);
}

static inline void
gtk_swift_accessible_update_description(GtkWidget *widget, const char *description) {
    gtk_accessible_update_property(
        GTK_ACCESSIBLE(widget),
        GTK_ACCESSIBLE_PROPERTY_DESCRIPTION,
        description ? description : "",
        -1);
}
"""
if "gtk_swift_accessible_update_label" not in text:
    label_marker = """static inline gboolean
gtk_swift_label_get_use_markup(GtkWidget *label) {
    return gtk_label_get_use_markup(GTK_LABEL(label));
}
"""
    if label_marker in text:
        text = text.replace(label_marker, label_marker + accessibility_helpers, 1)
    else:
        include_marker = "#include <fontconfig/fontconfig.h>\n"
        if include_marker not in text:
            raise SystemExit("SwiftOpenUI GTK shim include block was not recognized")
        text = text.replace(include_marker, include_marker + accessibility_helpers, 1)
if "gtk_swift_flow_box_new" not in text:
    flow_box_helpers = """static inline GtkWidget *
gtk_swift_flow_box_new(void) {
    return gtk_flow_box_new();
}

static inline void
gtk_swift_flow_box_configure(GtkWidget *flow, guint spacing) {
    GtkFlowBox *box = GTK_FLOW_BOX(flow);
    gtk_flow_box_set_selection_mode(box, GTK_SELECTION_NONE);
    gtk_flow_box_set_activate_on_single_click(box, FALSE);
    gtk_flow_box_set_column_spacing(box, spacing);
    gtk_flow_box_set_row_spacing(box, spacing);
    gtk_flow_box_set_min_children_per_line(box, 1);
    gtk_flow_box_set_max_children_per_line(box, 128);
    gtk_flow_box_set_homogeneous(box, FALSE);
}

static inline void
gtk_swift_flow_box_insert(GtkWidget *flow, GtkWidget *child) {
    gtk_flow_box_insert(GTK_FLOW_BOX(flow), child, -1);
}

"""
    fixed_marker = """static inline GtkWidget *
gtk_swift_fixed_new(void) {
    return gtk_fixed_new();
}

"""
    if fixed_marker in text:
        text = text.replace(fixed_marker, fixed_marker + flow_box_helpers, 1)
    else:
        include_marker = "#include <fontconfig/fontconfig.h>\n"
        if include_marker not in text:
            raise SystemExit("SwiftOpenUI GTK shim include block was not recognized")
        text = text.replace(include_marker, include_marker + "\n" + flow_box_helpers, 1)
pattern = re.compile(
    r"gtk_swift_add_gesture\(GtkWidget \*widget, GtkGesture \*gesture\)\s*\{\s*"
    r"gtk_widget_add_controller\(widget, GTK_EVENT_CONTROLLER\(gesture\)\);\s*"
    r"\}",
    re.S,
)
bubble_replacement = """gtk_swift_add_gesture(GtkWidget *widget, GtkGesture *gesture) {
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture), GTK_PHASE_BUBBLE);
    gtk_gesture_single_set_exclusive(GTK_GESTURE_SINGLE(gesture), FALSE);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(gesture));
}
"""
if "gtk_gesture_single_set_exclusive(GTK_GESTURE_SINGLE(gesture), FALSE)" not in text:
    text, count = pattern.subn(bubble_replacement, text, count=1)
    if count != 1:
        raise SystemExit("SwiftOpenUI GTK gesture shim shape was not recognized")
if "gtk_swift_add_capture_gesture" not in text:
    capture_helper = """static inline void
gtk_swift_add_capture_gesture(GtkWidget *widget, GtkGesture *gesture) {
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture), GTK_PHASE_CAPTURE);
    gtk_gesture_single_set_exclusive(GTK_GESTURE_SINGLE(gesture), FALSE);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(gesture));
}
"""
    if bubble_replacement not in text:
        raise SystemExit("SwiftOpenUI GTK bubble gesture shim shape was not recognized")
    text = text.replace(bubble_replacement, bubble_replacement + "\n" + capture_helper, 1)
if "gtk_swift_root_grab_focus" not in text:
    clear_focus_marker = """static inline void
gtk_swift_clear_focus(GtkWidget *widget) {
    GtkRoot *root = gtk_widget_get_root(widget);
    if (root) {
        gtk_root_set_focus(root, NULL);
    }
}
"""
    root_focus_helper = """static inline gboolean
gtk_swift_root_grab_focus(GtkWidget *widget) {
    if (widget == NULL) {
        return FALSE;
    }
    GtkRoot *root = gtk_widget_get_root(widget);
    if (root == NULL) {
        return gtk_widget_grab_focus(widget);
    }
    gtk_root_set_focus(root, widget);
    if (gtk_widget_is_focus(widget)) {
        return TRUE;
    }
    return gtk_widget_grab_focus(widget);
}
"""
    if clear_focus_marker in text:
        text = text.replace(clear_focus_marker, clear_focus_marker + "\n" + root_focus_helper, 1)
    else:
        editable_marker = "\n// --- Editable type check ---\n"
        if editable_marker in text:
            text = text.replace(editable_marker, "\n" + root_focus_helper + editable_marker, 1)
        else:
            text = text.rstrip() + "\n\n" + root_focus_helper
if "gtk_swift_search_entry_set_key_capture_widget" not in text:
    search_entry_marker = """static inline GtkWidget *
gtk_swift_search_entry_new(void) {
    return gtk_search_entry_new();
}
"""
    search_entry_key_capture_helpers = """
static inline void
gtk_swift_search_entry_set_key_capture_widget(GtkWidget *entry, GtkWidget *widget) {
    gtk_search_entry_set_key_capture_widget(GTK_SEARCH_ENTRY(entry), widget);
}

static inline GtkWidget *
gtk_swift_search_entry_get_key_capture_widget(GtkWidget *entry) {
    return gtk_search_entry_get_key_capture_widget(GTK_SEARCH_ENTRY(entry));
}
"""
    if search_entry_marker in text:
        text = text.replace(search_entry_marker, search_entry_marker + search_entry_key_capture_helpers, 1)
    else:
        editable_marker = "static inline void\ngtk_swift_editable_set_text"
        if editable_marker not in text:
            raise SystemExit("SwiftOpenUI GTK search-entry shim shape was not recognized")
        text = text.replace(editable_marker, search_entry_key_capture_helpers + "\n" + editable_marker, 1)
if "gtk_swift_drop_down_new(gpointer model)" not in text:
    dropdown_helper = """static inline GtkWidget *
gtk_swift_drop_down_new(gpointer model) {
    return gtk_drop_down_new(G_LIST_MODEL(model), NULL);
}
"""
    string_list_marker = """static inline gpointer
gtk_swift_string_list_new(void) {
    return (gpointer)gtk_string_list_new(NULL);
}
"""
    if string_list_marker in text:
        text = text.replace(string_list_marker, string_list_marker + "\n" + dropdown_helper, 1)
    else:
        include_marker = "#include <fontconfig/fontconfig.h>\n"
        if include_marker not in text:
            raise SystemExit("SwiftOpenUI GTK shim include block was not recognized")
        text = text.replace(include_marker, include_marker + "\n" + dropdown_helper, 1)
if "gtk_swift_legacy_capture_controller" not in text:
    capture_helper = """static inline void
gtk_swift_add_capture_gesture(GtkWidget *widget, GtkGesture *gesture) {
    gtk_event_controller_set_propagation_phase(GTK_EVENT_CONTROLLER(gesture), GTK_PHASE_CAPTURE);
    gtk_gesture_single_set_exclusive(GTK_GESTURE_SINGLE(gesture), FALSE);
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(gesture));
}
"""
    legacy_helpers = """static inline gpointer
gtk_swift_legacy_capture_controller(void) {
    GtkEventController *controller = gtk_event_controller_legacy_new();
    gtk_event_controller_set_propagation_phase(controller, GTK_PHASE_CAPTURE);
    return controller;
}

static inline void
gtk_swift_add_event_controller(GtkWidget *widget, gpointer controller) {
    gtk_widget_add_controller(widget, GTK_EVENT_CONTROLLER(controller));
}

static inline void
gtk_swift_remove_event_controller(GtkWidget *widget, gpointer controller) {
    gtk_widget_remove_controller(widget, GTK_EVENT_CONTROLLER(controller));
}

static inline gboolean
gtk_swift_event_is_primary_button_press(gpointer event) {
    GdkEvent *gdk_event = (GdkEvent *)event;
    return gdk_event != NULL
        && gdk_event_get_event_type(gdk_event) == GDK_BUTTON_PRESS
        && gdk_button_event_get_button(gdk_event) == GDK_BUTTON_PRIMARY;
}

static inline gboolean
gtk_swift_event_get_position(gpointer event, double *x, double *y) {
    GdkEvent *gdk_event = (GdkEvent *)event;
    return gdk_event != NULL ? gdk_event_get_position(gdk_event, x, y) : FALSE;
}

static inline GtkWidget *
gtk_swift_widget_root_widget(GtkWidget *widget) {
    GtkRoot *root = gtk_widget_get_root(widget);
    return root != NULL ? GTK_WIDGET(root) : NULL;
}

static inline gboolean
gtk_swift_widget_contains_root_point(GtkWidget *root, GtkWidget *widget, double x, double y) {
    if (root == NULL || widget == NULL) {
        return FALSE;
    }
    double local_x = 0;
    double local_y = 0;
    if (!gtk_widget_translate_coordinates(root, widget, x, y, &local_x, &local_y)) {
        return FALSE;
    }
    return local_x >= 0
        && local_y >= 0
        && local_x < gtk_widget_get_width(widget)
        && local_y < gtk_widget_get_height(widget);
}

static inline gboolean
gtk_swift_widget_is_ancestor_or_self(GtkWidget *ancestor, GtkWidget *widget) {
    while (widget != NULL) {
        if (widget == ancestor) {
            return TRUE;
        }
        widget = gtk_widget_get_parent(widget);
    }
    return FALSE;
}

static inline gboolean
gtk_swift_widget_is_topmost_at_root_point(GtkWidget *root, GtkWidget *widget, double x, double y) {
    if (!gtk_swift_widget_contains_root_point(root, widget, x, y)) {
        return FALSE;
    }
    GtkWidget *picked = gtk_widget_pick(root, x, y, GTK_PICK_DEFAULT);
    if (picked != NULL && gtk_swift_widget_is_ancestor_or_self(widget, picked)) {
        return TRUE;
    }
    if (picked != NULL && picked != root && gtk_swift_widget_is_ancestor_or_self(picked, widget)) {
        return TRUE;
    }
    picked = gtk_widget_pick(root, x, y, GTK_PICK_NON_TARGETABLE);
    if (picked != NULL && gtk_swift_widget_is_ancestor_or_self(widget, picked)) {
        return TRUE;
    }
    if (picked != NULL && picked != root && gtk_swift_widget_is_ancestor_or_self(picked, widget)) {
        return TRUE;
    }
    picked = gtk_widget_pick(
        root,
        x,
        y,
        (GtkPickFlags)(GTK_PICK_NON_TARGETABLE | GTK_PICK_INSENSITIVE)
    );
    if (picked != NULL && gtk_swift_widget_is_ancestor_or_self(widget, picked)) {
        return TRUE;
    }
    return picked != NULL && picked != root && gtk_swift_widget_is_ancestor_or_self(picked, widget);
}
"""
    if capture_helper not in text:
        raise SystemExit("SwiftOpenUI GTK capture gesture shim shape was not recognized")
    text = text.replace(capture_helper, capture_helper + "\n" + legacy_helpers, 1)
if "gtk_swift_widget_is_button" not in text:
    widget_is_button_helper = """static inline gboolean
gtk_swift_widget_is_button(GtkWidget *widget) {
    return widget != NULL && GTK_IS_BUTTON(widget);
}

"""
    list_row_marker = """static inline GtkWidget *
gtk_swift_list_box_row_at_point(GtkWidget *list_box, double x, double y) {
"""
    if list_row_marker in text:
        text = text.replace(list_row_marker, widget_is_button_helper + list_row_marker, 1)
    else:
        text = text.rstrip() + "\n\n" + widget_is_button_helper
if "gtk_swift_event_controller_widget" not in text:
    event_controller_widget_helper = """static inline GtkWidget *
gtk_swift_event_controller_widget(gpointer controller) {
    return controller != NULL
        ? gtk_event_controller_get_widget(GTK_EVENT_CONTROLLER(controller))
        : NULL;
}

"""
    remove_controller_marker = """static inline void
gtk_swift_remove_event_controller(GtkWidget *widget, gpointer controller) {
"""
    if remove_controller_marker in text:
        text = text.replace(remove_controller_marker, event_controller_widget_helper + remove_controller_marker, 1)
    else:
        text = text.rstrip() + "\n\n" + event_controller_widget_helper
if "gtk_swift_compressible_height_clamp_new" not in text:
    compressible_height_clamp = """static inline void
gtk_swift_compressible_height_clamp_measure(GtkWidget *widget,
                                            GtkOrientation orientation,
                                            int for_size,
                                            int *minimum,
                                            int *natural,
                                            int *minimum_baseline,
                                            int *natural_baseline) {
    GtkWidget *child = gtk_widget_get_first_child(widget);
    if (minimum_baseline) *minimum_baseline = -1;
    if (natural_baseline) *natural_baseline = -1;
    if (child == NULL || !gtk_widget_should_layout(child)) {
        if (minimum) *minimum = 0;
        if (natural) *natural = 0;
        return;
    }

    if (orientation == GTK_ORIENTATION_VERTICAL) {
        if (minimum) *minimum = 1;
        if (natural) *natural = 1;
        return;
    }

    gtk_widget_measure(
        child,
        orientation,
        for_size,
        minimum,
        natural,
        minimum_baseline,
        natural_baseline);
}

static inline GtkWidget *
gtk_swift_compressible_height_clamp_new(GtkWidget *child) {
    GtkWidget *container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    GtkLayoutManager *layout = gtk_custom_layout_new(
        gtk_swift_width_clamp_request_mode,
        gtk_swift_compressible_height_clamp_measure,
        gtk_swift_width_clamp_allocate);
    gtk_widget_set_layout_manager(container, layout);
    gtk_widget_set_parent(child, container);
    gtk_widget_set_hexpand(container, gtk_widget_get_hexpand(child));
    gtk_widget_set_vexpand(container, gtk_widget_get_vexpand(child));
    gtk_widget_set_halign(container, GTK_ALIGN_FILL);
    gtk_widget_set_valign(container, GTK_ALIGN_FILL);
    return container;
}

"""
    width_clamp_marker = """static inline GtkWidget *
gtk_swift_compressible_width_clamp_new(GtkWidget *child) {
    GtkWidget *container = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0);
    GtkLayoutManager *layout = gtk_custom_layout_new(
        gtk_swift_width_clamp_request_mode,
        gtk_swift_compressible_width_clamp_measure,
        gtk_swift_width_clamp_allocate);
    gtk_widget_set_layout_manager(container, layout);
    gtk_widget_set_parent(child, container);
    gtk_widget_set_hexpand(container, gtk_widget_get_hexpand(child));
    gtk_widget_set_vexpand(container, gtk_widget_get_vexpand(child));
    gtk_widget_set_halign(container, GTK_ALIGN_FILL);
    gtk_widget_set_valign(container, GTK_ALIGN_FILL);
    return container;
}

"""
    if width_clamp_marker not in text:
        raise SystemExit("SwiftOpenUI GTK compressible width clamp insertion point was not recognized")
    text = text.replace(width_clamp_marker, width_clamp_marker + compressible_height_clamp, 1)
if "gtk_swift_attach_context_popover" not in text:
    context_popover_helpers = """static inline void
gtk_swift_context_popover_anchor_destroy(GtkWidget *anchor, gpointer user_data) {
    GtkWidget *popover = GTK_WIDGET(user_data);
    if (popover != NULL && gtk_widget_get_parent(popover) == anchor) {
        gtk_widget_unparent(popover);
    }
}

static inline void
gtk_swift_context_popover_release(gpointer user_data, GClosure *closure) {
    (void)closure;
    g_object_unref(user_data);
}

static inline void
gtk_swift_attach_context_popover(GtkWidget *anchor, GtkWidget *popover) {
    gtk_widget_set_parent(popover, anchor);
    g_signal_connect_data(
        anchor,
        "destroy",
        G_CALLBACK(gtk_swift_context_popover_anchor_destroy),
        g_object_ref(popover),
        gtk_swift_context_popover_release,
        0);
}

"""
    popover_marker = "// --- GtkPopover shims ---\n\n"
    if popover_marker not in text:
        raise SystemExit("SwiftOpenUI GTK popover shim insertion point was not recognized")
    text = text.replace(popover_marker, popover_marker + context_popover_helpers, 1)
if text != original:
    path.write_text(text)
PY
fi

python3 - "$SCROLL_VIEW" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

if "public let showsIndicators: Bool" not in text:
    axis_storage = "    public let axes: Axis\n    public let content: Content\n"
    if axis_storage not in text:
        raise SystemExit("SwiftOpenUI ScrollView storage shape was not recognized")
    text = text.replace(
        axis_storage,
        "    public let axes: Axis\n    public let showsIndicators: Bool\n    public let content: Content\n",
        1,
    )

    default_init = "        self.axes = axes\n        self.content = content()\n"
    if default_init not in text:
        raise SystemExit("SwiftOpenUI ScrollView default initializer shape was not recognized")
    text = text.replace(
        default_init,
        "        self.axes = axes\n        self.showsIndicators = true\n        self.content = content()\n",
        1,
    )

legacy_indicators_init = "        _ = showsIndicators\n        self.axes = axes\n        self.content = content()\n"
indicators_init = "        self.axes = axes\n        self.showsIndicators = showsIndicators\n        self.content = content()\n"
if legacy_indicators_init in text:
    text = text.replace(legacy_indicators_init, indicators_init, 1)
elif "self.showsIndicators = showsIndicators" not in text:
    raise SystemExit("SwiftOpenUI ScrollView indicators initializer shape was not recognized")

if text != original:
    path.write_text(text)
PY

python3 - "$LOCALIZATION" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

old_plural_struct = """    private struct PluralSubstitution {
        var one: String?
        var other: String?
    }
"""
new_plural_struct = """    private struct PluralSubstitution {
        var argumentIndex: Int?
        var zero: String?
        var one: String?
        var two: String?
        var few: String?
        var many: String?
        var other: String?

        var hasAnyValue: Bool {
            zero != nil || one != nil || two != nil || few != nil || many != nil || other != nil
        }
    }
"""
if "var hasAnyValue: Bool" not in text:
    if old_plural_struct not in text:
        raise SystemExit("SwiftOpenUI localization plural substitution shape was not recognized")
    text = text.replace(old_plural_struct, new_plural_struct, 1)
elif "var argumentIndex: Int?" not in text:
    marker = "    private struct PluralSubstitution {\n        var zero: String?\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI localization plural substitution argument-index shape was not recognized")
    text = text.replace(marker, "    private struct PluralSubstitution {\n        var argumentIndex: Int?\n        var zero: String?\n", 1)

old_template_start = """    private func localizationTemplate(_ value: Any?) -> LocalizedTemplate? {
        guard let localization = value as? [String: Any],
              let stringUnit = localization["stringUnit"] as? [String: Any] else {
            return nil
        }
        guard let value = stringUnit["value"] as? String else {
            return nil
        }

        var template = LocalizedTemplate(value: value)
"""
new_template_start = """    private func localizationTemplate(_ value: Any?) -> LocalizedTemplate? {
        guard let localization = value as? [String: Any] else {
            return nil
        }

        var template: LocalizedTemplate
        if let stringUnit = localization["stringUnit"] as? [String: Any],
           let value = stringUnit["value"] as? String {
            template = LocalizedTemplate(value: value)
        } else if let variations = localization["variations"] as? [String: Any],
                  let plural = variations["plural"] as? [String: Any] {
            let pluralName = "__quill_plural"
            let substitution = pluralSubstitution(in: plural)
            guard substitution.hasAnyValue else {
                return nil
            }
            template = LocalizedTemplate(value: "%#@\\(pluralName)@")
            template.pluralSubstitutions[pluralName] = substitution
        } else {
            return nil
        }

"""
if 'let pluralName = "__quill_plural"' not in text:
    if old_template_start not in text:
        raise SystemExit("SwiftOpenUI localization template shape was not recognized")
    text = text.replace(old_template_start, new_template_start, 1)

old_named_substitution = """                template.pluralSubstitutions[name] = PluralSubstitution(
                    one: pluralString(in: plural["one"]),
                    other: pluralString(in: plural["other"])
                )
"""
new_named_substitution = """                var pluralSubstitution = pluralSubstitution(in: plural)
                pluralSubstitution.argumentIndex = substitutionArgumentIndex(substitution["argNum"])
                if pluralSubstitution.hasAnyValue {
                    template.pluralSubstitutions[name] = pluralSubstitution
                }
"""
if old_named_substitution in text:
    text = text.replace(old_named_substitution, new_named_substitution, 1)
elif "pluralSubstitution.argumentIndex = substitutionArgumentIndex(substitution[\"argNum\"])" not in text:
    current_named_substitution = """                let pluralSubstitution = pluralSubstitution(in: plural)
                if pluralSubstitution.hasAnyValue {
                    template.pluralSubstitutions[name] = pluralSubstitution
                }
"""
    if current_named_substitution not in text:
        raise SystemExit("SwiftOpenUI named plural substitution shape was not recognized")
    text = text.replace(current_named_substitution, new_named_substitution, 1)

argument_index_helper = """    private func substitutionArgumentIndex(_ value: Any?) -> Int? {
        let argumentNumber: Int?
        if let number = value as? NSNumber {
            argumentNumber = number.intValue
        } else if let int = value as? Int {
            argumentNumber = int
        } else if let string = value as? String {
            argumentNumber = Int(string)
        } else {
            argumentNumber = nil
        }
        guard let argumentNumber, argumentNumber > 0 else {
            return nil
        }
        return argumentNumber - 1
    }

"""
if "private func substitutionArgumentIndex(_ value: Any?) -> Int?" not in text:
    marker = "    private func pluralSubstitution(in plural: [String: Any]) -> PluralSubstitution {\n"
    if marker in text:
        text = text.replace(marker, argument_index_helper + marker, 1)
    else:
        marker = "    private func pluralString(in value: Any?) -> String? {\n"
        if marker not in text:
            raise SystemExit("SwiftOpenUI plural argument-index helper insertion marker was not recognized")
        text = text.replace(marker, argument_index_helper + marker, 1)

old_count_selection = """            let count = arguments.first.flatMap { Double($0) } ?? 0
"""
new_count_selection = """            let argumentIndex = substitution.argumentIndex ?? 0
            let argument = arguments.indices.contains(argumentIndex) ? arguments[argumentIndex] : (arguments.first ?? "0")
            let count = Double(argument) ?? 0
"""
if old_count_selection in text:
    text = text.replace(old_count_selection, new_count_selection, 1)
elif "let argumentIndex = substitution.argumentIndex ?? 0" not in text:
    raise SystemExit("SwiftOpenUI named plural substitution shape was not recognized")

plural_helper = """    private func pluralSubstitution(in plural: [String: Any]) -> PluralSubstitution {
        PluralSubstitution(
            zero: pluralString(in: plural["zero"]),
            one: pluralString(in: plural["one"]),
            two: pluralString(in: plural["two"]),
            few: pluralString(in: plural["few"]),
            many: pluralString(in: plural["many"]),
            other: pluralString(in: plural["other"])
        )
    }

"""
if "private func pluralSubstitution(in plural: [String: Any]) -> PluralSubstitution" not in text:
    marker = "    private func pluralString(in value: Any?) -> String? {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI plural helper insertion marker was not recognized")
    text = text.replace(marker, plural_helper + marker, 1)

old_replacement = """            let replacement = count == 1 ? (substitution.one ?? substitution.other) : (substitution.other ?? substitution.one)
"""
new_replacement = """            let replacement: String?
            switch count {
            case 0:
                replacement = substitution.zero ?? substitution.other ?? substitution.one
            case 1:
                replacement = substitution.one ?? substitution.other
            case 2:
                replacement = substitution.two ?? substitution.other ?? substitution.one
            default:
                replacement = substitution.other ?? substitution.many ?? substitution.few ?? substitution.one
            }
"""
if old_replacement in text:
    text = text.replace(old_replacement, new_replacement, 1)
elif "replacement = substitution.zero ?? substitution.other ?? substitution.one" not in text:
    raise SystemExit("SwiftOpenUI plural category selection shape was not recognized")

old_plural_write = """            if let replacement {
                value = value.replacingOccurrences(of: "%#@\\(name)@", with: replacement)
            }
"""
new_plural_write = """            if let replacement {
                let formattedReplacement = formatPluralReplacement(replacement, argument: argument, arguments: arguments)
                value = value.replacingOccurrences(of: "%#@\\(name)@", with: formattedReplacement)
            }
"""
if old_plural_write in text:
    text = text.replace(old_plural_write, new_plural_write, 1)
elif "let formattedReplacement = formatPluralReplacement(replacement, argument: argument, arguments: arguments)" not in text:
    raise SystemExit("SwiftOpenUI plural replacement formatting shape was not recognized")

plural_replacement_helper = """    private func formatPluralReplacement(_ replacement: String, argument: String, arguments: [String]) -> String {
        let argResolved = replacement.replacingOccurrences(of: "%arg", with: argument)
        return format(argResolved, arguments: arguments)
    }

"""
if "private func formatPluralReplacement(_ replacement: String, argument: String, arguments: [String]) -> String" not in text:
    marker = "    private func format(_ template: String, arguments: [String]) -> String {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI plural replacement helper insertion marker was not recognized")
    text = text.replace(marker, plural_replacement_helper + marker, 1)

if text != original:
    path.write_text(text)
PY

python3 - "$SCROLL_VIEW_READER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

optional_id_helpers = """// MARK: - Optional ID compatibility

fileprivate protocol _SwiftOpenUIOptionalHashableID {
    var _swiftOpenUIWrappedHashableID: AnyHashable? { get }
    var _swiftOpenUIIsNil: Bool { get }
}

extension Optional: _SwiftOpenUIOptionalHashableID where Wrapped: Hashable {
    fileprivate var _swiftOpenUIWrappedHashableID: AnyHashable? {
        switch self {
        case .some(let value):
            return AnyHashable(value)
        case .none:
            return nil
        }
    }

    fileprivate var _swiftOpenUIIsNil: Bool {
        switch self {
        case .some:
            return false
        case .none:
            return true
        }
    }
}

fileprivate func swiftOpenUIHashableScrollID<ID: Hashable>(_ id: ID) -> AnyHashable? {
    if let optionalID = id as? _SwiftOpenUIOptionalHashableID {
        guard !optionalID._swiftOpenUIIsNil else { return nil }
        return optionalID._swiftOpenUIWrappedHashableID
    }
    return AnyHashable(id)
}

"""

if "_SwiftOpenUIOptionalHashableID" not in text:
    text = text.replace("// MARK: - View Identity\n", optional_id_helpers + "// MARK: - View Identity\n", 1)

old_scroll_to = """    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        scrollToAction?(AnyHashable(id), anchor)
    }
"""
new_scroll_to = """    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
        guard let resolvedID = swiftOpenUIHashableScrollID(id) else { return }
        scrollToAction?(resolvedID, anchor)
    }
"""
if "swiftOpenUIHashableScrollID(id)" not in text and old_scroll_to in text:
    text = text.replace(old_scroll_to, new_scroll_to, 1)
elif "swiftOpenUIHashableScrollID(id)" not in text:
    raise SystemExit("SwiftOpenUI ScrollViewProxy.scrollTo shape was not recognized")

if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

searchable_visibility_helper = """private func gtkSearchableKeepsChromeVisible(for placement: SearchFieldPlacement) -> Bool {
    switch placement {
    case .navigationBarDrawer(let displayMode):
        return displayMode == .always
    case .automatic, .toolbar, .sidebar:
        return false
    }
}

private func gtkInstallSearchFocusGesture(
    on widget: UnsafeMutablePointer<GtkWidget>,
    entry: UnsafeMutablePointer<GtkWidget>,
    binding: Binding<String>,
    isPresented: Binding<Bool>?
) {
    let focusGesture = gtk_gesture_click_new()!
    let focusBox = Unmanaged.passRetained(
        SearchBox(entry: entry, binding: binding, isPresented: isPresented)
    ).toOpaque()
    gtk_swift_gesture_single_set_button(focusGesture, 1)
    g_signal_connect_data(
        gpointer(focusGesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
            guard let userData else { return }
            let box = Unmanaged<SearchBox>.fromOpaque(userData).takeUnretainedValue()
            box.isPresented?.wrappedValue = true
            gtk_widget_set_focusable(box.entry, 1)
            let entryGrabbed = gtk_swift_root_grab_focus(box.entry)
            gtkDebugLog("searchable focus pressed entryGrabbed=\\(entryGrabbed)")
            if let delegate = gtk_editable_get_delegate(OpaquePointer(box.entry)) {
                let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
                gtk_widget_set_focusable(delegateWidget, 1)
                let delegateGrabbed = gtk_swift_root_grab_focus(delegateWidget)
                gtkDebugLog("searchable focus delegateGrabbed=\\(delegateGrabbed)")
            }
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        focusBox,
        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            Unmanaged<SearchBox>.fromOpaque(userData!).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, focusGesture)
}

"""
if "private func gtkSearchableKeepsChromeVisible(for placement: SearchFieldPlacement) -> Bool" not in text:
    marker = "extension SearchableView: GTKRenderable, GTKDescribable {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI SearchableView GTK extension marker was not recognized")
    text = text.replace(marker, searchable_visibility_helper + marker, 1)
elif "private func gtkInstallSearchFocusGesture(" not in text:
    marker = "extension SearchableView: GTKRenderable, GTKDescribable {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI SearchableView GTK extension marker was not recognized")
    text = text.replace(marker, searchable_visibility_helper.split("\n\n", 1)[1] + marker, 1)

old_search_box_creation = """        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let boxPtr = boxPointer(box)

        let entry = gtk_swift_search_entry_new()!
"""
new_search_box_creation = """        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let boxPtr = boxPointer(box)
        gtk_widget_set_can_target(box, 1)
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        gtk_widget_set_halign(box, GTK_ALIGN_FILL)
        gtk_widget_set_valign(box, GTK_ALIGN_FILL)
        gtkMarkVerticalFillIntent(box)
        let binding = text
        let presentedBinding = isPresented

        let entry = gtk_swift_search_entry_new()!
"""
if old_search_box_creation in text:
    text = text.replace(old_search_box_creation, new_search_box_creation, 1)
elif "gtk_widget_set_can_target(box, 1)" not in text:
    raise SystemExit("SwiftOpenUI SearchableView search wrapper creation was not recognized")

old_search_entry_creation = "        let entry = gtk_swift_search_entry_new()!\n"
new_search_entry_creation = """        let entry = gtk_swift_search_entry_new()!
        gtkDebugLog("searchable create placement=\\(placement) prompt='\\(prompt)' text='\\(binding.wrappedValue)'")
        gtk_widget_set_focusable(entry, 1)
        gtk_widget_set_focus_on_click(entry, 1)
        if let delegate = gtk_editable_get_delegate(OpaquePointer(entry)) {
            let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
            gtk_widget_set_focusable(delegateWidget, 1)
            gtk_widget_set_focus_on_click(delegateWidget, 1)
            gtkInstallSearchFocusGesture(
                on: delegateWidget,
                entry: entry,
                binding: binding,
                isPresented: presentedBinding
            )
        }
        gtkInstallSearchFocusGesture(on: entry, entry: entry, binding: binding, isPresented: presentedBinding)
        gtkInstallSearchFocusGesture(on: box, entry: entry, binding: binding, isPresented: presentedBinding)
"""
if old_search_entry_creation in text and "gtk_widget_set_focus_on_click(entry, 1)" not in text:
    text = text.replace(old_search_entry_creation, new_search_entry_creation, 1)
elif "gtk_widget_set_focus_on_click(entry, 1)" not in text:
    raise SystemExit("SwiftOpenUI SearchableView search entry creation was not recognized")

old_content_append = """        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_vexpand(contentWidget, 1)
        gtk_box_append(boxPtr, contentWidget)
"""
new_content_append = """        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_hexpand(contentWidget, 1)
        gtk_widget_set_vexpand(contentWidget, 1)
        gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
        gtk_swift_search_entry_set_key_capture_widget(entry, box)
        gtk_box_append(boxPtr, contentWidget)
"""
if old_content_append in text:
    text = text.replace(old_content_append, new_content_append, 1)
elif "gtk_swift_search_entry_set_key_capture_widget(entry, contentWidget)" in text:
    text = text.replace(
        "gtk_swift_search_entry_set_key_capture_widget(entry, contentWidget)",
        "gtk_swift_search_entry_set_key_capture_widget(entry, box)",
        1)
elif "gtk_swift_search_entry_set_key_capture_widget(entry, box)" not in text:
    raise SystemExit("SwiftOpenUI SearchableView content append was not recognized")

if "extension SearchableView: GTKRenderable, GTKDescribable" in text:
    search_box_marker = """        gtk_widget_set_can_target(box, 1)
        let binding = text
"""
    search_box_fill = """        gtk_widget_set_can_target(box, 1)
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        gtk_widget_set_halign(box, GTK_ALIGN_FILL)
        gtk_widget_set_valign(box, GTK_ALIGN_FILL)
        gtkMarkVerticalFillIntent(box)
        let binding = text
"""
    if search_box_marker in text:
        text = text.replace(search_box_marker, search_box_fill, 1)
    text = text.replace(
        """        gtk_widget_set_can_target(box, 1)
        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
        gtk_widget_set_halign(box, GTK_ALIGN_FILL)
        gtk_widget_set_valign(box, GTK_ALIGN_FILL)
        let binding = text
""",
        search_box_fill,
        1,
    )

    search_content_marker = """        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_vexpand(contentWidget, 1)
        gtk_swift_search_entry_set_key_capture_widget(entry, box)
"""
    search_content_fill = """        let contentWidget = widgetFromOpaque(gtkRenderView(content))
        gtk_widget_set_hexpand(contentWidget, 1)
        gtk_widget_set_vexpand(contentWidget, 1)
        gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
        gtk_swift_search_entry_set_key_capture_widget(entry, box)
"""
    if search_content_marker in text:
        text = text.replace(search_content_marker, search_content_fill, 1)

old_is_dismissed = "        let isDismissed = isPresented.map { !$0.wrappedValue } ?? false\n"
new_is_dismissed = """        let isDismissed = isPresented.map {
            !$0.wrappedValue && !gtkSearchableKeepsChromeVisible(for: placement)
        } ?? false
"""
if old_is_dismissed in text:
    text = text.replace(old_is_dismissed, new_is_dismissed, 1)
elif "gtkSearchableKeepsChromeVisible(for: placement)" not in text:
    raise SystemExit("SwiftOpenUI SearchableView visibility expression was not recognized")

old_search_binding_write = """                if newValue != box.binding.wrappedValue {
                    box.binding.wrappedValue = newValue
                }
"""
new_search_binding_write = """                if newValue != box.binding.wrappedValue {
                    gtkDebugLog("searchable search-changed text='\\(newValue)'")
                    gtkScheduleTextBindingUpdate(box.binding, value: newValue)
                }
"""
if old_search_binding_write in text:
    text = text.replace(old_search_binding_write, new_search_binding_write, 1)
elif "gtkScheduleTextBindingUpdate(box.binding, value: newValue)" not in text:
    raise SystemExit("SwiftOpenUI SearchableView search-changed binding update was not recognized")

focus_handler = """        let focusGesture = gtk_gesture_click_new()!
        let focusBox = Unmanaged.passRetained(
            SearchBox(entry: entry, binding: binding, isPresented: presentedBinding)
        ).toOpaque()
        gtk_swift_gesture_single_set_button(focusGesture, 1)
        g_signal_connect_data(
            gpointer(focusGesture),
            "pressed",
            unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
                guard let userData else { return }
                let box = Unmanaged<SearchBox>.fromOpaque(userData).takeUnretainedValue()
                box.isPresented?.wrappedValue = true
                gtk_widget_set_focusable(box.entry, 1)
                let entryGrabbed = gtk_swift_root_grab_focus(box.entry)
                gtkDebugLog("searchable focus pressed entryGrabbed=\\(entryGrabbed)")
                if let delegate = gtk_editable_get_delegate(OpaquePointer(box.entry)) {
                    let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
                    gtk_widget_set_focusable(delegateWidget, 1)
                    let delegateGrabbed = gtk_swift_root_grab_focus(delegateWidget)
                    gtkDebugLog("searchable focus delegateGrabbed=\\(delegateGrabbed)")
                }
            } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
            focusBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<SearchBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_capture_gesture(box, focusGesture)

"""
if "let focusGesture = gtk_gesture_click_new()!" not in text:
    marker = """        g_signal_connect_data(
            gpointer(entry),
            "search-changed",
"""
    if marker not in text:
        raise SystemExit("SwiftOpenUI SearchableView search focus marker was not recognized")
    text = text.replace(marker, focus_handler + marker, 1)

changed_handler = """        let changedBox = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(entry),
            "changed",
            unsafeBitCast({ (editable: gpointer?, userData: gpointer?) in
                let box = Unmanaged<StringClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let cStr = gtk_editable_get_text(OpaquePointer(editable))!
                let newText = String(cString: cStr)
                gtkDebugLog("searchable changed text='\\(newText)'")
                box.closure(newText)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            changedBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<StringClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

"""
if "let changedBox = Unmanaged.passRetained(StringClosureBox { newText in\n            gtkScheduleTextBindingUpdate(binding, value: newText)" not in text:
    marker = "        // Render token labels between search entry and content\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI SearchableView token marker was not recognized")
    text = text.replace(marker, changed_handler + marker, 1)

searchable_root_focus_helper = r"""private let gtkSearchableFocusDataKey = "gtk-swift-searchable-focus"
private let gtkSearchableTopSurfaceDataKey = "gtk-swift-searchable-top-surface-focus"
private let gtkSearchableDefaultHitHeight = 48.0

private final class GTKSearchRootEventContext {
    let entry: UnsafeMutablePointer<GtkWidget>
    let box: SearchBox
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?
    var loggedRootUnavailable = false

    init(entry: UnsafeMutablePointer<GtkWidget>, box: SearchBox) {
        self.entry = entry
        self.box = box
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
    }
}

private func gtkSearchableKeepsChromeVisible(for placement: SearchFieldPlacement) -> Bool {
    switch placement {
    case .navigationBarDrawer(let displayMode):
        return displayMode == .always
    case .automatic, .toolbar, .sidebar:
        return false
    }
}

private func gtkAttachSearchFocusData(to widget: UnsafeMutablePointer<GtkWidget>, box: SearchBox) {
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    let retained = Unmanaged.passRetained(box).toOpaque()
    g_object_set_data_full(object, gtkSearchableFocusDataKey, retained) { userData in
        guard let userData else { return }
        Unmanaged<SearchBox>.fromOpaque(userData).release()
    }
}

private func gtkAttachSearchTopSurfaceData(to widget: UnsafeMutablePointer<GtkWidget>, box: SearchBox) {
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    let retained = Unmanaged.passRetained(box).toOpaque()
    g_object_set_data_full(object, gtkSearchableTopSurfaceDataKey, retained) { userData in
        guard let userData else { return }
        Unmanaged<SearchBox>.fromOpaque(userData).release()
    }
}

private func gtkFocusSearchBox(_ box: SearchBox, source: String) -> Bool {
    box.isPresented?.wrappedValue = true
    gtk_widget_set_focusable(box.entry, 1)
    gtk_widget_set_focus_on_click(box.entry, 1)
    let entryGrabbed = gtk_swift_root_grab_focus(box.entry) != 0
    var delegateGrabbed = false
    if let delegate = gtk_editable_get_delegate(OpaquePointer(box.entry)) {
        let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
        gtk_widget_set_focusable(delegateWidget, 1)
        gtk_widget_set_focus_on_click(delegateWidget, 1)
        delegateGrabbed = gtk_swift_root_grab_focus(delegateWidget) != 0
    }
    gtkDebugLog(
        "searchable focus \(source) entryGrabbed=\(entryGrabbed ? 1 : 0) "
        + "delegateGrabbed=\(delegateGrabbed ? 1 : 0)"
    )
    return entryGrabbed || delegateGrabbed
}

private func gtkSearchFocusBoxAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> SearchBox? {
    var result: SearchBox?

    func walk(_ widget: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard result == nil, depth < 160 else { return }
        guard gtk_widget_get_visible(widget) != 0 else { return }
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if let raw = g_object_get_data(object, gtkSearchableTopSurfaceDataKey),
           let box = Optional(Unmanaged<SearchBox>.fromOpaque(raw).takeUnretainedValue()) {
            if gtkSearchEntryAllocationContainsRootPoint(box.entry, root: root, x: x, y: y)
                || gtkSearchEntryEstimatedChromeContainsRootPoint(box.entry, root: root, x: x, y: y) {
                result = box
                return
            }
            if let frame = gtkWidgetVisualFrameInRoot(widget, root: root),
               x >= frame.x, x < frame.x + frame.width,
               y >= frame.y, y < frame.y + gtkSearchableDefaultHitHeight {
                result = box
                return
            }
        }
        if let raw = g_object_get_data(object, gtkSearchableFocusDataKey),
           let box = Optional(Unmanaged<SearchBox>.fromOpaque(raw).takeUnretainedValue()) {
            if gtkSearchEntryAllocationContainsRootPoint(box.entry, root: root, x: x, y: y)
                || gtkSearchEntryEstimatedChromeContainsRootPoint(box.entry, root: root, x: x, y: y)
                || gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
                result = box
                return
            }
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(root, depth: 0)
    return result
}

private func gtkSearchEntryEstimatedChromeContainsRootPoint(
    _ entry: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    guard gtk_widget_get_mapped(entry) != 0 else { return false }
    guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(root, root: root, x: x, y: y) else {
        return false
    }
    guard let frame = gtkWidgetVisualFrameInRoot(entry, root: root) else { return false }
    let rootWidth = Double(gtk_widget_get_width(root))
    guard rootWidth > 0 else { return false }
    return x >= 0
        && x < rootWidth
        && y >= frame.y
        && y < frame.y + gtkSearchableDefaultHitHeight
}

private func gtkSearchEntryAllocationContainsRootPoint(
    _ entry: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    let width = Double(gtk_widget_get_width(entry))
    let height = Double(gtk_widget_get_height(entry))
    guard width > 0, height > 0 else { return false }
    var entryX = 0.0
    var entryY = 0.0
    guard gtk_swift_widget_compute_point(entry, root, 0, 0, &entryX, &entryY) != 0 else {
        return false
    }
    return x >= entryX
        && x < entryX + width
        && y >= entryY
        && y < entryY + max(height, gtkSearchableDefaultHitHeight)
}

private func gtkDebugSearchFocusCandidates(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    var total = 0
    var hits = 0

    func walk(_ widget: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard depth < 160 else { return }
        let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        let hasEntryData = g_object_get_data(object, gtkSearchableFocusDataKey) != nil
        let hasTopSurfaceData = g_object_get_data(object, gtkSearchableTopSurfaceDataKey) != nil
        if hasEntryData || hasTopSurfaceData {
            let raw = g_object_get_data(object, gtkSearchableTopSurfaceDataKey)
                ?? g_object_get_data(object, gtkSearchableFocusDataKey)
            let allocationHit = raw.map {
                let box = Unmanaged<SearchBox>.fromOpaque($0).takeUnretainedValue()
                return gtkSearchEntryAllocationContainsRootPoint(box.entry, root: root, x: x, y: y)
            } ?? false
            let estimatedChromeHit = raw.map {
                let box = Unmanaged<SearchBox>.fromOpaque($0).takeUnretainedValue()
                return gtkSearchEntryEstimatedChromeContainsRootPoint(box.entry, root: root, x: x, y: y)
            } ?? false
            let containsEntry = gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y)
            var containsTopSurface = false
            if hasTopSurfaceData,
               let frame = gtkWidgetVisualFrameInRoot(widget, root: root),
               x >= frame.x, x < frame.x + frame.width,
               y >= frame.y, y < frame.y + gtkSearchableDefaultHitHeight {
                containsTopSurface = true
            }
            let contains = allocationHit || estimatedChromeHit || containsEntry || containsTopSurface
            total += 1
            if contains { hits += 1 }
            gtkDebugLog(
                "\(source) search-candidate[\(total - 1)] hit=\(contains ? 1 : 0) "
                + "surface=\(hasTopSurfaceData ? 1 : 0) "
                + "allocation=\(allocationHit ? 1 : 0) "
                + "estimated=\(estimatedChromeHit ? 1 : 0) "
                + gtkDebugVisualFrameDescription(widget, root: root)
            )
        }

        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(root, depth: 0)
    gtkDebugLog("\(source) search-candidates total=\(total) hits=\(hits) root@\(Int(x)),\(Int(y))")
}

private func gtkFocusSearchEntryAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) -> Bool {
    guard let box = gtkSearchFocusBoxAtRootPoint(root: root, x: x, y: y) else {
        gtkDebugSearchFocusCandidates(root: root, x: x, y: y, source: source)
        return false
    }
    return gtkFocusSearchBox(box, source: source)
}

private func gtkInstallSearchRootEventFallback(_ context: GTKSearchRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.entry) else {
        if !context.loggedRootUnavailable {
            context.loggedRootUnavailable = true
            gtkDebugLog("searchable root fallback root unavailable")
        }
        return
    }

    let controller = gtk_swift_legacy_capture_controller()!
    context.root = root
    context.controller = controller
    gtkDebugLog("searchable root fallback installed")
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return 0 }
            var rootX: Double = 0
            var rootY: Double = 0
            guard gtk_swift_event_get_position(event, &rootX, &rootY) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            if gtkRootSheetLayerOccludesRootPoint(root: root, x: rootX, y: rootY) {
                gtkDebugLog("searchable root skipped root sheet root@\(Int(rootX)),\(Int(rootY))")
                return 0
            }
            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "search-root@\(Int(rootX)),\(Int(rootY))"
            ) {
                return 1
            }
            return 0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

private func gtkSearchRootInstallTickCallback(
    _ widget: UnsafeMutablePointer<GtkWidget>?,
    _ frameClock: OpaquePointer?,
    _ userData: gpointer?
) -> gboolean {
    guard let userData else { return 0 }
    let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
    gtkInstallSearchRootEventFallback(context)
    return context.controller == nil ? 1 : 0
}

private func gtkInstallSearchFocusGesture(
    on widget: UnsafeMutablePointer<GtkWidget>,
    entry: UnsafeMutablePointer<GtkWidget>,
    binding: Binding<String>,
    isPresented: Binding<Bool>?
) {
    let focusGesture = gtk_gesture_click_new()!
    let focusBox = Unmanaged.passRetained(
        SearchBox(entry: entry, binding: binding, isPresented: isPresented)
    ).toOpaque()
    gtk_swift_gesture_single_set_button(focusGesture, 1)
    g_signal_connect_data(
        gpointer(focusGesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
            guard let userData else { return }
            let box = Unmanaged<SearchBox>.fromOpaque(userData).takeUnretainedValue()
            _ = gtkFocusSearchBox(box, source: "gesture")
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        focusBox,
        { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            Unmanaged<SearchBox>.fromOpaque(userData!).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(widget, focusGesture)
}

"""
if "private let gtkSearchableFocusDataKey" not in text:
    marker = "private func gtkSearchableKeepsChromeVisible(for placement: SearchFieldPlacement) -> Bool"
    extension_marker = "extension SearchableView: GTKRenderable, GTKDescribable {\n"
    if marker not in text or extension_marker not in text:
        raise SystemExit("SwiftOpenUI SearchableView root focus helper shape was not recognized")
    start = text.index(marker)
    end = text.index(extension_marker, start)
    text = text[:start] + searchable_root_focus_helper + text[end:]

searchable_entry_setup = r"""        let entry = gtk_swift_search_entry_new()!
        gtkDebugLog("searchable create placement=\(placement) prompt='\(prompt)' text='\(binding.wrappedValue)'")
        gtk_widget_set_focusable(entry, 1)
        gtk_widget_set_focus_on_click(entry, 1)
        let searchFocusBox = SearchBox(entry: entry, binding: binding, isPresented: presentedBinding)
        gtkAttachSearchTopSurfaceData(to: box, box: searchFocusBox)
        gtkAttachSearchFocusData(to: entry, box: searchFocusBox)
        let entryContainer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_can_target(entryContainer, 1)
        gtk_widget_set_hexpand(entryContainer, 1)
        gtk_widget_set_halign(entryContainer, GTK_ALIGN_FILL)
        gtk_widget_set_valign(entryContainer, GTK_ALIGN_START)
        gtkAttachSearchFocusData(to: entryContainer, box: searchFocusBox)
        if let delegate = gtk_editable_get_delegate(OpaquePointer(entry)) {
            let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
            gtk_widget_set_focusable(delegateWidget, 1)
            gtk_widget_set_focus_on_click(delegateWidget, 1)
            gtkAttachSearchFocusData(to: delegateWidget, box: searchFocusBox)
            gtkInstallSearchFocusGesture(
                on: delegateWidget,
                entry: entry,
                binding: binding,
                isPresented: presentedBinding
            )
        }
        gtkInstallSearchFocusGesture(on: entry, entry: entry, binding: binding, isPresented: presentedBinding)
        gtkInstallSearchFocusGesture(on: box, entry: entry, binding: binding, isPresented: presentedBinding)
        let rootContextObject = GTKSearchRootEventContext(entry: entry, box: searchFocusBox)
        let rootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
        g_signal_connect_data(
            gpointer(entry),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallSearchRootEventFallback(context)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(entry),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        let tickRootEventContext = Unmanaged.passRetained(rootContextObject).toOpaque()
        _ = gtk_widget_add_tick_callback(
            entry,
            gtkSearchRootInstallTickCallback,
            tickRootEventContext,
            { userData in
                guard let userData else { return }
                Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).release()
            }
        )
        g_signal_connect_data(
            gpointer(entry),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKSearchRootEventContext>.fromOpaque(userData).takeRetainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            rootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
"""
if "let searchFocusBox = SearchBox(entry: entry" not in text:
    extension_start = text.index("extension SearchableView: GTKRenderable, GTKDescribable {\n")
    start = text.index("        let entry = gtk_swift_search_entry_new()!\n", extension_start)
    end = text.index("        if !prompt.isEmpty {\n", start)
    text = text[:start] + searchable_entry_setup + text[end:]

if "gtk_box_append(boxPointer(entryContainer), entry)" not in text:
    old_append = "        gtk_box_append(boxPtr, entry)\n"
    new_append = """        gtk_box_append(boxPointer(entryContainer), entry)
        gtk_box_append(boxPtr, entryContainer)
"""
    if old_append not in text:
        raise SystemExit("SwiftOpenUI SearchableView entry container append was not recognized")
    text = text.replace(old_append, new_append, 1)

if "gtk_widget_set_visible(entryContainer, 0)" not in text:
    old_hide = """        if isDismissed {
            gtk_widget_set_visible(entry, 0)
        }
"""
    new_hide = """        if isDismissed {
            gtk_widget_set_visible(entry, 0)
            gtk_widget_set_visible(entryContainer, 0)
        }
"""
    if old_hide not in text:
        raise SystemExit("SwiftOpenUI SearchableView entry container visibility was not recognized")
    text = text.replace(old_hide, new_hide, 1)

def insert_search_focus_guard(anchor: str, guard: str, error: str) -> None:
    global text
    if guard in text:
        return
    if anchor not in text:
        raise SystemExit(error)
    text = text.replace(anchor, guard + anchor, 1)

insert_search_focus_guard(
    '''            if gtkOpenVisualMenuButtonAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "tap-root-dispatch@\\(Int(rootX)),\\(Int(rootY))"
            ) {
''',
    '''            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "tap-root-dispatch@\\(Int(rootX)),\\(Int(rootY))"
            ) {
                return 1
            }

''',
    "SwiftOpenUI tap root dispatcher searchable guard shape was not recognized",
)
insert_search_focus_guard(
    '''            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "tap-root-dispatch@\\(Int(rootX)),\\(Int(rootY))"
            ) {
''',
    '''            if gtkRootSheetLayerOccludesRootPoint(root: root, x: rootX, y: rootY) {
                gtkDebugLog("tap gesture global dispatch skipped root sheet root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }
''',
    "SwiftOpenUI tap root dispatcher root sheet guard shape was not recognized",
)
insert_search_focus_guard(
    '''            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y)
''',
    '''            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: x,
                y: y,
                source: "tap-root@\\(Int(x)),\\(Int(y))"
            ) {
                return 1
            }

''',
    "SwiftOpenUI tap root fallback searchable guard shape was not recognized",
)
insert_search_focus_guard(
    '''            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: x,
                y: y,
                source: "tap-root@\\(Int(x)),\\(Int(y))"
            ) {
''',
    '''            if gtkRootSheetLayerOccludesRootPoint(
                root: root,
                x: x,
                y: y,
                excludingDescendant: context.widget
            ) {
                gtkDebugLog("tap gesture root skipped root sheet root@\\(Int(x)),\\(Int(y)) \\(context.source)")
                return 0
            }
''',
    "SwiftOpenUI tap root fallback root sheet guard shape was not recognized",
)
insert_search_focus_guard(
    '''            if gtkOpenVisualMenuButtonAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "list-row-root-dispatch@\\(Int(rootX)),\\(Int(rootY))"
            ) {
''',
    '''            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "list-row-root-dispatch@\\(Int(rootX)),\\(Int(rootY))"
            ) {
                return 1
            }

''',
    "SwiftOpenUI list row root dispatcher searchable guard shape was not recognized",
)

if text != original:
    path.write_text(text)
PY

if [[ -f "$SWIFT_DEPENDENCIES_MAIN_QUEUE" ]]; then
  chmod u+w "$SWIFT_DEPENDENCIES_MAIN_QUEUE"
  python3 - "$SWIFT_DEPENDENCIES_MAIN_QUEUE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
needle = "  import Foundation\n"
insert = """  import Foundation
  #if canImport(OpenCombineDispatch)
    import OpenCombineDispatch
  #endif
"""
if "import OpenCombineDispatch" not in text:
    text = text.replace(needle, insert, 1)
if text != original:
    path.write_text(text)
PY
fi

if [[ -f "$SWIFT_DEPENDENCIES_MAIN_RUN_LOOP" ]]; then
  chmod u+w "$SWIFT_DEPENDENCIES_MAIN_RUN_LOOP"
  python3 - "$SWIFT_DEPENDENCIES_MAIN_RUN_LOOP" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
needle = "  import Foundation\n"
insert = """  import Foundation
  #if canImport(OpenCombineFoundation)
    import OpenCombineFoundation
  #endif
"""
if "import OpenCombineFoundation" not in text:
    text = text.replace(needle, insert, 1)
if text != original:
    path.write_text(text)
PY
fi

for SWIFTUI_OPTIONAL_SOURCE_DIR in \
  "$SWIFT_DEPENDENCIES_SOURCE_DIR" \
  "$SWIFT_SHARING_SOURCE_DIR" \
  "$COMBINE_SCHEDULERS_SOURCE_DIR" \
  "$CUSTOM_DUMP_SOURCE_DIR" \
  "$XCTEST_DYNAMIC_OVERLAY_SOURCE_DIR"
do
if [[ -d "$SWIFTUI_OPTIONAL_SOURCE_DIR" ]]; then
  python3 - "$SWIFTUI_OPTIONAL_SOURCE_DIR" <<'PY'
import re
import stat
import sys
from pathlib import Path

source_dir = Path(sys.argv[1])
pattern = re.compile(r"canImport\((SwiftUI|AppKit|UIKit|WatchKit)\)(?!\s*&&\s*!os\(Linux\))")
for path in source_dir.rglob("*.swift"):
    text = path.read_text()
    next_text = pattern.sub(lambda match: f"canImport({match.group(1)}) && !os(Linux)", text)
    if next_text != text:
        path.chmod(path.stat().st_mode | stat.S_IWUSR)
        path.write_text(next_text)
PY
fi
done

if [[ -d "$SWIFT_SHARING_SOURCE_DIR" ]]; then
  python3 - "$SWIFT_SHARING_SOURCE_DIR" <<'PY'
import re
import sys
from pathlib import Path

def disable_can_import(text: str, module: str) -> str:
    text = re.sub(rf"!os\(Linux\)\s*&&\s*canImport\({module}\)", "false", text)
    text = re.sub(rf"canImport\({module}\)(?:\s*&&\s*!os\(Linux\))+", "false", text)
    return text.replace(f"canImport({module})", "false")

root = Path(sys.argv[1])
for path in root.rglob("*.swift"):
    text = path.read_text()
    new = disable_can_import(text, "SwiftUI")
    if new != text:
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(new)
PY
fi

if [[ -f "$SWIFT_SHARING_PASSTHROUGH_RELAY" ]]; then
  chmod u+w "$SWIFT_SHARING_PASSTHROUGH_RELAY"
  python3 - "$SWIFT_SHARING_PASSTHROUGH_RELAY" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
text = text.replace("private let lock: os_unfair_lock_t", "private let lock: NSRecursiveLock")
text = text.replace(
    """self.lock = os_unfair_lock_t.allocate(capacity: 1)
      self.lock.initialize(to: os_unfair_lock())""",
    "self.lock = NSRecursiveLock()",
)
text = text.replace(
    """self.lock = os_unfair_lock_t.allocate(capacity: 1)
        self.lock.initialize(to: os_unfair_lock())""",
    "self.lock = NSRecursiveLock()",
)
text = text.replace(
    """      lock.deinitialize(count: 1)
      lock.deallocate()
""",
    "",
)
text = text.replace(
    """        lock.deinitialize(count: 1)
        lock.deallocate()
""",
    "",
)
old_extension = """  extension os_unfair_lock_t {
    fileprivate func withLock<R>(_ body: () throws -> R) rethrows -> R {
      lock()
      defer { unlock() }
      return try body()
    }

    fileprivate func lock() {
      os_unfair_lock_lock(self)
    }

    fileprivate func unlock() {
      os_unfair_lock_unlock(self)
    }
  }
"""
new_extension = """  extension NSRecursiveLock {
    fileprivate func withLock<R>(_ body: () throws -> R) rethrows -> R {
      lock()
      defer { unlock() }
      return try body()
    }
  }
"""
text = text.replace(old_extension, new_extension)
if text != original:
    path.write_text(text)
PY
fi

if [[ -f "$SWIFT_SHARING_APP_STORAGE_KEY" ]]; then
  chmod u+w "$SWIFT_SHARING_APP_STORAGE_KEY"
  python3 - "$SWIFT_SHARING_APP_STORAGE_KEY" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
text = text.replace("#if DEBUG\n        if store.responds", "#if DEBUG && !os(Linux)\n        if store.responds")
text = text.replace(
    """      let removeObserver: @Sendable () -> Void
      let keyContainsPeriod = key.contains(".")
      if keyContainsPeriod || key.hasPrefix("@") {
""",
    """      let removeObserver: @Sendable () -> Void
      let keyContainsPeriod = key.contains(".")
      #if os(Linux)
        let usesNotificationFallback = true
      #else
        let usesNotificationFallback = keyContainsPeriod || key.hasPrefix("@")
      #endif
      if usesNotificationFallback {
""",
)
text = text.replace(
    "if appStorageKeyFormatWarningEnabled {\n",
    "if appStorageKeyFormatWarningEnabled && (keyContainsPeriod || key.hasPrefix(\"@\")) {\n",
    1,
)
old_kvo = """      } else {
        let observer = Observer {
          guard !SharedAppStorageLocals.isSetting
          else { return }
          subscriber.yield(with: .success(lookupValue(default: context.initialValue)))
        }
        store.wrappedValue.addObserver(observer, forKeyPath: key, context: nil)
        removeObserver = { store.wrappedValue.removeObserver(observer, forKeyPath: key) }
      }
"""
new_kvo = """      } else {
        #if os(Linux)
          removeObserver = {}
        #else
          let observer = Observer {
            guard !SharedAppStorageLocals.isSetting
            else { return }
            subscriber.yield(with: .success(lookupValue(default: context.initialValue)))
          }
          store.wrappedValue.addObserver(observer, forKeyPath: key, context: nil)
          removeObserver = { store.wrappedValue.removeObserver(observer, forKeyPath: key) }
        #endif
      }
"""
text = text.replace(old_kvo, new_kvo)
observer_start = text.find("    private final class Observer: NSObject, Sendable {")
observer_end_marker = "\n  }\n\n  extension AppStorageKey"
if observer_start != -1 and "#if !os(Linux)\n    private final class Observer" not in text:
    observer_end = text.find(observer_end_marker, observer_start)
    if observer_end != -1:
        observer_block = text[observer_start:observer_end]
        text = (
            text[:observer_start]
            + "    #if !os(Linux)\n"
            + observer_block
            + "\n    #endif"
            + text[observer_end:]
        )
if text != original:
    path.write_text(text)
PY
fi

if [[ -f "$SWIFT_SHARING_FILE_STORAGE_KEY" ]]; then
  chmod u+w "$SWIFT_SHARING_FILE_STORAGE_KEY"
  python3 - "$SWIFT_SHARING_FILE_STORAGE_KEY" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
needle = """  import CombineSchedulers
  import ConcurrencyExtras
  import Dependencies
  @preconcurrency import Dispatch
"""
insert = """  import CombineSchedulers
  import ConcurrencyExtras
  import Dependencies
  @preconcurrency import Dispatch
  import Foundation
  #if canImport(OpenCombineDispatch)
    import OpenCombineDispatch
  #endif
  #if canImport(Glibc)
    import Glibc
  #endif

  #if os(Linux)
    private let O_EVTONLY = O_RDONLY
  #endif
"""
if "import OpenCombineDispatch" not in text:
    text = text.replace(needle, insert, 1)
text = text.replace(
    "id: AnyHashableSendable(DispatchQueue.main)",
    "id: AnyHashableSendable(ObjectIdentifier(DispatchQueue.main))",
)
start = text.find("      fileSystemSource: {\n")
end = text.find("      load: { url in\n", start)
if start != -1 and end != -1 and "fileSystemSource: { _, _, _ in" not in text[start:end]:
    text = (
        text[:start]
        + """      fileSystemSource: { _, _, _ in
        SharedSubscription {}
      },
"""
        + text[end:]
    )
if text != original:
    path.write_text(text)
PY
fi

if [[ -d "$COMBINE_SCHEDULERS_SOURCE_DIR" ]]; then
  python3 - "$COMBINE_SCHEDULERS_SOURCE_DIR" <<'PY'
import sys
import re
from pathlib import Path

def disable_can_import(text: str, module: str) -> str:
    text = re.sub(rf"!os\(Linux\)\s*&&\s*canImport\({module}\)", "false", text)
    text = re.sub(rf"canImport\({module}\)(?:\s*&&\s*!os\(Linux\))+", "false", text)
    return text.replace(f"canImport({module})", "false")

root = Path(sys.argv[1])
for path in root.rglob("*.swift"):
    text = path.read_text()
    new = disable_can_import(text, "UIKit")
    new = disable_can_import(new, "SwiftUI")
    if new != text:
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(new)
PY
fi

if [[ -d "$CUSTOM_DUMP_SOURCE_DIR" ]]; then
  python3 - "$CUSTOM_DUMP_SOURCE_DIR" <<'PY'
import sys
import re
from pathlib import Path

def disable_can_import(text: str, module: str) -> str:
    text = re.sub(rf"!os\(Linux\)\s*&&\s*canImport\({module}\)", "false", text)
    text = re.sub(rf"canImport\({module}\)(?:\s*&&\s*!os\(Linux\))+", "false", text)
    return text.replace(f"canImport({module})", "false")

root = Path(sys.argv[1])
for path in root.rglob("*.swift"):
    text = path.read_text()
    new = disable_can_import(text, "UIKit")
    new = disable_can_import(new, "SwiftUI")
    new = disable_can_import(new, "CoreGraphics")
    if new != text:
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(new)
PY
fi

if [[ -d "$SWIFT_PERCEPTION_SOURCE_DIR" ]]; then
  python3 - "$SWIFT_PERCEPTION_SOURCE_DIR" <<'PY'
import sys
import re
from pathlib import Path

def disable_can_import(text: str, module: str) -> str:
    text = re.sub(rf"!os\(Linux\)\s*&&\s*canImport\({module}\)", "false", text)
    text = re.sub(rf"canImport\({module}\)(?:\s*&&\s*!os\(Linux\))+", "false", text)
    return text.replace(f"canImport({module})", "false")

root = Path(sys.argv[1])
for path in root.rglob("*.swift"):
    text = path.read_text()
    new = disable_can_import(text, "SwiftUI")
    if new != text:
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(new)
PY
fi

if [[ -d "$XCTEST_DYNAMIC_OVERLAY_SOURCE_DIR" ]]; then
  python3 - "$XCTEST_DYNAMIC_OVERLAY_SOURCE_DIR" <<'PY'
import sys
import re
from pathlib import Path

def disable_can_import(text: str, module: str) -> str:
    text = re.sub(rf"!os\(Linux\)\s*&&\s*canImport\({module}\)", "false", text)
    text = re.sub(rf"canImport\({module}\)(?:\s*&&\s*!os\(Linux\))+", "false", text)
    return text.replace(f"canImport({module})", "false")

root = Path(sys.argv[1])
for path in root.rglob("*.swift"):
    text = path.read_text()
    new = disable_can_import(text, "os")
    new = disable_can_import(new, "Darwin")
    if new != text:
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(new)
PY
fi

for candidate_grdb_source_dir in "$GRDB_SOURCE_DIR" "$VENDORED_GRDB_SOURCE_DIR"; do
  [[ -d "$candidate_grdb_source_dir" ]] || continue

  python3 - "$candidate_grdb_source_dir" <<'PY'
import sys
import re
from pathlib import Path

def disable_can_import(text: str, module: str) -> str:
    text = re.sub(rf"!os\(Linux\)\s*&&\s*canImport\({module}\)", "false", text)
    text = re.sub(rf"canImport\({module}\)(?:\s*&&\s*!os\(Linux\))+", "false", text)
    return text.replace(f"canImport({module})", "false")

root = Path(sys.argv[1])
for path in root.rglob("*.swift"):
    text = path.read_text()
    new = disable_can_import(text, "Combine")
    if new != text:
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(new)

cgfloat = root / "Core" / "Support" / "CoreGraphics" / "CGFloat.swift"
if cgfloat.exists():
    text = cgfloat.read_text()
    body_start = text.find("/// CGFloat adopts DatabaseValueConvertible")
    if body_start != -1 and not text.startswith("#if os(Linux)"):
        body = text[body_start:].strip()
        if body.endswith("#endif"):
            body = body[: -len("#endif")].strip()
        cgfloat.chmod(cgfloat.stat().st_mode | 0o200)
        cgfloat.write_text(
            """#if os(Linux)
// QUILLUI_GRDB_SKIP_CGFLOAT_ON_LINUX
#elseif canImport(CoreGraphics)
import CoreGraphics

"""
            + body
            + "\n#endif\n"
        )
PY
done

if [[ -d "$SQLITE_DATA_SOURCE_DIR" ]]; then
  python3 - "$SQLITE_DATA_SOURCE_DIR" <<'PY'
import sys
import re
from pathlib import Path

def disable_can_import(text: str, module: str) -> str:
    text = re.sub(rf"!os\(Linux\)\s*&&\s*canImport\({module}\)", "false", text)
    text = re.sub(rf"canImport\({module}\)(?:\s*&&\s*!os\(Linux\))+", "false", text)
    return text.replace(f"canImport({module})", "false")

root = Path(sys.argv[1])
for path in root.rglob("*.swift"):
    text = path.read_text()
    new = disable_can_import(text, "SwiftUI")
    new = disable_can_import(new, "CloudKit")
    new = disable_can_import(new, "UIKit")
    new = disable_can_import(new, "Combine")
    if new != text:
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(new)
PY
fi

if [[ -f "$STATE" ]]; then
  python3 - "$STATE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
if "swiftOpenUIStateDebugLog(_ message: String)" not in text:
    text = text.replace(
        "import Foundation\n",
        """import Foundation

private func swiftOpenUIStateDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
        return
    }
    if let data = ("[QuillUI GTK] " + message + "\\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}
""",
        1,
    )
if "forwardMutations(to other: AnyStateStorage)" not in text:
    text = text.replace(
        """public protocol AnyStateStorage: AnyObject {
    var host: AnyViewHost? { get set }
    /// Copy the stored value from another storage of the same concrete type.
    func restoreValue(from other: AnyStateStorage)
}
""",
        """public protocol AnyStateStorage: AnyObject {
    var host: AnyViewHost? { get set }
    /// Copy the stored value from another storage of the same concrete type.
    func restoreValue(from other: AnyStateStorage)
    /// Forward writes from stale widget closures to the current render storage.
    func forwardMutations(to other: AnyStateStorage)
}

public extension AnyStateStorage {
    func forwardMutations(to other: AnyStateStorage) {}
}
""",
        1,
    )
    text = text.replace(
        "    var _value: Value  // internal for restoreValue cross-storage access\n",
        "    var _value: Value  // internal for restoreValue cross-storage access\n    private var forwardedStorage: StateStorage<Value>?\n",
        1,
    )
    text = text.replace(
        """    public func setValue(_ newValue: Value) {
        lock.lock()
        _value = newValue
        generation += 1
        lock.unlock()
""",
        """    public func setValue(_ newValue: Value) {
        lock.lock()
        _value = newValue
        generation += 1
        let forwarded = forwardedStorage
        lock.unlock()
        if let forwarded {
            forwarded.setValue(newValue)
            return
        }
""",
        1,
    )
    text = text.replace(
        """    public func restoreValue(from other: AnyStateStorage) {
        if let typed = other as? StateStorage<Value> {
""",
        """    public func forwardMutations(to other: AnyStateStorage) {
        lock.lock()
        defer { lock.unlock() }
        guard let typed = other as? StateStorage<Value>, typed !== self else {
            forwardedStorage = nil
            return
        }
        forwardedStorage = typed
    }

    public func restoreValue(from other: AnyStateStorage) {
        if let typed = other as? StateStorage<Value> {
""",
        1,
    )
if "wireObservableObjectStateValueIfNeeded" not in text:
    text = text.replace(
        "    public weak var host: AnyViewHost?\n",
        """    public weak var host: AnyViewHost? {
        didSet { wireObservableObjectStateValueIfNeeded() }
    }

    private func wireObservableObjectStateValueIfNeeded() {
        guard let object = _value as? any ObservableObject else { return }
        var mirror: Mirror? = Mirror(reflecting: object)
        while let current = mirror {
            for child in current.children {
                guard let provider = child.value as? AnyPublishedProvider else { continue }
                provider.anyPublished.setObserver(token: ObjectIdentifier(self)) { [weak self] in
                    self?.host?.scheduleRebuild()
                }
            }
            mirror = current.superclassMirror
        }
    }
""",
        1,
    )
if 'swiftOpenUIStateDebugLog("state set type=' not in text:
    text = text.replace(
        """        let forwarded = forwardedStorage
        lock.unlock()
        if let forwarded {
            forwarded.setValue(newValue)
            return
        }
""",
        """        let forwarded = forwardedStorage
        lock.unlock()
        swiftOpenUIStateDebugLog("state set type=\\(Value.self) forwarded=\\(forwarded != nil)")
        if let forwarded {
            forwarded.setValue(newValue)
            return
        }
""",
        1,
    )
if 'swiftOpenUIStateDebugLog("state forward type=' not in text:
    text = text.replace(
        """        forwardedStorage = typed
    }

    public func restoreValue(from other: AnyStateStorage) {
""",
        """        forwardedStorage = typed
        swiftOpenUIStateDebugLog("state forward type=\\(Value.self)")
    }

    public func restoreValue(from other: AnyStateStorage) {
""",
        1,
    )
if text != original:
    path.write_text(text)
PY
fi

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
text = text.replace('css += " object-fit: contain;"', 'css += ""')
text = text.replace(
    'css += " object-fit: cover; overflow: hidden;"',
    'css += " overflow: hidden;"',
)
text = text.replace(
    'applyCSSToWidget(entry, properties: "border: none; outline: none; box-shadow: none;")',
    'applyCSSToWidget(entry, properties: "background: transparent; background-color: transparent; border: none; outline: none; box-shadow: none; padding: 0;")',
)

legacy_scroll_policy = '''        let hPolicy: GtkPolicyType = axes.contains(.horizontal) ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER
        let vPolicy: GtkPolicyType = axes.contains(.vertical) ? GTK_POLICY_AUTOMATIC : GTK_POLICY_NEVER
        gtk_scrolled_window_set_policy(scrolledOp, hPolicy, vPolicy)
'''
scroll_policy = '''        let visibleScrollPolicy: GtkPolicyType = showsIndicators ? GTK_POLICY_AUTOMATIC : GTK_POLICY_EXTERNAL
        let hPolicy: GtkPolicyType = axes.contains(.horizontal) ? visibleScrollPolicy : GTK_POLICY_NEVER
        let vPolicy: GtkPolicyType = axes.contains(.vertical) ? visibleScrollPolicy : GTK_POLICY_NEVER
        gtk_scrolled_window_set_policy(scrolledOp, hPolicy, vPolicy)
'''
if legacy_scroll_policy in text:
    text = text.replace(legacy_scroll_policy, scroll_policy, 1)
elif "let visibleScrollPolicy: GtkPolicyType = showsIndicators ? GTK_POLICY_AUTOMATIC : GTK_POLICY_EXTERNAL" not in text:
    raise SystemExit("SwiftOpenUI ScrollView indicator policy shape was not recognized")

legacy_lazy_stack_policy = '''    gtk_widget_add_css_class(listView, "gtk-swift-lazy-transparent")

    // Wrap in scrolled window
    let scrolled = gtk_scrolled_window_new()!
    gtk_scrolled_window_set_policy(OpaquePointer(scrolled),
        GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
    gtk_scrolled_window_set_child(OpaquePointer(scrolled), listView)
'''
lazy_stack_policy = '''    gtk_widget_add_css_class(listView, "gtk-swift-lazy-transparent")

    // Wrap in scrolled window
    let scrolled = gtk_scrolled_window_new()!
    gtk_scrolled_window_set_policy(
        OpaquePointer(scrolled),
        GTK_POLICY_EXTERNAL,
        GTK_POLICY_EXTERNAL
    )
    gtk_scrolled_window_set_has_frame(OpaquePointer(scrolled), 0)
    gtk_scrolled_window_set_child(OpaquePointer(scrolled), listView)
'''
if legacy_lazy_stack_policy in text:
    text = text.replace(legacy_lazy_stack_policy, lazy_stack_policy, 1)
elif "gtk_scrolled_window_set_has_frame(OpaquePointer(scrolled), 0)" not in text:
    raise SystemExit("SwiftOpenUI LazyStack scroll policy shape was not recognized")

state_identity = '''// MARK: - Stateful view identity

private var gtkStateCache: [String: [AnyStateStorage]] = [:]
private var gtkStateTypeCounters: [String: [String: Int]] = [:]

private var gtkForcedStateIdentityNamespace: String?

private func gtkStateIdentityNamespace() -> String {
    gtkForcedStateIdentityNamespace
        ?? GTKViewHost.getCurrentRebuilding()?.stateIdentityNamespace
        ?? "root"
}

public func gtkBeginStateIdentityPass() {
    gtkStateTypeCounters[gtkStateIdentityNamespace()] = [:]
    gtkMountTypeCounters[gtkStateIdentityNamespace()] = [:]
}

// MARK: - Mount identity for external renderable leaves

private var gtkMountTypeCounters: [String: [String: Int]] = [:]

public func gtkMountIdentity(for type: Any.Type) -> String {
    let namespace = gtkStateIdentityNamespace()
    let typeName = String(reflecting: type)
    var counters = gtkMountTypeCounters[namespace] ?? [:]
    let index = counters[typeName] ?? 0
    counters[typeName] = index + 1
    gtkMountTypeCounters[namespace] = counters
    return "\\(namespace)|mount|\\(typeName)#\\(index)"
}

/// Claims a stable child namespace slot in the current namespace. Deferred
/// render paths (GeometryReader map/idle/tick callbacks) run with no
/// rebuilding host; without a captured namespace their whole subtree keys
/// on the shared never-reset "root" pool, so every @State below them is
/// reborn on each deferred render (observed: the sidebar's sheet flags
/// resetting ~1s after presentation).
func gtkClaimStateIdentityNamespace(_ kind: String) -> String {
    let namespace = gtkStateIdentityNamespace()
    let marker = "<\\(kind)>"
    var counters = gtkStateTypeCounters[namespace] ?? [:]
    let index = counters[marker] ?? 0
    counters[marker] = index + 1
    gtkStateTypeCounters[namespace] = counters
    return "\\(namespace)::\\(marker)#\\(index)"
}

private func gtkForEachStateIdentityComponent<ID: Hashable>(for id: ID) -> String {
    "ForEach[\\(String(reflecting: AnyHashable(id)))]"
}

private func gtkWithStateIdentityNamespaceComponent<T>(_ component: String, _ body: () -> T) -> T {
    let previous = gtkForcedStateIdentityNamespace
    let namespace = "\\(gtkStateIdentityNamespace())::\\(component)"
    gtkForcedStateIdentityNamespace = namespace
    gtkStateTypeCounters[namespace] = [:]
    gtkMountTypeCounters[namespace] = [:]
    defer { gtkForcedStateIdentityNamespace = previous }
    return body()
}

/// Runs a deferred render under a captured namespace, starting a fresh
/// counter pass for it so keys inside the subtree are stable per render.
func gtkWithForcedStateIdentityNamespace<T>(_ namespace: String, _ body: () -> T) -> T {
    let previous = gtkForcedStateIdentityNamespace
    gtkForcedStateIdentityNamespace = namespace
    gtkStateTypeCounters[namespace] = [:]
    gtkMountTypeCounters[namespace] = [:]
    defer { gtkForcedStateIdentityNamespace = previous }
    return body()
}

private func gtkStateCacheKey<V>(for view: V) -> String {
    let namespace = gtkStateIdentityNamespace()
    let typeName = String(reflecting: type(of: view))
    var counters = gtkStateTypeCounters[namespace] ?? [:]
    let index = counters[typeName] ?? 0
    counters[typeName] = index + 1
    gtkStateTypeCounters[namespace] = counters
    return "\\(namespace)::\\(typeName)#\\(index)"
}

private func gtkRestoreAndInstallState<V>(_ view: V, host: GTKViewHost) {
    // EVERY composite view consumes a key slot and namespaces its children,
    // including stateless wrappers. If stateless hosts kept the shared parent
    // namespace, all stateful views under different wrappers would draw from
    // one counter pool, and conditional content (an open sheet, a banner)
    // would shift sibling indices between passes — alternating cache
    // lineages and silently dropping interim @State writes.
    let key = gtkStateCacheKey(for: view)
    host.stateIdentityNamespace = key
    let mirror = Mirror(reflecting: view)
    let providers = mirror.children.compactMap { $0.value as? AnyStateStorageProvider }
    guard !providers.isEmpty else { return }

    if let cached = gtkStateCache[key], cached.count == providers.count {
        for (provider, old) in zip(providers, cached) {
            provider.anyStorage.restoreValue(from: old)
            old.forwardMutations(to: provider.anyStorage)
        }
    }

    for provider in providers {
        provider.anyStorage.host = host
    }
    gtkStateCache[key] = providers.map { $0.anyStorage }
}

private struct GTKStateNamespaceView<Content: View>: View {
    typealias Body = Never

    let component: String
    let content: Content

    var body: Never { fatalError("GTKStateNamespaceView is a primitive view") }
}

extension GTKStateNamespaceView: GTKRenderable, GTKDescribable {
    func gtkCreateWidget() -> OpaquePointer {
        gtkWithStateIdentityNamespaceComponent(component) {
            gtkRenderView(content)
        }
    }

    func gtkDescribeNode() -> GTK4DescriptorNode {
        gtkWithStateIdentityNamespaceComponent(component) {
            GTK4DescriptorNode(
                kind: .composite,
                typeName: "GTKStateNamespaceView<\\(component)>",
                children: [gtkDescribeView(content)]
            )
        }
    }
}

'''
marker = "// MARK: - Rendering dispatch\n"
if marker not in text:
    raise SystemExit("SwiftOpenUI GTK rendering dispatch marker was not recognized")
if "private var gtkStateTypeCounters: [String: Int]" in text:
    start = text.index("// MARK: - Stateful view identity")
    end = text.index(marker, start)
    text = text[:start] + state_identity + text[end:]
elif "gtkStateCacheKey" not in text:
    text = text.replace(marker, state_identity + marker, 1)

if "gtkEnvironmentObjectTypeCounters" not in text:
    old_counter = "private var gtkStateTypeCounters: [String: [String: Int]] = [:]\n"
    new_counter = old_counter + "private var gtkEnvironmentObjectTypeCounters: [String: [String: Int]] = [:]\n"
    if old_counter not in text:
        raise SystemExit("SwiftOpenUI GTK environment scope counter insertion point was not recognized")
    text = text.replace(old_counter, new_counter, 1)

    reset_marker = "    gtkMountTypeCounters[namespace] = [:]\n"
    begin_reset_marker = "    gtkMountTypeCounters[gtkStateIdentityNamespace()] = [:]\n"
    if text.count(reset_marker) < 2 or begin_reset_marker not in text:
        raise SystemExit("SwiftOpenUI GTK environment scope reset shape was not recognized")
    text = text.replace(
        begin_reset_marker,
        begin_reset_marker + "    gtkEnvironmentObjectTypeCounters[gtkStateIdentityNamespace()] = [:]\n",
        1,
    )
    text = text.replace(
        reset_marker,
        reset_marker + "    gtkEnvironmentObjectTypeCounters[namespace] = [:]\n",
    )

    mount_identity = r'''public func gtkMountIdentity(for type: Any.Type) -> String {
    let namespace = gtkStateIdentityNamespace()
    let typeName = String(reflecting: type)
    var counters = gtkMountTypeCounters[namespace] ?? [:]
    let index = counters[typeName] ?? 0
    counters[typeName] = index + 1
    gtkMountTypeCounters[namespace] = counters
    return "\(namespace)|mount|\(typeName)#\(index)"
}
'''
    environment_scope = mount_identity + r'''
private func gtkEnvironmentObjectScope(for type: Any.Type) -> String {
    let namespace = gtkStateIdentityNamespace()
    let typeName = String(reflecting: type)
    var counters = gtkEnvironmentObjectTypeCounters[namespace] ?? [:]
    let index = counters[typeName] ?? 0
    counters[typeName] = index + 1
    gtkEnvironmentObjectTypeCounters[namespace] = counters
    return "\(namespace)|environment|\(typeName)#\(index)"
}
'''
    if mount_identity not in text:
        raise SystemExit("SwiftOpenUI GTK environment scope helper insertion point was not recognized")
    text = text.replace(mount_identity, environment_scope, 1)

    object_injection = "        env.setObject(object)\n"
    scoped_object_injection = (
        "        env.setObject(object, scope: "
        "gtkEnvironmentObjectScope(for: ObjectType.self))\n"
    )
    if text.count(object_injection) < 4:
        raise SystemExit("SwiftOpenUI GTK scoped environment modifier shape was not recognized")
    text = text.replace(object_injection, scoped_object_injection)

if 'let capturedEnvironment = getCurrentEnvironment()\n        let stateNamespace = gtkClaimStateIdentityNamespace("GeometryReader")' not in text:
    old_geometry_environment = '''        let stateNamespace = gtkClaimStateIdentityNamespace("GeometryReader")
        self.renderContent = { proxy in
            gtkWithForcedStateIdentityNamespace(stateNamespace) {
                gtkRenderView(content(proxy))
            }
        }
'''
    new_geometry_environment = '''        let capturedEnvironment = getCurrentEnvironment()
        let stateNamespace = gtkClaimStateIdentityNamespace("GeometryReader")
        self.renderContent = { proxy in
            let previousEnvironment = getCurrentEnvironment()
            var environment = capturedEnvironment
            environment.refreshInjectedObjectsFromRegistry()
            setCurrentEnvironment(environment)
            defer { setCurrentEnvironment(previousEnvironment) }
            return gtkWithForcedStateIdentityNamespace(stateNamespace) {
                gtkRenderView(content(proxy))
            }
        }
'''
    if old_geometry_environment not in text:
        raise SystemExit("SwiftOpenUI GTK GeometryReader deferred environment shape was not recognized")
    text = text.replace(old_geometry_environment, new_geometry_environment, 1)

if "private func gtkDebugLog(_ message: String)" not in text:
    debug_helper = '''private func gtkDebugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else {
        return
    }
    if let data = ("[QuillUI GTK] " + message + "\\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

'''
    text = text.replace(marker, debug_helper + marker, 1)

if "gtkRestoreAndInstallState(view, host: host)" not in text:
    old_install_state = "    installState(view, host: host)\n"
    if old_install_state not in text:
        raise SystemExit("SwiftOpenUI stateful view install shape was not recognized")
    text = text.replace(old_install_state, "    gtkRestoreAndInstallState(view, host: host)\n", 1)

if 'gtkClaimStateIdentityNamespace("GeometryReader")' not in text:
    old_geometry_init = '''    init<Content: View>(content: @escaping (GeometryProxy) -> Content,
                        box: UnsafeMutablePointer<GtkWidget>) {
        self.box = box
        self.renderContent = { proxy in
            gtkRenderView(content(proxy))
        }
    }
'''
    new_geometry_init = '''    init<Content: View>(content: @escaping (GeometryProxy) -> Content,
                        box: UnsafeMutablePointer<GtkWidget>) {
        self.box = box
        // Deferred geometry renders run from GTK map/idle/tick callbacks
        // with no rebuilding host. Capture a stable state-identity namespace
        // now (inside the live render pass) so @State under this reader
        // keeps one cache lineage across geometry re-renders.
        let stateNamespace = gtkClaimStateIdentityNamespace("GeometryReader")
        self.renderContent = { proxy in
            gtkWithForcedStateIdentityNamespace(stateNamespace) {
                gtkRenderView(content(proxy))
            }
        }
    }
'''
    if old_geometry_init not in text:
        raise SystemExit("SwiftOpenUI GeometryReader context init shape was not recognized")
    text = text.replace(old_geometry_init, new_geometry_init, 1)

if 'gtkDebugLog("state install type=' not in text:
    text = text.replace(
        """    guard !providers.isEmpty else { return }

    if let cached = gtkStateCache[key], cached.count == providers.count {
""",
        """    guard !providers.isEmpty else { return }

    gtkDebugLog("state install type=\\(String(reflecting: type(of: view))) key=\\(key) providers=\\(providers.count) cached=\\(gtkStateCache[key] != nil)")
    if let cached = gtkStateCache[key], cached.count == providers.count {
""",
        1,
    )

if "buttonWantsHExpand" not in text:
    old_button_decl = '''    public func gtkCreateWidget() -> OpaquePointer {
        let button: UnsafeMutablePointer<GtkWidget>

        if let textLabel = label as? Text {
'''
    new_button_decl = '''    public func gtkCreateWidget() -> OpaquePointer {
        let button: UnsafeMutablePointer<GtkWidget>
        var buttonWantsHExpand = false
        var buttonWantsVExpand = false

        if let textLabel = label as? Text {
'''
    old_button_child = '''            let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
            gtk_button_set_child(btnPtr, childWidget)
            // Remove GTK default button border/padding so custom-styled
'''
    new_button_child = '''            let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
            gtk_button_set_child(btnPtr, childWidget)
            gtkDisableButtonChildTargeting(childWidget)
            if gtk_widget_get_hexpand(childWidget) != 0 {
                buttonWantsHExpand = true
                gtk_widget_set_halign(childWidget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(childWidget) != 0 {
                buttonWantsVExpand = true
                gtk_widget_set_valign(childWidget, GTK_ALIGN_FILL)
            }
            // Remove GTK default button border/padding so custom-styled
'''
    old_button_expand = '''        gtk_widget_set_hexpand(button, 0)
        gtk_widget_set_halign(button, GTK_ALIGN_START)
'''
    new_button_expand = '''        gtk_widget_set_hexpand(button, buttonWantsHExpand ? 1 : 0)
        gtk_widget_set_vexpand(button, buttonWantsVExpand ? 1 : 0)
        gtk_widget_set_halign(button, buttonWantsHExpand ? GTK_ALIGN_FILL : GTK_ALIGN_START)
        gtk_widget_set_valign(button, buttonWantsVExpand ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)
'''
    if old_button_decl not in text or old_button_child not in text or old_button_expand not in text:
        raise SystemExit("SwiftOpenUI Button expansion shape was not recognized")
    text = text.replace(old_button_decl, new_button_decl, 1)
    text = text.replace(old_button_child, new_button_child, 1)
    text = text.replace(old_button_expand, new_button_expand, 1)

if "private func gtkDisableButtonChildTargeting" not in text:
    button_targeting_helper = '''private func gtkDisableButtonChildTargeting(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    gtk_widget_set_can_target(widget, 0)
    var child = gtk_widget_get_first_child(widget)
    while let c = child {
        gtkDisableButtonChildTargeting(c)
        child = gtk_widget_get_next_sibling(c)
    }
}

'''
    button_marker = "extension Button: GTKRenderable"
    if button_marker not in text:
        raise SystemExit("SwiftOpenUI Button renderer marker was not recognized")
    text = text.replace(button_marker, button_targeting_helper + button_marker, 1)

if "gtkDisableButtonChildTargeting(childWidget)" not in text:
    button_child_set = "            gtk_button_set_child(btnPtr, childWidget)\n"
    if button_child_set not in text:
        raise SystemExit("SwiftOpenUI Button child install shape was not recognized")
    text = text.replace(
        button_child_set,
        button_child_set + "            gtkDisableButtonChildTargeting(childWidget)\n",
        1,
    )

if "private final class GTKButtonActionBox" not in text:
    button_action_helper = '''private final class GTKButtonActionBox {
    let action: () -> Void
    var lastActivationTime: TimeInterval = 0

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

private final class GTKButtonIdleActionContext {
    let box: GTKButtonActionBox
    let source: String

    init(box: GTKButtonActionBox, source: String) {
        self.box = box
        self.source = source
    }
}

/// Debug-only: tags a button activation source with the widget's root-frame
/// so QUILLUI_GTK_DEBUG_ACTIONS logs identify WHICH button fired.
private func gtkButtonDebugSource(_ source: String, widget: UnsafeMutablePointer<GtkWidget>) -> String {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return source }
    guard gtk_swift_is_widget(widget) != 0, let root = gtk_swift_widget_root_widget(widget) else { return source }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, 0, 0, &rootX, &rootY) != 0 else { return source }
    return "\\(source)@\\(Int(rootX)),\\(Int(rootY)) \\(gtk_widget_get_width(widget))x\\(gtk_widget_get_height(widget))"
}

private final class GTKButtonRootEventContext {
    let widget: UnsafeMutablePointer<GtkWidget>
    let box: GTKButtonActionBox
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?
    var gestureController: gpointer?

    init(widget: UnsafeMutablePointer<GtkWidget>, box: GTKButtonActionBox) {
        self.widget = widget
        self.box = box
    }

    func removeController() {
        guard let root else { return }
        if let controller {
            gtk_swift_remove_event_controller(root, controller)
        }
        if let gestureController {
            gtk_swift_remove_event_controller(root, gestureController)
        }
        self.root = nil
        self.controller = nil
        self.gestureController = nil
    }
}

private func gtkScheduleButtonAction(_ box: GTKButtonActionBox, source: String) {
    let now = Date().timeIntervalSinceReferenceDate
    if now - box.lastActivationTime < 0.08 {
        gtkDebugLog("button duplicate \\(source)")
        return
    }
    box.lastActivationTime = now
    gtkDebugLog("button \\(source)")
    let context = Unmanaged.passRetained(GTKButtonIdleActionContext(box: box, source: source)).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKButtonIdleActionContext>.fromOpaque(userData).takeRetainedValue()
        gtkDebugLog("button action \\(context.source)")
        context.box.action()
        return 0
    }, context)
}

private func gtkInstallButtonRootEventFallback(_ context: GTKButtonRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.widget) else { return }

    let controller = gtk_swift_legacy_capture_controller()!
    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, 1)
    context.root = root
    context.controller = controller
    context.gestureController = gpointer(gesture)
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return 0 }
            var x: Double = 0
            var y: Double = 0
            guard gtk_swift_event_get_position(event, &x, &y) != 0 else { return 0 }
            return gtkDispatchButtonRootPress(context, root: root, x: x, y: y, source: "root-legacy")
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, x: gdouble, y: gdouble, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return }
            _ = gtkDispatchButtonRootPress(context, root: root, x: x, y: y, source: "root-gesture")
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(root, gesture)
}

private func gtkDispatchButtonRootPress(
    _ context: GTKButtonRootEventContext,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) -> gboolean {
    if gtkActiveMenuOverlayState != nil {
        return gtkHandleActiveMenuOverlayClick(x: x, y: y)
    }
    if gtkRootSheetLayerOccludesRootPoint(
        root: root,
        x: x,
        y: y,
        excludingDescendant: context.widget
    ) {
        gtkDebugLog("button root skipped root sheet root@\\(Int(x)),\\(Int(y))")
        return 0
    }
    let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
    let isVisualHit = gtkWidgetVisuallyContainsRootPoint(context.widget, root: root, x: x, y: y)
    gtkDebugButtonRootHitTest(
        widget: context.widget,
        root: root,
        x: x,
        y: y,
        isTopmost: isTopmost,
        isVisualHit: isVisualHit
    )
    guard isTopmost || isVisualHit else { return 0 }
    let resolvedSource = isTopmost ? source : "\\(source)-visual"
    gtkScheduleButtonAction(
        context.box,
        source: gtkButtonDebugSource("\\(resolvedSource)@\\(Int(x)),\\(Int(y))", widget: context.widget)
    )
    return 0
}

'''
    button_marker = "extension Button: GTKRenderable"
    if button_marker not in text:
        raise SystemExit("SwiftOpenUI Button renderer marker was not recognized")
    text = text.replace(button_marker, button_action_helper + button_marker, 1)

if "private final class GTKButtonRootEventContext" not in text:
    root_context_helper = '''private final class GTKButtonRootEventContext {
    let widget: UnsafeMutablePointer<GtkWidget>
    let box: GTKButtonActionBox
    var root: UnsafeMutablePointer<GtkWidget>?
    var controller: gpointer?
    var gestureController: gpointer?

    init(widget: UnsafeMutablePointer<GtkWidget>, box: GTKButtonActionBox) {
        self.widget = widget
        self.box = box
    }

    func removeController() {
        guard let root else { return }
        if let controller {
            gtk_swift_remove_event_controller(root, controller)
        }
        if let gestureController {
            gtk_swift_remove_event_controller(root, gestureController)
        }
        self.root = nil
        self.controller = nil
        self.gestureController = nil
    }
}

'''
    schedule_marker = "private func gtkScheduleButtonAction(_ box: GTKButtonActionBox, source: String) {\n"
    if schedule_marker not in text:
        raise SystemExit("SwiftOpenUI Button scheduler marker was not recognized")
    text = text.replace(schedule_marker, root_context_helper + schedule_marker, 1)

# Committed copies of the root-event fallback predate the debug-source tagger;
# upgrade their call in place (no-op once applied).
text = text.replace(
    'gtkScheduleButtonAction(context.box, source: "root-legacy")',
    'gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("root-legacy@\\(Int(x)),\\(Int(y))", widget: context.widget))',
)

# Standalone guard: trees where GTKButtonActionBox is already committed skip the
# helper block above, but the debug-source tagger must still be present for the
# instrumented click handlers.
if "private func gtkButtonDebugSource" not in text:
    button_debug_source_helper = '''/// Debug-only: tags a button activation source with the widget's root-frame
/// so QUILLUI_GTK_DEBUG_ACTIONS logs identify WHICH button fired.
private func gtkButtonDebugSource(_ source: String, widget: UnsafeMutablePointer<GtkWidget>) -> String {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return source }
    guard gtk_swift_is_widget(widget) != 0, let root = gtk_swift_widget_root_widget(widget) else { return source }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, 0, 0, &rootX, &rootY) != 0 else { return source }
    return "\\(source)@\\(Int(rootX)),\\(Int(rootY)) \\(gtk_widget_get_width(widget))x\\(gtk_widget_get_height(widget))"
}

'''
    debug_source_marker = "private func gtkScheduleButtonAction(_ box: GTKButtonActionBox, source: String) {\n"
    if debug_source_marker not in text:
        raise SystemExit("SwiftOpenUI Button debug-source marker was not recognized")
    text = text.replace(debug_source_marker, button_debug_source_helper + debug_source_marker, 1)

if "private func gtkWidgetVisuallyContainsRootPoint" not in text:
    visual_button_hit_helpers = '''private func gtkWidgetCumulativeOffset(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>
) -> (x: Double, y: Double) {
    var offsetX = 0.0
    var offsetY = 0.0
    var current: UnsafeMutablePointer<GtkWidget>? = widget
    var depth = 0
    while let node = current, depth < 64 {
        offsetX += getWidgetDouble(node, key: gtkSwiftOffsetXKey) ?? 0
        offsetY += getWidgetDouble(node, key: gtkSwiftOffsetYKey) ?? 0
        if node == root { break }
        current = gtk_widget_get_parent(node)
        depth += 1
    }
    return (offsetX, offsetY)
}

private func gtkWidgetVisuallyContainsRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    let width = Double(gtk_widget_get_width(widget))
    let height = Double(gtk_widget_get_height(widget))
    guard width > 0, height > 0 else { return false }

    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(widget, root, 0, 0, &rootX, &rootY) != 0 else {
        return false
    }

    let offset = gtkWidgetCumulativeOffset(widget, root: root)
    let localX = x - rootX - offset.x
    let localY = y - rootY - offset.y
    return localX >= 0 && localX < width && localY >= 0 && localY < height
}

private func gtkDebugButtonRootHitTest(
    widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    isTopmost: Bool,
    isVisualHit: Bool
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    guard let frame = gtkWidgetVisualFrameInRoot(widget, root: root) else { return }
    guard y >= frame.y - 24, y <= frame.y + frame.height + 24 else { return }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    gtkDebugLog(
        "button root-hit-test root@\\(Int(x)),\\(Int(y)) widget=\\(typeName) frame=\\(Int(frame.x)),\\(Int(frame.y)) \\(Int(frame.width))x\\(Int(frame.height)) topmost=\\(isTopmost) visual=\\(isVisualHit)"
    )
}

private func gtkWidgetTreeContainsVisualButtonAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> Bool {
    guard depth < 96, gtk_swift_is_widget(widget) != 0 else { return false }
    if gtk_swift_widget_is_button(widget) != 0,
       gtkWidgetVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
        return true
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if gtkWidgetTreeContainsVisualButtonAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            return true
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return false
}

func gtkTestWidgetVisuallyContainsRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    gtkWidgetVisuallyContainsRootPoint(widget, root: root, x: x, y: y)
}

func gtkTestWidgetTreeContainsVisualButtonAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> Bool {
    gtkWidgetTreeContainsVisualButtonAtRootPoint(widget, root: root, x: x, y: y)
}

'''
    visual_hit_marker = "private func gtkScheduleButtonAction(_ box: GTKButtonActionBox, source: String) {\n"
    if visual_hit_marker not in text:
        raise SystemExit("SwiftOpenUI Button visual hit-test insertion marker was not recognized")
    text = text.replace(visual_hit_marker, visual_button_hit_helpers + visual_hit_marker, 1)

if "private func gtkDebugButtonRootHitTest" not in text:
    debug_button_root_hit_helper = '''private func gtkDebugButtonRootHitTest(
    widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    isTopmost: Bool,
    isVisualHit: Bool
) {
    guard ProcessInfo.processInfo.environment["QUILLUI_GTK_DEBUG_ACTIONS"] == "1" else { return }
    guard let frame = gtkWidgetVisualFrameInRoot(widget, root: root) else { return }
    guard y >= frame.y - 24, y <= frame.y + frame.height + 24 else { return }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    gtkDebugLog(
        "button root-hit-test root@\\(Int(x)),\\(Int(y)) widget=\\(typeName) frame=\\(Int(frame.x)),\\(Int(frame.y)) \\(Int(frame.width))x\\(Int(frame.height)) topmost=\\(isTopmost) visual=\\(isVisualHit)"
    )
}

'''
    debug_button_root_marker = "private func gtkWidgetOrDescendantVisuallyContainsRootPoint(\n"
    if debug_button_root_marker not in text:
        debug_button_root_marker = "private func gtkWidgetTreeContainsVisualButtonAtRootPoint(\n"
    if debug_button_root_marker not in text:
        raise SystemExit("SwiftOpenUI Button root-hit-test debug insertion marker was not recognized")
    text = text.replace(debug_button_root_marker, debug_button_root_hit_helper + debug_button_root_marker, 1)

if "private func gtkInstallButtonRootEventFallback" not in text:
    root_install_helper = '''private func gtkInstallButtonRootEventFallback(_ context: GTKButtonRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.widget) else { return }

    let controller = gtk_swift_legacy_capture_controller()!
    let gesture = gtk_gesture_click_new()!
    gtk_swift_gesture_single_set_button(gesture, 1)
    context.root = root
    context.controller = controller
    context.gestureController = gpointer(gesture)
    let contextPointer = Unmanaged.passUnretained(context).toOpaque()
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return 0 }
            var x: Double = 0
            var y: Double = 0
            guard gtk_swift_event_get_position(event, &x, &y) != 0 else { return 0 }
            return gtkDispatchButtonRootPress(context, root: root, x: x, y: y, source: "root-legacy")
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, x: gdouble, y: gdouble, userData: gpointer?) in
            guard let userData else { return }
            let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
            guard let root = context.root else { return }
            _ = gtkDispatchButtonRootPress(context, root: root, x: x, y: y, source: "root-gesture")
        } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(root, gesture)
}

private func gtkDispatchButtonRootPress(
    _ context: GTKButtonRootEventContext,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    source: String
) -> gboolean {
    if gtkActiveMenuOverlayState != nil {
        return gtkHandleActiveMenuOverlayClick(x: x, y: y)
    }
    if gtkRootSheetLayerOccludesRootPoint(
        root: root,
        x: x,
        y: y,
        excludingDescendant: context.widget
    ) {
        gtkDebugLog("button root skipped root sheet root@\\(Int(x)),\\(Int(y))")
        return 0
    }
    let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
    let isVisualHit = gtkWidgetVisuallyContainsRootPoint(context.widget, root: root, x: x, y: y)
    gtkDebugButtonRootHitTest(
        widget: context.widget,
        root: root,
        x: x,
        y: y,
        isTopmost: isTopmost,
        isVisualHit: isVisualHit
    )
    guard isTopmost || isVisualHit else { return 0 }
    let resolvedSource = isTopmost ? source : "\\(source)-visual"
    gtkScheduleButtonAction(
        context.box,
        source: gtkButtonDebugSource("\\(resolvedSource)@\\(Int(x)),\\(Int(y))", widget: context.widget)
    )
    return 0
}

'''
    button_marker = "extension Button: GTKRenderable"
    if button_marker not in text:
        raise SystemExit("SwiftOpenUI Button renderer marker was not recognized")
    text = text.replace(button_marker, root_install_helper + button_marker, 1)

if "private let gtkButtonGlobalDispatcherDataKey" not in text:
    global_button_dispatcher_helper = '''private let gtkButtonGlobalDispatcherDataKey = "gtk-swift-button-global-dispatcher"

private final class GTKButtonGlobalRootDispatcher {
    let root: UnsafeMutablePointer<GtkWidget>
    var controller: gpointer?

    init(root: UnsafeMutablePointer<GtkWidget>) {
        self.root = root
    }
}

private func gtkButtonActionBox(from widget: UnsafeMutablePointer<GtkWidget>) -> GTKButtonActionBox? {
    guard gtk_swift_widget_is_button(widget) != 0 else { return nil }
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let actionData = g_object_get_data(object, gtkSwiftButtonActionBoxDataKey) else {
        return nil
    }
    return Unmanaged<GTKButtonActionBox>.fromOpaque(actionData).takeUnretainedValue()
}

private func gtkPickedButtonActionWidgetAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> UnsafeMutablePointer<GtkWidget>? {
    var current = gtk_swift_root_point_pick_widget(root, x, y)
    var depth = 0
    while let widget = current, depth < 32 {
        if gtkButtonActionBox(from: widget) != nil {
            return widget
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
    return nil
}

private typealias GTKVisualButtonActionCandidate = (
    widget: UnsafeMutablePointer<GtkWidget>,
    depth: Int,
    area: Double
)

private func gtkPreferredVisualButtonActionCandidate(
    _ current: GTKVisualButtonActionCandidate?,
    _ proposed: GTKVisualButtonActionCandidate
) -> GTKVisualButtonActionCandidate {
    guard let current else { return proposed }
    if proposed.depth > current.depth { return proposed }
    if proposed.depth == current.depth && proposed.area < current.area { return proposed }
    return current
}

private func gtkVisualButtonActionCandidateAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> GTKVisualButtonActionCandidate? {
    guard depth < 160 else { return nil }
    guard gtk_widget_get_visible(widget) != 0,
          gtk_widget_get_sensitive(widget) != 0,
          gtk_widget_get_opacity(widget) > 0.001 else { return nil }
    var best: GTKVisualButtonActionCandidate?

    if gtkButtonActionBox(from: widget) != nil {
        let frame = gtkWidgetVisualFrameInRoot(widget, root: root)
        let isHit: Bool
        if let frame {
            let localX = x - frame.x
            let localY = y - frame.y
            isHit = localX >= 0 && localX < frame.width && localY >= 0 && localY < frame.height
        } else {
            isHit = false
        }
        gtkDebugVisualButtonCandidate(widget, root: root, x: x, y: y, isHit: isHit, frame: frame)
        if isHit || gtkWidgetOrDescendantVisuallyContainsRootPoint(widget, root: root, x: x, y: y) {
            let area = frame.map { max(1, $0.width * $0.height) } ?? Double.greatestFiniteMagnitude
            best = gtkPreferredVisualButtonActionCandidate(best, (widget, depth, area))
        }
    }

    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let match = gtkVisualButtonActionCandidateAtRootPoint(
            current,
            root: root,
            x: x,
            y: y,
            depth: depth + 1
        ) {
            best = gtkPreferredVisualButtonActionCandidate(best, match)
        }
        child = gtk_widget_get_next_sibling(current)
    }
    return best
}

private func gtkVisualButtonActionWidgetAtRootPoint(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    depth: Int = 0
) -> UnsafeMutablePointer<GtkWidget>? {
    gtkVisualButtonActionCandidateAtRootPoint(
        widget,
        root: root,
        x: x,
        y: y,
        depth: depth
    )?.widget
}

private func gtkPreferredButtonActionAtRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double
) -> (widget: UnsafeMutablePointer<GtkWidget>, box: GTKButtonActionBox)? {
    if let widget = gtkPickedButtonActionWidgetAtRootPoint(root: root, x: x, y: y),
       let box = gtkButtonActionBox(from: widget) {
        return (widget, box)
    }
    if let widget = gtkVisualButtonActionWidgetAtRootPoint(root, root: root, x: x, y: y),
       let box = gtkButtonActionBox(from: widget) {
        return (widget, box)
    }
    return nil
}

private func gtkInstallGlobalButtonRootDispatcher(for widget: UnsafeMutablePointer<GtkWidget>) {
    guard let root = gtk_swift_widget_root_widget(widget) else { return }
    let rootObject = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GObject.self)
    guard g_object_get_data(rootObject, gtkButtonGlobalDispatcherDataKey) == nil else { return }

    let dispatcher = GTKButtonGlobalRootDispatcher(root: root)
    let controller = gtk_swift_legacy_capture_controller()!
    dispatcher.controller = controller

    let dispatcherPointer = Unmanaged.passRetained(dispatcher).toOpaque()
    g_object_set_data_full(
        rootObject,
        gtkButtonGlobalDispatcherDataKey,
        dispatcherPointer,
        { userData in
            guard let userData else { return }
            Unmanaged<GTKButtonGlobalRootDispatcher>.fromOpaque(userData).release()
        }
    )

    gtkDebugLog("button global root dispatcher installed")
    g_signal_connect_data(
        controller,
        "event",
        unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
            guard let event, let userData else { return 0 }
            guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
            let dispatcher = Unmanaged<GTKButtonGlobalRootDispatcher>
                .fromOpaque(userData)
                .takeUnretainedValue()
            let root = dispatcher.root
            var rootX: Double = 0
            var rootY: Double = 0
            guard gtk_swift_event_get_position(event, &rootX, &rootY) != 0 else { return 0 }
            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            guard let target = gtkPreferredButtonActionAtRootPoint(root: root, x: rootX, y: rootY) else {
                gtkDebugPickedWidgetChain(
                    root: root,
                    x: rootX,
                    y: rootY,
                    source: "button global dispatch"
                )
                gtkDebugLog("button global dispatch miss root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }
            if gtkRootSheetLayerOccludesRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                excludingDescendant: target.widget
            ) {
                gtkDebugLog("button global dispatch skipped root sheet root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }
            gtkDebugLog(
                "button global root-hit root@\\(Int(rootX)),\\(Int(rootY)) "
                + gtkDebugVisualFrameDescription(target.widget, root: root)
            )
            gtkScheduleButtonAction(
                target.box,
                source: gtkButtonDebugSource(
                    "global-root@\\(Int(rootX)),\\(Int(rootY))",
                    widget: target.widget
                )
            )
            return 0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        dispatcherPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

'''
    root_fallback_marker = "private func gtkInstallButtonRootEventFallback(_ context: GTKButtonRootEventContext) {\n"
    if root_fallback_marker not in text:
        raise SystemExit("SwiftOpenUI global button dispatcher insertion point was not recognized")
    text = text.replace(root_fallback_marker, global_button_dispatcher_helper + root_fallback_marker, 1)

old_button_global_root_sheet_guard = '''            guard let target = gtkPreferredButtonActionAtRootPoint(root: root, x: rootX, y: rootY) else {
                gtkDebugPickedWidgetChain(
                    root: root,
                    x: rootX,
                    y: rootY,
                    source: "button global dispatch"
                )
                gtkDebugLog("button global dispatch miss root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }
            gtkDebugLog(
                "button global root-hit root@\\(Int(rootX)),\\(Int(rootY)) "
'''
new_button_global_root_sheet_guard = '''            guard let target = gtkPreferredButtonActionAtRootPoint(root: root, x: rootX, y: rootY) else {
                gtkDebugPickedWidgetChain(
                    root: root,
                    x: rootX,
                    y: rootY,
                    source: "button global dispatch"
                )
                gtkDebugLog("button global dispatch miss root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }
            if gtkRootSheetLayerOccludesRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                excludingDescendant: target.widget
            ) {
                gtkDebugLog("button global dispatch skipped root sheet root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }
            gtkDebugLog(
                "button global root-hit root@\\(Int(rootX)),\\(Int(rootY)) "
'''
if old_button_global_root_sheet_guard in text:
    text = text.replace(old_button_global_root_sheet_guard, new_button_global_root_sheet_guard, 1)
elif (
    "button global dispatch skipped root sheet root@" not in text
    and "gtkInstallGlobalButtonRootDispatcher" in text
):
    raise SystemExit("SwiftOpenUI Button global root sheet guard shape was not recognized")

old_button_root_guard = '''            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
            guard isTopmost else { return 0 }
            gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("root-legacy@\\(Int(x)),\\(Int(y))", widget: context.widget))
'''
new_button_root_guard = '''            if gtkRootSheetLayerOccludesRootPoint(
                root: root,
                x: x,
                y: y,
                excludingDescendant: context.widget
            ) {
                gtkDebugLog("button root skipped root sheet root@\\(Int(x)),\\(Int(y))")
                return 0
            }
            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
            let isVisualHit = gtkWidgetVisuallyContainsRootPoint(context.widget, root: root, x: x, y: y)
            guard isTopmost || isVisualHit else { return 0 }
            let source = isTopmost ? "root-legacy" : "root-visual"
            gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("\\(source)@\\(Int(x)),\\(Int(y))", widget: context.widget))
'''
if old_button_root_guard in text:
    text = text.replace(old_button_root_guard, new_button_root_guard, 1)
elif "let isVisualHit = gtkWidgetVisuallyContainsRootPoint(context.widget, root: root, x: x, y: y)" not in text:
    raise SystemExit("SwiftOpenUI Button root visual hit-test guard shape was not recognized")

old_button_root_sheet_guard = '''    if gtkActiveMenuOverlayState != nil {
        return gtkHandleActiveMenuOverlayClick(x: x, y: y)
    }
    let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
'''
new_button_root_sheet_guard = '''    if gtkActiveMenuOverlayState != nil {
        return gtkHandleActiveMenuOverlayClick(x: x, y: y)
    }
    if gtkRootSheetLayerOccludesRootPoint(
        root: root,
        x: x,
        y: y,
        excludingDescendant: context.widget
    ) {
        gtkDebugLog("button root skipped root sheet root@\\(Int(x)),\\(Int(y))")
        return 0
    }
    let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0
'''
if old_button_root_sheet_guard in text:
    text = text.replace(old_button_root_sheet_guard, new_button_root_sheet_guard, 1)
elif (
    "button root skipped root sheet root@" not in text
    and "gtkDispatchButtonRootPress" in text
):
    raise SystemExit("SwiftOpenUI Button root sheet guard shape was not recognized")

old_list_row_root_button_guard = '''            guard gtk_swift_root_point_picks_button(root, x, y) == 0 else {
                gtkDebugLog("list row tap skipped button root@\\(Int(x)),\\(Int(y)) \\(context.box.source)")
                return 0
            }
            gtkScheduleListRowTapAction(context.box, source: "root@\\(Int(x)),\\(Int(y))")
'''
new_list_row_root_button_guard = '''            guard gtk_swift_root_point_picks_button(root, x, y) == 0 else {
                gtkDebugLog("list row tap skipped button root@\\(Int(x)),\\(Int(y)) \\(context.box.source)")
                return 0
            }
            guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(context.row, root: root, x: x, y: y) else {
                gtkDebugLog("list row tap skipped visual button root@\\(Int(x)),\\(Int(y)) \\(context.box.source)")
                return 0
            }
            gtkScheduleListRowTapAction(context.box, source: "root@\\(Int(x)),\\(Int(y))")
'''
if old_list_row_root_button_guard in text:
    text = text.replace(old_list_row_root_button_guard, new_list_row_root_button_guard, 1)
elif (
    "list row tap skipped visual button \\(source)@" not in text
    and "gtkInstallListRowRootEventFallback" in text
):
    raise SystemExit("SwiftOpenUI List row root visual button guard shape was not recognized")

old_list_row_global_root_sheet_guard = '''            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "list-row-root-dispatch@\\(Int(rootX)),\\(Int(rootY))"
            ) {
'''
new_list_row_global_root_sheet_guard = '''            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            if gtkRootSheetLayerOccludesRootPoint(root: root, x: rootX, y: rootY) {
                gtkDebugLog("list row global dispatch skipped root sheet root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }
            if gtkFocusSearchEntryAtRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                source: "list-row-root-dispatch@\\(Int(rootX)),\\(Int(rootY))"
            ) {
'''
if old_list_row_global_root_sheet_guard in text:
    text = text.replace(old_list_row_global_root_sheet_guard, new_list_row_global_root_sheet_guard, 1)
elif (
    "list row global dispatch skipped root sheet root@" not in text
    and "GTKListRowGlobalRootDispatcher" in text
):
    raise SystemExit("SwiftOpenUI List row global root sheet guard shape was not recognized")

old_listbox_root_sheet_guard = '''            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }

            let visibleContainer = gtk_widget_get_parent(context.listBox) ?? context.listBox
'''
new_listbox_root_sheet_guard = '''            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: rootX, y: rootY)
            }
            if gtkRootSheetLayerOccludesRootPoint(
                root: root,
                x: rootX,
                y: rootY,
                excludingDescendant: context.listBox
            ) {
                gtkDebugLog("listbox-root skipped root sheet root@\\(Int(rootX)),\\(Int(rootY))")
                return 0
            }

            let visibleContainer = gtk_widget_get_parent(context.listBox) ?? context.listBox
'''
if old_listbox_root_sheet_guard in text:
    text = text.replace(old_listbox_root_sheet_guard, new_listbox_root_sheet_guard, 1)
elif (
    "listbox-root skipped root sheet root@" not in text
    and "gtkInstallListBoxRootEventFallback" in text
):
    raise SystemExit("SwiftOpenUI List box root sheet guard shape was not recognized")

old_list_row_root_sheet_guard = '''            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: x, y: y)
            }
            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.row, x, y) != 0
'''
new_list_row_root_sheet_guard = '''            if gtkActiveMenuOverlayState != nil {
                return gtkHandleActiveMenuOverlayClick(x: x, y: y)
            }
            if gtkRootSheetLayerOccludesRootPoint(
                root: root,
                x: x,
                y: y,
                excludingDescendant: context.row
            ) {
                gtkDebugLog("list row tap skipped root sheet root@\\(Int(x)),\\(Int(y)) \\(context.box.source)")
                return 0
            }
            let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.row, x, y) != 0
'''
if old_list_row_root_sheet_guard in text:
    text = text.replace(old_list_row_root_sheet_guard, new_list_row_root_sheet_guard, 1)
elif (
    "list row tap skipped root sheet root@" not in text
    and "gtkInstallListRowRootEventFallback" in text
):
    raise SystemExit("SwiftOpenUI List row root sheet guard shape was not recognized")

old_listbox_button_guard = '''            guard gtk_swift_root_point_picks_button(listBox, x, y) == 0 else {
                gtkDebugLog("list row tap skipped button listbox@\\(Int(x)),\\(Int(y))")
                return
            }
            guard let row = gtk_swift_list_box_row_at_point(listBox, x, y) else {
'''
new_listbox_button_guard = '''            guard gtk_swift_root_point_picks_button(listBox, x, y) == 0 else {
                gtkDebugLog("list row tap skipped button listbox@\\(Int(x)),\\(Int(y))")
                return
            }
            guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(listBox, root: listBox, x: x, y: y) else {
                gtkDebugLog("list row tap skipped visual button listbox@\\(Int(x)),\\(Int(y))")
                return
            }
            guard let row = gtk_swift_list_box_row_at_point(listBox, x, y) else {
'''
if old_listbox_button_guard in text:
    text = text.replace(old_listbox_button_guard, new_listbox_button_guard, 1)
elif (
    "list row tap skipped visual button listbox@" not in text
    and "gtkInstallListBoxTapFallback" in text
):
    raise SystemExit("SwiftOpenUI List box visual button guard shape was not recognized")

old_list_row_gesture_guard = '''        unsafeBitCast({ (_: gpointer?, nPress: gint, _: gdouble, _: gdouble, userData: gpointer?) in
            guard Int(nPress) == 1, let userData else { return }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(userData).takeUnretainedValue()
            gtkScheduleListRowTapAction(box, source: "gesture")
'''
new_list_row_gesture_guard = '''        unsafeBitCast({ (gesture: gpointer?, nPress: gint, x: gdouble, y: gdouble, userData: gpointer?) in
            guard Int(nPress) == 1, let userData else { return }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(userData).takeUnretainedValue()
            guard let row = gtk_swift_event_controller_widget(gesture) else {
                gtkScheduleListRowTapAction(box, source: "gesture")
                return
            }
            guard gtk_swift_root_point_picks_button(row, x, y) == 0 else {
                gtkDebugLog("list row tap skipped button gesture@\\(Int(x)),\\(Int(y)) \\(box.source)")
                return
            }
            guard !gtkWidgetTreeContainsVisualButtonAtRootPoint(row, root: row, x: x, y: y) else {
                gtkDebugLog("list row tap skipped visual button gesture@\\(Int(x)),\\(Int(y)) \\(box.source)")
                return
            }
            gtkScheduleListRowTapAction(box, source: "gesture")
'''
if old_list_row_gesture_guard in text:
    text = text.replace(old_list_row_gesture_guard, new_list_row_gesture_guard, 1)
elif "gtk_swift_event_controller_widget(gesture)" not in text and "gtkInstallListRowTapFallback" in text:
    raise SystemExit("SwiftOpenUI List row gesture visual button guard shape was not recognized")

# Keep these frame/layout rewrites independent from the Button idempotency guard.
# A vendored renderer may already contain button expansion while still needing
# the finite .frame(maxWidth:) fixes below.
text = text.replace('(maxWidth != nil && maxWidth == .infinity)', '(maxWidth != nil)')
text = text.replace('(maxHeight != nil && maxHeight == .infinity)', '(maxHeight != nil)')
text = text.replace('if let xw = maxWidth, xw == .infinity {', 'if maxWidth != nil {')
text = text.replace('if let xh = maxHeight, xh == .infinity {', 'if maxHeight != nil {')
text = text.replace('let hexp: gint = (maxWidth != nil && maxWidth == .infinity) ? 1 : 0', 'let hexp: gint = (maxWidth != nil) ? 1 : 0')
text = text.replace('let vexp: gint = (maxHeight != nil && maxHeight == .infinity) ? 1 : 0', 'let vexp: gint = (maxHeight != nil) ? 1 : 0')

# Ensure fallback stacks fill the cross-axis when children expand.
text = text.replace(
    'if gtk_widget_get_vexpand(widget) != 0 { needsVExpand = true }',
    'if gtk_widget_get_vexpand(widget) != 0 { needsVExpand = true; gtk_widget_set_valign(widget, GTK_ALIGN_FILL) }'
)
text = text.replace(
    'if gtk_widget_get_hexpand(widget) != 0 { needsHExpand = true }',
    'if gtk_widget_get_hexpand(widget) != 0 { needsHExpand = true; gtk_widget_set_halign(widget, GTK_ALIGN_FILL) }'
)

if 'gtkButtonDebugSource("gesture", widget: context.widget)' not in text:
    button_extension_index = text.find("extension Button: GTKRenderable")
    if button_extension_index == -1:
        raise SystemExit("SwiftOpenUI Button GTKRenderable extension was not recognized")
    button_action_start = text.find(
        "        let boundAction = bindActionToCurrentEnvironment(action)\n",
        button_extension_index,
    )
    button_action_end = text.find(
        "        // Register keyboard shortcut if present in environment\n",
        button_action_start,
    )
    if button_action_end == -1:
        button_action_end = text.find(
            "        return opaqueFromWidget(button)\n",
            button_action_start,
        )
    if button_action_start == -1 or button_action_end == -1:
        raise SystemExit("SwiftOpenUI Button action callback shape was not recognized")
    button_activation = '''        let boundAction = bindActionToCurrentEnvironment(action)
        let buttonActionBox = Unmanaged.passRetained(
            GTKButtonActionBox(boundAction, widget: button)
        ).toOpaque()
        let buttonRootEventContext = Unmanaged.passRetained(
            GTKButtonRootEventContext(
                widget: button,
                box: Unmanaged<GTKButtonActionBox>.fromOpaque(buttonActionBox).takeUnretainedValue()
            )
        ).toOpaque()
        g_signal_connect_data(
            gpointer(button),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallGlobalButtonRootDispatcher(for: context.widget)
                gtkInstallButtonRootEventFallback(context)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(button),
            "clicked",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("clicked", widget: context.widget))
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        let gesture = gtk_gesture_click_new()!
        gtk_swift_gesture_single_set_button(gesture, 1)
        g_signal_connect_data(
            gpointer(gesture),
            "pressed",
            unsafeBitCast({ (_: gpointer?, _: gint, _: gdouble, _: gdouble, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("gesture", widget: context.widget))
            } as @convention(c) (gpointer?, gint, gdouble, gdouble, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_capture_gesture(button, gesture)
        let legacyController = gtk_swift_legacy_capture_controller()!
        g_signal_connect_data(
            legacyController,
            "event",
            unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
                guard let event, let userData else { return 0 }
                guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
                let box = Unmanaged<GTKButtonActionBox>.fromOpaque(userData).takeUnretainedValue()
                gtkScheduleButtonAction(box, source: "legacy")
                return 0
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
            buttonActionBox,
            nil,
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_event_controller(button, legacyController)
        g_signal_connect_data(
            gpointer(button),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeRetainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(button),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<GTKButtonActionBox>.fromOpaque(userData).release()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonActionBox,
            nil,
            GConnectFlags(rawValue: 0)
        )
'''
    text = text[:button_action_start] + button_activation + text[button_action_end:]

text = text.replace(
    "        gtk_swift_add_gesture(button, gesture)\n"
    "        g_signal_connect_data(\n"
    "            gpointer(button),\n"
    "            \"destroy\",\n",
    "        gtk_swift_add_capture_gesture(button, gesture)\n"
    "        g_signal_connect_data(\n"
    "            gpointer(button),\n"
    "            \"destroy\",\n",
    1,
)

if "let buttonRootEventContext = Unmanaged.passRetained" not in text:
    action_box_line = "        let buttonActionBox = Unmanaged.passRetained(GTKButtonActionBox(boundAction)).toOpaque()\n"
    root_context_activation = '''        let buttonActionBox = Unmanaged.passRetained(
            GTKButtonActionBox(boundAction, widget: button)
        ).toOpaque()
        let buttonRootEventContext = Unmanaged.passRetained(
            GTKButtonRootEventContext(
                widget: button,
                box: Unmanaged<GTKButtonActionBox>.fromOpaque(buttonActionBox).takeUnretainedValue()
            )
        ).toOpaque()
        g_signal_connect_data(
            gpointer(button),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallGlobalButtonRootDispatcher(for: context.widget)
                gtkInstallButtonRootEventFallback(context)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
'''
    if action_box_line not in text:
        raise SystemExit("SwiftOpenUI Button action box insertion point was not recognized")
    text = text.replace(action_box_line, root_context_activation, 1)

if "gtkInstallGlobalButtonRootDispatcher(for: context.widget)" not in text:
    button_map_context = '''                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallButtonRootEventFallback(context)
'''
    button_map_context_with_global = '''                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeUnretainedValue()
                gtkInstallGlobalButtonRootDispatcher(for: context.widget)
                gtkInstallButtonRootEventFallback(context)
'''
    if button_map_context not in text:
        raise SystemExit("SwiftOpenUI Button map global dispatcher insertion point was not recognized")
    text = text.replace(button_map_context, button_map_context_with_global, 1)

if 'gtkScheduleButtonAction(box, source: "legacy"' not in text:
    button_legacy_marker = (
        "        gtk_swift_add_capture_gesture(button, gesture)\n"
        "        g_signal_connect_data(\n"
        "            gpointer(button),\n"
        "            \"destroy\",\n"
    )
    button_legacy_block = '''        gtk_swift_add_capture_gesture(button, gesture)
        let legacyController = gtk_swift_legacy_capture_controller()!
        g_signal_connect_data(
            gpointer(legacyController),
            "event",
            unsafeBitCast({ (_: gpointer?, event: gpointer?, userData: gpointer?) -> gboolean in
                guard let event, let userData else { return 0 }
                guard gtk_swift_event_is_primary_button_press(event) != 0 else { return 0 }
                let box = Unmanaged<GTKButtonActionBox>.fromOpaque(userData).takeUnretainedValue()
                gtkScheduleButtonAction(box, source: "legacy")
                return 0
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
            buttonActionBox,
            nil,
            GConnectFlags(rawValue: 0)
        )
        gtk_swift_add_event_controller(button, legacyController)
        g_signal_connect_data(
            gpointer(button),
            "destroy",
'''
    if button_legacy_marker not in text:
        raise SystemExit("SwiftOpenUI Button legacy event insertion point was not recognized")
    text = text.replace(button_legacy_marker, button_legacy_block, 1)

if "gtkListControlActivationGateDataKey" not in text:
    old_button_action_box = '''private final class GTKButtonActionBox {
    var action: () -> Void
    var activationGate = GTKButtonActivationGate()

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}
'''
    new_button_action_box = '''private final class GTKButtonActionBox {
    var action: () -> Void
    var activationGate = GTKButtonActivationGate()
    let widget: UnsafeMutablePointer<GtkWidget>

    init(_ action: @escaping () -> Void, widget: UnsafeMutablePointer<GtkWidget>) {
        self.action = action
        self.widget = widget
    }
}
'''
    if old_button_action_box not in text:
        raise SystemExit("SwiftOpenUI Button action box list-control shape was not recognized")
    text = text.replace(old_button_action_box, new_button_action_box, 1)

    idle_context_marker = "private final class GTKButtonIdleActionContext {\n"
    list_control_activation_gate = r'''private let gtkListControlActivationGateDataKey = "gtk-swift-list-control-activation-gate"

private final class GTKListControlActivationGate {
    private var deadline: TimeInterval = -.infinity
    private var row: UnsafeMutablePointer<GtkWidget>?

    func mark(row: UnsafeMutablePointer<GtkWidget>, now: TimeInterval) {
        self.row = row
        deadline = now + 0.75
    }

    func consumeIfRecent(row: UnsafeMutablePointer<GtkWidget>, now: TimeInterval) -> Bool {
        guard self.row == row, now <= deadline else {
            self.row = nil
            deadline = -.infinity
            return false
        }
        self.row = nil
        deadline = -.infinity
        return true
    }
}

private func gtkListControlActivationGate(
    for root: UnsafeMutablePointer<GtkWidget>,
    create: Bool
) -> GTKListControlActivationGate? {
    let object = UnsafeMutableRawPointer(root).assumingMemoryBound(to: GObject.self)
    if let pointer = g_object_get_data(object, gtkListControlActivationGateDataKey) {
        return Unmanaged<GTKListControlActivationGate>.fromOpaque(pointer).takeUnretainedValue()
    }
    guard create else { return nil }

    let gate = GTKListControlActivationGate()
    g_object_set_data_full(
        object,
        gtkListControlActivationGateDataKey,
        Unmanaged.passRetained(gate).toOpaque(),
        { userData in
            guard let userData else { return }
            Unmanaged<GTKListControlActivationGate>.fromOpaque(userData).release()
        }
    )
    return gate
}

private func gtkMarkListControlActivationAtRoot(
    _ root: UnsafeMutablePointer<GtkWidget>,
    row: UnsafeMutablePointer<GtkWidget>
) {
    gtkListControlActivationGate(for: root, create: true)?.mark(
        row: row,
        now: Date().timeIntervalSinceReferenceDate
    )
}

private func gtkMarkContainingListControlActivation(_ widget: UnsafeMutablePointer<GtkWidget>) {
    var current: UnsafeMutablePointer<GtkWidget>? = widget
    var row: UnsafeMutablePointer<GtkWidget>?
    var listBox: UnsafeMutablePointer<GtkWidget>?
    while let candidate = current {
        if row == nil, gtk_swift_widget_is_list_box_row(candidate) != 0 {
            row = candidate
        }
        if gtk_swift_widget_is_list_box(candidate) != 0 {
            listBox = candidate
            break
        }
        current = gtk_widget_get_parent(candidate)
    }
    guard let row, let listBox else { return }
    let root = gtk_swift_widget_root_widget(widget) ?? listBox
    gtkMarkListControlActivationAtRoot(root, row: row)
}

private func gtkConsumeRecentListControlActivation(
    in listBox: UnsafeMutablePointer<GtkWidget>,
    row: UnsafeMutablePointer<GtkWidget>
) -> Bool {
    let root = gtk_swift_widget_root_widget(listBox) ?? listBox
    return gtkListControlActivationGate(for: root, create: false)?.consumeIfRecent(
        row: row,
        now: Date().timeIntervalSinceReferenceDate
    ) ?? false
}

'''
    if idle_context_marker not in text:
        raise SystemExit("SwiftOpenUI Button idle context insertion point was not recognized")
    text = text.replace(
        idle_context_marker,
        list_control_activation_gate + idle_context_marker,
        1,
    )

if "gtkMarkContainingListControlActivation(box.widget)" not in text:
    schedule_start = text.find("private func gtkScheduleButtonAction(")
    schedule_end = text.find("private func gtkInstallGlobalButtonRootDispatcher", schedule_start)
    if schedule_start == -1 or schedule_end == -1:
        raise SystemExit("SwiftOpenUI Button scheduling section was not recognized")
    schedule_block = text[schedule_start:schedule_end]
    schedule_log = '    gtkDebugLog("button \\(source)")\n'
    if schedule_log not in schedule_block:
        raise SystemExit("SwiftOpenUI Button scheduling activation point was not recognized")
    schedule_block = schedule_block.replace(
        schedule_log,
        "    if case .pointerPress = phase {\n"
        "        gtkMarkContainingListControlActivation(box.widget)\n"
        "    }\n" + schedule_log,
        1,
    )
    text = text[:schedule_start] + schedule_block + text[schedule_end:]

text = text.replace(
    "GTKButtonActionBox(boundAction)).toOpaque()",
    "GTKButtonActionBox(boundAction, widget: button)).toOpaque()",
)
text = text.replace(
    "        let buttonActionBox = Unmanaged.passRetained(GTKButtonActionBox(boundAction, widget: button)).toOpaque()\n",
    "        let buttonActionBox = Unmanaged.passRetained(\n"
    "            GTKButtonActionBox(boundAction, widget: button)\n"
    "        ).toOpaque()\n",
)
text = text.replace(
    '                gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("clicked", widget: context.widget), phase: .clicked)\n',
    "                gtkScheduleButtonAction(\n"
    "                    context.box,\n"
    '                    source: gtkButtonDebugSource("clicked", widget: context.widget),\n'
    "                    phase: .clicked\n"
    "                )\n",
)
text = text.replace(
    '                gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("gesture", widget: context.widget), phase: .pointerPress)\n',
    "                gtkScheduleButtonAction(\n"
    "                    context.box,\n"
    '                    source: gtkButtonDebugSource("gesture", widget: context.widget),\n'
    "                    phase: .pointerPress\n"
    "                )\n",
)

if "list row activation suppressed after nested control" not in text:
    old_list_row_activation = r'''private func gtkInstallListBoxRowActivationFallback(on listBox: UnsafeMutablePointer<GtkWidget>) {
    gtk_swift_list_box_set_activate_on_single_click(listBox, 1)
    g_signal_connect_data(
        gpointer(listBox),
        "row-activated",
        unsafeBitCast({ (_: gpointer?, row: gpointer?, _: gpointer?) in
            guard let row else { return }
            guard let actionData = g_object_get_data(
                UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
                gtkListRowTapActionDataKey
            ) else {
                return
            }
            let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(actionData).takeUnretainedValue()
            gtkScheduleListRowTapAction(box, source: "row-activated")
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        nil,
        nil,
        GConnectFlags(rawValue: 0)
    )
}
'''
    new_list_row_activation = r'''private func gtkHandleListBoxRowActivation(
    listBox: UnsafeMutablePointer<GtkWidget>,
    row: UnsafeMutablePointer<GtkWidget>
) {
    if gtkConsumeRecentListControlActivation(in: listBox, row: row) {
        gtkDebugLog("list row activation suppressed after nested control")
        return
    }
    guard let actionData = g_object_get_data(
        UnsafeMutableRawPointer(row).assumingMemoryBound(to: GObject.self),
        gtkListRowTapActionDataKey
    ) else {
        return
    }
    let box = Unmanaged<GTKListRowTapActionBox>.fromOpaque(actionData).takeUnretainedValue()
    gtkScheduleListRowTapAction(box, source: "row-activated")
}

func gtkTestActivateListBoxRow(
    listBox: UnsafeMutablePointer<GtkWidget>,
    row: UnsafeMutablePointer<GtkWidget>
) {
    gtkHandleListBoxRowActivation(listBox: listBox, row: row)
}

private func gtkInstallListBoxRowActivationFallback(on listBox: UnsafeMutablePointer<GtkWidget>) {
    gtk_swift_list_box_set_activate_on_single_click(listBox, 1)
    g_signal_connect_data(
        gpointer(listBox),
        "row-activated",
        unsafeBitCast({ (listBox: gpointer?, row: gpointer?, _: gpointer?) in
            guard let listBox, let row else { return }
            gtkHandleListBoxRowActivation(
                listBox: listBox.assumingMemoryBound(to: GtkWidget.self),
                row: row.assumingMemoryBound(to: GtkWidget.self)
            )
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
        nil,
        nil,
        GConnectFlags(rawValue: 0)
    )
}
'''
    if old_list_row_activation not in text:
        raise SystemExit("SwiftOpenUI List row native activation shape was not recognized")
    text = text.replace(old_list_row_activation, new_list_row_activation, 1)

text = text.replace("            gpointer(legacyController),\n", "            legacyController,\n")

if "context.removeController()" not in text:
    action_destroy_marker = '''        g_signal_connect_data(
            gpointer(button),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<GTKButtonActionBox>.fromOpaque(userData).release()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonActionBox,
            nil,
            GConnectFlags(rawValue: 0)
        )
'''
    root_destroy_block = '''        g_signal_connect_data(
            gpointer(button),
            "destroy",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                let context = Unmanaged<GTKButtonRootEventContext>.fromOpaque(userData).takeRetainedValue()
                context.removeController()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            buttonRootEventContext,
            nil,
            GConnectFlags(rawValue: 0)
        )
''' + action_destroy_marker
    if action_destroy_marker not in text:
        raise SystemExit("SwiftOpenUI Button destroy insertion point was not recognized")
    text = text.replace(action_destroy_marker, root_destroy_block, 1)

tap_extension_index = text.find("extension TapGestureView: GTKRenderable")
if tap_extension_index != -1:
    long_press_index = text.find("extension LongPressGestureView", tap_extension_index)
    if long_press_index == -1:
        raise SystemExit("SwiftOpenUI TapGesture renderer end marker was not recognized")
    tap_block = text[tap_extension_index:long_press_index]
    if "gtk_swift_add_capture_gesture(widget, gesture)" not in tap_block:
        if "gtk_swift_add_gesture(widget, gesture)" not in tap_block:
            raise SystemExit("SwiftOpenUI TapGesture gesture attach shape was not recognized")
        tap_block = tap_block.replace(
            "gtk_swift_add_gesture(widget, gesture)",
            "gtk_swift_add_capture_gesture(widget, gesture)",
            1,
        )
        text = text[:tap_extension_index] + tap_block + text[long_press_index:]

finite_frame_width = "childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity)"
finite_frame_height = "childExpV || (height == nil && maxHeight != nil && maxHeight != .infinity)"
if finite_frame_width not in text or finite_frame_height not in text:
    old_frame_fill = '''            expandsToFillWidth: childExpH,
            expandsToFillHeight: childExpV
'''
    new_frame_fill = '''            expandsToFillWidth: childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity),
            expandsToFillHeight: childExpV || (height == nil && maxHeight != nil && maxHeight != .infinity)
'''
    if old_frame_fill not in text:
        raise SystemExit("SwiftOpenUI FrameView fill sizing shape was not recognized")
    text = text.replace(old_frame_fill, new_frame_fill)

finite_frame_flexible_height = "gtk_widget_get_vexpand(child) != 0 || (height == nil && maxHeight != nil && maxHeight != .infinity)"
if finite_frame_flexible_height not in text:
    old_flexible_axis_frame_fill = '''            expandsToFillWidth: childExpH,
            expandsToFillHeight: gtk_widget_get_vexpand(child) != 0
'''
    new_flexible_axis_frame_fill = '''            expandsToFillWidth: childExpH || (width == nil && maxWidth != nil && maxWidth != .infinity),
            expandsToFillHeight: gtk_widget_get_vexpand(child) != 0 || (height == nil && maxHeight != nil && maxHeight != .infinity)
'''
    if old_flexible_axis_frame_fill in text:
        text = text.replace(old_flexible_axis_frame_fill, new_flexible_axis_frame_fill)

fixed_frame_child_sizing = "SwiftUI proposes the clamped fixed-frame size to children"
has_fixed_frame_clip_region = (
    "let clampsChild =" in text
    or "gtk_swift_scrolled_window_configure_clip(" in text
    or fixed_frame_child_sizing in text
    or "Expanding fixed-frame children receive the proposed frame size" in text
    or "Fixed-frame clipping uses a normal GtkBox allocation" in text
)
if has_fixed_frame_clip_region and fixed_frame_child_sizing not in text:
    old_clamped_child_size = '''            if childExpH || childExpV {
                gtk_widget_set_size_request(
                    child,
                    childExpH ? gint(layout.childPlacement.size.width) : -1,
                    childExpV ? gint(layout.childPlacement.size.height) : -1
                )
            }
'''
    new_clamped_child_size = '''            // SwiftUI proposes the clamped fixed-frame size to children.
            // Without this, HStacks with Spacer() inside fixed-width
            // sheets keep their oversized natural width and GTK clips
            // trailing controls such as Close/New/Edit/Delete buttons.
            gtk_widget_set_size_request(
                child,
                gtkPixelSize(layout.childPlacement.size.width),
                gtkPixelSize(layout.childPlacement.size.height)
            )
'''
    if old_clamped_child_size not in text:
        raise SystemExit("SwiftOpenUI fixed-frame clamped child sizing shape was not recognized")
    text = text.replace(old_clamped_child_size, new_clamped_child_size, 1)

fixed_frame_expanding_child_sizing = "Expanding fixed-frame children receive the proposed frame size"
if has_fixed_frame_clip_region and fixed_frame_expanding_child_sizing not in text:
    old_expanding_child_slot = '''        let slot: UnsafeMutablePointer<GtkWidget> = clampsChild
            ? gtk_swift_scrolled_window_new()!
            : gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!

        // Expanding children should fill the slot; non-expanding ones
'''
    new_expanding_child_slot = '''        let slot: UnsafeMutablePointer<GtkWidget> = clampsChild
            ? gtk_swift_scrolled_window_new()!
            : gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!

        // Expanding fixed-frame children receive the proposed frame size
        // even when the child does not need clipping. Otherwise a padded
        // VStack/HStack can keep its natural width and lose trailing
        // Spacer-aligned controls.
        if childExpH || childExpV {
            gtk_widget_set_size_request(
                child,
                childExpH ? gtkPixelSize(layout.childPlacement.size.width) : -1,
                childExpV ? gtkPixelSize(layout.childPlacement.size.height) : -1
            )
        }

        // Expanding children should fill the slot; non-expanding ones
'''
    if old_expanding_child_slot not in text:
        raise SystemExit("SwiftOpenUI fixed-frame expanding child sizing shape was not recognized")
    text = text.replace(old_expanding_child_slot, new_expanding_child_slot, 1)

fixed_frame_box_clipping = "Fixed-frame clipping uses a normal GtkBox allocation"
if has_fixed_frame_clip_region and fixed_frame_box_clipping not in text:
    old_fixed_clip_slot = '''        let slot: UnsafeMutablePointer<GtkWidget> = clampsChild
            ? gtk_swift_scrolled_window_new()!
            : gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
'''
    new_fixed_clip_slot = '''        // Fixed-frame clipping uses a normal GtkBox allocation.
        // GtkScrolledWindow preserves the child's wider natural width
        // internally, which breaks SwiftUI Spacer rows inside clipped
        // fixed-width sheets.
        let slot: UnsafeMutablePointer<GtkWidget> = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
'''
    if old_fixed_clip_slot not in text:
        raise SystemExit("SwiftOpenUI fixed-frame clip slot shape was not recognized")
    text = text.replace(old_fixed_clip_slot, new_fixed_clip_slot, 1)

    old_fixed_clip_child = '''            gtk_swift_scrolled_window_configure_clip(
                slot,
                gint(layout.childPlacement.size.width),
                gint(layout.childPlacement.size.height)
            )
            gtk_swift_scrolled_window_set_child(slot, child)
'''
    if old_fixed_clip_child not in text:
        raise SystemExit("SwiftOpenUI fixed-frame clip child shape was not recognized")
    text = text.replace(old_fixed_clip_child, "", 1)

    old_fixed_unclipped_append = '''        if !clampsChild {
            gtk_box_append(boxPointer(slot), child)
        }
'''
    new_fixed_unclipped_append = '''        gtk_box_append(boxPointer(slot), child)
'''
    if old_fixed_unclipped_append not in text:
        raise SystemExit("SwiftOpenUI fixed-frame child append shape was not recognized")
    text = text.replace(old_fixed_unclipped_append, new_fixed_unclipped_append, 1)

fixed_frame_flexible_width_fixed_height_clip = "gtkFrameFlexibleWidthFixedHeightClip"
if has_fixed_frame_clip_region and fixed_frame_flexible_width_fixed_height_clip not in text:
    old_parent_flexible_request = '''        let requestWidth = widthMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.width)
        let requestHeight = heightMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.height)
        gtk_widget_set_size_request(wrapper, requestWidth, requestHeight)
'''
    new_parent_flexible_request = '''        if !widthMayGrowWithParent && heightMayGrowWithParent && childExpV {
            return gtkFrameFixedWidthFlexibleHeightClip(
                child: child,
                width: gtkPixelSize(layout.containerSize.width)
            )
        }

        let requestWidth = widthMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.width)
        let requestHeight = heightMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.height)
        if widthMayGrowWithParent && !heightMayGrowWithParent {
            return gtkFrameFlexibleWidthFixedHeightClip(
                child: child,
                height: gtkPixelSize(layout.containerSize.height)
            )
        }
        gtk_widget_set_size_request(wrapper, requestWidth, requestHeight)
'''
    if old_parent_flexible_request not in text:
        raise SystemExit("SwiftOpenUI parent-flexible frame request shape was not recognized")
    text = text.replace(old_parent_flexible_request, new_parent_flexible_request, 1)

    old_parent_flexible_child_expansion = '''        if childExpV {
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
            gtk_widget_set_vexpand(child, 1)
            gtk_box_append(boxPointer(wrapper), child)
            return opaqueFromWidget(wrapper)
        }
'''
    new_parent_flexible_child_expansion = '''        if childExpV {
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
            gtk_widget_set_vexpand(child, heightMayGrowWithParent ? 1 : 0)
            gtk_box_append(boxPointer(wrapper), child)
            return opaqueFromWidget(wrapper)
        }
'''
    if old_parent_flexible_child_expansion not in text:
        raise SystemExit("SwiftOpenUI parent-flexible child vexpand shape was not recognized")
    text = text.replace(old_parent_flexible_child_expansion, new_parent_flexible_child_expansion, 1)

    fixed_height_clip_helper_anchor = '''    /// Build a frame wrapper using GtkBox instead of GtkFixed, for frames
'''
    fixed_height_clip_helper = '''    private func gtkFrameFlexibleWidthFixedHeightClip(
        child: UnsafeMutablePointer<GtkWidget>,
        height: gint
    ) -> OpaquePointer {
        let scrolled = gtk_scrolled_window_new()!
        let scrolledOp = OpaquePointer(scrolled)
        gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
        gtk_scrolled_window_set_has_frame(scrolledOp, 0)
        gtk_scrolled_window_set_min_content_height(scrolledOp, height)
        gtk_scrolled_window_set_max_content_height(scrolledOp, height)
        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
        gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)

        gtk_widget_set_hexpand(scrolled, 1)
        gtk_widget_set_vexpand(scrolled, 0)
        gtk_widget_set_hexpand(child, 1)
        gtk_widget_set_vexpand(child, 0)
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(child, -1, height)
        gtk_scrolled_window_set_child(scrolledOp, child)
        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: true,
            fillHeight: false
        )
        return opaqueFromWidget(scrolled)
    }

'''
    if fixed_height_clip_helper_anchor not in text:
        raise SystemExit("SwiftOpenUI flexible-width fixed-height frame helper anchor was not recognized")
    text = text.replace(
        fixed_height_clip_helper_anchor,
        fixed_height_clip_helper + fixed_height_clip_helper_anchor,
        1,
    )

clipped_width_clamp = "let wrapper = gtk_swift_width_clamp_new(inner)!"
if "extension ClippedView: GTKRenderable" in text and clipped_width_clamp not in text:
    old_clipped_wrapper = '''        let inner = widgetFromOpaque(gtkRenderView(content))
        let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_box_append(boxPointer(wrapper), inner)
        gtk_widget_set_overflow(wrapper, GTK_OVERFLOW_HIDDEN)
'''
    new_clipped_wrapper = '''        let inner = widgetFromOpaque(gtkRenderView(content))
        let wrapper = gtk_swift_width_clamp_new(inner)!
        gtk_widget_set_overflow(wrapper, GTK_OVERFLOW_HIDDEN)
'''
    if old_clipped_wrapper not in text:
        raise SystemExit("SwiftOpenUI clipped wrapper shape was not recognized")
    text = text.replace(old_clipped_wrapper, new_clipped_wrapper, 1)

fixed_width_flexible_height_clip = "gtkFrameFixedWidthFlexibleHeightClip"
if fixed_width_flexible_height_clip not in text:
    fixed_width_clip_helper_anchor = '''    /// Build a frame wrapper using GtkBox instead of GtkFixed, for frames
'''
    fixed_width_clip_helper = '''    private func gtkFrameFixedWidthFlexibleHeightClip(
        child: UnsafeMutablePointer<GtkWidget>,
        width: gint
    ) -> OpaquePointer {
        let scrolled = gtk_scrolled_window_new()!
        let scrolledOp = OpaquePointer(scrolled)
        gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
        gtk_scrolled_window_set_has_frame(scrolledOp, 0)
        gtk_scrolled_window_set_min_content_width(scrolledOp, width)
        gtk_scrolled_window_set_max_content_width(scrolledOp, width)
        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
        gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)

        gtk_widget_set_size_request(scrolled, width, -1)
        gtk_widget_set_hexpand(scrolled, 0)
        gtk_widget_set_vexpand(scrolled, 1)
        gtk_widget_set_hexpand(child, 1)
        gtk_widget_set_vexpand(child, 1)
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        gtk_widget_set_size_request(child, width, -1)
        gtk_scrolled_window_set_child(scrolledOp, child)
        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: true,
            fillHeight: true
        )
        if gtkHasVerticalFillIntent(child) {
            gtkMarkVerticalFillIntent(scrolled)
        }
        return opaqueFromWidget(scrolled)
    }

'''
    if fixed_width_clip_helper_anchor not in text:
        raise SystemExit("SwiftOpenUI flexible-height fixed-width frame helper anchor was not recognized")
    text = text.replace(
        fixed_width_clip_helper_anchor,
        fixed_width_clip_helper + fixed_width_clip_helper_anchor,
        1,
    )

    old_fixed_width_flexible_height = '''        if constrainedWidth {
            // Width constrained, height flexible
            gtk_widget_set_size_request(wrapper, gtkPixelSize(layout.containerSize.width), -1)
            let hexp: gint = (maxWidth != nil) ? 1 : 0
            gtk_widget_set_hexpand(wrapper, hexp)
            gtk_widget_set_vexpand(wrapper, 1)
        } else {
'''
    old_fixed_width_flexible_height_with_child_request = '''        if constrainedWidth {
            // Width constrained, height flexible
            gtk_widget_set_size_request(wrapper, gtkPixelSize(layout.containerSize.width), -1)
            gtk_widget_set_size_request(child, gtkPixelSize(layout.childPlacement.size.width), -1)
            let hexp: gint = (maxWidth != nil) ? 1 : 0
            gtk_widget_set_hexpand(wrapper, hexp)
            gtk_widget_set_vexpand(wrapper, 1)
        } else {
'''
    new_fixed_width_flexible_height = '''        if constrainedWidth {
            // Width constrained, height flexible
            return gtkFrameFixedWidthFlexibleHeightClip(
                child: child,
                width: gtkPixelSize(layout.containerSize.width)
            )
        } else {
'''
    if old_fixed_width_flexible_height in text:
        text = text.replace(old_fixed_width_flexible_height, new_fixed_width_flexible_height, 1)
    elif old_fixed_width_flexible_height_with_child_request in text:
        text = text.replace(old_fixed_width_flexible_height_with_child_request, new_fixed_width_flexible_height, 1)
    else:
        raise SystemExit("SwiftOpenUI fixed-width flexible-height branch shape was not recognized")

fixed_width_parent_flexible_guard = "!widthMayGrowWithParent && heightMayGrowWithParent && childExpV"
if fixed_width_parent_flexible_guard not in text:
    old_parent_flexible_guard_anchor = '''        let requestWidth = widthMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.width)
        let requestHeight = heightMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.height)
'''
    new_parent_flexible_guard_anchor = '''        if !widthMayGrowWithParent && heightMayGrowWithParent && childExpV {
            return gtkFrameFixedWidthFlexibleHeightClip(
                child: child,
                width: gtkPixelSize(layout.containerSize.width)
            )
        }

        let requestWidth = widthMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.width)
        let requestHeight = heightMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.height)
'''
    if old_parent_flexible_guard_anchor not in text:
        raise SystemExit("SwiftOpenUI parent-flexible fixed-width guard anchor was not recognized")
    text = text.replace(old_parent_flexible_guard_anchor, new_parent_flexible_guard_anchor, 1)

padded_view_child_fill = "PaddedView must let expanding content fill its margin wrapper"
has_padded_view_region = (
    "extension PaddedView" in text
    or "gtkMarkHostedNodeKind(wrapper, kind: .padding)" in text
    or padded_view_child_fill in text
)
if has_padded_view_region and padded_view_child_fill not in text:
    old_padded_expand = '''        gtk_widget_set_margin_top(child, gint(top))
        gtk_widget_set_margin_bottom(child, gint(bottom))
        gtk_widget_set_margin_start(child, gint(leading))
        gtk_widget_set_margin_end(child, gint(trailing))
        if gtk_widget_get_hexpand(child) != 0 { gtk_widget_set_hexpand(wrapper, 1) }
        if gtk_widget_get_vexpand(child) != 0 { gtk_widget_set_vexpand(wrapper, 1) }
        gtkMarkHostedNodeKind(wrapper, kind: .padding)
'''
    new_padded_expand = '''        gtk_widget_set_margin_top(child, gint(top))
        gtk_widget_set_margin_bottom(child, gint(bottom))
        gtk_widget_set_margin_start(child, gint(leading))
        gtk_widget_set_margin_end(child, gint(trailing))
        // PaddedView must let expanding content fill its margin wrapper.
        // This is what carries a fixed frame's proposed width into a
        // padded VStack/HStack instead of clipping Spacer-based rows at
        // their natural size.
        if gtk_widget_get_hexpand(child) != 0 {
            gtk_widget_set_hexpand(wrapper, 1)
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        }
        if gtk_widget_get_vexpand(child) != 0 {
            gtk_widget_set_vexpand(wrapper, 1)
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        }
        gtkMarkHostedNodeKind(wrapper, kind: .padding)
'''
    if old_padded_expand not in text:
        raise SystemExit("SwiftOpenUI PaddedView child fill shape was not recognized")
    text = text.replace(old_padded_expand, new_padded_expand, 1)

if "let transientRoot: gpointer?" not in text:
    old_sheet_info = '''private class SheetInfo {
    let anchor: UnsafeMutablePointer<GtkWidget>
    let render: () -> OpaquePointer
    let onDismiss: () -> Void
    /// Dismissal config from sheet content, used to present confirmation dialog on intercept.
    let dismissalConfig: DismissalConfirmationConfiguration?

    init(anchor: UnsafeMutablePointer<GtkWidget>,
         render: @escaping () -> OpaquePointer,
         onDismiss: @escaping () -> Void,
         dismissalConfig: DismissalConfirmationConfiguration? = nil) {
        self.anchor = anchor
        self.render = render
        self.onDismiss = onDismiss
        self.dismissalConfig = dismissalConfig
    }
}
'''
    new_sheet_info = '''private final class GTKSheetLifecycleScope {
    private var disappearActions: [() -> Void] = []
    private var didRunDisappearActions = false

    func registerOnDisappear(_ action: @escaping () -> Void) {
        disappearActions.append(action)
    }

    func runDisappearActions() {
        guard !didRunDisappearActions else { return }
        didRunDisappearActions = true
        for action in disappearActions {
            action()
        }
    }
}

private var gtkSheetLifecycleScopes: [GTKSheetLifecycleScope] = []

private func gtkCurrentSheetLifecycleScope() -> GTKSheetLifecycleScope? {
    gtkSheetLifecycleScopes.last
}

private func gtkWithSheetLifecycleScope<T>(
    _ scope: GTKSheetLifecycleScope,
    perform body: () -> T
) -> T {
    gtkSheetLifecycleScopes.append(scope)
    defer { _ = gtkSheetLifecycleScopes.popLast() }
    return body()
}

private func gtkSheetDataKey(_ suffix: String, modifierType: Any.Type) -> String {
    return "swift-sheet-\\(String(reflecting: modifierType))-\\(suffix)"
}

private class SheetInfo {
    let anchor: UnsafeMutablePointer<GtkWidget>
    let activeKey: String
    let windowKey: String
    let itemIDKey: String
    let transientRoot: gpointer?
    let lifecycleScope: GTKSheetLifecycleScope
    let render: () -> OpaquePointer
    let onDismiss: () -> Void
    /// Dismissal config from sheet content, used to present confirmation dialog on intercept.
    let dismissalConfig: DismissalConfirmationConfiguration?

    init(anchor: UnsafeMutablePointer<GtkWidget>,
         activeKey: String,
         windowKey: String,
         itemIDKey: String = "",
         transientRoot: gpointer?,
         lifecycleScope: GTKSheetLifecycleScope,
         render: @escaping () -> OpaquePointer,
         onDismiss: @escaping () -> Void,
         dismissalConfig: DismissalConfirmationConfiguration? = nil) {
        self.anchor = anchor
        self.activeKey = activeKey
        self.windowKey = windowKey
        self.itemIDKey = itemIDKey
        self.transientRoot = transientRoot
        self.lifecycleScope = lifecycleScope
        self.render = render
        self.onDismiss = onDismiss
        self.dismissalConfig = dismissalConfig
    }
}
'''
    if old_sheet_info not in text:
        raise SystemExit("SwiftOpenUI SheetInfo shape was not recognized")
    text = text.replace(old_sheet_info, new_sheet_info, 1)
    sheet_default_size = '''private func gtkSheetDefaultWidth() -> gint {
    guard let rawWidth = ProcessInfo.processInfo.environment["QUILLUI_GTK_SHEET_DEFAULT_WIDTH"],
          let width = Int(rawWidth),
          width > 0
    else {
        return 900
    }
    return gint(width)
}

private func gtkSheetDefaultHeight() -> gint {
    guard let rawHeight = ProcessInfo.processInfo.environment["QUILLUI_GTK_SHEET_DEFAULT_HEIGHT"],
          let height = Int(rawHeight),
          height > 0
    else {
        return 650
    }
    return gint(height)
}

'''
    text = text.replace("private func gtkSheetDataKey", sheet_default_size + "private func gtkSheetDataKey", 1)

    old_bool_keys = '''        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        if !isPresented.wrappedValue {
'''
    new_bool_keys = '''        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
        let activeKey = gtkSheetDataKey("active", modifierType: type(of: self))
        let windowKey = gtkSheetDataKey("window", modifierType: type(of: self))
        let overlayKey = gtkSheetDataKey("overlay", modifierType: type(of: self))

        if !isPresented.wrappedValue {
'''
    if old_bool_keys not in text:
        raise SystemExit("SwiftOpenUI bool sheet key insertion shape was not recognized")
    text = text.replace(old_bool_keys, new_bool_keys, 1)

    old_item_keys = '''        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)

        guard let currentItem = item.wrappedValue else {
'''
    new_item_keys = '''        let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
        let activeKey = gtkSheetDataKey("active", modifierType: type(of: self))
        let windowKey = gtkSheetDataKey("window", modifierType: type(of: self))
        let overlayKey = gtkSheetDataKey("overlay", modifierType: type(of: self))
        let itemIDKey = gtkSheetDataKey("item-id", modifierType: type(of: self))

        guard let currentItem = item.wrappedValue else {
'''
    if old_item_keys not in text:
        raise SystemExit("SwiftOpenUI item sheet key insertion shape was not recognized")
    text = text.replace(old_item_keys, new_item_keys, 1)

    old_bool_info = '''        let info = Unmanaged.passRetained(SheetInfo(
            anchor: anchor,
            render: { gtkRenderView(sheetView) },
'''
    new_bool_info = '''        let transientRoot = gtk_widget_get_root(anchor).map { gpointer($0) }
        if let transientRoot {
            g_object_ref(transientRoot)
        }

        let lifecycleScope = GTKSheetLifecycleScope()
        let info = Unmanaged.passRetained(SheetInfo(
            anchor: anchor,
            activeKey: activeKey,
            windowKey: windowKey,
            transientRoot: transientRoot,
            lifecycleScope: lifecycleScope,
            render: { gtkRenderView(sheetView) },
'''
    if old_bool_info not in text:
        raise SystemExit("SwiftOpenUI bool sheet info shape was not recognized")
    text = text.replace(old_bool_info, new_bool_info, 1)

    old_item_info = '''        let info = Unmanaged.passRetained(SheetInfo(
            anchor: anchor,
            render: { gtkRenderView(sheetBuilder(currentItem)) },
'''
    new_item_info = '''        let transientRoot = gtk_widget_get_root(anchor).map { gpointer($0) }
        if let transientRoot {
            g_object_ref(transientRoot)
        }
        let lifecycleScope = GTKSheetLifecycleScope()
        let info = Unmanaged.passRetained(SheetInfo(
            anchor: anchor,
            activeKey: activeKey,
            windowKey: windowKey,
            itemIDKey: itemIDKey,
            transientRoot: transientRoot,
            lifecycleScope: lifecycleScope,
            render: { gtkRenderView(sheetBuilder(currentItem)) },
'''
    if old_item_info not in text:
        raise SystemExit("SwiftOpenUI item sheet info shape was not recognized")
    text = text.replace(old_item_info, new_item_info, 1)

    old_idle_guard = '''            guard let root = gtk_widget_get_root(info.anchor) else {
                info.onDismiss()
                g_object_unref(gpointer(info.anchor))
                return 0
            }
'''
    new_idle_guard = '''            let liveRoot = gtk_widget_get_root(info.anchor).map { gpointer($0) }
            guard let root = liveRoot ?? info.transientRoot else {
                info.onDismiss()
                if let transientRoot = info.transientRoot {
                    g_object_unref(transientRoot)
                }
                g_object_unref(gpointer(info.anchor))
                return 0
            }
'''
    if text.count(old_idle_guard) < 2:
        raise SystemExit("SwiftOpenUI sheet idle root guard shape was not recognized")
    text = text.replace(old_idle_guard, new_idle_guard, 2)

    old_present_unref = '''            gtk_window_present(dialogWin)
            g_object_unref(gpointer(info.anchor))
            return 0
        }, info)
'''
    new_present_unref = '''            gtk_window_present(dialogWin)
            if let transientRoot = info.transientRoot {
                g_object_unref(transientRoot)
            }
            g_object_unref(gpointer(info.anchor))
            return 0
        }, info)
'''
    if text.count(old_present_unref) < 2:
        raise SystemExit("SwiftOpenUI sheet present cleanup shape was not recognized")
    text = text.replace(old_present_unref, new_present_unref, 2)
    text = text.replace(
        'let transientRoot = gtk_widget_get_root(anchor).map { gpointer($0) }',
        '''let transientRoot = gtk_widget_get_root(anchor).map { gpointer($0) }
            ?? GTKViewHost.getCurrentRebuilding()?.rebuildPresentationRoot''',
    )

    text = text.replace('g_object_get_data(gobject, "swift-sheet-active")', 'g_object_get_data(gobject, activeKey)')
    text = text.replace('g_object_set_data(gobject, "swift-sheet-active", nil)', 'g_object_set_data(gobject, activeKey, nil)')
    text = text.replace('g_object_set_data(gobject, "swift-sheet-active", gpointer(bitPattern: 1))', 'g_object_set_data(gobject, activeKey, gpointer(bitPattern: 1))')
    text = text.replace('g_object_get_data(gobject, "swift-sheet-window")', 'g_object_get_data(gobject, windowKey)')
    text = text.replace('g_object_set_data(gobject, "swift-sheet-window", nil)', 'g_object_set_data(gobject, windowKey, nil)')
    text = text.replace('g_object_get_data(obj, "swift-sheet-active")', 'g_object_get_data(obj, activeKey)')
    text = text.replace('g_object_set_data(obj, "swift-sheet-active", nil)', 'g_object_set_data(obj, activeKey, nil)')
    text = text.replace('g_object_set_data(obj, "swift-sheet-window", nil)', 'g_object_set_data(obj, windowKey, nil)')
    text = text.replace('g_object_get_data(gobject, "swift-sheet-item-id")', 'g_object_get_data(gobject, itemIDKey)')
    text = text.replace('g_object_set_data(gobject, "swift-sheet-item-id", nil)', 'g_object_set_data(gobject, itemIDKey, nil)')
    text = text.replace('g_object_set_data(gobject, "swift-sheet-item-id", gpointer(bitPattern: currentIdHash))', 'g_object_set_data(gobject, itemIDKey, gpointer(bitPattern: currentIdHash))')
    text = text.replace('g_object_set_data(obj, "swift-sheet-item-id", nil)', 'g_object_set_data(obj, itemIDKey, nil)')
    text = text.replace('g_object_set_data(anchorObj, "swift-sheet-window", gpointer(dialogWin))', 'g_object_set_data(anchorObj, info.windowKey, gpointer(dialogWin))')
    text = text.replace('g_object_set_data(anchorObj, "swift-sheet-item-id", gpointer(bitPattern: currentIdHash))', 'g_object_set_data(anchorObj, info.itemIDKey, gpointer(bitPattern: currentIdHash))')
    text = text.replace(
        "            let sheetWidget = widgetFromOpaque(info.render())\n",
        "            let sheetWidget = widgetFromOpaque(gtkWithSheetLifecycleScope(info.lifecycleScope) { info.render() })\n",
        2,
    )
    text = text.replace(
        """            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    info.render()
                }
            )
""",
        """            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithSheetLifecycleScope(info.lifecycleScope) { info.render() }
                }
            )
""",
        2,
    )
    text = text.replace(
        """                binding.wrappedValue = false
                userOnDismiss?()
""",
        """                binding.wrappedValue = false
                lifecycleScope.runDisappearActions()
                userOnDismiss?()
""",
        1,
    )
    text = text.replace(
        """                itemBinding.wrappedValue = nil
                userOnDismiss?()
""",
        """                itemBinding.wrappedValue = nil
                lifecycleScope.runDisappearActions()
                userOnDismiss?()
""",
        1,
    )

    bool_overlay_dismiss = '''        if !isPresented.wrappedValue {
            gtkRemoveSheetRootOverlay(
                anchor: anchor,
                overlayKey: overlayKey,
                activeKey: activeKey,
                onDismiss: onDismiss
            )
            // Dismiss active sheet if binding turned false
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
'''
    bool_overlay_dismiss_without_comment = '''        if !isPresented.wrappedValue {
            gtkRemoveSheetRootOverlay(
                anchor: anchor,
                overlayKey: overlayKey,
                activeKey: activeKey,
                onDismiss: onDismiss
            )
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
'''
    if "        if !isPresented.wrappedValue {\n            gtkRemoveSheetRootOverlay(" not in text:
        text = text.replace(
            '''        if !isPresented.wrappedValue {
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
''',
            bool_overlay_dismiss_without_comment,
            1,
        )
        text = text.replace(
            '''        if !isPresented.wrappedValue {
            // Dismiss active sheet if binding turned false
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
''',
            bool_overlay_dismiss,
            1,
        )

    item_overlay_dismiss = '''        guard let currentItem = item.wrappedValue else {
            gtkRemoveSheetRootOverlay(
                anchor: anchor,
                overlayKey: overlayKey,
                activeKey: activeKey,
                itemIDKey: itemIDKey,
                onDismiss: onDismiss
            )
            // Dismiss active sheet if item became nil
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
'''
    item_overlay_dismiss_without_comment = '''        guard let currentItem = item.wrappedValue else {
            gtkRemoveSheetRootOverlay(
                anchor: anchor,
                overlayKey: overlayKey,
                activeKey: activeKey,
                itemIDKey: itemIDKey,
                onDismiss: onDismiss
            )
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
'''
    if "        guard let currentItem = item.wrappedValue else {\n            gtkRemoveSheetRootOverlay(" not in text:
        text = text.replace(
            '''        guard let currentItem = item.wrappedValue else {
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
''',
            item_overlay_dismiss_without_comment,
            1,
        )
        text = text.replace(
            '''        guard let currentItem = item.wrappedValue else {
            // Dismiss active sheet if item became nil
            if let dialogPtr = g_object_get_data(gobject, windowKey) {
''',
            item_overlay_dismiss,
        1,
    )

sheet_dismissal_scheduler = '''private func gtkScheduleSheetDismissal(_ action: @escaping () -> Void) {
    let box = Unmanaged.passRetained(ClosureBox(action)).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        Unmanaged<ClosureBox>.fromOpaque(userData).takeRetainedValue().closure()
        return 0
    }, box)
}
'''
if "private func gtkScheduleSheetDismissal" not in text:
    marker = "\n\nextension SheetModifierView: GTKRenderable"
    if marker not in text:
        raise SystemExit("SwiftOpenUI sheet dismissal scheduler insertion shape was not recognized")
    text = text.replace(marker, "\n\n" + sheet_dismissal_scheduler + marker, 1)

sheet_presentation_environment = '''private func gtkSheetPresentationEnvironment(
    from previous: EnvironmentValues,
    dismissAction: @escaping () -> Void,
    debugName: String
) -> EnvironmentValues {
    var env = previous
    env.dismiss = DismissAction(handler: dismissAction, debugName: debugName)
    env.isPresentedInSheet = true
    return env
}
'''
if "private func gtkSheetPresentationEnvironment(" not in text:
    marker = "\n\nextension SheetModifierView: GTKDescribable"
    if marker not in text:
        marker = "\n\nextension SheetModifierView: GTKRenderable"
    if marker not in text:
        raise SystemExit("SwiftOpenUI sheet presentation environment insertion shape was not recognized")
    text = text.replace(marker, "\n\n" + sheet_presentation_environment + marker, 1)

text = text.replace(
    "                env.dismiss = DismissAction { gtk_window_destroy(dialogWin) }",
    """                env.dismiss = DismissAction {
                    gtkScheduleSheetDismissal {
                        gtk_window_destroy(dialogWin)
                    }
                }""",
)

if 'gtkDebugLog("sheet bool presented=' not in text:
    text = text.replace(
        """        let activeKey = gtkSheetDataKey("active", modifierType: type(of: self))
        let windowKey = gtkSheetDataKey("window", modifierType: type(of: self))
        let overlayKey = gtkSheetDataKey("overlay", modifierType: type(of: self))

        if !isPresented.wrappedValue {
""",
        """        let activeKey = gtkSheetDataKey("active", modifierType: type(of: self))
        let windowKey = gtkSheetDataKey("window", modifierType: type(of: self))
        let overlayKey = gtkSheetDataKey("overlay", modifierType: type(of: self))
        gtkDebugLog("sheet bool presented=\\(isPresented.wrappedValue) activeKey=\\(activeKey)")

        if !isPresented.wrappedValue {
""",
        1,
    )

if 'gtkDebugLog("sheet bool scheduling present' not in text:
    text = text.replace(
        """        g_object_set_data(gobject, activeKey, gpointer(bitPattern: 1))
        g_object_ref(gpointer(anchor))

        let sheetView = sheetContent
""",
        """        g_object_set_data(gobject, activeKey, gpointer(bitPattern: 1))
        gtkDebugLog("sheet bool scheduling present activeKey=\\(activeKey)")
        g_object_ref(gpointer(anchor))

        let sheetView = sheetContent
""",
        1,
    )

if 'gtkDebugLog("sheet bool idle present' not in text:
    text = text.replace(
        """            gtk_window_present(dialogWin)
            if let transientRoot = info.transientRoot {
""",
        """            gtkDebugLog("sheet bool idle present window=\\(dialogWin)")
            gtk_window_present(dialogWin)
            if let transientRoot = info.transientRoot {
""",
        1,
    )

sheet_overlay_helpers = '''private let gtkSheetOverlayHorizontalMargins: gint = 32
private let gtkSheetOverlayVerticalMargins: gint = 32

private final class GTKSheetPanelSizeContext {
    let preferredWidth: gint
    let preferredHeight: gint
    var lastWidth: gint = -1
    var lastHeight: gint = -1

    init(preferredWidth: gint, preferredHeight: gint) {
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
    }
}

private func gtkClampedSheetPanelDimension(
    preferred: gint,
    hostSize: gint,
    margins: gint
) -> gint {
    guard hostSize > 1 else { return preferred }
    return min(preferred, max(gint(1), hostSize - margins))
}

private let gtkSheetPanelSizeTickCallback: GtkTickCallback = { widget, _, userData in
    guard let panel = widget, let userData else { return 0 }
    let context = Unmanaged<GTKSheetPanelSizeContext>.fromOpaque(userData).takeUnretainedValue()
    let host = gtk_widget_get_parent(panel)
    let hostWidth = host.map { gtk_widget_get_width($0) } ?? gtk_widget_get_width(panel)
    let hostHeight = host.map { gtk_widget_get_height($0) } ?? gtk_widget_get_height(panel)
    let nextWidth = gtkClampedSheetPanelDimension(
        preferred: context.preferredWidth,
        hostSize: hostWidth,
        margins: gtkSheetOverlayHorizontalMargins
    )
    let nextHeight = gtkClampedSheetPanelDimension(
        preferred: context.preferredHeight,
        hostSize: hostHeight,
        margins: gtkSheetOverlayVerticalMargins
    )
    guard nextWidth != context.lastWidth || nextHeight != context.lastHeight else { return 1 }

    context.lastWidth = nextWidth
    context.lastHeight = nextHeight
    gtk_widget_set_size_request(panel, nextWidth, nextHeight)
    gtk_widget_queue_resize(panel)
    return 1
}

private func gtkInstallSheetPanelOverlaySizeClamp(
    on panel: UnsafeMutablePointer<GtkWidget>,
    preferredWidth: gint,
    preferredHeight: gint
) {
    let context = GTKSheetPanelSizeContext(
        preferredWidth: preferredWidth,
        preferredHeight: preferredHeight
    )
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    _ = gtk_widget_add_tick_callback(
        panel,
        gtkSheetPanelSizeTickCallback,
        contextPtr,
        { userData in Unmanaged<GTKSheetPanelSizeContext>.fromOpaque(userData!).release() }
    )
}

private func gtkSheetPresentationMode() -> String {
    return (ProcessInfo.processInfo.environment["QUILLUI_BACKEND_SHEET_PRESENTATION"]
        ?? ProcessInfo.processInfo.environment["QUILLUI_GTK_SHEET_PRESENTATION"]
        ?? "root-overlay")
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
}

private func gtkShouldRenderSheetInRootOverlay() -> Bool {
    let mode = gtkSheetPresentationMode()
    return mode.isEmpty || mode == "root" || mode == "root-overlay" || mode == "window-overlay"
}

private func gtkShouldRenderSheetInWindow() -> Bool {
    let mode = gtkSheetPresentationMode()
    return mode == "overlay" || mode == "in-window" || mode == "inline"
}

private var gtkRootSheetOverlayStack: [OpaquePointer] = []

// Presented root-overlay sheet layers, keyed by the type-derived activeKey.
// Anchors (GTKViewHost containers) are recreated on every parent render, so
// per-anchor g_object data is lost after the first rebuild — a layer tracked
// there could never be dismissed (or deduplicated) again. The activeKey is
// stable across hosts, so a global registry survives parent rebuilds.
private var gtkRootSheetLayers: [String: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkRootSheetItemIDs: [String: Int] = [:]

private func gtkCurrentRootSheetOverlay() -> OpaquePointer? {
    gtkRootSheetOverlayStack.last
}

private func gtkWithRootSheetOverlay<T>(_ rootOverlay: OpaquePointer, _ body: () -> T) -> T {
    gtkRootSheetOverlayStack.append(rootOverlay)
    defer { _ = gtkRootSheetOverlayStack.popLast() }
    return body()
}

private func gtkWidgetIsDescendant(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    of ancestor: UnsafeMutablePointer<GtkWidget>
) -> Bool {
    var current: UnsafeMutablePointer<GtkWidget>? = widget
    var depth = 0
    while let node = current, depth < 160 {
        if node == ancestor {
            return true
        }
        current = gtk_widget_get_parent(node)
        depth += 1
    }
    return false
}

private func gtkRootSheetLayerOccludesRootPoint(
    root: UnsafeMutablePointer<GtkWidget>,
    x: Double,
    y: Double,
    excludingDescendant excluded: UnsafeMutablePointer<GtkWidget>? = nil
) -> Bool {
    for layer in gtkRootSheetLayers.values {
        guard gtk_swift_is_widget(layer) != 0 else { continue }
        guard let layerRoot = gtk_widget_get_root(layer),
              gpointer(layerRoot) == gpointer(root) else { continue }
        if let excluded, gtkWidgetIsDescendant(excluded, of: layer) {
            continue
        }
        if gtkWidgetOrDescendantVisuallyContainsRootPoint(layer, root: root, x: x, y: y) {
            return true
        }
    }
    return false
}

private func gtkSheetRootOverlay(for anchor: UnsafeMutablePointer<GtkWidget>) -> OpaquePointer? {
    if let rootOverlay = gtkCurrentRootSheetOverlay() {
        return rootOverlay
    }
    if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(anchor)) {
        return rootOverlay
    }
    var ancestor = gtk_widget_get_parent(anchor)
    while let current = ancestor {
        if let rootOverlay = gtkStoredRootPresentationOverlay(on: gpointer(current)) {
            return rootOverlay
        }
        ancestor = gtk_widget_get_parent(current)
    }
    if let root = gtk_widget_get_root(anchor).map({ gpointer($0) }),
       let rootOverlay = gtkRootPresentationOverlay(for: root) {
        return rootOverlay
    }
    if let root = GTKViewHost.getCurrentRebuilding()?.rebuildPresentationRoot,
       let rootOverlay = gtkRootPresentationOverlay(for: root) {
        return rootOverlay
    }
    if let rootOverlay = gtkFallbackRootPresentationOverlay() {
        return rootOverlay
    }
    return nil
}

private func gtkRemoveSheetRootOverlay(
    anchor: UnsafeMutablePointer<GtkWidget>,
    overlayKey: String,
    activeKey: String,
    itemIDKey: String? = nil,
    onDismiss: (() -> Void)? = nil
) {
    guard let layer = gtkRootSheetLayers.removeValue(forKey: activeKey) else {
        return
    }
    gtkRootSheetItemIDs[activeKey] = nil
    gtkDebugLog("sheet root dismiss activeKey=\\(activeKey)")
    gtk_widget_unparent(layer)
    // Clear any legacy per-anchor markers so a same-anchor re-render starts clean.
    let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, overlayKey, nil)
    g_object_set_data(gobject, activeKey, nil)
    if let itemIDKey {
        g_object_set_data(gobject, itemIDKey, nil)
    }
    onDismiss?()
}

private func gtkCreateSheetOverlayPanel(
    sheetWidget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let panel = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    let preferredWidth = gtkSheetDefaultWidth()
    let preferredHeight = gtkSheetDefaultHeight()
    gtk_widget_set_size_request(panel, preferredWidth, preferredHeight)
    gtkInstallSheetPanelOverlaySizeClamp(
        on: panel,
        preferredWidth: preferredWidth,
        preferredHeight: preferredHeight
    )
    gtk_widget_set_halign(panel, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(panel, GTK_ALIGN_CENTER)
    gtk_widget_set_can_target(panel, 1)
    applyCSSToWidget(
        panel,
        properties: "background: #f8f8fb; border: 1px solid rgba(0,0,0,0.12); border-radius: 12px; box-shadow: 0 18px 48px rgba(0,0,0,0.18);"
    )

    gtk_widget_set_hexpand(sheetWidget, 1)
    gtk_widget_set_vexpand(sheetWidget, 1)
    gtk_widget_set_halign(sheetWidget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(sheetWidget, GTK_ALIGN_FILL)
    gtk_box_append(boxPointer(panel), sheetWidget)
    gtkInstallSheetPanelFocusBridge(on: panel)
    gtkScheduleFirstSheetEditableFocus(in: panel)
    return panel
}

private func gtkCreateSheetOverlayLayer(
    panel: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let layer = gtk_overlay_new()!
    gtk_widget_set_hexpand(layer, 1)
    gtk_widget_set_vexpand(layer, 1)
    gtk_widget_set_halign(layer, GTK_ALIGN_FILL)
    gtk_widget_set_valign(layer, GTK_ALIGN_FILL)

    let backdrop = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtk_widget_set_hexpand(backdrop, 1)
    gtk_widget_set_vexpand(backdrop, 1)
    gtk_widget_set_halign(backdrop, GTK_ALIGN_FILL)
    gtk_widget_set_valign(backdrop, GTK_ALIGN_FILL)
    gtk_widget_set_can_target(backdrop, 1)
    applyCSSToWidget(backdrop, properties: "background: #f8f8fb;")

    gtk_overlay_set_child(OpaquePointer(layer), backdrop)
    gtk_overlay_add_overlay(OpaquePointer(layer), panel)
    return layer
}

private func gtkAttachRootSheetOverlay(
    _ layer: UnsafeMutablePointer<GtkWidget>,
    to rootOverlay: OpaquePointer
) {
    let overlayWidget = UnsafeMutableRawPointer(rootOverlay).assumingMemoryBound(to: GtkWidget.self)
    let previousTop = gtk_widget_get_last_child(overlayWidget)
    gtk_overlay_add_overlay(rootOverlay, layer)
    if let previousTop, previousTop != layer {
        gtk_widget_insert_after(layer, overlayWidget, previousTop)
    }
}

private final class GTKSheetPanelFocusBox {
    let panel: UnsafeMutablePointer<GtkWidget>

    init(panel: UnsafeMutablePointer<GtkWidget>) {
        self.panel = panel
    }
}

private final class GTKSheetEditableFocusTarget {
    let widget: UnsafeMutablePointer<GtkWidget>

    init(widget: UnsafeMutablePointer<GtkWidget>) {
        self.widget = widget
    }
}

private final class GTKSheetPanelFocusTarget {
    let panel: UnsafeMutablePointer<GtkWidget>
    var retries = 0

    init(panel: UnsafeMutablePointer<GtkWidget>) {
        self.panel = panel
    }
}

private func gtkInstallSheetPanelFocusBridge(on panel: UnsafeMutablePointer<GtkWidget>) {
    let gesture = gtk_gesture_click_new()!
    let box = Unmanaged.passRetained(GTKSheetPanelFocusBox(panel: panel)).toOpaque()
    g_signal_connect_data(
        gpointer(gesture),
        "pressed",
        unsafeBitCast({ (_: gpointer?, _: gint, x: Double, y: Double, userData: gpointer?) in
            guard let userData else { return }
            let box = Unmanaged<GTKSheetPanelFocusBox>.fromOpaque(userData).takeUnretainedValue()
            gtkFocusSheetEditable(in: box.panel, localX: x, localY: y)
        } as @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void, to: GCallback.self),
        box,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<GTKSheetPanelFocusBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_capture_gesture(panel, gesture)
}

private func gtkFocusSheetEditable(
    in panel: UnsafeMutablePointer<GtkWidget>,
    localX: Double,
    localY: Double
) {
    guard gtk_swift_is_widget(panel) != 0 else { return }
    guard let root = gtk_swift_widget_root_widget(panel) else { return }
    var rootX = 0.0
    var rootY = 0.0
    guard gtk_widget_translate_coordinates(panel, root, localX, localY, &rootX, &rootY) != 0 else {
        return
    }
    if let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) {
        gtkDebugLog("sheet focus bridge editable root@\\(Int(rootX)),\\(Int(rootY))")
        gtkScheduleSheetEditableFocus(editable)
        return
    }
    guard !gtkSheetPointTargetsControl(root: root, rootX: rootX, rootY: rootY) else {
        gtkDebugLog("sheet focus bridge skipped control root@\\(Int(rootX)),\\(Int(rootY))")
        return
    }
    guard let editable = gtkFindFirstSheetEditable(in: panel) else {
        gtkDebugLog("sheet focus found NO editable at root@\\(Int(rootX)),\\(Int(rootY))")
        return
    }
    gtkDebugLog("sheet focus bridge editable root@\\(Int(rootX)),\\(Int(rootY))")
    gtkScheduleSheetEditableFocus(editable)
}

func gtkSheetPointTargetsControl(
    root: UnsafeMutablePointer<GtkWidget>,
    rootX: Double,
    rootY: Double
) -> Bool {
    var current = gtk_swift_root_point_pick_widget(root, rootX, rootY)
    var depth = 0
    while let widget = current, depth < 64 {
        if gtk_swift_widget_is_button(widget) != 0
            || gtk_swift_widget_is_check_button(widget) != 0
            || gtk_swift_widget_is_switch(widget) != 0
            || gtk_swift_widget_is_scale(widget) != 0
            || gtk_swift_widget_is_editable(widget) != 0
        {
            return true
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
    return false
}

private func gtkFocusSheetEditableWidget(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    gtk_widget_set_can_target(widget, 1)
    gtk_widget_set_can_focus(widget, 1)
    gtk_widget_set_focusable(widget, 1)
    let grabbed = gtk_swift_root_grab_focus(widget)
    gtkDebugLog("sheet focus widget grab=\\(grabbed) target=\\(gtkButtonDebugSource("editable", widget: widget))")
    if let delegate = gtk_editable_get_delegate(OpaquePointer(widget)) {
        let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
        gtk_widget_set_can_target(delegateWidget, 1)
        gtk_widget_set_can_focus(delegateWidget, 1)
        gtk_widget_set_focusable(delegateWidget, 1)
        _ = gtk_swift_root_grab_focus(delegateWidget)
        gtkScheduleSheetEditableFocus(delegateWidget)
    }
    gtkScheduleSheetEditableFocus(widget)
}

private func gtkScheduleSheetEditableFocus(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    g_object_ref(gpointer(widget))
    let target = GTKSheetEditableFocusTarget(widget: widget)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let target = Unmanaged<GTKSheetEditableFocusTarget>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(target.widget)) }
        guard gtk_swift_is_widget(target.widget) != 0 else { return 0 }
        gtk_widget_set_can_target(target.widget, 1)
        gtk_widget_set_can_focus(target.widget, 1)
        gtk_widget_set_focusable(target.widget, 1)
        let grabbed = gtk_swift_root_grab_focus(target.widget)
        gtkDebugLog("sheet focus idle grab=\\(grabbed) target=\\(gtkButtonDebugSource("editable", widget: target.widget))")
        return 0
    }, Unmanaged.passRetained(target).toOpaque())
}

private func gtkScheduleFirstSheetEditableFocus(in panel: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(panel) != 0 else { return }
    g_object_ref(gpointer(panel))
    let target = GTKSheetPanelFocusTarget(panel: panel)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let target = Unmanaged<GTKSheetPanelFocusTarget>.fromOpaque(userData).takeUnretainedValue()
        func finish() -> gboolean {
            g_object_unref(gpointer(target.panel))
            Unmanaged<GTKSheetPanelFocusTarget>.fromOpaque(userData).release()
            return 0
        }
        guard gtk_swift_is_widget(target.panel) != 0 else { return finish() }
        // The panel attaches in the same main-loop tick that presents the
        // sheet, so the first idle can run before GTK allocates it; a focus
        // grab then silently fails and the keyboard stays on the sheet's
        // first focusable button (typed spaces activate Cancel). Retry until
        // the panel has a real allocation.
        if gtk_widget_get_width(target.panel) <= 1 {
            target.retries += 1
            if target.retries <= 120 {
                return 1
            }
            gtkDebugLog("sheet first-focus gave up: panel never allocated")
            return finish()
        }
        if let editable = gtkFindFirstSheetEditable(in: target.panel) {
            gtkDebugLog("sheet first-focus found editable after \\(target.retries) retries")
            gtkFocusSheetEditableWidget(editable)
        } else {
            gtkDebugLog("sheet first-focus found NO editable in panel")
        }
        return finish()
    }, Unmanaged.passRetained(target).toOpaque())
}

private func gtkFindSheetEditable(
    in widget: UnsafeMutablePointer<GtkWidget>,
    root: UnsafeMutablePointer<GtkWidget>,
    rootX: Double,
    rootY: Double
) -> UnsafeMutablePointer<GtkWidget>? {
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = gtkFindSheetEditable(in: current, root: root, rootX: rootX, rootY: rootY) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    guard gtkSheetWidgetIsTextInput(widget),
          gtk_swift_widget_is_topmost_at_root_point(root, widget, rootX, rootY) != 0
    else {
        return nil
    }
    return widget
}

private func gtkFindFirstSheetEditable(
    in widget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget>? {
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let found = gtkFindFirstSheetEditable(in: current) {
            return found
        }
        child = gtk_widget_get_next_sibling(current)
    }

    return gtkSheetWidgetIsTextInput(widget) ? widget : nil
}

private func gtkSheetWidgetIsTextInput(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    guard gtk_swift_is_widget(widget) != 0 else { return false }
    if gtk_swift_widget_is_editable(widget) != 0 { return true }
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    return typeName == "GtkTextView"
}

private func gtkCreateSheetOverlay(
    contentWidget: UnsafeMutablePointer<GtkWidget>,
    sheetWidget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let overlay = gtk_overlay_new()!
    gtk_widget_set_hexpand(overlay, 1)
    gtk_widget_set_vexpand(overlay, 1)
    gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_valign(overlay, GTK_ALIGN_FILL)

    gtk_widget_set_hexpand(contentWidget, 1)
    gtk_widget_set_vexpand(contentWidget, 1)
    gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
    gtk_overlay_set_child(OpaquePointer(overlay), contentWidget)

    let panel = gtkCreateSheetOverlayPanel(sheetWidget: sheetWidget)
    let layer = gtkCreateSheetOverlayLayer(panel: panel)
    gtk_overlay_add_overlay(OpaquePointer(overlay), layer)
    return overlay
}

'''
if "private func gtkShouldRenderSheetInWindow" not in text:
    marker = "\nprivate func gtkSheetDataKey"
    if marker not in text:
        raise SystemExit("SwiftOpenUI sheet overlay helper insertion shape was not recognized")
    text = text.replace(marker, "\n" + sheet_overlay_helpers + "private func gtkSheetDataKey", 1)

sheet_control_focus_helper = r'''func gtkSheetPointTargetsControl(
    root: UnsafeMutablePointer<GtkWidget>,
    rootX: Double,
    rootY: Double
) -> Bool {
    var current = gtk_swift_root_point_pick_widget(root, rootX, rootY)
    var depth = 0
    while let widget = current, depth < 64 {
        if gtk_swift_widget_is_button(widget) != 0
            || gtk_swift_widget_is_check_button(widget) != 0
            || gtk_swift_widget_is_switch(widget) != 0
            || gtk_swift_widget_is_scale(widget) != 0
            || gtk_swift_widget_is_editable(widget) != 0
        {
            return true
        }
        if widget == root {
            break
        }
        current = gtk_widget_get_parent(widget)
        depth += 1
    }
    return false
}
'''
if "func gtkSheetPointTargetsControl(" not in text:
    marker = "\nprivate func gtkFocusSheetEditableWidget"
    if marker not in text:
        raise SystemExit("SwiftOpenUI sheet control focus helper insertion shape was not recognized")
    text = text.replace(marker, "\n" + sheet_control_focus_helper + marker, 1)

text = text.replace(
    """    guard let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) else {
        return
    }
    gtkFocusSheetEditableWidget(editable)
}
""",
    """    if let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) {
        gtkDebugLog("sheet focus bridge editable root@\\(Int(rootX)),\\(Int(rootY))")
        gtkScheduleSheetEditableFocus(editable)
        return
    }
    guard !gtkSheetPointTargetsControl(root: root, rootX: rootX, rootY: rootY) else {
        gtkDebugLog("sheet focus bridge skipped control root@\\(Int(rootX)),\\(Int(rootY))")
        return
    }
    guard let editable = gtkFindFirstSheetEditable(in: panel) else {
        gtkDebugLog("sheet focus found NO editable at root@\\(Int(rootX)),\\(Int(rootY))")
        return
    }
    gtkDebugLog("sheet focus bridge editable root@\\(Int(rootX)),\\(Int(rootY))")
    gtkScheduleSheetEditableFocus(editable)
}
    """,
)

text = text.replace(
    """    guard let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY)
        ?? gtkFindFirstSheetEditable(in: panel) else {
        gtkDebugLog("sheet focus found NO editable at root@\\(Int(rootX)),\\(Int(rootY))")
        return
    }
    gtkDebugLog("sheet focus bridge editable root@\\(Int(rootX)),\\(Int(rootY))")
    gtkScheduleSheetEditableFocus(editable)
}
""",
    """    if let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) {
        gtkDebugLog("sheet focus bridge editable root@\\(Int(rootX)),\\(Int(rootY))")
        gtkScheduleSheetEditableFocus(editable)
        return
    }
    guard !gtkSheetPointTargetsControl(root: root, rootX: rootX, rootY: rootY) else {
        gtkDebugLog("sheet focus bridge skipped control root@\\(Int(rootX)),\\(Int(rootY))")
        return
    }
    guard let editable = gtkFindFirstSheetEditable(in: panel) else {
        gtkDebugLog("sheet focus found NO editable at root@\\(Int(rootX)),\\(Int(rootY))")
        return
    }
    gtkDebugLog("sheet focus bridge editable root@\\(Int(rootX)),\\(Int(rootY))")
    gtkScheduleSheetEditableFocus(editable)
}
""",
)

bool_sheet_overlay = r'''        if gtkShouldRenderSheetInWindow() {
            let sheetView = sheetContent
            let binding = isPresented
            let userOnDismiss = onDismiss
            let dismissalConfig = gtkExtractDismissalConfig(from: sheetView)
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = dismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        binding.wrappedValue = false
                        lifecycleScope.runDisappearActions()
                        userOnDismiss?()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetView) }
                }
            )
            setCurrentEnvironment(previous)
            return opaqueFromWidget(gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget))
        }

        if gtkShouldRenderSheetInRootOverlay(),
           let rootOverlay = gtkSheetRootOverlay(for: anchor) {
            guard gtkRootSheetLayers[activeKey] == nil else {
                return opaqueFromWidget(widget)
            }
            let sheetView = sheetContent
            let binding = isPresented
            let userOnDismiss = onDismiss
            let dismissalConfig = gtkExtractDismissalConfig(from: sheetView)
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = dismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        binding.wrappedValue = false
                        lifecycleScope.runDisappearActions()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithRootSheetOverlay(rootOverlay) {
                        gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetView) }
                    }
                }
            )
            setCurrentEnvironment(previous)
            let panel = gtkCreateSheetOverlayPanel(sheetWidget: sheetWidget)
            let layer = gtkCreateSheetOverlayLayer(panel: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: layer)
            gtkStoreRootPresentationOverlay(rootOverlay, on: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)
            gtkRootSheetLayers[activeKey] = layer
            gtkAttachRootSheetOverlay(layer, to: rootOverlay)
            return opaqueFromWidget(widget)
        }

'''
if "gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget)" not in text:
    bool_marker = "        // Guard against duplicate presentation on rebuild\n"
    if bool_marker not in text:
        raise SystemExit("SwiftOpenUI bool sheet overlay insertion shape was not recognized")
    text = text.replace(bool_marker, bool_sheet_overlay + bool_marker, 1)

item_sheet_overlay = r'''        if gtkShouldRenderSheetInWindow() {
            let sheetBuilder = sheetContent
            let itemBinding = item
            let userOnDismiss = onDismiss
            let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = itemDismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        itemBinding.wrappedValue = nil
                        lifecycleScope.runDisappearActions()
                        userOnDismiss?()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetBuilder(currentItem)) }
                }
            )
            setCurrentEnvironment(previous)
            return opaqueFromWidget(gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget))
        }

        if gtkShouldRenderSheetInRootOverlay(),
           let rootOverlay = gtkSheetRootOverlay(for: anchor) {
            let currentIdHash = currentItem.id.hashValue
            gtkDebugLog("sheet item root present activeKey=\(activeKey) itemID=\(currentIdHash)")
            if gtkRootSheetLayers[activeKey] != nil {
                if gtkRootSheetItemIDs[activeKey] == currentIdHash {
                    return opaqueFromWidget(widget)
                }
                gtkRemoveSheetRootOverlay(
                    anchor: anchor,
                    overlayKey: overlayKey,
                    activeKey: activeKey,
                    itemIDKey: itemIDKey,
                    onDismiss: onDismiss
                )
            }
            gtkRootSheetItemIDs[activeKey] = currentIdHash
            let sheetBuilder = sheetContent
            let itemBinding = item
            let userOnDismiss = onDismiss
            let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = itemDismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        itemBinding.wrappedValue = nil
                        lifecycleScope.runDisappearActions()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
            setCurrentEnvironment(env)
            let sheetWidget = widgetFromOpaque(
                swiftOpenUIWithPresentationDismissAction(dismissAction) {
                    gtkWithRootSheetOverlay(rootOverlay) {
                        gtkWithSheetLifecycleScope(lifecycleScope) { gtkRenderView(sheetBuilder(currentItem)) }
                    }
                }
            )
            setCurrentEnvironment(previous)
            let panel = gtkCreateSheetOverlayPanel(sheetWidget: sheetWidget)
            let layer = gtkCreateSheetOverlayLayer(panel: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: layer)
            gtkStoreRootPresentationOverlay(rootOverlay, on: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)
            gtkRootSheetLayers[activeKey] = layer
            gtkAttachRootSheetOverlay(layer, to: rootOverlay)
            return opaqueFromWidget(widget)
        }
        gtkDebugLog("sheet item root unavailable activeKey=\(activeKey)")

'''
if "let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))" in text and text.count("gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget)") < 2:
    item_marker = "        // Check if the item identity changed while a sheet is already active\n"
    if item_marker not in text:
        raise SystemExit("SwiftOpenUI item sheet overlay insertion shape was not recognized")
    text = text.replace(item_marker, item_sheet_overlay + item_marker, 1)

old_root_sheet_remove = r'''private func gtkRemoveSheetRootOverlay(
    anchor: UnsafeMutablePointer<GtkWidget>,
    overlayKey: String,
    activeKey: String,
    itemIDKey: String? = nil,
    onDismiss: (() -> Void)? = nil
) {
    guard let layer = gtkRootSheetLayers.removeValue(forKey: activeKey) else {
        return
    }
    gtkRootSheetItemIDs[activeKey] = nil
    gtkDebugLog("sheet root dismiss activeKey=\\(activeKey)")
    gtk_widget_unparent(layer)
    // Clear any legacy per-anchor markers so a same-anchor re-render starts clean.
    let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, overlayKey, nil)
    g_object_set_data(gobject, activeKey, nil)
    if let itemIDKey {
        g_object_set_data(gobject, itemIDKey, nil)
    }
    onDismiss?()
}
'''
new_root_sheet_remove = r'''private func gtkRemoveSheetRootOverlay(
    anchor: UnsafeMutablePointer<GtkWidget>,
    overlayKey: String,
    activeKey: String,
    itemIDKey: String? = nil,
    onDismiss: (() -> Void)? = nil
) {
    guard gtkRemoveRootSheetLayer(activeKey: activeKey) else {
        return
    }
    // Clear any legacy per-anchor markers so a same-anchor re-render starts clean.
    let gobject = UnsafeMutableRawPointer(anchor).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, overlayKey, nil)
    g_object_set_data(gobject, activeKey, nil)
    if let itemIDKey {
        g_object_set_data(gobject, itemIDKey, nil)
    }
    onDismiss?()
}

@discardableResult
private func gtkRemoveRootSheetLayer(
    activeKey: String,
    fallbackLayer: UnsafeMutablePointer<GtkWidget>? = nil
) -> Bool {
    let layer: UnsafeMutablePointer<GtkWidget>
    let usedFallback: Bool
    if let registeredLayer = gtkRootSheetLayers.removeValue(forKey: activeKey) {
        layer = registeredLayer
        usedFallback = false
    } else if let fallbackLayer,
              gtk_swift_is_widget(fallbackLayer) != 0,
              gtk_widget_get_parent(fallbackLayer) != nil {
        layer = fallbackLayer
        usedFallback = true
    } else {
        gtkDebugLog("sheet root dismiss miss activeKey=\\(activeKey)")
        return false
    }
    gtkRootSheetItemIDs[activeKey] = nil
    gtkDebugLog("sheet root dismiss activeKey=\\(activeKey) fallback=\\(usedFallback)")
    gtk_widget_unparent(layer)
    return true
}
'''
if "private func gtkRemoveRootSheetLayer(" not in text and old_root_sheet_remove in text:
    text = text.replace(old_root_sheet_remove, new_root_sheet_remove, 1)

text = text.replace(
'''            let userOnDismiss = onDismiss
            let dismissalConfig = gtkExtractDismissalConfig(from: sheetView)
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = dismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        binding.wrappedValue = false
                        lifecycleScope.runDisappearActions()
                        userOnDismiss?()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
''',
'''            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    binding.wrappedValue = false
                    lifecycleScope.runDisappearActions()
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet bool window")
''',
)

text = text.replace(
'''            let userOnDismiss = onDismiss
            let dismissalConfig = gtkExtractDismissalConfig(from: sheetView)
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = dismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        binding.wrappedValue = false
                        lifecycleScope.runDisappearActions()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
''',
'''            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            var presentedLayer: UnsafeMutablePointer<GtkWidget>?
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    binding.wrappedValue = false
                    lifecycleScope.runDisappearActions()
                    _ = gtkRemoveRootSheetLayer(activeKey: activeKey, fallbackLayer: presentedLayer)
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet bool root overlay")
''',
)
text = text.replace(
'''            gtkRootSheetLayers[activeKey] = layer
            gtkAttachRootSheetOverlay(layer, to: rootOverlay)
''',
'''            presentedLayer = layer
            gtkRootSheetLayers[activeKey] = layer
            gtkAttachRootSheetOverlay(layer, to: rootOverlay)
''',
)

text = text.replace(
'''            let userOnDismiss = onDismiss
            let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = itemDismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        itemBinding.wrappedValue = nil
                        lifecycleScope.runDisappearActions()
                        userOnDismiss?()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
''',
'''            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    itemBinding.wrappedValue = nil
                    lifecycleScope.runDisappearActions()
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet item window")
''',
)

text = text.replace(
'''            let userOnDismiss = onDismiss
            let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            let dismissAction: () -> Void
            if let config = itemDismissalConfig {
                dismissAction = {
                    config.isPresented.wrappedValue = true
                }
            } else {
                dismissAction = {
                    gtkScheduleSheetDismissal {
                        itemBinding.wrappedValue = nil
                        lifecycleScope.runDisappearActions()
                    }
                }
            }
            env.dismiss = DismissAction(handler: dismissAction)
''',
'''            let userOnDismiss = onDismiss
            let lifecycleScope = GTKSheetLifecycleScope()
            let previous = getCurrentEnvironment()
            var env = previous
            var presentedLayer: UnsafeMutablePointer<GtkWidget>?
            let dismissAction: () -> Void
            dismissAction = {
                gtkScheduleSheetDismissal {
                    itemBinding.wrappedValue = nil
                    lifecycleScope.runDisappearActions()
                    _ = gtkRemoveRootSheetLayer(activeKey: activeKey, fallbackLayer: presentedLayer)
                    userOnDismiss?()
                }
            }
            env.dismiss = DismissAction(handler: dismissAction, debugName: "gtk sheet item root overlay")
''',
)
while '''            presentedLayer = layer
            presentedLayer = layer
''' in text:
    text = text.replace(
'''            presentedLayer = layer
            presentedLayer = layer
''',
'''            presentedLayer = layer
''',
    )

for debug_name in [
    "gtk sheet bool window",
    "gtk sheet bool root overlay",
    "gtk sheet bool dialog",
    "gtk sheet item window",
    "gtk sheet item root overlay",
    "gtk sheet item dialog",
]:
    text = text.replace(
        f'''            env.dismiss = DismissAction(handler: dismissAction, debugName: "{debug_name}")''',
        f'''            env = gtkSheetPresentationEnvironment(
                from: previous,
                dismissAction: dismissAction,
                debugName: "{debug_name}"
            )''',
    )

legacy_item_sheet_window_or_root_condition = (
    "        if gtkShouldRenderSheetInWindow() "
    + "|| gtkShouldRenderSheetInRootOverlay() {\n"
)
text = text.replace(
    legacy_item_sheet_window_or_root_condition
    + "            let sheetBuilder = sheetContent\n",
    "        if gtkShouldRenderSheetInWindow() {\n"
    "            let sheetBuilder = sheetContent\n",
)

text = text.replace(
    'gtk_window_set_default_size(dialogWin, 400, 300)',
    'gtk_window_set_default_size(dialogWin, gtkSheetDefaultWidth(), gtkSheetDefaultHeight())',
)

old_scroll = '''        let child = widgetFromOpaque(gtkRenderView(content))
        if axes.contains(.vertical) {
            gtk_widget_set_vexpand(child, 0)
        }
        if axes.contains(.horizontal) {
            gtk_widget_set_hexpand(child, 0)
        }
        gtk_scrolled_window_set_child(scrolledOp, child)
'''
new_scroll = '''        let child = widgetFromOpaque(gtkRenderView(content))
        if axes.contains(.vertical) {
            gtk_widget_set_vexpand(child, 0)
        }
        if axes.contains(.horizontal) {
            gtk_widget_set_hexpand(child, 0)
        }
        if axes.contains(.vertical) && !axes.contains(.horizontal) {
            // SwiftUI lays vertical ScrollView content out in the viewport
            // width. This lets rows that rely on HStack + Spacer, such as
            // chat bubbles and settings rows, align against the visible
            // scroll area instead of their natural text width.
            gtk_widget_set_hexpand(child, 1)
            gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        }
        if axes.contains(.horizontal) && !axes.contains(.vertical) {
            // A horizontal-only SwiftUI ScrollView has the natural height of
            // its content. If it advertises vertical expansion, fixed-height
            // rows such as IceCubes' status summary buttons allocate the
            // scroller as the row's fill child and push neighboring sections
            // below the fold. External FrameView constraints can still make
            // the scroller taller; the primitive itself should fit content.
            gtk_widget_set_vexpand(child, 0)
            gtk_widget_set_valign(child, GTK_ALIGN_START)
        }
        gtk_scrolled_window_set_child(scrolledOp, child)
'''
if "SwiftUI lays vertical ScrollView content out in the viewport" not in text:
    if old_scroll not in text:
        raise SystemExit("SwiftOpenUI ScrollView child sizing shape was not recognized")
    text = text.replace(old_scroll, new_scroll, 1)

if "gtk_scrolled_window_set_min_content_height(scrolledOp, 1)" not in text:
    old_scroll_natural_size = '''        if axes.contains(.horizontal) {
            gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
        }
        if axes.contains(.vertical) {
            gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)
        }
'''
    new_scroll_natural_size = '''        if axes.contains(.horizontal) {
            gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
            gtk_scrolled_window_set_min_content_width(scrolledOp, 1)
            if !axes.contains(.vertical) {
                gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 1)
            }
        }
        if axes.contains(.vertical) {
            gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)
            gtk_scrolled_window_set_min_content_height(scrolledOp, 1)
        }
'''
    if old_scroll_natural_size not in text:
        raise SystemExit("SwiftOpenUI ScrollView natural-size clamp shape was not recognized")
    text = text.replace(old_scroll_natural_size, new_scroll_natural_size, 1)
elif "gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 1)" not in text:
    horizontal_scroll_natural_width_marker = '''            gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
            gtk_scrolled_window_set_min_content_width(scrolledOp, 1)
'''
    if horizontal_scroll_natural_width_marker not in text:
        raise SystemExit("SwiftOpenUI horizontal ScrollView natural-height shape was not recognized")
    text = text.replace(
        horizontal_scroll_natural_width_marker,
        horizontal_scroll_natural_width_marker
        + '''            if !axes.contains(.vertical) {
                gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 1)
            }
''',
        1,
    )

text = text.replace("        let childWantsVerticalFill = gtkHasVerticalFillIntent(child)\n", "")

legacy_horizontal_scroll_child_sizing = '''        if axes.contains(.horizontal) && !axes.contains(.vertical) {
            gtk_widget_set_vexpand(child, 1)
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        }
'''
horizontal_scroll_child_sizing = '''        if axes.contains(.horizontal) && !axes.contains(.vertical) {
            // A horizontal-only SwiftUI ScrollView has the natural height of
            // its content. If it advertises vertical expansion, fixed-height
            // rows such as IceCubes' status summary buttons allocate the
            // scroller as the row's fill child and push neighboring sections
            // below the fold. External FrameView constraints can still make
            // the scroller taller; the primitive itself should fit content.
            gtk_widget_set_vexpand(child, 0)
            gtk_widget_set_valign(child, GTK_ALIGN_START)
        }
'''
if legacy_horizontal_scroll_child_sizing in text:
    text = text.replace(legacy_horizontal_scroll_child_sizing, horizontal_scroll_child_sizing, 1)

old_horizontal_scroll_child_sizing_with_comment = '''        if axes.contains(.horizontal) && !axes.contains(.vertical) {
            // A horizontal-only SwiftUI ScrollView has the natural height of
            // its content. If it advertises vertical expansion, fixed-height
            // rows such as IceCubes' status summary buttons allocate the
            // scroller as the row's fill child and clip neighboring labels.
            gtk_widget_set_vexpand(child, 0)
            gtk_widget_set_valign(child, GTK_ALIGN_CENTER)
        }
'''
if old_horizontal_scroll_child_sizing_with_comment in text:
    text = text.replace(old_horizontal_scroll_child_sizing_with_comment, horizontal_scroll_child_sizing, 1)

duplicate_scroll_cross_axis_install = '''        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: false
        )
        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: false
        )
'''
single_scroll_cross_axis_install = '''        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: false
        )
'''
if duplicate_scroll_cross_axis_install in text:
    text = text.replace(duplicate_scroll_cross_axis_install, single_scroll_cross_axis_install, 1)

scroll_helper_marker = "\n// MARK: - GTK rendering protocol\n"
scroll_helper = r'''
private final class GTKScrollViewCrossAxisContext {
    let child: UnsafeMutablePointer<GtkWidget>
    let fillWidth: Bool
    let fillHeight: Bool
    var lastWidth: gint = -1
    var lastHeight: gint = -1

    init(child: UnsafeMutablePointer<GtkWidget>, fillWidth: Bool, fillHeight: Bool) {
        self.child = child
        self.fillWidth = fillWidth
        self.fillHeight = fillHeight
    }
}

private let gtkScrollViewCrossAxisTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget, let userData else { return 0 }
    let context = Unmanaged<GTKScrollViewCrossAxisContext>.fromOpaque(userData).takeUnretainedValue()
    let width = gtk_widget_get_width(widget)
    let height = gtk_widget_get_height(widget)

    if context.fillWidth, width > 1, width != context.lastWidth {
        context.lastWidth = width
        let horizontalMargins = gtk_widget_get_margin_start(context.child)
            + gtk_widget_get_margin_end(context.child)
        gtk_widget_set_size_request(context.child, max(gint(1), width - horizontalMargins), -1)
        gtk_widget_queue_resize(context.child)
    }
    if context.fillWidth {
        gtkClampHiddenHorizontalScrollOffset(widget)
    }
    if context.fillHeight, height > 1, height != context.lastHeight {
        context.lastHeight = height
        let verticalMargins = gtk_widget_get_margin_top(context.child)
            + gtk_widget_get_margin_bottom(context.child)
        gtk_widget_set_size_request(context.child, -1, max(gint(1), height - verticalMargins))
        gtk_widget_queue_resize(context.child)
    }

    return 1
}

private func gtkClampHiddenHorizontalScrollOffset(_ scrolled: UnsafeMutablePointer<GtkWidget>) {
    guard let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) else {
        return
    }
    let lower = gtk_adjustment_get_lower(hadjustment)
    if gtk_adjustment_get_value(hadjustment) != lower {
        gtk_adjustment_set_value(hadjustment, lower)
    }
}

private func gtkInstallScrollViewCrossAxisFill(
    on scrolled: UnsafeMutablePointer<GtkWidget>,
    child: UnsafeMutablePointer<GtkWidget>,
    fillWidth: Bool,
    fillHeight: Bool
) {
    guard fillWidth || fillHeight else { return }
    let context = GTKScrollViewCrossAxisContext(
        child: child,
        fillWidth: fillWidth,
        fillHeight: fillHeight
    )
    let contextPtr = Unmanaged.passRetained(context).toOpaque()
    _ = gtk_widget_add_tick_callback(
        scrolled,
        gtkScrollViewCrossAxisTickCallback,
        contextPtr,
        { userData in Unmanaged<GTKScrollViewCrossAxisContext>.fromOpaque(userData!).release() }
    )
}

private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let anchor: UnitPoint?
    var remainingTicks: Int

    init(target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?, remainingTicks: Int = 180) {
        self.target = target
        self.anchor = anchor
        self.remainingTicks = remainingTicks
    }
}

private struct GTKPendingScrollRequest {
    let anchor: UnitPoint?
}

private var gtkScrollTargetRegistry: [AnyHashable: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkPendingScrollRequests: [AnyHashable: GTKPendingScrollRequest] = [:]

private func gtkRegisterScrollTarget(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    g_object_ref(gpointer(widget))
    if let previous = gtkScrollTargetRegistry.updateValue(widget, forKey: id) {
        g_object_unref(gpointer(previous))
    }
    registerViewID(id, element: widget)
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

private func gtkClampScrollValue(_ value: Double, lower: Double, upper: Double) -> Double {
    return min(max(value, lower), upper)
}

private func gtkApplyScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }

    var parent = gtk_widget_get_parent(target)
    while let scrolled = parent {
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(scrolled)))
        if typeName == "GtkScrolledWindow" {
            var targetX = 0.0
            var targetY = 0.0
            guard gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0 else { return }

            let anchorPoint = anchor ?? .top
            if let vadjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(vadjustment)
                let upper = gtk_adjustment_get_upper(vadjustment)
                let pageSize = gtk_adjustment_get_page_size(vadjustment)
                let currentValue = gtk_adjustment_get_value(vadjustment)
                let maxValue = max(lower, upper - pageSize)
                let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                if anchorPoint.y >= 1.0 {
                    gtk_adjustment_set_value(vadjustment, maxValue)
                } else {
                    let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                    gtk_adjustment_set_value(
                        vadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                }
            }

            if let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(hadjustment)
                let upper = gtk_adjustment_get_upper(hadjustment)
                let pageSize = gtk_adjustment_get_page_size(hadjustment)
                let currentValue = gtk_adjustment_get_value(hadjustment)
                let maxValue = max(lower, upper - pageSize)
                let targetWidth = max(1.0, Double(gtk_widget_get_width(target)))
                let desired = currentValue + targetX - ((pageSize - targetWidth) * anchorPoint.x)
                gtk_adjustment_set_value(
                    hadjustment,
                    gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                )
            }
            return
        }
        parent = gtk_widget_get_parent(scrolled)
    }
}

private func gtkScheduleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
    _ = g_timeout_add(16, { userData -> gboolean in
        guard let userData else { return 0 }
        let unmanaged = Unmanaged<GTKScrollToContext>.fromOpaque(userData)
        let context = unmanaged.takeUnretainedValue()
        guard gtk_swift_is_widget(context.target) != 0 else {
            g_object_unref(gpointer(context.target))
            unmanaged.release()
            return 0
        }
        gtkApplyScrollTo(context.target, anchor: context.anchor)
        context.remainingTicks -= 1
        if context.remainingTicks > 0 { return 1 }
        g_object_unref(gpointer(context.target))
        unmanaged.release()
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

private func gtkScheduleIdleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKScrollToContext>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(context.target)) }
        guard gtk_swift_is_widget(context.target) != 0 else { return 0 }
        gtkApplyOrScheduleScrollTo(context.target, anchor: context.anchor)
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

private func gtkApplyOrScheduleScrollTo(_ widget: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    gtkApplyScrollTo(widget, anchor: anchor)
    gtkScheduleScrollTo(widget, anchor: anchor)
}

private func gtkResolveOrQueueScrollTo(id: AnyHashable, anchor: UnitPoint?) {
    let request = GTKPendingScrollRequest(anchor: anchor)
    gtkPendingScrollRequests[id] = request
    guard let widget = gtkScrollTargetRegistry[id] else { return }
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

private func gtkResolvePendingScrollTo(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    guard let request = gtkPendingScrollRequests.removeValue(forKey: id) else { return }
    gtkScheduleIdleScrollTo(widget, anchor: request.anchor)
}

'''
scroll_to_helper = r'''
private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let anchor: UnitPoint?
    var remainingTicks: Int

    init(target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?, remainingTicks: Int = 180) {
        self.target = target
        self.anchor = anchor
        self.remainingTicks = remainingTicks
    }
}

private struct GTKPendingScrollRequest {
    let anchor: UnitPoint?
}

private var gtkScrollTargetRegistry: [AnyHashable: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkPendingScrollRequests: [AnyHashable: GTKPendingScrollRequest] = [:]

private func gtkRegisterScrollTarget(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    g_object_ref(gpointer(widget))
    if let previous = gtkScrollTargetRegistry.updateValue(widget, forKey: id) {
        g_object_unref(gpointer(previous))
    }
    registerViewID(id, element: widget)
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

private func gtkClampScrollValue(_ value: Double, lower: Double, upper: Double) -> Double {
    return min(max(value, lower), upper)
}

private func gtkApplyScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }

    var parent = gtk_widget_get_parent(target)
    while let scrolled = parent {
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(scrolled)))
        if typeName == "GtkScrolledWindow" {
            var targetX = 0.0
            var targetY = 0.0
            guard gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0 else { return }

            let anchorPoint = anchor ?? .top
            if let vadjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(vadjustment)
                let upper = gtk_adjustment_get_upper(vadjustment)
                let pageSize = gtk_adjustment_get_page_size(vadjustment)
                let currentValue = gtk_adjustment_get_value(vadjustment)
                let maxValue = max(lower, upper - pageSize)
                let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                if anchorPoint.y >= 1.0 {
                    gtk_adjustment_set_value(vadjustment, maxValue)
                } else {
                    let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                    gtk_adjustment_set_value(
                        vadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                }
            }

            if let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(hadjustment)
                let upper = gtk_adjustment_get_upper(hadjustment)
                let pageSize = gtk_adjustment_get_page_size(hadjustment)
                let currentValue = gtk_adjustment_get_value(hadjustment)
                let maxValue = max(lower, upper - pageSize)
                let targetWidth = max(1.0, Double(gtk_widget_get_width(target)))
                let desired = currentValue + targetX - ((pageSize - targetWidth) * anchorPoint.x)
                gtk_adjustment_set_value(
                    hadjustment,
                    gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                )
            }
            return
        }
        parent = gtk_widget_get_parent(scrolled)
    }
}

private func gtkScheduleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
    _ = g_timeout_add(16, { userData -> gboolean in
        guard let userData else { return 0 }
        let unmanaged = Unmanaged<GTKScrollToContext>.fromOpaque(userData)
        let context = unmanaged.takeUnretainedValue()
        guard gtk_swift_is_widget(context.target) != 0 else {
            g_object_unref(gpointer(context.target))
            unmanaged.release()
            return 0
        }
        gtkApplyScrollTo(context.target, anchor: context.anchor)
        context.remainingTicks -= 1
        if context.remainingTicks > 0 { return 1 }
        g_object_unref(gpointer(context.target))
        unmanaged.release()
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

private func gtkScheduleIdleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKScrollToContext>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(context.target)) }
        guard gtk_swift_is_widget(context.target) != 0 else { return 0 }
        gtkApplyOrScheduleScrollTo(context.target, anchor: context.anchor)
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

private func gtkApplyOrScheduleScrollTo(_ widget: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    gtkApplyScrollTo(widget, anchor: anchor)
    gtkScheduleScrollTo(widget, anchor: anchor)
}

private func gtkResolveOrQueueScrollTo(id: AnyHashable, anchor: UnitPoint?) {
    let request = GTKPendingScrollRequest(anchor: anchor)
    gtkPendingScrollRequests[id] = request
    guard let widget = gtkScrollTargetRegistry[id] else { return }
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

private func gtkResolvePendingScrollTo(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    guard let request = gtkPendingScrollRequests.removeValue(forKey: id) else { return }
    gtkScheduleIdleScrollTo(widget, anchor: request.anchor)
}

'''
if "GTKScrollViewCrossAxisContext" not in text:
    if scroll_helper_marker not in text:
        raise SystemExit("SwiftOpenUI renderer protocol marker was not recognized")
    text = text.replace(scroll_helper_marker, "\n" + scroll_helper + scroll_helper_marker, 1)
elif "GTKScrollToContext" not in text:
    if scroll_helper_marker not in text:
        raise SystemExit("SwiftOpenUI renderer protocol marker was not recognized")
    text = text.replace(scroll_helper_marker, "\n" + scroll_to_helper + scroll_helper_marker, 1)
elif "gtkPendingScrollRequests" not in text:
    old_scroll_context_init = '''private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let anchor: UnitPoint?

    init(target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
        self.target = target
        self.anchor = anchor
    }
}

'''
    new_scroll_context_init = '''private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let anchor: UnitPoint?
    var remainingTicks: Int

    init(target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?, remainingTicks: Int = 180) {
        self.target = target
        self.anchor = anchor
        self.remainingTicks = remainingTicks
    }
}

private struct GTKPendingScrollRequest {
    let anchor: UnitPoint?
}

private var gtkScrollTargetRegistry: [AnyHashable: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkPendingScrollRequests: [AnyHashable: GTKPendingScrollRequest] = [:]

private func gtkRegisterScrollTarget(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    g_object_ref(gpointer(widget))
    if let previous = gtkScrollTargetRegistry.updateValue(widget, forKey: id) {
        g_object_unref(gpointer(previous))
    }
    registerViewID(id, element: widget)
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

'''
    if old_scroll_context_init not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader context upgrade shape was not recognized")
    text = text.replace(old_scroll_context_init, new_scroll_context_init, 1)
if "private func gtkClampHiddenHorizontalScrollOffset" not in text:
    old_scroll_cross_axis_clamp = '''    if context.fillWidth, width > 1, width != context.lastWidth {
        context.lastWidth = width
        gtk_widget_set_size_request(context.child, width, -1)
        gtk_widget_queue_resize(context.child)
    }
    if context.fillHeight, height > 1, height != context.lastHeight {
'''
    new_scroll_cross_axis_clamp = '''    if context.fillWidth, width > 1, width != context.lastWidth {
        context.lastWidth = width
        gtk_widget_set_size_request(context.child, width, -1)
        gtk_widget_queue_resize(context.child)
    }
    if context.fillWidth {
        gtkClampHiddenHorizontalScrollOffset(widget)
    }
    if context.fillHeight, height > 1, height != context.lastHeight {
'''
    scroll_cross_axis_helper_marker = '''private func gtkInstallScrollViewCrossAxisFill(
'''
    scroll_cross_axis_clamp_helper = '''private func gtkClampHiddenHorizontalScrollOffset(_ scrolled: UnsafeMutablePointer<GtkWidget>) {
    guard let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) else {
        return
    }
    let lower = gtk_adjustment_get_lower(hadjustment)
    if gtk_adjustment_get_value(hadjustment) != lower {
        gtk_adjustment_set_value(hadjustment, lower)
    }
}

'''
    if old_scroll_cross_axis_clamp not in text:
        raise SystemExit("SwiftOpenUI ScrollView hidden horizontal clamp shape was not recognized")
    if scroll_cross_axis_helper_marker not in text:
        raise SystemExit("SwiftOpenUI ScrollView hidden horizontal clamp helper marker was not recognized")
    text = text.replace(old_scroll_cross_axis_clamp, new_scroll_cross_axis_clamp, 1)
    text = text.replace(scroll_cross_axis_helper_marker, scroll_cross_axis_clamp_helper + scroll_cross_axis_helper_marker, 1)
if "remainingTicks: Int = 4" in text:
    text = text.replace("remainingTicks: Int = 4", "remainingTicks: Int = 180")
old_apply_scroll = '''private func gtkApplyScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }

    var parent = gtk_widget_get_parent(target)
    while let scrolled = parent {
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(scrolled)))
        if typeName == "GtkScrolledWindow" {
            var targetX = 0.0
            var targetY = 0.0
            guard gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0 else { return }

            let anchorPoint = anchor ?? .top
            if let vadjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(vadjustment)
                let upper = gtk_adjustment_get_upper(vadjustment)
                let pageSize = gtk_adjustment_get_page_size(vadjustment)
                let currentValue = gtk_adjustment_get_value(vadjustment)
                let maxValue = max(lower, upper - pageSize)
                let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                if anchorPoint.y >= 1.0 {
                    gtk_adjustment_set_value(vadjustment, maxValue)
                } else {
                    let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                    gtk_adjustment_set_value(
                        vadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                }
            }

            if let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(hadjustment)
                let upper = gtk_adjustment_get_upper(hadjustment)
                let pageSize = gtk_adjustment_get_page_size(hadjustment)
                let currentValue = gtk_adjustment_get_value(hadjustment)
                let maxValue = max(lower, upper - pageSize)
                let targetWidth = max(1.0, Double(gtk_widget_get_width(target)))
                let desired = currentValue + targetX - ((pageSize - targetWidth) * anchorPoint.x)
                gtk_adjustment_set_value(
                    hadjustment,
                    gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                )
            }
            return
        }
        parent = gtk_widget_get_parent(scrolled)
    }
}
'''
new_apply_scroll = '''private func gtkApplyScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }

    var parent = gtk_widget_get_parent(target)
    while let scrolled = parent {
        let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(scrolled)))
        if typeName == "GtkScrolledWindow" {
            var targetX = 0.0
            var targetY = 0.0
            guard gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0 else {
                parent = gtk_widget_get_parent(scrolled)
                continue
            }

            let anchorPoint = anchor ?? .top
            var applied = false
            if let vadjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(vadjustment)
                let upper = gtk_adjustment_get_upper(vadjustment)
                let pageSize = gtk_adjustment_get_page_size(vadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(vadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                    if anchorPoint.y >= 1.0 {
                        gtk_adjustment_set_value(vadjustment, maxValue)
                    } else {
                        let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                        gtk_adjustment_set_value(
                            vadjustment,
                            gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                        )
                    }
                    applied = true
                }
            }

            if let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(hadjustment)
                let upper = gtk_adjustment_get_upper(hadjustment)
                let pageSize = gtk_adjustment_get_page_size(hadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(hadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetWidth = max(1.0, Double(gtk_widget_get_width(target)))
                    let desired = currentValue + targetX - ((pageSize - targetWidth) * anchorPoint.x)
                    gtk_adjustment_set_value(
                        hadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                    applied = true
                }
            }
            if applied { return }
        }
        parent = gtk_widget_get_parent(scrolled)
    }
}
'''
if old_apply_scroll in text:
    text = text.replace(old_apply_scroll, new_apply_scroll)
elif (
    "private func gtkApplyScrollTo(" in text
    and "var applied = false" not in text
    and "let requiresVerticalAnchor = anchorPoint.y > 0.0" not in text
):
    raise SystemExit("SwiftOpenUI ScrollViewReader scroll-range upgrade shape was not recognized")
if "anchorPoint.y >= 1.0" not in text:
    old_bottom_anchor_scroll = '''                    let currentValue = gtk_adjustment_get_value(vadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                    let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                    gtk_adjustment_set_value(
                        vadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                    applied = true
'''
    new_bottom_anchor_scroll = '''                    let currentValue = gtk_adjustment_get_value(vadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                    if anchorPoint.y >= 1.0 {
                        gtk_adjustment_set_value(vadjustment, maxValue)
                    } else {
                        let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                        gtk_adjustment_set_value(
                            vadjustment,
                            gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                        )
                    }
                    applied = true
'''
    if old_bottom_anchor_scroll not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader bottom-anchor scroll shape was not recognized")
    text = text.replace(old_bottom_anchor_scroll, new_bottom_anchor_scroll, 1)
if "gtkScrollTargetRegistry" not in text:
    old_scroll_registry = '''private var gtkPendingScrollRequests: [AnyHashable: GTKPendingScrollRequest] = [:]

'''
    new_scroll_registry = '''private var gtkScrollTargetRegistry: [AnyHashable: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkPendingScrollRequests: [AnyHashable: GTKPendingScrollRequest] = [:]

private func gtkRegisterScrollTarget(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    g_object_ref(gpointer(widget))
    if let previous = gtkScrollTargetRegistry.updateValue(widget, forKey: id) {
        g_object_unref(gpointer(previous))
    }
    registerViewID(id, element: widget)
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

'''
    if old_scroll_registry not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader GTK target registry shape was not recognized")
    text = text.replace(old_scroll_registry, new_scroll_registry, 1)
if "context.remainingTicks -= 1" not in text:
    text = text.replace(
        '''    gtkApplyScrollTo(context.target, anchor: context.anchor)
    return 0
}
''',
        '''    gtkApplyScrollTo(context.target, anchor: context.anchor)
    context.remainingTicks -= 1
    return context.remainingTicks > 0 ? 1 : 0
}
''',
        1,
    )
if "gtkApplyOrScheduleScrollTo(_ widget" not in text and "private func gtkScheduleScrollTo(_ target" in text:
    schedule_end = '''    _ = gtk_widget_add_tick_callback(
        target,
        gtkScrollToTickCallback,
        Unmanaged.passRetained(context).toOpaque(),
        { userData in Unmanaged<GTKScrollToContext>.fromOpaque(userData!).release() }
    )
}

'''
    timeout_schedule_end = '''    g_object_ref(gpointer(target))
    _ = g_timeout_add(16, { userData -> gboolean in
        guard let userData else { return 0 }
        let unmanaged = Unmanaged<GTKScrollToContext>.fromOpaque(userData)
        let context = unmanaged.takeUnretainedValue()
        guard gtk_swift_is_widget(context.target) != 0 else {
            g_object_unref(gpointer(context.target))
            unmanaged.release()
            return 0
        }
        gtkApplyScrollTo(context.target, anchor: context.anchor)
        context.remainingTicks -= 1
        if context.remainingTicks > 0 { return 1 }
        g_object_unref(gpointer(context.target))
        unmanaged.release()
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

'''
    text = text.replace(
        schedule_end,
        timeout_schedule_end + '''private func gtkApplyOrScheduleScrollTo(_ widget: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    gtkApplyScrollTo(widget, anchor: anchor)
    gtkScheduleScrollTo(widget, anchor: anchor)
}

private func gtkResolveOrQueueScrollTo(id: AnyHashable, anchor: UnitPoint?) {
    guard
        let widget = lookupViewID(id) as? UnsafeMutablePointer<GtkWidget>,
        gtk_swift_is_widget(widget) != 0
    else {
        gtkPendingScrollRequests[id] = GTKPendingScrollRequest(anchor: anchor)
        return
    }
    gtkApplyOrScheduleScrollTo(widget, anchor: anchor)
}

private func gtkResolvePendingScrollTo(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    guard let request = gtkPendingScrollRequests.removeValue(forKey: id) else { return }
    gtkScheduleIdleScrollTo(widget, anchor: request.anchor)
}

		''',
        1,
    )

if (
    "gtkScheduleIdleScrollTo(_ target" not in text
    and "gtkScheduleIdleScrollTo(id: AnyHashable? = nil, _ target" not in text
    and "private func gtkScheduleIdleScrollTo(" not in text
):
    idle_helper_marker = '''private func gtkApplyOrScheduleScrollTo(_ widget: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    gtkApplyScrollTo(widget, anchor: anchor)
    gtkScheduleScrollTo(widget, anchor: anchor)
}

'''
    idle_helper = '''private func gtkScheduleIdleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKScrollToContext>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(context.target)) }
        guard gtk_swift_is_widget(context.target) != 0 else { return 0 }
        gtkApplyOrScheduleScrollTo(context.target, anchor: context.anchor)
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

'''
    if idle_helper_marker not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader idle scroll insertion shape was not recognized")
    text = text.replace(idle_helper_marker, idle_helper + idle_helper_marker, 1)

old_idle_helper = '''private func gtkScheduleIdleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    let context = GTKScrollToContext(target: target, anchor: anchor)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKScrollToContext>.fromOpaque(userData).takeRetainedValue()
        gtkApplyOrScheduleScrollTo(context.target, anchor: context.anchor)
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

'''
new_idle_helper = '''private func gtkScheduleIdleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
    _ = g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKScrollToContext>.fromOpaque(userData).takeRetainedValue()
        defer { g_object_unref(gpointer(context.target)) }
        guard gtk_swift_is_widget(context.target) != 0 else { return 0 }
        gtkApplyOrScheduleScrollTo(context.target, anchor: context.anchor)
        return 0
    }, Unmanaged.passRetained(context).toOpaque())
}

'''
if old_idle_helper in text:
    text = text.replace(old_idle_helper, new_idle_helper, 1)
elif (
    (
        "gtkScheduleIdleScrollTo(_ target" in text
        or "gtkScheduleIdleScrollTo(id: AnyHashable? = nil, _ target" in text
    )
    and "g_object_ref(gpointer(target))" not in text
):
    raise SystemExit("SwiftOpenUI ScrollViewReader idle scroll ownership shape was not recognized")

old_resolve_pending = '''private func gtkResolvePendingScrollTo(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    guard let request = gtkPendingScrollRequests.removeValue(forKey: id) else { return }
    gtkApplyOrScheduleScrollTo(widget, anchor: request.anchor)
}

'''
new_resolve_pending = '''private func gtkResolvePendingScrollTo(id: AnyHashable, widget: UnsafeMutablePointer<GtkWidget>) {
    guard let request = gtkPendingScrollRequests.removeValue(forKey: id) else { return }
    gtkScheduleIdleScrollTo(widget, anchor: request.anchor)
}

'''
if old_resolve_pending in text:
    text = text.replace(old_resolve_pending, new_resolve_pending, 1)
elif (
    "gtkScheduleIdleScrollTo(widget, anchor: request.anchor)" not in text
    and "gtkScheduleIdleScrollTo(id: id, widget, anchor: request.anchor)" not in text
):
    raise SystemExit("SwiftOpenUI ScrollViewReader pending scroll shape was not recognized")

old_resolve_or_queue = '''private func gtkResolveOrQueueScrollTo(id: AnyHashable, anchor: UnitPoint?) {
    guard
        let widget = lookupViewID(id) as? UnsafeMutablePointer<GtkWidget>,
        gtk_swift_is_widget(widget) != 0
    else {
        gtkPendingScrollRequests[id] = GTKPendingScrollRequest(anchor: anchor)
        return
    }
    gtkApplyOrScheduleScrollTo(widget, anchor: anchor)
}

'''
new_resolve_or_queue = '''private func gtkResolveOrQueueScrollTo(id: AnyHashable, anchor: UnitPoint?) {
    let request = GTKPendingScrollRequest(anchor: anchor)
    gtkPendingScrollRequests[id] = request
    guard let widget = gtkScrollTargetRegistry[id] else { return }
    gtkResolvePendingScrollTo(id: id, widget: widget)
}

'''
if old_resolve_or_queue in text:
    text = text.replace(old_resolve_or_queue, new_resolve_or_queue)
elif (
    "let request = GTKPendingScrollRequest(anchor: anchor)" not in text
    and "gtkPendingScrollRequests[anyID] = GTKPendingScrollRequest(anchor: anchor)" not in text
):
    raise SystemExit("SwiftOpenUI ScrollViewReader request queue shape was not recognized")
elif (
    "private func gtkResolveOrQueueScrollTo" in text
    and "lookupViewID(id) as? UnsafeMutablePointer<GtkWidget>" in text
):
    stale_resolve_or_queue = '''private func gtkResolveOrQueueScrollTo(id: AnyHashable, anchor: UnitPoint?) {
    let request = GTKPendingScrollRequest(anchor: anchor)
    gtkPendingScrollRequests[id] = request
    guard
        let widget = lookupViewID(id) as? UnsafeMutablePointer<GtkWidget>,
        gtk_swift_is_widget(widget) != 0
    else { return }
    gtkApplyOrScheduleScrollTo(widget, anchor: anchor)
}

'''
    if stale_resolve_or_queue not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader request queue stale-lookup shape was not recognized")
    text = text.replace(stale_resolve_or_queue, new_resolve_or_queue)

on_appear_helper = r'''
private let gtkOnAppearTickCallback: GtkTickCallback = { _, _, userData in
    guard let userData else { return 0 }
    let box = Unmanaged<ClosureBox>.fromOpaque(userData).takeUnretainedValue()
    box.closure()
    return 0
}

private func gtkScheduleOnAppear(_ action: @escaping () -> Void, on widget: UnsafeMutablePointer<GtkWidget>) {
    let box = Unmanaged.passRetained(ClosureBox(action)).toOpaque()
    _ = gtk_widget_add_tick_callback(
        widget,
        gtkOnAppearTickCallback,
        box,
        { userData in Unmanaged<ClosureBox>.fromOpaque(userData!).release() }
    )
}

'''
if "gtkScheduleOnAppear(_ action" not in text:
    if scroll_helper_marker not in text:
        raise SystemExit("SwiftOpenUI renderer protocol marker was not recognized")
    text = text.replace(scroll_helper_marker, "\n" + on_appear_helper + scroll_helper_marker, 1)
if "gtkInstallScrollViewCrossAxisFill(on: scrolled" not in text:
    text = text.replace(
        "        gtk_scrolled_window_set_child(scrolledOp, child)\n",
        """        gtk_scrolled_window_set_child(scrolledOp, child)
        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: false
        )
""",
        1,
    )

legacy_scroll_view_expansion = '''        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: false
        )

        gtk_widget_set_vexpand(scrolled, 1)
        gtk_widget_set_hexpand(scrolled, 1)
'''
scroll_view_expansion = '''        gtkInstallScrollViewCrossAxisFill(
            on: scrolled,
            child: child,
            fillWidth: axes.contains(.vertical) && !axes.contains(.horizontal),
            fillHeight: false
        )

        let scrollerWantsVerticalFill = axes.contains(.vertical)
        gtk_widget_set_vexpand(scrolled, scrollerWantsVerticalFill ? 1 : 0)
        gtk_widget_set_valign(scrolled, scrollerWantsVerticalFill ? GTK_ALIGN_FILL : GTK_ALIGN_START)
        if scrollerWantsVerticalFill {
            gtkMarkVerticalFillIntent(scrolled)
        }
        gtk_widget_set_hexpand(scrolled, 1)
'''
legacy_axis_vexpand = "gtk_widget_set_vexpand(scrolled, axes.contains(.vertical) ? " + "1 : 0)"
if legacy_scroll_view_expansion in text:
    text = text.replace(legacy_scroll_view_expansion, scroll_view_expansion, 1)
elif legacy_axis_vexpand in text:
    text = text.replace(
        "        " + legacy_axis_vexpand + "\n        gtk_widget_set_hexpand(scrolled, 1)\n",
        "        let scrollerWantsVerticalFill = axes.contains(.vertical)\n        gtk_widget_set_vexpand(scrolled, scrollerWantsVerticalFill ? 1 : 0)\n        gtk_widget_set_valign(scrolled, scrollerWantsVerticalFill ? GTK_ALIGN_FILL : GTK_ALIGN_START)\n        if scrollerWantsVerticalFill {\n            gtkMarkVerticalFillIntent(scrolled)\n        }\n        gtk_widget_set_hexpand(scrolled, 1)\n",
        1,
    )
elif "gtk_widget_set_vexpand(scrolled, scrollerWantsVerticalFill ? 1 : 0)" not in text:
    raise SystemExit("SwiftOpenUI ScrollView expansion shape was not recognized")
elif "gtk_widget_set_valign(scrolled, scrollerWantsVerticalFill ? GTK_ALIGN_FILL : GTK_ALIGN_START)" not in text:
    text = text.replace(
        "        gtk_widget_set_vexpand(scrolled, scrollerWantsVerticalFill ? 1 : 0)\n        if scrollerWantsVerticalFill {\n",
        "        gtk_widget_set_vexpand(scrolled, scrollerWantsVerticalFill ? 1 : 0)\n        gtk_widget_set_valign(scrolled, scrollerWantsVerticalFill ? GTK_ALIGN_FILL : GTK_ALIGN_START)\n        if scrollerWantsVerticalFill {\n",
        1,
    )

legacy_lazy_list_expansion = '''    gtk_widget_set_vexpand(scrolled, 1)
    gtk_widget_set_hexpand(scrolled, 1)
    applyCSSToWidget(scrolled, properties: "background-color: transparent;")
'''
lazy_list_expansion = '''    gtk_widget_set_vexpand(scrolled, orientation == GTK_ORIENTATION_VERTICAL ? 1 : 0)
    gtk_widget_set_hexpand(scrolled, 1)
    applyCSSToWidget(scrolled, properties: "background-color: transparent;")
'''
if legacy_lazy_list_expansion in text:
    text = text.replace(legacy_lazy_list_expansion, lazy_list_expansion, 1)
elif "gtk_widget_set_vexpand(scrolled, orientation == GTK_ORIENTATION_VERTICAL ? 1 : 0)" not in text:
    raise SystemExit("SwiftOpenUI LazyHStack expansion shape was not recognized")

legacy_static_lazy_stack_render = '''    for item in items {
        let child = widgetFromOpaque(gtkRenderView(contentBuilder(item)))
        renderedChildren.append(child)
        gtk_box_append(boxPointer(box), child)
    }
'''
flattened_static_lazy_stack_render = '''    for item in items {
        for renderedChild in gtkRenderChildren(contentBuilder(item)) {
            let child = widgetFromOpaque(renderedChild)
            if gtkIsEmptyViewWidget(child) { continue }
            renderedChildren.append(child)
            gtk_box_append(boxPointer(box), child)
        }
    }
'''
aligned_static_lazy_stack_render = '''    for item in items {
        for renderedChild in gtkRenderChildren(contentBuilder(item)) {
            let child = widgetFromOpaque(renderedChild)
            if gtkIsEmptyViewWidget(child) { continue }
            if orientation == GTK_ORIENTATION_VERTICAL {
                gtk_widget_set_halign(
                    child,
                    gtk_widget_get_hexpand(child) != 0 ? GTK_ALIGN_FILL : crossAxisAlignment
                )
            } else {
                gtk_widget_set_valign(
                    child,
                    gtk_widget_get_vexpand(child) != 0 ? GTK_ALIGN_FILL : crossAxisAlignment
                )
            }
            renderedChildren.append(child)
            gtk_box_append(boxPointer(box), child)
        }
    }
'''
if legacy_static_lazy_stack_render in text:
    text = text.replace(legacy_static_lazy_stack_render, aligned_static_lazy_stack_render, 1)
elif flattened_static_lazy_stack_render in text:
    text = text.replace(flattened_static_lazy_stack_render, aligned_static_lazy_stack_render, 1)
elif aligned_static_lazy_stack_render not in text:
    raise SystemExit("SwiftOpenUI builder-style lazy stack child flattening shape was not recognized")

has_list_renderer_region = (
    "extension List: GTKRenderable" in text
    or "let listBox = gtk_list_box_new()" in text
    or "gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox" in text
)
if has_list_renderer_region and "gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox" not in text:
    old_list_width_propagation = "        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 1)\n"
    new_list_width_propagation = """        // A vertical SwiftUI List lays rows out in the viewport width.
        // Propagating natural width lets fixed-width row content push
        // trailing controls outside the visible sheet.
        gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
"""
    if old_list_width_propagation not in text:
        raise SystemExit("SwiftOpenUI List natural-width propagation shape was not recognized")
    text = text.replace(old_list_width_propagation, new_list_width_propagation, 1)

    old_list_row = """            let row = gtk_list_box_row_new()!
            gtk_list_box_row_set_child(
"""
    new_list_row = """            let row = gtk_list_box_row_new()!
            gtk_widget_set_hexpand(row, 1)
            gtk_widget_set_halign(row, GTK_ALIGN_FILL)
            gtk_list_box_row_set_child(
"""
    if old_list_row not in text:
        raise SystemExit("SwiftOpenUI List row expansion shape was not recognized")
    text = text.replace(old_list_row, new_list_row, 1)

    old_list_child = """        gtk_scrolled_window_set_child(scrolledOp, listBox)
        gtk_widget_set_vexpand(scrolled, 1)
"""
    new_list_child = """        gtk_scrolled_window_set_child(scrolledOp, listBox)
        // A short SwiftUI List still occupies the viewport and packs rows
        // from the top. GTK's scrolled-window viewport can otherwise center
        // the natural-height listbox vertically, which made IceCubes'
        // Explore quick-access row appear halfway down the screen.
        gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: true)
        gtk_widget_set_vexpand(scrolled, 1)
"""
    if old_list_child not in text:
        raise SystemExit("SwiftOpenUI List cross-axis fill shape was not recognized")
    text = text.replace(old_list_child, new_list_child, 1)

if has_list_renderer_region:
    old_list_row_height = '''private func gtkListRowMinimumHeight(for view: any View) -> gint {
    let environmentMinimum = max(gint(1), gint(getCurrentEnvironment().defaultMinListRowHeight))
    if let explicitHeight = gtkExplicitFrameHeight(in: view) {
        return max(environmentMinimum, gtkPixelSize(explicitHeight))
    }
    let contentMinimum = gtkViewIsPlainTextRow(view)
        ? gtkPlainListRowMinimumHeight
        : gtkComplexListRowMinimumHeight
    return max(environmentMinimum, contentMinimum)
}
'''
    new_list_row_height = '''private func gtkListRowMinimumHeight(for view: any View) -> gint {
    let environmentMinimum = max(gint(1), gint(getCurrentEnvironment().defaultMinListRowHeight))
    if let explicitHeight = gtkExplicitFrameHeight(in: view) {
        return max(environmentMinimum, gtkPixelSize(explicitHeight))
    }
    return environmentMinimum
}

private func gtkListRowEstimatedHeight(for view: any View) -> gint {
    let minimumHeight = gtkListRowMinimumHeight(for: view)
    if gtkExplicitFrameHeight(in: view) != nil {
        return minimumHeight
    }
    let contentMinimum = gtkViewIsPlainTextRow(view)
        ? gtkPlainListRowMinimumHeight
        : gtkComplexListRowMinimumHeight
    return max(minimumHeight, contentMinimum)
}
'''
    if old_list_row_height in text:
        text = text.replace(old_list_row_height, new_list_row_height, 1)
    elif "private func gtkListRowEstimatedHeight(for view: any View) -> gint" not in text:
        raise SystemExit("SwiftOpenUI List row minimum-height shape was not recognized")

    if "let estimatedHeight = gtkListRowEstimatedHeight(for: child)" not in text:
        old_list_row_estimate_call = """            let metadata = gtkRowMetadata(from: child)
            let minimumHeight = gtkListRowMinimumHeight(for: child)
            let rowSource = String(reflecting: Swift.type(of: child))
"""
        new_list_row_estimate_call = """            let metadata = gtkRowMetadata(from: child)
            let minimumHeight = gtkListRowMinimumHeight(for: child)
            let estimatedHeight = gtkListRowEstimatedHeight(for: child)
            let rowSource = String(reflecting: Swift.type(of: child))
"""
        if old_list_row_estimate_call not in text:
            raise SystemExit("SwiftOpenUI List row estimated-height call shape was not recognized")
        text = text.replace(old_list_row_estimate_call, new_list_row_estimate_call, 1)

    text = text.replace(
        "                estimatedHeight: Double(minimumHeight),\n",
        "                estimatedHeight: Double(estimatedHeight),\n",
        1,
    )
    text = text.replace(
        "        gtk_widget_set_vexpand(listBox, 0)\n",
        "        gtk_widget_set_vexpand(listBox, 1)\n",
    )
    text = text.replace(
        "        gtk_widget_set_valign(listBox, GTK_ALIGN_START)\n",
        "        gtk_widget_set_valign(listBox, GTK_ALIGN_FILL)\n",
    )
    text = text.replace(
        "gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: false)",
        "gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: true)",
    )
    text = text.replace(
        "        gtk_widget_set_vexpand(scrolled, 1)\n        gtk_widget_set_hexpand(scrolled, 1)\n\n        return opaqueFromWidget(scrolled)\n",
        "        gtk_widget_set_vexpand(scrolled, 1)\n        gtk_widget_set_hexpand(scrolled, 1)\n        gtkMarkVerticalFillIntent(scrolled)\n\n        return opaqueFromWidget(scrolled)\n",
    )

old_scroll_reader = '''        proxy.scrollToAction = { anyID, anchor in
            guard let widget = lookupViewID(anyID) as? UnsafeMutablePointer<GtkWidget> else { return }
            // Verify the widget is still alive before operating on it
            guard gtk_swift_is_widget(widget) != 0 else { return }
            // Find the enclosing GtkScrolledWindow and scroll to the widget.
            var parent = gtk_widget_get_parent(widget)
            while let p = parent {
                let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(p)))
                if typeName == "GtkScrolledWindow" {
                    // Temporarily make the widget focusable so grab_focus
                    // triggers GTK4 auto-scroll. Restore after.
                    let wasFocusable = gtk_widget_get_focusable(widget)
                    gtk_widget_set_focusable(widget, 1)
                    gtk_widget_grab_focus(widget)
                    gtk_widget_set_focusable(widget, wasFocusable)
                    break
                }
                parent = gtk_widget_get_parent(p)
            }
        }
'''
new_scroll_reader = '''        proxy.scrollToAction = { anyID, anchor in
            gtkResolveOrQueueScrollTo(id: anyID, anchor: anchor)
        }
'''
if "gtkResolveOrQueueScrollTo(id: anyID, anchor: anchor)" not in text and old_scroll_reader in text:
    text = text.replace(old_scroll_reader, new_scroll_reader, 1)
elif "gtkResolveOrQueueScrollTo(id: anyID, anchor: anchor)" not in text:
    text = text.replace(
        """        proxy.scrollToAction = { anyID, anchor in
            guard let widget = lookupViewID(anyID) as? UnsafeMutablePointer<GtkWidget> else { return }
            guard gtk_swift_is_widget(widget) != 0 else { return }
            gtkApplyScrollTo(widget, anchor: anchor)
            gtkScheduleScrollTo(widget, anchor: anchor)
        }
""",
        new_scroll_reader,
        1,
    )

old_id_view = '''extension IdView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        registerViewID(id, element: widget)
        return opaqueFromWidget(widget)
    }
}
'''
new_id_view = '''extension IdView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        gtkRegisterScrollTarget(id: AnyHashable(id), widget: widget)
        return opaqueFromWidget(widget)
    }
}
'''
if "gtkResolvePendingScrollTo(id: AnyHashable(id), widget: widget)" not in text and old_id_view in text:
    text = text.replace(old_id_view, new_id_view, 1)
elif "gtkResolvePendingScrollTo(id: AnyHashable(id), widget: widget)" in text:
    old_patched_id_view = '''extension IdView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        registerViewID(id, element: widget)
        gtkResolvePendingScrollTo(id: AnyHashable(id), widget: widget)
        return opaqueFromWidget(widget)
    }
}
'''
    text = text.replace(old_patched_id_view, new_id_view, 1)

old_on_appear_rebuild = '''        if !isRebuild {
            let boundAction = bindActionToCurrentEnvironment(action)
            let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
            g_signal_connect_data(
                gpointer(widget),
                "map",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                    let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                    box.closure()
                } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }
'''
new_on_appear_rebuild = '''        let boundAction = bindActionToCurrentEnvironment(action)
        if !isRebuild {
            let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
            g_signal_connect_data(
                gpointer(widget),
                "map",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                    let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                    box.closure()
                } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }
'''
if "gtkScheduleOnAppear(boundAction, on: widget)" not in text and old_on_appear_rebuild in text:
    text = text.replace(old_on_appear_rebuild, new_on_appear_rebuild, 1)
elif "gtkScheduleOnAppear(boundAction, on: widget)" not in text:
    current_on_appear_rebuild = '''        // Stateful hosts reconcile `onAppear` by descriptor identity so actions
        // run once per appearance even when the subtree rebuilds.  Stateless
        // standalone renders still use the native map signal.
        if GTKViewHost.getCurrentRebuilding() == nil {
            let boundAction = bindActionToCurrentEnvironment(action)
            let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
            g_signal_connect_data(
                gpointer(widget),
                "map",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                    let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                    box.closure()
                } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }
'''
    current_on_appear_scheduled = '''        // Stateful hosts reconcile `onAppear` by descriptor identity so actions
        // run once per appearance even when the subtree rebuilds.  Stateless
        // standalone renders still use the native map signal.
        let boundAction = bindActionToCurrentEnvironment(action)
        if GTKViewHost.getCurrentRebuilding() == nil {
            let box = Unmanaged.passRetained(ClosureBox(boundAction)).toOpaque()
            g_signal_connect_data(
                gpointer(widget),
                "map",
                unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                    let box = Unmanaged<ClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                    box.closure()
                } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
                box,
                { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                    Unmanaged<ClosureBox>.fromOpaque(userData!).release()
                },
                GConnectFlags(rawValue: 0)
            )
        }
'''
    if current_on_appear_rebuild in text:
        text = text.replace(current_on_appear_rebuild, current_on_appear_scheduled, 1)
    elif (
        current_on_appear_scheduled not in text
        and "gtkCollectOnAppearPayload(GTK4OnAppearPayload(action: boundAction))" not in text
    ):
        raise SystemExit("SwiftOpenUI OnAppear lifecycle rebuild shape was not recognized")

mapped_on_disappear_marker = "GTK OnDisappear requires a prior map before firing"
has_on_disappear_region = (
    "extension OnDisappearView: GTKRenderable" in text
    or "private class DisappearBox" in text
    or mapped_on_disappear_marker in text
)
if has_on_disappear_region and mapped_on_disappear_marker not in text:
    old_on_disappear = '''/// Holds the disappear callback and a reference to the host container
/// for distinguishing rebuild unmaps from real disappears.
private class DisappearBox {
    let action: () -> Void
    let hostContainer: UnsafeMutablePointer<GtkWidget>?
    init(action: @escaping () -> Void, hostContainer: UnsafeMutablePointer<GtkWidget>?) {
        self.action = action
        self.hostContainer = hostContainer
    }
}

extension OnDisappearView: GTKRenderable, GTKDescribable {
    /// Describe through to the content (the wrapper's widget IS the content's
    /// widget; the disappear callback rides the existing widget's unmap
    /// signal, which the narrow mutation path leaves untouched). Without this
    /// the describe pass terminates here as a childless composite, so every
    /// ancestor host — e.g. a sheet whose root view chains
    /// .onAppear/.onDisappear — falls off the narrow path and tears down its
    /// widgets on every rebuild.
    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "OnDisappearView",
            children: [gtkDescribeView(content)]
        )
    }

    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))

        let hostContainer: UnsafeMutablePointer<GtkWidget>?
        if let host = GTKViewHost.getCurrentRebuilding() {
            hostContainer = host.container
        } else {
            hostContainer = nil
        }

        let boundAction = bindActionToCurrentEnvironment(action)
        let box = Unmanaged.passRetained(
            DisappearBox(action: boundAction, hostContainer: hostContainer)
        ).toOpaque()
        g_signal_connect_data(
            gpointer(widget),
            "unmap",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<DisappearBox>.fromOpaque(userData!).takeUnretainedValue()
                // If the host container is still mapped, this is a rebuild — suppress.
                if let container = box.hostContainer,
                   gtk_widget_get_mapped(container) != 0 {
                    return
                }
                box.action()
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<DisappearBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

        return opaqueFromWidget(widget)
    }
}
'''
    new_on_disappear = old_on_disappear.replace(
        "private class DisappearBox {\n    let action: () -> Void\n    let hostContainer: UnsafeMutablePointer<GtkWidget>?\n",
        "private class DisappearBox {\n    let action: () -> Void\n    let hostContainer: UnsafeMutablePointer<GtkWidget>?\n    // GTK OnDisappear requires a prior map before firing. Sheet content can\n    // be temporarily unrealized while it is being attached to a window; SwiftUI\n    // does not treat that construction churn as a disappearance.\n    var hasMapped: Bool = false\n",
        1,
    ).replace(
        '''        g_signal_connect_data(
            gpointer(widget),
            "unmap",
''',
        '''        g_signal_connect_data(
            gpointer(widget),
            "map",
            unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
                let box = Unmanaged<DisappearBox>.fromOpaque(userData!).takeUnretainedValue()
                box.hasMapped = true
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            box,
            nil,
            GConnectFlags(rawValue: 0)
        )
        g_signal_connect_data(
            gpointer(widget),
            "unmap",
''',
        1,
    ).replace(
        '''        let boundAction = bindActionToCurrentEnvironment(action)
        let box = Unmanaged.passRetained(
''',
        '''        let boundAction = bindActionToCurrentEnvironment(action)
        if let sheetLifecycleScope = gtkCurrentSheetLifecycleScope() {
            sheetLifecycleScope.registerOnDisappear(boundAction)
            return opaqueFromWidget(widget)
        }

        let box = Unmanaged.passRetained(
''',
        1,
    ).replace(
        '''                let box = Unmanaged<DisappearBox>.fromOpaque(userData!).takeUnretainedValue()
                // If the host container is still mapped, this is a rebuild — suppress.
''',
        '''                let box = Unmanaged<DisappearBox>.fromOpaque(userData!).takeUnretainedValue()
                guard box.hasMapped else { return }
                // If the host container is still mapped, this is a rebuild — suppress.
''',
        1,
    )
    if old_on_disappear not in text:
        raise SystemExit("SwiftOpenUI OnDisappear lifecycle shape was not recognized")
    text = text.replace(old_on_disappear, new_on_disappear, 1)

layout_marker_helper = r'''
private func gtkHasLayoutMarker(_ widget: UnsafeMutablePointer<GtkWidget>, key: String) -> Bool {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    return g_object_get_data(gobject, key) != nil
}

private func gtkSetLayoutMarker(_ widget: UnsafeMutablePointer<GtkWidget>, key: String) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, key, UnsafeMutableRawPointer(bitPattern: 1))
}

private func gtkPropagateSingleChildLayoutMarkers(
    from children: [UnsafeMutablePointer<GtkWidget>],
    to wrapper: UnsafeMutablePointer<GtkWidget>
) {
    guard children.count == 1, let child = children.first else { return }
    if gtkHasLayoutMarker(child, key: gtkSwiftSpacerMarker) {
        gtkSetLayoutMarker(wrapper, key: gtkSwiftSpacerMarker)
    }
    if gtkHasLayoutMarker(child, key: gtkSwiftDividerMarker) {
        gtkSetLayoutMarker(wrapper, key: gtkSwiftDividerMarker)
    }
}

private func gtkLayoutChildViews(from view: any View, depth: Int = 0) -> [any View] {
    guard depth < 24 else { return [view] }

    let mirror = Mirror(reflecting: view)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first?.value as? any View else { return [] }
        return gtkLayoutChildViews(from: child, depth: depth + 1)
    }

    if mirror.displayStyle == .enum,
       String(reflecting: Swift.type(of: view)).contains("_ConditionalView") {
        for child in mirror.children {
            if let nested = child.value as? any View {
                return gtkLayoutChildViews(from: nested, depth: depth + 1)
            }
        }
        return []
    }

    if let transparent = view as? any TransparentMultiChildView {
        return transparent.children.flatMap { gtkLayoutChildViews(from: $0, depth: depth + 1) }
    }

    return [view]
}

'''
if "gtkPropagateSingleChildLayoutMarkers" not in text:
    marker = "private func gtkVStackSpacing(_ spacing: Int) -> Int {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI layout marker insertion point was not recognized")
    text = text.replace(marker, layout_marker_helper + marker, 1)
elif "private func gtkLayoutChildViews(from view: any View" not in text:
    marker = "private func gtkVStackSpacing(_ spacing: Int) -> Int {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI layout child insertion point was not recognized")
    helper_body = layout_marker_helper.split("private func gtkLayoutChildViews", 1)[1]
    text = text.replace(marker, "private func gtkLayoutChildViews" + helper_body + marker, 1)

primitive_render_fallback = '''    if Swift.type(of: view) is any PrimitiveView.Type {
        gtkDebugLog("unsupported primitive view rendered as EmptyView: \\(String(reflecting: V.self))")
        return opaqueFromWidget(gtkCreateEmptyViewWidget())
    }

'''
if "unsupported primitive view rendered as EmptyView" not in text:
    marker = "    // Composite view with reactive state — wrap in GTKViewHost\n    if hasReactiveProperties(view) {\n"
    if marker not in text:
        marker = "    if hasReactiveProperties(view) {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI primitive render fallback insertion point was not recognized")
    text = text.replace(marker, primitive_render_fallback + marker, 1)

vertical_fill_constant = '''/// Marker string for views that intentionally fill the parent's vertical
/// proposal, rather than merely inheriting GTK vexpand from descendants.
private let gtkSwiftVerticalFillIntentMarker = "gtk-swift-vertical-fill-intent"
'''
if "gtkSwiftVerticalFillIntentMarker" not in text:
    if "let gtkSwiftVerticalScrollViewMarker = \"gtk-swift-vertical-scroll-view\"\n" in text:
        text = text.replace(
            "let gtkSwiftVerticalScrollViewMarker = \"gtk-swift-vertical-scroll-view\"\n",
            "let gtkSwiftVerticalScrollViewMarker = \"gtk-swift-vertical-scroll-view\"\n" + vertical_fill_constant,
            1,
        )
    elif "let gtkSwiftDividerMarker = \"gtk-swift-divider\"\n" in text:
        text = text.replace(
            "let gtkSwiftDividerMarker = \"gtk-swift-divider\"\n",
            "let gtkSwiftDividerMarker = \"gtk-swift-divider\"\n" + vertical_fill_constant,
            1,
        )
    else:
        raise SystemExit("SwiftOpenUI vertical fill marker constant insertion point was not recognized")

vertical_fill_helpers = '''private func gtkMarkVerticalFillIntent(_ widget: UnsafeMutablePointer<GtkWidget>) {
    gtkSetLayoutMarker(widget, key: gtkSwiftVerticalFillIntentMarker)
}

private func gtkHasVerticalFillIntent(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    gtkHasLayoutMarker(widget, key: gtkSwiftVerticalFillIntentMarker)
}

'''
if "private func gtkMarkVerticalFillIntent" not in text:
    set_layout_marker = '''private func gtkSetLayoutMarker(_ widget: UnsafeMutablePointer<GtkWidget>, key: String) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, key, UnsafeMutableRawPointer(bitPattern: 1))
}

'''
    if set_layout_marker not in text:
        raise SystemExit("SwiftOpenUI vertical fill helper insertion point was not recognized")
    text = text.replace(set_layout_marker, set_layout_marker + vertical_fill_helpers, 1)

if "if gtkHasVerticalFillIntent(child) {\n        gtkMarkVerticalFillIntent(wrapper)\n    }" not in text:
    empty_marker_propagation = '''    if gtkHasLayoutMarker(child, key: gtkSwiftEmptyViewMarker) {
        gtkMarkEmptyView(wrapper)
    }
'''
    divider_marker_propagation = '''    if gtkHasLayoutMarker(child, key: gtkSwiftDividerMarker) {
        gtkSetLayoutMarker(wrapper, key: gtkSwiftDividerMarker)
    }
'''
    fill_marker_propagation = '''    if gtkHasVerticalFillIntent(child) {
        gtkMarkVerticalFillIntent(wrapper)
    }
'''
    if empty_marker_propagation in text:
        text = text.replace(empty_marker_propagation, empty_marker_propagation + fill_marker_propagation, 1)
    elif divider_marker_propagation in text:
        text = text.replace(divider_marker_propagation, divider_marker_propagation + fill_marker_propagation, 1)
    else:
        raise SystemExit("SwiftOpenUI vertical fill propagation insertion point was not recognized")

if "gtkMarkVerticalFillIntent(box)" not in text:
    color_vexpand = '''        gtk_widget_set_hexpand(box, 1)
        gtk_widget_set_vexpand(box, 1)
'''
    if color_vexpand not in text:
        raise SystemExit("SwiftOpenUI Color fill marker insertion point was not recognized")
    text = text.replace(color_vexpand, color_vexpand + "        gtkMarkVerticalFillIntent(box)\n", 1)

if "let overlayWantsVerticalFill =" not in text:
    old_zstack_overlay_alignment = '''            // Align non-expanding overlays according to the ZStack alignment.
            if gtk_widget_get_hexpand(widget) == 0 {
                gtk_widget_set_halign(widget, hAlign)
            }
            if gtk_widget_get_vexpand(widget) == 0 {
                gtk_widget_set_valign(widget, vAlign)
            }
'''
    new_zstack_overlay_alignment = '''            let overlayWantsVerticalFill =
                gtk_widget_get_vexpand(widget) != 0 && gtkHasVerticalFillIntent(widget)
            // Align non-expanding overlays according to the ZStack alignment.
            if gtk_widget_get_hexpand(widget) == 0 {
                gtk_widget_set_halign(widget, hAlign)
            }
            if overlayWantsVerticalFill {
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            } else {
                gtk_widget_set_vexpand(widget, 0)
                gtk_widget_set_valign(widget, vAlign)
            }
'''
    if old_zstack_overlay_alignment not in text:
        raise SystemExit("SwiftOpenUI ZStack overlay vertical fill shape was not recognized")
    text = text.replace(old_zstack_overlay_alignment, new_zstack_overlay_alignment, 1)

if "gtkHasVerticalFillIntent(overlayWidget)" not in text:
    text = text.replace(
        "        let overlayWantsVExpand = gtk_widget_get_vexpand(overlayWidget) != 0\n",
        "        let overlayWantsVExpand =\n            gtk_widget_get_vexpand(overlayWidget) != 0 && gtkHasVerticalFillIntent(overlayWidget)\n",
        1,
    )
    overlay_valign = "        gtk_widget_set_valign(overlayWidget, overlayWantsVExpand ? GTK_ALIGN_FILL : vAlign)\n"
    if overlay_valign not in text:
        raise SystemExit("SwiftOpenUI OverlayView vertical fill shape was not recognized")
    text = text.replace(
        overlay_valign,
        overlay_valign + "        if !overlayWantsVExpand {\n            gtk_widget_set_vexpand(overlayWidget, 0)\n        }\n",
        1,
    )

if "gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)\n        gtkMarkHostedNodeKind(wrapper, kind: .padding)" not in text:
    text = text.replace(
        "        gtkMarkHostedNodeKind(wrapper, kind: .padding)\n",
        "        gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)\n        gtkMarkHostedNodeKind(wrapper, kind: .padding)\n",
        1,
    )

if "if maxHeight != nil {\n            gtk_widget_set_vexpand(wrapper, 1)\n            gtkMarkVerticalFillIntent(wrapper)\n        }" not in text:
    text = text.replace(
        "        if maxHeight != nil {\n            gtk_widget_set_vexpand(wrapper, 1)\n        }\n",
        "        if maxHeight != nil {\n            gtk_widget_set_vexpand(wrapper, 1)\n            gtkMarkVerticalFillIntent(wrapper)\n        }\n",
        1,
    )

if "if gtkHasVerticalFillIntent(child) {\n                gtkMarkVerticalFillIntent(wrapper)\n            }" not in text:
    text = text.replace(
        "        if height == nil && maxHeight == nil && gtk_widget_get_vexpand(child) != 0 {\n            gtk_widget_set_vexpand(wrapper, 1)\n        }\n",
        "        if height == nil && maxHeight == nil && gtk_widget_get_vexpand(child) != 0 {\n            gtk_widget_set_vexpand(wrapper, 1)\n            if gtkHasVerticalFillIntent(child) {\n                gtkMarkVerticalFillIntent(wrapper)\n            }\n        }\n",
        1,
    )

if "if maxHeight != nil || gtkHasVerticalFillIntent(child)" not in text:
    text = text.replace(
        "        if heightMayGrowWithParent {\n            gtk_widget_set_vexpand(wrapper, 1)\n        } else {\n",
        "        if heightMayGrowWithParent {\n            gtk_widget_set_vexpand(wrapper, 1)\n            if maxHeight != nil || gtkHasVerticalFillIntent(child) {\n                gtkMarkVerticalFillIntent(wrapper)\n            }\n        } else {\n",
        1,
    )

if "gtkPropagateSingleChildLayoutMarkers(from: [inner], to: wrapper)" not in text:
    text = text.replace(
        "        if gtk_widget_get_vexpand(inner) != 0 {\n            gtk_widget_set_vexpand(wrapper, 1)\n            gtk_widget_set_valign(inner, GTK_ALIGN_FILL)\n        }\n        return opaqueFromWidget(wrapper)\n",
        "        if gtk_widget_get_vexpand(inner) != 0 {\n            gtk_widget_set_vexpand(wrapper, 1)\n            gtk_widget_set_valign(inner, GTK_ALIGN_FILL)\n        }\n        gtkPropagateSingleChildLayoutMarkers(from: [inner], to: wrapper)\n        return opaqueFromWidget(wrapper)\n",
        1,
    )

if "gtkPropagateSingleChildLayoutMarkers(from: [contentWidget], to: wrapper)" not in text:
    text = text.replace(
        "    if gtk_widget_get_vexpand(contentWidget) != 0 {\n        gtk_widget_set_vexpand(wrapper, 1)\n        gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)\n    }\n\n    let css: String\n",
        "    if gtk_widget_get_vexpand(contentWidget) != 0 {\n        gtk_widget_set_vexpand(wrapper, 1)\n        gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)\n    }\n    gtkPropagateSingleChildLayoutMarkers(from: [contentWidget], to: wrapper)\n\n    let css: String\n",
        1,
    )

custom_layout_marker_propagation = '''        gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)
        return opaqueFromWidget(wrapper)
    }
}

// MARK: - ViewThatFits GTK extension
'''
custom_layout_owned_fill_intent = '''        gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)
        // A custom Layout owns its proposed size. A filling child should fill
        // that measured slot, but its fill intent must not escape to the
        // parent stack or the finite layout can be compressed to zero.
        gtkClearVerticalFillIntent(wrapper)
        return opaqueFromWidget(wrapper)
    }
}

// MARK: - ViewThatFits GTK extension
'''
if custom_layout_marker_propagation in text:
    text = text.replace(
        custom_layout_marker_propagation,
        custom_layout_owned_fill_intent,
        1,
    )
elif custom_layout_owned_fill_intent not in text:
    raise SystemExit("SwiftOpenUI custom Layout fill-intent boundary shape was not recognized")

if "gtkMarkVerticalFillIntent(area)" not in text:
    canvas_vexpand = '''        if height <= 0 {
            gtk_widget_set_vexpand(area, 1)
        }
'''
    if canvas_vexpand in text:
        text = text.replace(
            canvas_vexpand,
            '''        if height <= 0 {
            gtk_widget_set_vexpand(area, 1)
            gtkMarkVerticalFillIntent(area)
        }
''',
            1,
        )
    shape_vexpand = '''    gtk_widget_set_hexpand(area, 1)
    gtk_widget_set_vexpand(area, 1)
'''
    if shape_vexpand not in text:
        raise SystemExit("SwiftOpenUI shape fill marker insertion point was not recognized")
    text = text.replace(shape_vexpand, shape_vexpand + "    gtkMarkVerticalFillIntent(area)\n", 1)

compressible_layout_helpers = '''private func gtkCompressibleHeightClamp(
    _ child: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let wrapper = gtk_swift_compressible_height_clamp_new(child)!
    if gtk_widget_get_hexpand(child) != 0 {
        gtk_widget_set_hexpand(wrapper, 1)
        gtk_widget_set_halign(wrapper, GTK_ALIGN_FILL)
    }
    if gtk_widget_get_vexpand(child) != 0 {
        gtk_widget_set_vexpand(wrapper, 1)
        gtk_widget_set_valign(wrapper, GTK_ALIGN_FILL)
    }
    gtkPropagateSingleChildLayoutMarkers(from: [child], to: wrapper)
    return wrapper
}

private func gtkCompressibleProposalClamp(
    _ child: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let heightWrapper = gtkCompressibleHeightClamp(child)
    let widthWrapper = gtk_swift_compressible_width_clamp_new(heightWrapper)!
    if gtk_widget_get_hexpand(heightWrapper) != 0 {
        gtk_widget_set_hexpand(widthWrapper, 1)
        gtk_widget_set_halign(widthWrapper, GTK_ALIGN_FILL)
    }
    if gtk_widget_get_vexpand(heightWrapper) != 0 {
        gtk_widget_set_vexpand(widthWrapper, 1)
        gtk_widget_set_valign(widthWrapper, GTK_ALIGN_FILL)
    }
    gtkPropagateSingleChildLayoutMarkers(from: [heightWrapper], to: widthWrapper)
    return widthWrapper
}

'''
if "private func gtkCompressibleHeightClamp" not in text:
    measure_helper = '''private func gtkMeasureWidgetNaturalSize(_ widget: UnsafeMutablePointer<GtkWidget>) -> ViewSize {
    var widthMin: Int32 = 0
    var widthNat: Int32 = 0
    var heightMin: Int32 = 0
    var heightNat: Int32 = 0
    gtk_swift_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &widthMin, &widthNat)
    gtk_swift_widget_measure(widget, GTK_ORIENTATION_VERTICAL, -1, &heightMin, &heightNat)
    let width = max(widthMin, widthNat)
    let height = max(heightMin, heightNat)
    return ViewSize(width: Double(width), height: Double(height))
}

'''
    if measure_helper not in text:
        raise SystemExit("SwiftOpenUI compressible layout helper insertion point was not recognized")
    text = text.replace(measure_helper, measure_helper + compressible_layout_helpers, 1)

if "for originalWidget in children {\n        var widget = originalWidget" not in text:
    old_vstack_loop = '''    for widget in children {
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            gtk_widget_set_hexpand(widget, 0)
            gtk_widget_set_vexpand(widget, 1)
            hasVerticalFillIntent = true
        }
        if gtk_widget_get_hexpand(widget) != 0 {
            needsHExpand = true
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        } else {
            gtk_widget_set_halign(widget, gtkAlign)
        }
        if gtk_widget_get_vexpand(widget) != 0 { needsVExpand = true; gtk_widget_set_valign(widget, GTK_ALIGN_FILL) }
        gtk_box_append(boxPointer(box), widget)
    }
'''
    new_vstack_loop = '''    var hasVerticalFillIntent = false

    for originalWidget in children {
        var widget = originalWidget
        let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            gtk_widget_set_hexpand(widget, 0)
            gtk_widget_set_vexpand(widget, 1)
        }
        if gtk_widget_get_hexpand(widget) != 0 {
            needsHExpand = true
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        } else {
            gtk_widget_set_halign(widget, gtkAlign)
        }
        if gtk_widget_get_vexpand(widget) != 0 && gtkHasVerticalFillIntent(widget) {
            widget = gtkCompressibleHeightClamp(widget)
        }
        if gtkHasVerticalFillIntent(widget) {
            hasVerticalFillIntent = true
        }
        if gtk_widget_get_vexpand(widget) != 0 { needsVExpand = true; gtk_widget_set_valign(widget, GTK_ALIGN_FILL) }
        gtk_box_append(boxPointer(box), widget)
    }
'''
    if old_vstack_loop not in text:
        raise SystemExit("SwiftOpenUI VStack compressible-child loop shape was not recognized")
    text = text.replace(old_vstack_loop, new_vstack_loop, 1)

vstack_start = text.find("private func gtkRenderFallbackVStack(")
vstack_end = text.find("\nprivate func gtkRenderFallbackHStack", vstack_start)
if vstack_start == -1 or vstack_end == -1:
    raise SystemExit("SwiftOpenUI VStack fallback section was not recognized")
vstack_section = text[vstack_start:vstack_end]
vstack_spacer_vertical_fill = '''        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            gtk_widget_set_hexpand(widget, 0)
            gtk_widget_set_vexpand(widget, 1)
            hasVerticalFillIntent = true
        }
'''
if vstack_spacer_vertical_fill not in vstack_section:
    old_vstack_spacer = '''        if g_object_get_data(gobject, gtkSwiftSpacerMarker) != nil {
            gtk_widget_set_hexpand(widget, 0)
            gtk_widget_set_vexpand(widget, 1)
        }
'''
    if old_vstack_spacer not in vstack_section:
        raise SystemExit("SwiftOpenUI VStack spacer fill-intent shape was not recognized")
    vstack_section = vstack_section.replace(old_vstack_spacer, vstack_spacer_vertical_fill, 1)
    text = text[:vstack_start] + vstack_section + text[vstack_end:]

if "if hasVerticalFillIntent { gtkMarkVerticalFillIntent(box) }\n    return opaqueFromWidget(box)\n}\n\nprivate func gtkRenderFallbackHStack" not in text:
    text = text.replace(
        '''    if needsHExpand { gtk_widget_set_hexpand(box, 1) }
    if needsVExpand { gtk_widget_set_vexpand(box, 1) }
    return opaqueFromWidget(box)
}

private func gtkRenderFallbackHStack''',
        '''    if needsHExpand { gtk_widget_set_hexpand(box, 1) }
    if needsVExpand { gtk_widget_set_vexpand(box, 1) }
    if hasVerticalFillIntent { gtkMarkVerticalFillIntent(box) }
    return opaqueFromWidget(box)
}

private func gtkRenderFallbackHStack''',
        1,
    )

if "return opaqueFromWidget(gtkCompressibleProposalClamp(box))" not in text:
    geometry_return = '''        return opaqueFromWidget(box)
    }
}

// MARK: - Searchable GTK extension
'''
    if geometry_return not in text:
        raise SystemExit("SwiftOpenUI GeometryReader return shape was not recognized")
    text = text.replace(
        geometry_return,
        '''        return opaqueFromWidget(gtkCompressibleProposalClamp(box))
    }
}

// MARK: - Searchable GTK extension
''',
        1,
    )

overlay_marker = "\n// MARK: - Overlay GTK extension\n\n"
decorative_overlay_helper = """\nprivate protocol GTKDecorativeOverlay {}\nextension Circle: GTKDecorativeOverlay {}\nextension Rectangle: GTKDecorativeOverlay {}\nextension RoundedRectangle: GTKDecorativeOverlay {}\nextension Capsule: GTKDecorativeOverlay {}\nextension Ellipse: GTKDecorativeOverlay {}\nextension FilledShape: GTKDecorativeOverlay {}\nextension StrokedShape: GTKDecorativeOverlay {}\n\n"""
if "private protocol GTKDecorativeOverlay" not in text and overlay_marker in text:
    text = text.replace(overlay_marker, decorative_overlay_helper + overlay_marker, 1)

old_overlay_add = """        gtk_widget_set_halign(overlayWidget, overlayWantsHExpand ? GTK_ALIGN_FILL : hAlign)
        gtk_widget_set_valign(overlayWidget, overlayWantsVExpand ? GTK_ALIGN_FILL : vAlign)
        gtk_overlay_add_overlay(OpaquePointer(container), overlayWidget)
"""
new_overlay_add = """        gtk_widget_set_halign(overlayWidget, overlayWantsHExpand ? GTK_ALIGN_FILL : hAlign)
        gtk_widget_set_valign(overlayWidget, overlayWantsVExpand ? GTK_ALIGN_FILL : vAlign)
        if overlay is GTKDecorativeOverlay {
            gtk_widget_set_can_target(overlayWidget, 0)
        }
        gtk_overlay_add_overlay(OpaquePointer(container), overlayWidget)
"""
if "gtk_widget_set_can_target(overlayWidget, 0)" not in text:
    text = text.replace(old_overlay_add, new_overlay_add, 1)

old_multi = '''    if let multi = view as? MultiChildView {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        for child in multi.children {
            let widget = widgetFromOpaque(gtkRenderAnyView(child))
            gtk_box_append(boxPointer(box), widget)
        }
        return opaqueFromWidget(box)
    }
'''
new_multi = '''    if let multi = view as? MultiChildView {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        var needsHExpand = false
        var needsVExpand = false
        var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []
        for child in multi.children.flatMap({ gtkLayoutChildViews(from: $0) }) {
            let widget = widgetFromOpaque(gtkRenderAnyView(child))
            renderedChildren.append(widget)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
        if needsVExpand { gtk_widget_set_vexpand(box, 1) }
        return opaqueFromWidget(box)
    }
'''
if "var needsHExpand = false\n        var needsVExpand = false\n        for child in multi.children" not in text:
    text = text.replace(old_multi, new_multi, 1)
if "var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []\n        for child in multi.children.flatMap({ gtkLayoutChildViews(from: $0) })" not in text:
    old_patched_multi = '''        var needsHExpand = false
        var needsVExpand = false
        for child in multi.children {
            let widget = widgetFromOpaque(gtkRenderAnyView(child))
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
'''
    new_patched_multi = '''        var needsHExpand = false
        var needsVExpand = false
        var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []
        for child in multi.children.flatMap({ gtkLayoutChildViews(from: $0) }) {
            let widget = widgetFromOpaque(gtkRenderAnyView(child))
            renderedChildren.append(widget)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
'''
    if old_patched_multi not in text:
        raise SystemExit("SwiftOpenUI MultiChild marker propagation shape was not recognized")
    text = text.replace(old_patched_multi, new_patched_multi, 1)
elif "for child in multi.children {\n            let widget = widgetFromOpaque(gtkRenderAnyView(child))" in text:
    text = text.replace(
        "for child in multi.children {\n            let widget = widgetFromOpaque(gtkRenderAnyView(child))",
        "for child in multi.children.flatMap({ gtkLayoutChildViews(from: $0) }) {\n            let widget = widgetFromOpaque(gtkRenderAnyView(child))",
        1,
    )

old_render_children = '''public func gtkRenderChildren<V: View>(_ view: V) -> [OpaquePointer] {
    if let multi = view as? GTKMultiChildRenderable {
        return MainActor.assumeIsolated { multi.gtkRenderChildren() }
    }
    if let multi = view as? MultiChildView {
        return multi.children.map { child in
            func render<C: View>(_ c: C) -> OpaquePointer { gtkRenderView(c) }
            return render(child)
        }
    }
    return [gtkRenderView(view)]
}
'''
new_render_children = '''public func gtkRenderChildren<V: View>(_ view: V) -> [OpaquePointer] {
    if let multi = view as? GTKMultiChildRenderable {
        return MainActor.assumeIsolated { multi.gtkRenderChildren() }
    }
    if let multi = view as? MultiChildView {
        return multi.children.flatMap { child in
            func render<C: View>(_ c: C) -> OpaquePointer { gtkRenderView(c) }
            return gtkLayoutChildViews(from: child).map { render($0) }
        }
    }
    return gtkLayoutChildViews(from: view).map { gtkRenderAnyView($0) }
}
'''
if "return gtkLayoutChildViews(from: view).map { gtkRenderAnyView($0) }" not in text:
    if old_render_children not in text:
        raise SystemExit("SwiftOpenUI gtkRenderChildren layout-child shape was not recognized")
    text = text.replace(old_render_children, new_render_children, 1)

old_group = '''extension Group: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        for child in gtkRenderChildren(content) {
            gtk_box_append(boxPointer(box), widgetFromOpaque(child))
        }
        return opaqueFromWidget(box)
    }
}
'''
new_group = '''extension Group: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        var needsHExpand = false
        var needsVExpand = false
        var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []
        for child in gtkRenderChildren(content) {
            let widget = widgetFromOpaque(child)
            renderedChildren.append(widget)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
        if needsVExpand { gtk_widget_set_vexpand(box, 1) }
        return opaqueFromWidget(box)
    }
}
'''
if "extension Group: GTKRenderable {\n    public func gtkCreateWidget() -> OpaquePointer {\n        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!\n        var needsHExpand = false" not in text:
    text = text.replace(old_group, new_group, 1)
if "var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []\n        for child in gtkRenderChildren(content)" not in text:
    old_patched_group = '''        var needsHExpand = false
        var needsVExpand = false
        for child in gtkRenderChildren(content) {
            let widget = widgetFromOpaque(child)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
'''
    new_patched_group = '''        var needsHExpand = false
        var needsVExpand = false
        var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []
        for child in gtkRenderChildren(content) {
            let widget = widgetFromOpaque(child)
            renderedChildren.append(widget)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        gtkPropagateSingleChildLayoutMarkers(from: renderedChildren, to: box)
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
'''
    if old_patched_group not in text:
        raise SystemExit("SwiftOpenUI Group marker propagation shape was not recognized")
    text = text.replace(old_patched_group, new_patched_group, 1)

old_foreach = '''extension ForEach: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        for item in data {
            let childView = content(item)
            let widget = widgetFromOpaque(gtkRenderView(childView))
            gtk_box_append(boxPointer(box), widget)
        }
        return opaqueFromWidget(box)
    }
}
'''
new_foreach = '''extension ForEach: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        var needsHExpand = false
        var needsVExpand = false
        for item in data {
            let childView = content(item)
            let widget = widgetFromOpaque(gtkRenderView(childView))
            // SwiftUI lays repeated vertical rows against the parent's
            // proposed width. This keeps ScrollView/List rows from collapsing
            // to their natural text width and then being centered.
            needsHExpand = true
            gtk_widget_set_hexpand(widget, 1)
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(widget) != 0 {
                needsVExpand = true
                gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
            }
            gtk_box_append(boxPointer(box), widget)
        }
        if needsHExpand { gtk_widget_set_hexpand(box, 1) }
        if needsVExpand { gtk_widget_set_vexpand(box, 1) }
        return opaqueFromWidget(box)
    }
}
'''
if "extension ForEach: GTKRenderable {\n    public func gtkCreateWidget() -> OpaquePointer {\n        let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!\n        var needsHExpand = false" not in text:
    text = text.replace(old_foreach, new_foreach, 1)
if "SwiftUI lays repeated vertical rows against the parent's" not in text:
    old_patched_foreach = '''        for item in data {
            let childView = content(item)
            let widget = widgetFromOpaque(gtkRenderView(childView))
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
'''
    new_patched_foreach = '''        for item in data {
            let childView = content(item)
            let widget = widgetFromOpaque(gtkRenderView(childView))
            // SwiftUI lays repeated vertical rows against the parent's
            // proposed width. This keeps ScrollView/List rows from collapsing
            // to their natural text width and then being centered.
            needsHExpand = true
            gtk_widget_set_hexpand(widget, 1)
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            if gtk_widget_get_hexpand(widget) != 0 {
                needsHExpand = true
                gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
            }
'''
    if old_patched_foreach not in text:
        raise SystemExit("SwiftOpenUI ForEach row sizing shape was not recognized")
    text = text.replace(old_patched_foreach, new_patched_foreach, 1)

if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

menu_helper = '''private func gtkApplyPlainMenuButtonChrome(to button: UnsafeMutablePointer<GtkWidget>) {
    let className = "gtk-swift-plain-menu-button"
    let css = """
    .\\(className),
    menubutton.\\(className),
    menubutton.\\(className) > button,
    menubutton.\\(className) button {
        background: transparent;
        background-color: transparent;
        background-image: none;
        border: none;
        border-radius: 0;
        box-shadow: none;
        outline: none;
        padding: 0;
        min-height: 0;
        min-width: 0;
        -gtk-icon-shadow: none;
        text-shadow: none;
    }
    """

    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(provider, css)
    if let display = gtk_widget_get_display(button) {
        gtk_swift_add_css_provider_to_display(
            display,
            provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
    }
    gtk_widget_add_css_class(button, "flat")
    gtk_widget_add_css_class(button, className)
    g_object_unref(gpointer(provider))
}

'''

menu_marker = "extension Menu: GTKRenderable"
if menu_marker in text:
    if "private func gtkApplyPlainMenuButtonChrome" not in text:
        text = text.replace(menu_marker, menu_helper + menu_marker, 1)

    old_menu_renderer = '''extension Menu: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let button = gtk_menu_button_new()!
        gtk_swift_menu_button_set_label(button, title)

        let actionGroup = g_simple_action_group_new()!
'''
    new_menu_renderer = '''extension Menu: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let button = gtk_menu_button_new()!

        let buttonStyleType = getCurrentEnvironment().buttonStyle
        if let labelView {
            let childWidget = widgetFromOpaque(gtkRenderView(labelView))
            gtkDisableButtonChildTargeting(childWidget)
            gtk_swift_menu_button_set_always_show_arrow(button, 0)
            gtk_swift_menu_button_set_child(button, childWidget)
            gtkApplyPlainMenuButtonChrome(to: button)
        } else {
            gtk_swift_menu_button_set_label(button, title)
            if buttonStyleType == .plain {
                gtk_swift_menu_button_set_always_show_arrow(button, 0)
                gtkApplyPlainMenuButtonChrome(to: button)
            }
        }

        let actionGroup = g_simple_action_group_new()!
'''

    if "gtkApplyPlainMenuButtonChrome(to: button)" not in text[text.find(menu_marker):]:
        if old_menu_renderer not in text:
            raise SystemExit("SwiftOpenUI Menu GTK renderer shape was not recognized")
        text = text.replace(old_menu_renderer, new_menu_renderer, 1)

    menu_start = text.find(menu_marker)
    menu_end = text.find("\nprivate func gtkBuildMenuModel", menu_start)
    if menu_start == -1 or menu_end == -1:
        raise SystemExit("SwiftOpenUI Menu GTK renderer bounds were not recognized")
    menu_renderer = text[menu_start:menu_end]
    for required in [
        "if let labelView {",
        "gtkDisableButtonChildTargeting(childWidget)",
        "gtk_swift_menu_button_set_always_show_arrow(button, 0)",
        "gtk_swift_menu_button_set_child(button, childWidget)",
        "gtkApplyPlainMenuButtonChrome(to: button)",
    ]:
        if required not in menu_renderer:
            raise SystemExit(f"SwiftOpenUI Menu GTK renderer patch missing: {required}")

old_row_render = """    let child = gtkWithRowTextRenderContext(includeShortPlainText: includeShortPlainText) {
        widgetFromOpaque(gtkRenderAnyView(view))
    }
"""
new_row_render = """    let child = gtkWithSuppressedDescriptorLifecyclePayloads {
        gtkWithRowTextRenderContext(includeShortPlainText: includeShortPlainText) {
            widgetFromOpaque(gtkRenderAnyView(view))
        }
    }
"""
if old_row_render in text:
    text = text.replace(old_row_render, new_row_render, 1)
elif "let child = gtkWithSuppressedDescriptorLifecyclePayloads" not in text:
    raise SystemExit("SwiftOpenUI row lifecycle render suppression shape was not recognized")

old_task_render = """        if GTKViewHost.getCurrentRebuilding() == nil {
            gtkAttachStandaloneTaskLifecycle(
                to: widget,
                priority: priority,
                lifecycleID: lifecycleID,
                action: boundAction
            )
        }
        return opaqueFromWidget(widget)
"""
new_task_render = """        if GTKViewHost.getCurrentRebuilding() == nil {
            gtkAttachStandaloneTaskLifecycle(
                to: widget,
                priority: priority,
                lifecycleID: lifecycleID,
                action: boundAction
            )
        } else {
            gtkCollectTaskPayload(
                GTK4TaskPayload(
                    priority: priority,
                    lifecycleID: lifecycleID,
                    action: boundAction
                )
            )
        }
        return opaqueFromWidget(widget)
"""
if old_task_render in text:
    text = text.replace(old_task_render, new_task_render, 1)
elif "gtkCollectTaskPayload(\n                GTK4TaskPayload(" not in text:
    raise SystemExit("SwiftOpenUI TaskView render lifecycle payload shape was not recognized")

old_on_appear_render = """                },
                GConnectFlags(rawValue: 0)
            )
        }

        return opaqueFromWidget(widget)
"""
new_on_appear_render = """                },
                GConnectFlags(rawValue: 0)
            )
        } else {
            gtkCollectOnAppearPayload(GTK4OnAppearPayload(action: boundAction))
        }

        return opaqueFromWidget(widget)
"""
if old_on_appear_render in text and "gtkCollectOnAppearPayload(GTK4OnAppearPayload(action: boundAction))" not in text:
    text = text.replace(old_on_appear_render, new_on_appear_render, 1)
elif "gtkCollectOnAppearPayload(GTK4OnAppearPayload(action: boundAction))" not in text:
    raise SystemExit("SwiftOpenUI OnAppearView render lifecycle payload shape was not recognized")

text = text.replace(
    "onAppearPayloads: described.onAppearPayloads",
    "onAppearPayloads: host.renderCapturedOnAppearPayloads(fallback: described.onAppearPayloads)",
)
text = text.replace(
    "taskPayloads: described.taskPayloads",
    "taskPayloads: host.renderCapturedTaskPayloads(fallback: described.taskPayloads)",
)
if "host.renderCapturedTaskPayloads(fallback: described.taskPayloads)" not in text:
    raise SystemExit("SwiftOpenUI initial render task lifecycle reconciliation shape was not recognized")

if text != original:
    path.write_text(text)
PY

python3 - "$DESCRIPTOR_TREE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

if "case statefulLifecycleScope" not in text:
    marker = "    case listRowLifecycleScope\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI descriptor lifecycle-scope enum shape was not recognized")
    text = text.replace(marker, marker + "    case statefulLifecycleScope\n", 1)

owned_lifecycle_helper = '''/// A stateful host owns lifecycle actions declared in its body even when an
/// ancestor is suppressing payload collection for its descriptor-only walk.
func gtkWithOwnedDescriptorLifecyclePayloads<T>(_ body: () -> T) -> T {
    let previousDepth = gtkDescriptorLifecyclePayloadSuppressionDepth
    gtkDescriptorLifecyclePayloadSuppressionDepth = 0
    defer { gtkDescriptorLifecyclePayloadSuppressionDepth = previousDepth }
    return body()
}

'''
if "func gtkWithOwnedDescriptorLifecyclePayloads" not in text:
    marker = "public func gtkCollectButtonPayload"
    if marker not in text:
        raise SystemExit("SwiftOpenUI descriptor lifecycle ownership insertion point was not recognized")
    text = text.replace(marker, owned_lifecycle_helper + marker, 1)

render_lifecycle_capture_helper = '''public func gtkCaptureRenderLifecyclePayloads<T>(
    _ render: () -> T
) -> (
    value: T,
    onAppearPayloads: [GTK4OnAppearPayload],
    taskPayloads: [GTK4TaskPayload]
) {
    let collector = GTK4DescriptorPayloadCollector()
    let retained = Unmanaged.passRetained(collector)
    let previous = pthread_getspecific(gtkDescriptorPayloadCollectorKey)
    pthread_setspecific(gtkDescriptorPayloadCollectorKey, retained.toOpaque())
    let value = render()
    pthread_setspecific(gtkDescriptorPayloadCollectorKey, previous)
    retained.release()
    return (
        value,
        collector.onAppearPayloads,
        collector.taskPayloads
    )
}

'''
if "gtkCaptureRenderLifecyclePayloads" not in text:
    marker = "private func gtkDescriptorChildViews(from view: any View"
    if marker not in text:
        marker = "/// Build a GTK4-local descriptor tree without creating widgets."
    if marker not in text:
        raise SystemExit("SwiftOpenUI descriptor render lifecycle capture insertion point was not recognized")
    text = text.replace(marker, render_lifecycle_capture_helper + marker, 1)

stateful_descriptor_old = '''                children: [MainActor.assumeIsolated { gtkDescribeAnyView(view.body) }]
'''
stateful_descriptor_suppressed = '''                children: [gtkWithSuppressedDescriptorLifecyclePayloads {
                    MainActor.assumeIsolated { gtkDescribeAnyView(view.body) }
                }]
'''
stateful_descriptor_inline_only = r'''            let child: GTK4DescriptorNode
            if view is any GTKRenderable || view is any TransparentMultiChildView {
                // These views render inline before gtkRenderView considers
                // reactive hosting. Their lifecycle modifiers still belong to
                // the enclosing host and must remain visible to its descriptor.
                child = MainActor.assumeIsolated { gtkDescribeAnyView(view.body) }
            } else {
                child = gtkWithSuppressedDescriptorLifecyclePayloads {
                    MainActor.assumeIsolated { gtkDescribeAnyView(view.body) }
                }
            }
            return GTK4DescriptorNode(
                kind: .composite,
                typeName: "GTKStatefulHost<\(String(describing: type(of: view)))>",
                children: [child]
            )
'''
stateful_descriptor_scoped = r'''            let child: GTK4DescriptorNode
            let kind: GTK4DescriptorKind
            if view is any GTKRenderable || view is any TransparentMultiChildView {
                // These views render inline before gtkRenderView considers
                // reactive hosting. Their lifecycle modifiers still belong to
                // the enclosing host and must remain visible to its descriptor.
                kind = .composite
                child = MainActor.assumeIsolated { gtkDescribeAnyView(view.body) }
            } else {
                // The renderer creates a nested GTKViewHost for this view. Its
                // lifecycle nodes stay available for retained-tree planning,
                // but the parent host must not map or execute them.
                kind = .statefulLifecycleScope
                child = gtkWithSuppressedDescriptorLifecyclePayloads {
                    MainActor.assumeIsolated { gtkDescribeAnyView(view.body) }
                }
            }
            return GTK4DescriptorNode(
                kind: kind,
                typeName: "GTKStatefulHost<\(String(describing: type(of: view)))>",
                children: [child]
            )
'''
if stateful_descriptor_old in text:
    text = text.replace(
        r'''            return GTK4DescriptorNode(
                kind: .composite,
                typeName: "GTKStatefulHost<\(String(describing: type(of: view)))>",
''' + stateful_descriptor_old + '''            )
''',
        stateful_descriptor_scoped,
        1,
    )
elif stateful_descriptor_suppressed in text:
    text = text.replace(
        r'''            return GTK4DescriptorNode(
                kind: .composite,
                typeName: "GTKStatefulHost<\(String(describing: type(of: view)))>",
''' + stateful_descriptor_suppressed + '''            )
''',
        stateful_descriptor_scoped,
        1,
    )
elif stateful_descriptor_inline_only in text:
    text = text.replace(stateful_descriptor_inline_only, stateful_descriptor_scoped, 1)
elif stateful_descriptor_scoped not in text:
    raise SystemExit("SwiftOpenUI stateful descriptor lifecycle ownership shape was not recognized")

text = text.replace(
    "    case .listRowLifecycleScope: return .none\n",
    "    case .listRowLifecycleScope, .statefulLifecycleScope: return .none\n",
    1,
)
if "case .listRowLifecycleScope, .statefulLifecycleScope: return .none" not in text:
    raise SystemExit("SwiftOpenUI stateful lifecycle update-intent shape was not recognized")

task_collector = '''private func gtkCollectTaskDescriptorIdentities(
    from node: GTK4IdentifiedDescriptorNode,
    includingListRowScopes: Bool = true
) -> [GTK4DescriptorIdentity] {
'''
task_scope_guard = '''    if node.descriptor.kind == .statefulLifecycleScope {
        return []
    }
'''
task_start = text.find(task_collector)
if task_start < 0:
    raise SystemExit("SwiftOpenUI task descriptor collector shape was not recognized")
task_guard_at = task_start + len(task_collector)
if not text.startswith(task_scope_guard, task_guard_at):
    text = text[:task_guard_at] + task_scope_guard + text[task_guard_at:]

on_appear_collector = '''private func gtkCollectOnAppearDescriptorIdentities(
    from node: GTK4IdentifiedDescriptorNode,
    includingListRowScopes: Bool = true
) -> [GTK4DescriptorIdentity] {
'''
on_appear_start = text.find(on_appear_collector)
if on_appear_start < 0:
    raise SystemExit("SwiftOpenUI onAppear descriptor collector shape was not recognized")
on_appear_guard_at = on_appear_start + len(on_appear_collector)
if not text.startswith(task_scope_guard, on_appear_guard_at):
    text = text[:on_appear_guard_at] + task_scope_guard + text[on_appear_guard_at:]

payload_function_start = text.find("public func gtkOnAppearPayloadsByIdentity(")
payload_function_end = text.find("public func gtkButtonPayloadsByIdentity(", payload_function_start)
if payload_function_start < 0 or payload_function_end < 0:
    raise SystemExit("SwiftOpenUI onAppear payload mapper shape was not recognized")
payload_function = text[payload_function_start:payload_function_end]
plain_mismatch = "    guard identities.count == payloads.count else { return [:] }\n"
logged_mismatch = r'''    guard identities.count == payloads.count else {
        gtkDescriptorLifecycleDebugLog(
            "onAppear payload identity mismatch identities=\(identities.count) payloads=\(payloads.count)"
        )
        return [:]
    }
'''
if plain_mismatch in payload_function:
    payload_function = payload_function.replace(plain_mismatch, logged_mismatch, 1)
elif logged_mismatch not in payload_function:
    raise SystemExit("SwiftOpenUI onAppear payload mismatch shape was not recognized")
text = text[:payload_function_start] + payload_function + text[payload_function_end:]

descriptor_child_helper = '''private func gtkDescriptorChildViews(from view: any View, depth: Int = 0) -> [any View] {
    guard depth < 24 else { return [view] }

    let mirror = Mirror(reflecting: view)
    if mirror.displayStyle == .optional {
        guard let child = mirror.children.first?.value as? any View else { return [] }
        return gtkDescriptorChildViews(from: child, depth: depth + 1)
    }

    if mirror.displayStyle == .enum,
       String(reflecting: Swift.type(of: view)).contains("_ConditionalView") {
        for child in mirror.children {
            if let nested = child.value as? any View {
                return gtkDescriptorChildViews(from: nested, depth: depth + 1)
            }
        }
        return []
    }

    if let transparent = view as? any TransparentMultiChildView {
        return transparent.children.flatMap { gtkDescriptorChildViews(from: $0, depth: depth + 1) }
    }

    return [view]
}

'''

if "private func gtkDescriptorChildViews(from view: any View" not in text:
    marker = "/// Build a GTK4-local descriptor tree without creating widgets.\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI descriptor child helper marker was not recognized")
    text = text.replace(marker, descriptor_child_helper + marker, 1)

old_descriptor_children = '''    if let multi = view as? MultiChildView {
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: String(describing: type(of: view)),
            children: multi.children.map(gtkDescribeAnyView)
        )
    }
'''
new_descriptor_children = '''    if let multi = view as? MultiChildView {
        return GTK4DescriptorNode(
            kind: .composite,
            typeName: String(describing: type(of: view)),
            children: multi.children.flatMap { child in
                gtkDescriptorChildViews(from: child).map(gtkDescribeAnyView)
            }
        )
    }
'''
if "children: multi.children.flatMap { child in" not in text:
    if old_descriptor_children not in text:
        raise SystemExit("SwiftOpenUI descriptor multi-child shape was not recognized")
    text = text.replace(old_descriptor_children, new_descriptor_children, 1)

new_function = '''public func gtkCanApplyTextColorHostMutation(plan: GTK4DescriptorPlan) -> Bool {
    switch plan.kind {
    case .create, .replace:
        return false
    case .reuse:
        // Reused buttons stay on the narrow path: host state identity is
        // stable across rebuilds (structural-path namespaces), so the action
        // closure captured at widget creation writes to the same @State
        // storage the current pass reads. Without this, any host containing a
        // button tears down on every keystroke and the focused entry is
        // destroyed mid-typing. A button whose own props changed plans as
        // .update (intent .none) and still takes the full rebuild.
        if plan.newDescriptor.kind == .composite && plan.children.isEmpty {
            // Props-bearing leaves (TextField & co.) compare meaningfully:
            // identical descriptors mean nothing changed, and the native
            // widget owns its visible state, so reuse is safe. Only
            // prop-less childless composites are opaque.
            if case .none = plan.newDescriptor.props {
                return false
            }
        }
        return plan.children.allSatisfy(gtkCanApplyTextColorHostMutation)
    case .update:
        if plan.newDescriptor.kind == .button {
            return false
        }
        guard plan.updateIntent == .textContent || plan.updateIntent == .colorFill
                || plan.updateIntent == .canvasContent
                || plan.updateIntent == .sliderValue
                || plan.updateIntent == .paddingLayout else {
            return false
        }
        return plan.children.allSatisfy(gtkCanApplyTextColorHostMutation)
    }
}
'''
if (
    "Reused buttons stay on the narrow path" not in text
    or "if case .none = plan.newDescriptor.props" not in text
    or "if plan.newDescriptor.kind == .button" not in text
):
    signature = "public func gtkCanApplyTextColorHostMutation(plan: GTK4DescriptorPlan) -> Bool"
    start = text.find(signature)
    if start == -1:
        raise SystemExit("SwiftOpenUI descriptor mutation guard shape was not recognized")
    body_start = text.find("{", start)
    if body_start == -1:
        raise SystemExit("SwiftOpenUI descriptor mutation guard body was not recognized")
    depth = 0
    end = None
    for index in range(body_start, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                break
    if end is None:
        raise SystemExit("SwiftOpenUI descriptor mutation guard end was not recognized")
    text = text[:start] + new_function + text[end:]
if text != original:
    path.write_text(text)
PY

python3 - "$ENVIRONMENT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
if "refreshInjectedObjectsFromRegistry" not in text:
    old = '''    public mutating func setLatestObjectByID(_ id: ObjectIdentifier, fallback object: AnyObject) {
        setObjectByID(id, EnvironmentObjectRegistry.shared.object(id: id) ?? object)
    }
'''
    new = old + '''
    /// Refresh every captured injected object from the global environment
    /// registry when an ancestor has since replaced it. Deferred callbacks such
    /// as NavigationStack destination factories capture an EnvironmentValues
    /// snapshot at render time; this keeps those callbacks from pinning stale
    /// app-wide objects like the current account client.
    public mutating func refreshInjectedObjectsFromRegistry() {
        for (id, object) in objects {
            setLatestObjectByID(id, fallback: object)
        }
    }
'''
    if old not in text:
        raise SystemExit("SwiftOpenUI EnvironmentValues latest-object shape was not recognized")
    text = text.replace(old, new, 1)
if "public struct EnvironmentObjectCapture" not in text:
    def replace_once(old, new, message):
        global text
        if old not in text:
            raise SystemExit(message)
        text = text.replace(old, new, 1)

    replace_once(
        '''public extension DynamicProperty {
    mutating func update() {}
}
''',
        '''public extension DynamicProperty {
    mutating func update() {}
}

/// A reference-typed environment object together with the structural scope
/// that injected it. Backends retain these captures across body rebuilds so
/// same-typed objects installed by sibling views cannot replace one another.
public struct EnvironmentObjectCapture: @unchecked Sendable {
    public let object: AnyObject
    public let scope: String?

    public init(object: AnyObject, scope: String? = nil) {
        self.object = object
        self.scope = scope
    }
}
''',
        "SwiftOpenUI EnvironmentObjectCapture insertion point was not recognized",
    )
    replace_once(
        "    private var objects: [ObjectIdentifier: AnyObject] = [:]\n",
        "    private var objects: [ObjectIdentifier: EnvironmentObjectCapture] = [:]\n",
        "SwiftOpenUI scoped environment object storage shape was not recognized",
    )
    replace_once(
        '''    public mutating func setObject<T: AnyObject>(_ object: T) {
        let id = ObjectIdentifier(T.self)
        objects[id] = object
        EnvironmentObjectRegistry.shared.setObject(object, id: id)
    }
''',
        '''    public mutating func setObject<T: AnyObject>(_ object: T, scope: String? = nil) {
        let id = ObjectIdentifier(T.self)
        objects[id] = EnvironmentObjectCapture(object: object, scope: scope)
        EnvironmentObjectRegistry.shared.setObject(object, id: id, scope: scope)
    }
''',
        "SwiftOpenUI scoped setObject shape was not recognized",
    )
    replace_once(
        '''        return objects[id] as? T ?? EnvironmentObjectRegistry.shared.object(id: id) as? T
''',
        '''        return objects[id]?.object as? T
            ?? EnvironmentObjectRegistry.shared.object(id: id, scope: nil) as? T
''',
        "SwiftOpenUI scoped getObject shape was not recognized",
    )
    replace_once(
        '''    public mutating func setObjectByID(_ id: ObjectIdentifier, _ object: AnyObject) {
        objects[id] = object
        EnvironmentObjectRegistry.shared.setObject(object, id: id)
    }
''',
        '''    public mutating func setObjectByID(
        _ id: ObjectIdentifier,
        _ object: AnyObject,
        scope: String? = nil
    ) {
        objects[id] = EnvironmentObjectCapture(object: object, scope: scope)
        EnvironmentObjectRegistry.shared.setObject(object, id: id, scope: scope)
    }
''',
        "SwiftOpenUI scoped setObjectByID shape was not recognized",
    )
    replace_once(
        '''    public mutating func setLatestObjectByID(_ id: ObjectIdentifier, fallback object: AnyObject) {
        setObjectByID(id, EnvironmentObjectRegistry.shared.object(id: id) ?? object)
    }
''',
        '''    public mutating func setLatestObjectByID(
        _ id: ObjectIdentifier,
        fallback object: AnyObject,
        scope: String? = nil
    ) {
        setObjectByID(
            id,
            EnvironmentObjectRegistry.shared.object(id: id, scope: scope) ?? object,
            scope: scope
        )
    }
''',
        "SwiftOpenUI scoped latest-object shape was not recognized",
    )
    replace_once(
        '''    public mutating func refreshInjectedObjectsFromRegistry() {
        for (id, object) in objects {
            setLatestObjectByID(id, fallback: object)
        }
    }
''',
        '''    public mutating func refreshInjectedObjectsFromRegistry() {
        for (id, capture) in objects {
            setLatestObjectByID(id, fallback: capture.object, scope: capture.scope)
        }
    }

    internal func objectScope(for id: ObjectIdentifier) -> String? {
        objects[id]?.scope
    }
''',
        "SwiftOpenUI scoped environment refresh shape was not recognized",
    )
    replace_once(
        '''private final class EnvironmentObjectRegistry: @unchecked Sendable {
    static let shared = EnvironmentObjectRegistry()

    private let lock = NSLock()
    private var objects: [ObjectIdentifier: AnyObject] = [:]

    func setObject(_ object: AnyObject, id: ObjectIdentifier) {
        lock.lock()
        objects[id] = object
        lock.unlock()
    }

    func object(id: ObjectIdentifier) -> AnyObject? {
        lock.lock()
        let object = objects[id]
        lock.unlock()
        return object
    }
}
''',
        '''private final class EnvironmentObjectRegistry: @unchecked Sendable {
    static let shared = EnvironmentObjectRegistry()

    private final class WeakObjectBox {
        weak var object: AnyObject?

        init(_ object: AnyObject) {
            self.object = object
        }
    }

    private struct ScopedKey: Hashable {
        let typeID: ObjectIdentifier
        let scope: String
    }

    private let lock = NSLock()
    private var objects: [ObjectIdentifier: WeakObjectBox] = [:]
    private var scopedObjects: [ScopedKey: WeakObjectBox] = [:]

    func setObject(_ object: AnyObject, id: ObjectIdentifier, scope: String?) {
        lock.lock()
        if let scope {
            scopedObjects[ScopedKey(typeID: id, scope: scope)] = WeakObjectBox(object)
        } else {
            objects[id] = WeakObjectBox(object)
        }
        lock.unlock()
    }

    func object(id: ObjectIdentifier, scope: String?) -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        if let scope {
            let key = ScopedKey(typeID: id, scope: scope)
            guard let object = scopedObjects[key]?.object else {
                scopedObjects.removeValue(forKey: key)
                return nil
            }
            return object
        }
        guard let object = objects[id]?.object else {
            objects.removeValue(forKey: id)
            return nil
        }
        return object
    }
}
''',
        "SwiftOpenUI scoped environment registry shape was not recognized",
    )
    replace_once(
        "private var _envReadTrackerStack: [[ObjectIdentifier: AnyObject]] = []\n",
        "private var _envReadTrackerStack: [[ObjectIdentifier: EnvironmentObjectCapture]] = []\n",
        "SwiftOpenUI scoped environment read tracker storage shape was not recognized",
    )
    replace_once(
        '''public func endEnvironmentReadTracking() -> [ObjectIdentifier: AnyObject]? {
    guard !_envReadTrackerStack.isEmpty else { return nil }
    let result = _envReadTrackerStack.removeLast()
    if !_envReadTrackerStack.isEmpty {
        let parentIndex = _envReadTrackerStack.count - 1
        for (typeID, object) in result {
            _envReadTrackerStack[parentIndex][typeID] = object
        }
    }
    return result
}
''',
        '''private func endEnvironmentObjectCaptureTracking() -> [ObjectIdentifier: EnvironmentObjectCapture]? {
    guard !_envReadTrackerStack.isEmpty else { return nil }
    let result = _envReadTrackerStack.removeLast()
    if !_envReadTrackerStack.isEmpty {
        let parentIndex = _envReadTrackerStack.count - 1
        for (typeID, capture) in result {
            _envReadTrackerStack[parentIndex][typeID] = capture
        }
    }
    return result
}

/// Finish tracking while preserving each object's structural injection scope.
/// Reactive backends use this form when rebuilding hosts independently.
public func endScopedEnvironmentReadTracking() -> [ObjectIdentifier: EnvironmentObjectCapture]? {
    endEnvironmentObjectCaptureTracking()
}

/// Finish tracking using the original object-only result shape.
public func endEnvironmentReadTracking() -> [ObjectIdentifier: AnyObject]? {
    endEnvironmentObjectCaptureTracking()?.mapValues(\\.object)
}
''',
        "SwiftOpenUI scoped environment read tracker result shape was not recognized",
    )
    replace_once(
        '''    _envReadTrackerStack[index][typeID] = object
    recordEnvironmentObservableObjectRead(object)
''',
        '''    _envReadTrackerStack[index][typeID] = EnvironmentObjectCapture(
        object: object,
        scope: getCurrentEnvironment().objectScope(for: typeID)
    )
    recordEnvironmentObservableObjectRead(object)
''',
        "SwiftOpenUI scoped environment read recording shape was not recognized",
    )
legacy_sync_task_environment = '''public func withSynchronousTaskEnvironment<T>(
    _ env: EnvironmentValues,
    operation: () throws -> T
) rethrows -> T {
    try EnvironmentTaskLocal.$values.withValue(env) {
        try operation()
    }
}

'''
sync_task_environment = '''public func withSynchronousTaskEnvironment<T>(
    _ env: EnvironmentValues,
    operation: () throws -> T
) rethrows -> T {
    // Swift 6.2's task-local runtime can corrupt its lookup marker when a
    // scope is opened from a native callback that has no current Swift task
    // and the operation releases an actor-isolated object. Keep direct uses
    // safe with the thread-local environment; backends that need child Task
    // inheritance must first enter a real Swift task.
    let hasCurrentTask = withUnsafeCurrentTask { $0 != nil }
    guard hasCurrentTask else {
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(env)
        defer { setCurrentEnvironment(previousEnvironment) }
        return try operation()
    }

    return try EnvironmentTaskLocal.$values.withValue(env) {
        try operation()
    }
}

'''
if legacy_sync_task_environment in text:
    text = text.replace(legacy_sync_task_environment, sync_task_environment, 1)
if sync_task_environment not in text:
    async_task_environment = '''public func withTaskEnvironment<T>(
    _ env: EnvironmentValues,
    operation: () async -> T
) async -> T {
'''
    if async_task_environment not in text:
        raise SystemExit("SwiftOpenUI synchronous task environment helper shape was not recognized")
    text = text.replace(
        async_task_environment,
        sync_task_environment + async_task_environment,
        1,
    )
if "if let taskEnvironment = EnvironmentTaskLocal.values" not in text:
    old_posix_environment = '''public func getCurrentEnvironment() -> EnvironmentValues {
    guard let ptr = pthread_getspecific(_envKey) else {
        return EnvironmentTaskLocal.values ?? EnvironmentValues()
    }
    return Unmanaged<EnvironmentBox>.fromOpaque(ptr).takeUnretainedValue().values
}
'''
    new_posix_environment = '''public func getCurrentEnvironment() -> EnvironmentValues {
    if let taskEnvironment = EnvironmentTaskLocal.values {
        return taskEnvironment
    }
    guard let ptr = pthread_getspecific(_envKey) else { return EnvironmentValues() }
    return Unmanaged<EnvironmentBox>.fromOpaque(ptr).takeUnretainedValue().values
}
'''
    old_windows_environment = '''public func getCurrentEnvironment() -> EnvironmentValues {
    guard let ptr = TlsGetValue(_tlsIndex) else {
        return EnvironmentTaskLocal.values ?? EnvironmentValues()
    }
    return Unmanaged<EnvironmentBox>.fromOpaque(ptr).takeUnretainedValue().values
}
'''
    new_windows_environment = '''public func getCurrentEnvironment() -> EnvironmentValues {
    if let taskEnvironment = EnvironmentTaskLocal.values {
        return taskEnvironment
    }
    guard let ptr = TlsGetValue(_tlsIndex) else { return EnvironmentValues() }
    return Unmanaged<EnvironmentBox>.fromOpaque(ptr).takeUnretainedValue().values
}
'''
    old_fallback_environment = '''public func getCurrentEnvironment() -> EnvironmentValues {
    _currentEnvironment ?? EnvironmentTaskLocal.values ?? EnvironmentValues()
}
'''
    new_fallback_environment = '''public func getCurrentEnvironment() -> EnvironmentValues {
    EnvironmentTaskLocal.values ?? _currentEnvironment ?? EnvironmentValues()
}
'''
    for old, new, message in [
        (old_posix_environment, new_posix_environment, "POSIX"),
        (old_windows_environment, new_windows_environment, "Windows"),
        (old_fallback_environment, new_fallback_environment, "fallback"),
    ]:
        if old not in text:
            raise SystemExit(f"SwiftOpenUI {message} task environment precedence shape was not recognized")
        text = text.replace(old, new, 1)
old_presentation_precedence = '''public func swiftOpenUICurrentPresentationDismissAction() -> (() -> Void)? {
    _presentationDismissActionStack.last ?? PresentationDismissTaskLocal.context?.action
}
'''
new_presentation_precedence = '''public func swiftOpenUICurrentPresentationDismissAction() -> (() -> Void)? {
    PresentationDismissTaskLocal.context?.action ?? _presentationDismissActionStack.last
}
'''
if old_presentation_precedence in text:
    text = text.replace(old_presentation_precedence, new_presentation_precedence, 1)
elif new_presentation_precedence not in text:
    raise SystemExit("SwiftOpenUI presentation task context precedence shape was not recognized")
if "private final class EnvironmentInjectedObjectStorage" not in text:
    object_environment_protocol = '''public protocol AnyObjectInjectionEnvironment {
    func wireInjectedObject(to host: AnyViewHost?)
}
'''
    object_environment_storage = object_environment_protocol + '''
private final class EnvironmentInjectedObjectStorage {
    private let lock = NSLock()
    private var object: AnyObject?

    func store(_ object: AnyObject) {
        lock.lock()
        self.object = object
        lock.unlock()
    }

    func load() -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        return object
    }
}
'''
    if object_environment_protocol not in text:
        raise SystemExit("SwiftOpenUI injected environment object storage insertion shape was not recognized")
    text = text.replace(
        object_environment_protocol,
        object_environment_storage,
        1,
    )

    old_injected_object_reader = '''        self.reader = .injectedObject {
            guard let object = getCurrentEnvironment().getObject(type) else {
                fatalError(
                    "@Environment(\\(type).self) lookup failed — no object of this type was injected. " +
                    "Call `.environment(object)` on an ancestor view."
                )
            }
            // Record the read so the enclosing ViewHost can re-push
            // this object into env on rebuild, even if the
            // `.environment(object)` modifier that originally pushed
            // it lives inside a parent's body (between two ViewHosts
            // in the render tree) and wouldn't otherwise be
            // guaranteed to re-run before this read fires again.
            recordEnvironmentRead(typeID: ObjectIdentifier(type), object: object)
            return object
        }
'''
    new_injected_object_reader = '''        let storage = EnvironmentInjectedObjectStorage()
        self.reader = .injectedObject {
            if let object = getCurrentEnvironment().getObject(type) {
                storage.store(object)
                // Record the read so the enclosing ViewHost can re-push
                // this object into env on rebuild, even if the
                // `.environment(object)` modifier that originally pushed
                // it lives inside a parent's body (between two ViewHosts
                // in the render tree) and wouldn't otherwise be
                // guaranteed to re-run before this read fires again.
                recordEnvironmentRead(typeID: ObjectIdentifier(type), object: object)
                return object
            }
            if let object = storage.load() as? Value {
                return object
            }
            fatalError(
                "@Environment(\\(type).self) lookup failed — no object of this type was injected. " +
                "Call `.environment(object)` on an ancestor view."
            )
        }
'''
    if old_injected_object_reader not in text:
        raise SystemExit("SwiftOpenUI injected environment object reader shape was not recognized")
    text = text.replace(
        old_injected_object_reader,
        new_injected_object_reader,
        1,
    )
if text != original:
    path.write_text(text)
PY

python3 - "$GTK_VIEW_HOST" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
if "rebuildPresentationRoot" not in text:
    text = text.replace(
        """    private var observationDidFire = false
    var capturedEnvironment: EnvironmentValues
""",
        """    private var observationDidFire = false
    var rebuildPresentationRoot: gpointer?
    var capturedEnvironment: EnvironmentValues
""",
        1,
    )
    text = text.replace(
        """        g_object_ref(gpointer(container))
        defer { g_object_unref(gpointer(container)) }
""",
        """        g_object_ref(gpointer(container))
        defer { g_object_unref(gpointer(container)) }
        let presentationRoot = gtk_widget_get_root(container).map { gpointer($0) }
        if let presentationRoot {
            g_object_ref(presentationRoot)
        }
        rebuildPresentationRoot = presentationRoot
        defer {
            if let presentationRoot {
                g_object_unref(presentationRoot)
            }
            rebuildPresentationRoot = nil
        }
""",
        1,
    )
if "stateIdentityNamespace" not in text:
    if "    var rebuildPresentationRoot: gpointer?\n    var capturedEnvironment: EnvironmentValues\n" in text:
        text = text.replace(
            "    var rebuildPresentationRoot: gpointer?\n    var capturedEnvironment: EnvironmentValues\n",
            "    var rebuildPresentationRoot: gpointer?\n    var stateIdentityNamespace = \"root\"\n    var capturedEnvironment: EnvironmentValues\n",
            1,
        )
    elif "    var capturedEnvironment: EnvironmentValues\n" in text:
        text = text.replace(
            "    var capturedEnvironment: EnvironmentValues\n",
            "    var stateIdentityNamespace = \"root\"\n    var capturedEnvironment: EnvironmentValues\n",
            1,
        )
    else:
        raise SystemExit("SwiftOpenUI GTKViewHost state identity namespace insertion point was not recognized")

if "lastRenderTaskPayloads" not in text:
    marker = """    private var taskPayloadsByIdentity: [GTK4DescriptorIdentity: GTK4TaskPayload] = [:]
    private var activeTasksByIdentity: [GTK4DescriptorIdentity: GTKActiveTask] = [:]
"""
    replacement = marker + """    var lastRenderOnAppearPayloads: [GTK4OnAppearPayload] = []
    var lastRenderTaskPayloads: [GTK4TaskPayload] = []
"""
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost render lifecycle payload storage shape was not recognized")
    text = text.replace(marker, replacement, 1)

if "buildBodyCapturingRenderLifecyclePayloads" not in text:
    observation_old = """            withObservationTracking {
                gtkBeginStateIdentityPass()
                result = buildBody()
            } onChange: { [weak self] in
"""
    observation_old_without_state_pass = """            withObservationTracking {
                result = buildBody()
            } onChange: { [weak self] in
"""
    observation_new = """            withObservationTracking {
                result = buildBodyCapturingRenderLifecyclePayloads()
            } onChange: { [weak self] in
"""
    fallback_old = """        gtkBeginStateIdentityPass()
        let result = buildBody()
"""
    fallback_old_without_state_pass = """        let result = buildBody()
"""
    fallback_new = """        let result = buildBodyCapturingRenderLifecyclePayloads()
"""
    if observation_old not in text:
        observation_old = observation_old_without_state_pass
    if fallback_old not in text:
        fallback_old = fallback_old_without_state_pass
    if observation_old not in text or fallback_old not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost state identity pass shape was not recognized")
    text = text.replace(observation_old, observation_new, 1)
    text = text.replace(fallback_old, fallback_new, 1)
    helper_marker = """    /// Re-runs the describe pass under a fresh withObservationTracking
"""
    helper = """    private func buildBodyCapturingRenderLifecyclePayloads() -> OpaquePointer {
        gtkWithForcedStateIdentityNamespace(stateIdentityNamespace) {
            gtkWithOwnedDescriptorLifecyclePayloads {
                let captured = gtkCaptureRenderLifecyclePayloads {
                    buildBody()
                }
                lastRenderOnAppearPayloads = captured.onAppearPayloads
                lastRenderTaskPayloads = captured.taskPayloads
                return captured.value
            }
        }
    }

    func renderCapturedOnAppearPayloads(fallback described: [GTK4OnAppearPayload]) -> [GTK4OnAppearPayload] {
        lastRenderOnAppearPayloads.count == described.count ? lastRenderOnAppearPayloads : described
    }

    func renderCapturedTaskPayloads(fallback described: [GTK4TaskPayload]) -> [GTK4TaskPayload] {
        lastRenderTaskPayloads.count == described.count ? lastRenderTaskPayloads : described
    }

"""
    if helper_marker not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost render lifecycle helper insertion point was not recognized")
    text = text.replace(helper_marker, helper + helper_marker, 1)
elif "renderCapturedTaskPayloads(fallback described" not in text:
    raise SystemExit("SwiftOpenUI GTKViewHost render lifecycle helper shape was not recognized")

legacy_render_helper = """    private func buildBodyCapturingRenderLifecyclePayloads() -> OpaquePointer {
        gtkBeginStateIdentityPass()
        let captured = gtkCaptureRenderLifecyclePayloads {
            buildBody()
        }
        lastRenderOnAppearPayloads = captured.onAppearPayloads
        lastRenderTaskPayloads = captured.taskPayloads
        return captured.value
    }
"""
namespace_render_helper = """    private func buildBodyCapturingRenderLifecyclePayloads() -> OpaquePointer {
        gtkWithForcedStateIdentityNamespace(stateIdentityNamespace) {
            let captured = gtkCaptureRenderLifecyclePayloads {
                buildBody()
            }
            lastRenderOnAppearPayloads = captured.onAppearPayloads
            lastRenderTaskPayloads = captured.taskPayloads
            return captured.value
        }
    }
"""
stable_render_helper = """    private func buildBodyCapturingRenderLifecyclePayloads() -> OpaquePointer {
        gtkWithForcedStateIdentityNamespace(stateIdentityNamespace) {
            gtkWithOwnedDescriptorLifecyclePayloads {
                let captured = gtkCaptureRenderLifecyclePayloads {
                    buildBody()
                }
                lastRenderOnAppearPayloads = captured.onAppearPayloads
                lastRenderTaskPayloads = captured.taskPayloads
                return captured.value
            }
        }
    }
"""
if legacy_render_helper in text:
    text = text.replace(legacy_render_helper, stable_render_helper, 1)
elif namespace_render_helper in text:
    text = text.replace(namespace_render_helper, stable_render_helper, 1)
elif (
    "private func buildBodyCapturingRenderLifecyclePayloads() -> OpaquePointer" not in text
    or "gtkWithForcedStateIdentityNamespace(stateIdentityNamespace)" not in text
    or "gtkWithOwnedDescriptorLifecyclePayloads" not in text
):
    raise SystemExit("SwiftOpenUI GTKViewHost lifecycle-owned render shape was not recognized")

legacy_describe_scope = """        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(self)
        gtkBeginStateIdentityPass()
        defer { GTKViewHost.setCurrentRebuilding(previousHost) }
        return gtkDescribeCapturingCanvasPayloads(describeBody)
"""
stable_describe_scope = """        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(self)
        defer { GTKViewHost.setCurrentRebuilding(previousHost) }
        return gtkWithForcedStateIdentityNamespace(stateIdentityNamespace) {
            gtkDescribeCapturingCanvasPayloads(describeBody)
        }
"""
owned_describe_scope = """        let previousHost = GTKViewHost.getCurrentRebuilding()
        GTKViewHost.setCurrentRebuilding(self)
        defer { GTKViewHost.setCurrentRebuilding(previousHost) }
        return gtkWithForcedStateIdentityNamespace(stateIdentityNamespace) {
            gtkWithOwnedDescriptorLifecyclePayloads {
                gtkDescribeCapturingCanvasPayloads(describeBody)
            }
        }
"""
if legacy_describe_scope in text:
    text = text.replace(legacy_describe_scope, owned_describe_scope, 1)
elif stable_describe_scope in text:
    text = text.replace(stable_describe_scope, owned_describe_scope, 1)
elif owned_describe_scope not in text:
    raise SystemExit("SwiftOpenUI GTKViewHost lifecycle-owned describe shape was not recognized")

text = text.replace(
    "onAppearPayloads: described.onAppearPayloads",
    "onAppearPayloads: renderCapturedOnAppearPayloads(fallback: described.onAppearPayloads)",
)
text = text.replace(
    "taskPayloads: described.taskPayloads",
    "taskPayloads: renderCapturedTaskPayloads(fallback: described.taskPayloads)",
)
if "renderCapturedTaskPayloads(fallback: described.taskPayloads)" not in text:
    raise SystemExit("SwiftOpenUI GTKViewHost render lifecycle reconciliation shape was not recognized")
if "resumeLifecycleAfterProgrammaticVisibilityChange" not in text:
    old = '''    fileprivate func restoreLifecycleSnapshot(_ snapshot: GTKViewHostLifecycleSnapshot) {
        lock.lock()
        appearedOnAppearIdentities.formUnion(snapshot.appearedOnAppearIdentities)
        for (identity, activeTask) in snapshot.activeTasksByIdentity {
            activeTasksByIdentity[identity] = activeTask
        }
        lock.unlock()
    }
'''
    new = old + '''
    func resumeLifecycleAfterProgrammaticVisibilityChange() {
        resumeTasksAfterAppear()
    }
'''
    if old not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost lifecycle restore shape was not recognized")
    text = text.replace(old, new, 1)
if "gtkResumeViewHostLifecycleForVisibleSubtree" not in text:
    old = '''private let gtkViewHostWidthTickCallback: GtkTickCallback = { _, _, userData in
'''
    new = '''func gtkResumeViewHostLifecycleForVisibleSubtree(_ widget: UnsafeMutablePointer<GtkWidget>) {
    func walk(_ node: UnsafeMutablePointer<GtkWidget>, depth: Int) {
        guard depth < 128, gtk_swift_is_widget(node) != 0 else { return }
        if let rawHost = g_object_get_data(
            UnsafeMutableRawPointer(node).assumingMemoryBound(to: GObject.self),
            "gtk-swift-view-host"
        ) {
            let host = Unmanaged<GTKViewHost>.fromOpaque(rawHost).takeUnretainedValue()
            host.resumeLifecycleAfterProgrammaticVisibilityChange()
        }

        var child = gtk_widget_get_first_child(node)
        while let current = child {
            walk(current, depth: depth + 1)
            child = gtk_widget_get_next_sibling(current)
        }
    }

    walk(widget, depth: 0)
}

''' + old
    if old not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost width tick callback shape was not recognized")
    text = text.replace(old, new, 1)
if "capturedInjectedObjects: [ObjectIdentifier: EnvironmentObjectCapture]" not in text:
    old_capture_storage = "    private var capturedInjectedObjects: [ObjectIdentifier: AnyObject] = [:]\n"
    new_capture_storage = "    private var capturedInjectedObjects: [ObjectIdentifier: EnvironmentObjectCapture] = [:]\n"
    if old_capture_storage not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost scoped environment capture storage was not recognized")
    text = text.replace(old_capture_storage, new_capture_storage, 1)

    old_rebuild_environment = '''        for (typeID, object) in capturedInjectedObjects {
            env.setLatestObjectByID(typeID, fallback: object)
        }
'''
    new_rebuild_environment = '''        for (typeID, capture) in capturedInjectedObjects {
            env.setLatestObjectByID(
                typeID,
                fallback: capture.object,
                scope: capture.scope
            )
        }
'''
    if old_rebuild_environment not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost scoped environment rebuild shape was not recognized")
    text = text.replace(old_rebuild_environment, new_rebuild_environment, 1)

    read_capture = "            if let reads = endEnvironmentReadTracking() {\n"
    fallback_read_capture = "        if let reads = endEnvironmentReadTracking() {\n"
    if read_capture not in text or fallback_read_capture not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost scoped environment read completion shape was not recognized")
    text = text.replace(
        read_capture,
        "            if let reads = endScopedEnvironmentReadTracking() {\n",
        1,
    )
    text = text.replace(
        fallback_read_capture,
        "        if let reads = endScopedEnvironmentReadTracking() {\n",
        1,
    )
if text != original:
    path.write_text(text)
PY

python3 - "$LAYOUT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
old = '''    if let maxWidth, maxWidth != .infinity { containerWidth = min(containerWidth, maxWidth) }
    if let maxHeight, maxHeight != .infinity { containerHeight = min(containerHeight, maxHeight) }
'''
new = '''    if let maxWidth, maxWidth != .infinity {
        containerWidth = expandsToFillWidth && width == nil ? maxWidth : min(containerWidth, maxWidth)
    }
    if let maxHeight, maxHeight != .infinity {
        containerHeight = expandsToFillHeight && height == nil ? maxHeight : min(containerHeight, maxHeight)
    }
'''
if "expandsToFillWidth && width == nil ? maxWidth" not in text:
    text = text.replace(old, new, 1)
if text != original:
    path.write_text(text)
PY

python3 - "$GTK_BACKEND" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
root_overlay_helpers = '''private let gtkRootPresentationOverlayKey = "quillui-root-presentation-overlay"
private var gtkRootPresentationOverlayFallback: OpaquePointer?

func gtkCreateRootPresentationContainer(
    winPtr: UnsafeMutablePointer<GtkWindow>,
    contentWidget: UnsafeMutablePointer<GtkWidget>
) -> UnsafeMutablePointer<GtkWidget> {
    let overlay = gtk_overlay_new()!
    gtk_widget_set_hexpand(overlay, 1)
    gtk_widget_set_vexpand(overlay, 1)
    gtk_widget_set_halign(overlay, GTK_ALIGN_FILL)
    gtk_widget_set_valign(overlay, GTK_ALIGN_FILL)

    gtk_widget_set_hexpand(contentWidget, 1)
    gtk_widget_set_vexpand(contentWidget, 1)
    gtk_widget_set_halign(contentWidget, GTK_ALIGN_FILL)
    gtk_widget_set_valign(contentWidget, GTK_ALIGN_FILL)
    gtk_overlay_set_child(OpaquePointer(overlay), contentWidget)

    gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: widgetPointer(winPtr))
    gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: overlay)
    gtkStoreRootPresentationOverlay(OpaquePointer(overlay), on: contentWidget)
    gtkRootPresentationOverlayFallback = OpaquePointer(overlay)
    return overlay
}

func gtkStoreRootPresentationOverlay(
    _ rootOverlay: OpaquePointer,
    on widget: UnsafeMutablePointer<GtkWidget>
) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, gtkRootPresentationOverlayKey, UnsafeMutableRawPointer(rootOverlay))
}

func gtkStoredRootPresentationOverlay(on widget: gpointer) -> OpaquePointer? {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    guard let overlayPtr = g_object_get_data(gobject, gtkRootPresentationOverlayKey) else { return nil }
    let overlay = overlayPtr.assumingMemoryBound(to: GtkWidget.self)
    return OpaquePointer(overlay)
}

func gtkRootPresentationOverlay(for root: gpointer) -> OpaquePointer? {
    gtkStoredRootPresentationOverlay(on: root) ?? gtkRootPresentationOverlayFallback
}

func gtkFallbackRootPresentationOverlay() -> OpaquePointer? {
    gtkRootPresentationOverlayFallback
}

'''
if "gtkRootPresentationOverlayKey" not in text:
    marker = "func gtkConfigureRootContentToFillWindow"
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTK root presentation helper insertion point was not recognized")
    text = text.replace(marker, root_overlay_helpers + marker, 1)
old = '''        case .automatic:
            return (
                defaultWindowWidth ?? defaultAutomaticWindowWidth,
                defaultWindowHeight ?? defaultAutomaticWindowHeight
            )
'''
new = '''        case .automatic:
            let environment = ProcessInfo.processInfo.environment
            func environmentDouble(_ canonical: String, legacy: String) -> Double? {
                (environment[canonical] ?? environment[legacy]).flatMap(Double.init)
            }
            let requestedWidth = environmentDouble(
                "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH",
                legacy: "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"
            )
            let requestedHeight = environmentDouble(
                "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT",
                legacy: "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT"
            )
            return (
                requestedWidth ?? defaultWindowWidth ?? defaultAutomaticWindowWidth,
                requestedHeight ?? defaultWindowHeight ?? defaultAutomaticWindowHeight
            )
'''
legacy_new = '''        case .automatic:
            let environment = ProcessInfo.processInfo.environment
            let requestedWidth = environment["QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"].flatMap(Double.init)
            let requestedHeight = environment["QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT"].flatMap(Double.init)
            return (
                requestedWidth ?? defaultWindowWidth ?? defaultAutomaticWindowWidth,
                requestedHeight ?? defaultWindowHeight ?? defaultAutomaticWindowHeight
            )
'''
if "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH" not in text:
    if legacy_new in text:
        text = text.replace(legacy_new, new, 1)
    else:
        text = text.replace(old, new, 1)
old_default_size = '''        if let defaultSize = gtkResolvedDefaultWindowSize() {
            gtk_window_set_default_size(
                winPtr,
                gint(defaultSize.width),
                gint(defaultSize.height)
            )
        }
'''
new_default_size = '''        if let defaultSize = gtkResolvedDefaultWindowSize() {
            gtk_window_set_default_size(
                winPtr,
                gint(defaultSize.width),
                gint(defaultSize.height)
            )
            gtk_widget_set_size_request(
                contentWidget,
                gint(defaultSize.width),
                gint(defaultSize.height)
            )
        }
'''
if "gtk_widget_set_size_request(\n                contentWidget,\n                gint(defaultSize.width)" not in text:
    text = text.replace(old_default_size, new_default_size, 1)
root_content_old = '''        gtkConfigureRootContentToFillWindow(contentWidget)

        gtk_window_set_child(winPtr, contentWidget)
        let winWidget = widgetPointer(winPtr)
        gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: contentWidget, windowID: Int(bitPattern: winPtr))
'''
root_content_new = '''        let rootContentWidget = gtkCreateRootPresentationContainer(winPtr: winPtr, contentWidget: contentWidget)
        gtkConfigureRootContentToFillWindow(rootContentWidget)

        gtk_window_set_child(winPtr, rootContentWidget)
        let winWidget = widgetPointer(winPtr)
        gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: rootContentWidget, windowID: Int(bitPattern: winPtr))
'''
if "gtkCreateRootPresentationContainer(winPtr: winPtr, contentWidget: contentWidget)" not in text:
    if root_content_old not in text:
        raise SystemExit("SwiftOpenUI GTK root presentation content insertion shape was not recognized")
    text = text.replace(root_content_old, root_content_new)
old_menubar_label = '''        gtk_swift_menu_append_submenu(menuModel, "File", fileMenu)
'''
new_menubar_label = '''        let environment = ProcessInfo.processInfo.environment
        let topLevelMenuTitle = (
            environment["QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL"]
                ?? environment["QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL"]
        ) == "1" ? " " : "File"
        gtk_swift_menu_append_submenu(menuModel, topLevelMenuTitle, fileMenu)
'''
legacy_menubar_label = '''        let topLevelMenuTitle = ProcessInfo.processInfo.environment["QUILLUI_GTK_HIDE_WINDOW_MENUBAR_LABEL"] == "1" ? " " : "File"
        gtk_swift_menu_append_submenu(menuModel, topLevelMenuTitle, fileMenu)
'''
if "QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR_LABEL" not in text:
    if legacy_menubar_label in text:
        text = text.replace(legacy_menubar_label, new_menubar_label, 1)
    else:
        text = text.replace(old_menubar_label, new_menubar_label, 1)
menu_visibility_helpers = '''private func gtkEnvironmentFlag(_ canonical: String, legacy: String) -> Bool? {
    guard let rawValue = ProcessInfo.processInfo.environment[canonical]
        ?? ProcessInfo.processInfo.environment[legacy]
    else {
        return nil
    }
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["1", "true", "yes", "on"].contains(normalized) { return true }
    if ["0", "false", "no", "off"].contains(normalized) { return false }
    return nil
}

private func gtkShouldShowWindowMenuBar() -> Bool {
    if let explicitShow = gtkEnvironmentFlag(
        "QUILLUI_BACKEND_SHOW_WINDOW_MENUBAR",
        legacy: "QUILLUI_GTK_SHOW_WINDOW_MENUBAR"
    ) {
        return explicitShow
    }
    if let explicitHide = gtkEnvironmentFlag(
        "QUILLUI_BACKEND_HIDE_WINDOW_MENUBAR",
        legacy: "QUILLUI_GTK_HIDE_WINDOW_MENUBAR"
    ) {
        return !explicitHide
    }
    return false
}

'''
if "private func gtkShouldShowWindowMenuBar" not in text:
    marker = "private final class MenuActionClosure"
    if marker in text:
        text = text.replace(marker, menu_visibility_helpers + marker, 1)
    elif "\nextension WindowGroup" in text:
        text = text.replace("\nextension WindowGroup", "\n" + menu_visibility_helpers + "extension WindowGroup", 1)
    else:
        raise SystemExit("SwiftOpenUI GTK menu action closure shape was not recognized")
root_content_menubar_setup = """        gtk_window_set_child(winPtr, rootContentWidget)
        let winWidget = widgetPointer(winPtr)
        gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: rootContentWidget, windowID: Int(bitPattern: winPtr))
"""
window_group_menubar_setup = """        gtk_window_set_child(winPtr, rootContentWidget)
        let winWidget = widgetPointer(winPtr)
        if !quillHidesTitleBar && gtkShouldShowWindowMenuBar() {
            gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: rootContentWidget, windowID: Int(bitPattern: winPtr))
        } else {
            gtkSetupCommandShortcutsIfNeeded(winPtr: winWidget, windowID: Int(bitPattern: winPtr))
        }
"""
window_menubar_setup = """        gtk_window_set_child(winPtr, rootContentWidget)
        let winWidget = widgetPointer(winPtr)
        if gtkShouldShowWindowMenuBar() {
            gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: rootContentWidget, windowID: Int(bitPattern: winPtr))
        } else {
            gtkSetupCommandShortcutsIfNeeded(winPtr: winWidget, windowID: Int(bitPattern: winPtr))
        }
"""
legacy_content_menubar_setup = """        gtk_window_set_child(winPtr, contentWidget)
        let winWidget = widgetPointer(winPtr)
        gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: contentWidget, windowID: Int(bitPattern: winPtr))
"""
legacy_window_menubar_setup = """        gtk_window_set_child(winPtr, contentWidget)
        let winWidget = widgetPointer(winPtr)
        if gtkShouldShowWindowMenuBar() {
            gtkSetupMenuBarIfNeeded(winPtr: winWidget, contentWidget: contentWidget, windowID: Int(bitPattern: winPtr))
        } else {
            gtkSetupCommandShortcutsIfNeeded(winPtr: winWidget, windowID: Int(bitPattern: winPtr))
        }
"""
old_window_group_menubar_setup = window_menubar_setup
if old_window_group_menubar_setup in text and window_group_menubar_setup not in text:
    text = text.replace(old_window_group_menubar_setup, window_group_menubar_setup, 1)
if root_content_menubar_setup in text:
    text = text.replace(root_content_menubar_setup, window_group_menubar_setup, 1)
if root_content_menubar_setup in text:
    text = text.replace(root_content_menubar_setup, window_menubar_setup, 1)
if legacy_content_menubar_setup in text:
    text = text.replace(legacy_content_menubar_setup, legacy_window_menubar_setup, 1)
text = text.replace(
    "/// Protocol for scenes that can render onto a GtkApplication.",
    "/// Protocol for scenes that can render onto GTK top-level windows.",
    1,
)
text = text.replace("func gtkRender(app: OpaquePointer)", "func gtkRender(app: OpaquePointer?)")
text = text.replace("func gtkCreateWindow(app: OpaquePointer)", "func gtkCreateWindow(app: OpaquePointer?)")
application_window = '''        let window = gtk_application_window_new(gtkApplicationPointer(app))!
'''
plain_window = '''        let window: UnsafeMutablePointer<GtkWidget>
        if let app {
            window = gtk_application_window_new(gtkApplicationPointer(app))!
        } else {
            window = gtk_window_new()!
        }
'''
if application_window in text:
    text = text.replace(application_window, plain_window)
plain_lifecycle = '''        let factory: (OpaquePointer?) -> Void = { appPtr in
            // Inject openWindow action into the environment so views
            // can programmatically open Window scenes by id.
            var env = getCurrentEnvironment()
            env.openWindow = OpenWindowAction { id in
                GTK4WindowRegistry.shared.open(id: id)
            }
            setCurrentEnvironment(env)

            MainActor.assumeIsolated {
                let instance = A()
                gtkRenderScene(instance.body, app: appPtr)
            }
        }

        // Pump Foundation RunLoop sources (Timer, etc.) periodically.
        // GTK4's GMainLoop blocks the thread, so Foundation
        // timers (e.g. Timer.scheduledTimer) never fire unless we
        // explicitly spin RunLoop.main from a GLib timeout source.
        g_timeout_add(5, { _ -> gboolean in
            let limit = Date(timeIntervalSinceNow: 0.001)
            _ = RunLoop.main.run(mode: .default, before: limit)
            return 1 // G_SOURCE_CONTINUE
        }, nil)

        if gtk_init_check() == 0 {
            return
        }
        factory(nil)

        let loop = g_main_loop_new(nil, 0)
        g_main_loop_run(loop)
        g_main_loop_unref(loop)
'''
start = text.find("        let gtkApp = gtk_application_new")
if start != -1:
    end = text.find("\n    }\n}\n\n/// GTK4 rendering for Window", start)
    if end == -1:
        raise SystemExit("SwiftOpenUI GTK application lifecycle shape was not recognized")
    text = text[:start] + plain_lifecycle + text[end:]
group_scene_rendering = '''
/// GTK4 rendering for Group<Scene> — transparent scene grouping.
extension Group: GTKWindowRenderable where Content: Scene {
    func gtkRender(app: OpaquePointer?) {
        gtkRenderScene(content, app: app)
    }
}

'''
if "extension Group: GTKWindowRenderable where Content: Scene" not in text:
    marker = "/// Registry for single-instance Window scenes. Tracks factories and live\n"
    if marker in text:
        text = text.replace(marker, group_scene_rendering + marker, 1)
    else:
        text = text.rstrip() + "\n\n" + group_scene_rendering
if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
needle = '''        gtk_widget_set_tooltip_text(widget, text)
        return opaqueFromWidget(widget)
'''
replacement = '''        gtk_widget_set_tooltip_text(widget, text)
        text.withCString { textPointer in
            gtk_swift_accessible_update_description(widget, textPointer)
        }
        return opaqueFromWidget(widget)
'''
helpStart = text.find("extension HelpView: GTKRenderable")
helpEnd = text.find("\n// MARK: - Clip Shape GTK extensions", helpStart)
if helpStart == -1 or helpEnd == -1:
    raise SystemExit("SwiftOpenUI GTK HelpView renderer shape was not recognized")
helpRenderer = text[helpStart:helpEnd]
if "gtk_swift_accessible_update_description(widget, textPointer)" not in helpRenderer:
    if needle not in helpRenderer:
        raise SystemExit("SwiftOpenUI GTK HelpView renderer shape was not recognized")
    helpRenderer = helpRenderer.replace(needle, replacement, 1)
    text = text[:helpStart] + helpRenderer + text[helpEnd:]
if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

old_init = '''    init<Data, Content: View>(items: [Data], contentBuilder: @escaping (Data) -> Content,
                              cellMinWidth: Int) {
        self.itemCount = items.count
        self.cellMinWidth = cellMinWidth
        self.renderItem = { index in
            widgetFromOpaque(gtkRenderView(contentBuilder(items[index])))
        }
    }
'''
new_init = old_init + '''
    init(views: [any View], cellMinWidth: Int) {
        self.itemCount = views.count
        self.cellMinWidth = cellMinWidth
        self.renderItem = { index in
            widgetFromOpaque(gtkRenderAnyView(views[index]))
        }
    }
'''
if "init(views: [any View], cellMinWidth: Int)" not in text:
    text = text.replace(old_init, new_init)

old_list = '''    let stringList = gtk_swift_string_list_new()!
    for i in 0..<items.count {
        gtk_swift_string_list_append(stringList, "\\(i)")
    }
'''
new_list = '''    let expandedChildren: [any View]? = {
        guard items.count == 1 else { return nil }
        let built = contentBuilder(items[0])
        guard let multi = built as? MultiChildView else { return nil }
        return multi.children
    }()
    let itemCount = expandedChildren?.count ?? items.count

    let stringList = gtk_swift_string_list_new()!
    for i in 0..<itemCount {
        gtk_swift_string_list_append(stringList, "\\(i)")
    }
'''
grid_marker = "private func gtkCreateLazyGridWidget"
grid_start = text.index(grid_marker)
prefix = text[:grid_start]
grid_text = text[grid_start:]
if "let itemCount = expandedChildren?.count ?? items.count" not in grid_text:
    grid_text = grid_text.replace(old_list, new_list, 1)

old_context = '''    let context = LazyGridContext(items: items, contentBuilder: contentBuilder,
                                  cellMinWidth: cellMinWidth)
'''
new_context = '''    let context: LazyGridContext
    if let expandedChildren {
        context = LazyGridContext(views: expandedChildren, cellMinWidth: cellMinWidth)
    } else {
        context = LazyGridContext(items: items, contentBuilder: contentBuilder,
                                  cellMinWidth: cellMinWidth)
    }
'''
if "context = LazyGridContext(views: expandedChildren" not in grid_text:
    grid_text = grid_text.replace(old_context, new_context, 1)
old_cell_min_width = "    let cellMinWidth = configuration.adaptiveMinimum\n"
new_cell_min_width = """    let cellMinWidth = configuration.adaptiveMinimum > 0
        ? configuration.adaptiveMinimum
        : (configuration.maxColumns > 1 ? 160 : 0)
"""
if "let cellMinWidth = configuration.adaptiveMinimum > 0" not in grid_text:
    if old_cell_min_width not in grid_text:
        raise SystemExit("SwiftOpenUI LazyGrid cell width shape was not recognized")
    grid_text = grid_text.replace(old_cell_min_width, new_cell_min_width, 1)

static_grid_helper = '''private func gtkCreateStaticLazyGridWidget(
    views: [any View],
    configuration: LazyGridConfiguration,
    cellMinWidth: Int,
    orientation: GtkOrientation
) -> OpaquePointer? {
    guard !views.isEmpty else { return nil }
    guard orientation == GTK_ORIENTATION_VERTICAL else { return nil }
    guard views.count <= 64 else { return nil }

    let columns = max(1, min(max(configuration.maxColumns, configuration.minColumns), views.count))
    let grid = gtk_grid_new()!
    gtk_swift_grid_set_row_spacing(grid, 15)
    gtk_swift_grid_set_column_spacing(grid, 15)
    gtk_swift_grid_set_column_homogeneous(grid, 1)
    gtk_widget_set_hexpand(grid, 1)
    gtk_widget_set_halign(grid, GTK_ALIGN_FILL)

    for (index, view) in views.enumerated() {
        let child = widgetFromOpaque(gtkRenderAnyView(view))
        let slot = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(slot, 1)
        gtk_widget_set_halign(slot, GTK_ALIGN_FILL)
        gtk_widget_set_hexpand(child, 1)
        gtk_widget_set_halign(child, GTK_ALIGN_FILL)
        if cellMinWidth > 0 {
            gtk_widget_set_size_request(slot, gint(cellMinWidth), -1)
        }
        gtk_box_append(boxPointer(slot), child)
        gtk_swift_grid_attach(
            grid,
            slot,
            gint(index % columns),
            gint(index / columns),
            1,
            1
        )
    }

    return opaqueFromWidget(grid)
}

'''
if "private func gtkCreateStaticLazyGridWidget(" not in grid_text:
    grid_text = grid_text.replace(
        "private func gtkCreateLazyGridWidget",
        static_grid_helper + "private func gtkCreateLazyGridWidget",
        1,
    )
while grid_text.count("private func gtkCreateStaticLazyGridWidget(") > 1:
    first = grid_text.find("private func gtkCreateStaticLazyGridWidget(")
    second = grid_text.find("private func gtkCreateStaticLazyGridWidget(", first + 1)
    lazy = grid_text.find("private func gtkCreateLazyGridWidget", second)
    if second == -1 or lazy == -1:
        break
    grid_text = grid_text[:second] + grid_text[lazy:]
static_grid_return = '''    if let expandedChildren,
       let staticGrid = gtkCreateStaticLazyGridWidget(
            views: expandedChildren,
            configuration: configuration,
            cellMinWidth: cellMinWidth,
            orientation: orientation
       ) {
        return staticGrid
    }

'''
if "let staticGrid = gtkCreateStaticLazyGridWidget" not in grid_text:
    grid_text = grid_text.replace(
        "    let context: LazyGridContext\n",
        static_grid_return + "    let context: LazyGridContext\n",
        1,
    )

text = prefix + grid_text
while text.count("private func gtkCreateStaticLazyGridWidget(") > 1:
    first = text.find("private func gtkCreateStaticLazyGridWidget(")
    second = text.find("private func gtkCreateStaticLazyGridWidget(", first + 1)
    end = text.find("\n}\n\n", second)
    if second == -1 or end == -1:
        break
    text = text[:second] + text[end + 4:]
if text != original:
    path.write_text(text)
PY

python3 - "$TOOLBAR_MODIFIER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

old = '''public struct AnyToolbarItem {
    public let placement: ToolbarItemPlacement
    public let wrapped: any View

    public init<Content: View>(_ item: ToolbarItem<Content>) {
        self.placement = item.placement
        self.wrapped = item.content
    }
}
'''
new = '''public struct AnyToolbarItem {
    public let placement: ToolbarItemPlacement
    public let wrapped: any View
    public let renderedViews: [any View]

    public init<Content: View>(_ item: ToolbarItem<Content>) {
        self.placement = item.placement
        self.wrapped = item.content
        if let multi = item.content as? MultiChildView {
            self.renderedViews = multi.children
        } else if Content.Body.self != Never.self {
            // View.body is @MainActor (Apple semantics); toolbar erasure only
            // happens during render on the GTK main loop == the main thread,
            // so the assumption always holds (blessed boundary pattern).
            let body = MainActor.assumeIsolated { item.content.body }
            if let multi = body as? MultiChildView {
                self.renderedViews = multi.children
            } else {
                self.renderedViews = [body]
            }
        } else {
            self.renderedViews = [item.content]
        }
    }
}
'''
if "public let renderedViews: [any View]" not in text:
    text = text.replace(old, new)
if "public let renderedViews: [any View]" not in text:
    start = text.find("public struct AnyToolbarItem {")
    marker = "\n/// Protocol for views"
    end = text.find(marker, start)
    if start >= 0 and end > start:
        text = text[:start] + new + text[end:]

if text != original:
    path.write_text(text)
PY

python3 - "$NAVIGATION_DESTINATION" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

if "NavigationPresentedDestinationModifier" not in text:
    marker = "\nextension View {"
    inserted = """\n/// Modifier that pushes a destination when a Boolean binding becomes true.\npublic struct NavigationPresentedDestinationModifier<Content: View, Destination: View>: View {\n    public typealias Body = Never\n\n    public let content: Content\n    public let isPresented: Binding<Bool>\n    public let destination: () -> Destination\n\n    public init(\n        content: Content,\n        isPresented: Binding<Bool>,\n        destination: @escaping () -> Destination\n    ) {\n        self.content = content\n        self.isPresented = isPresented\n        self.destination = destination\n    }\n\n    public var body: Never { fatalError(\"NavigationPresentedDestinationModifier is a primitive view\") }\n}\n"""
    if marker not in text:
        raise SystemExit("SwiftOpenUI NavigationDestination extension shape was not recognized")
    text = text.replace(marker, inserted + marker, 1)

if "isPresented: Binding<Bool>" not in text:
    insertion = """\n    /// Register a destination view that is pushed while `isPresented` is true.\n    public func navigationDestination<Destination: View>(\n        isPresented: Binding<Bool>,\n        @ViewBuilder destination: @escaping () -> Destination\n    ) -> NavigationPresentedDestinationModifier<Self, Destination> {\n        NavigationPresentedDestinationModifier(\n            content: self,\n            isPresented: isPresented,\n            destination: destination\n        )\n    }\n"""
    close = text.rfind("\n}")
    if close < 0:
        raise SystemExit("SwiftOpenUI NavigationDestination closing extension was not recognized")
    text = text[:close] + insertion + text[close:]

if text != original:
    path.write_text(text)
PY

python3 - "$NAVIGATION" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original
text = text.replace(
    "let sidebarW = gtkExtractColumnWidth(from: sidebar) ?? Double(sidebarWidth)",
    "let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))",
)
text = text.replace(
    "let sidebarW = gtkExtractColumnWidth(from: sidebar) ?? max(320.0, Double(sidebarWidth))",
    "let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))",
)
text = text.replace(
    "let sidebarW = gtkExtractColumnWidth(from: sidebar) ?? gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth))",
    "let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))",
)
text = text.replace(
    "        let title = resolved.title.isEmpty ? String(describing: value.base) : resolved.title\n",
    "        let title = resolved.title\n",
)
if "let stateNamespace: String" not in text:
    text = text.replace(
        "    let backButton: UnsafeMutablePointer<GtkWidget>\n"
        "    var entries: [GTKNavigationEntry] = []",
        "    let backButton: UnsafeMutablePointer<GtkWidget>\n"
        "    let stateNamespace: String\n"
        "    var entries: [GTKNavigationEntry] = []",
    )
if "stateNamespace: String\n    )" not in text:
    text = text.replace(
        "    init(stack: OpaquePointer, headerBar: OpaquePointer, backButton: UnsafeMutablePointer<GtkWidget>) {\n"
        "        self.stack = stack\n"
        "        self.headerBar = headerBar\n"
        "        self.backButton = backButton\n"
        "    }",
        "    init(\n"
        "        stack: OpaquePointer,\n"
        "        headerBar: OpaquePointer,\n"
        "        backButton: UnsafeMutablePointer<GtkWidget>,\n"
        "        stateNamespace: String\n"
        "    ) {\n"
        "        self.stack = stack\n"
        "        self.headerBar = headerBar\n"
        "        self.backButton = backButton\n"
        "        self.stateNamespace = stateNamespace\n"
        "    }",
    )
if "stateNamespace: String? = nil" not in text:
    text = text.replace(
        "    func push(title: String, toolbarItems: [AnyToolbarItem] = [], content: @escaping () -> OpaquePointer) {\n",
        "    func push(\n"
        "        title: String,\n"
        "        toolbarItems: [AnyToolbarItem] = [],\n"
        "        stateNamespace: String? = nil,\n"
        "        content: @escaping () -> OpaquePointer\n"
        "    ) {\n",
    )
    text = text.replace(
        "        let widget = widgetFromOpaque(content())",
        "        let pageNamespace = stateNamespace ?? \"\\(self.stateNamespace)::Entry[\\(name)]\"\n"
        "        let widget = widgetFromOpaque(\n"
        "            gtkWithForcedStateIdentityNamespace(pageNamespace) {\n"
        "                content()\n"
        "            }\n"
        "        )",
    )
if "let navigationStateNamespace = gtkClaimStateIdentityNamespace(\"NavigationStack\")" not in text:
    text = text.replace(
        "        // Create context\n"
        "        let context = GTKNavigationContext(stack: stackOp, headerBar: headerBarOp, backButton: backButton)",
        "        // Create context\n"
        "        let navigationStateNamespace = gtkClaimStateIdentityNamespace(\"NavigationStack\")\n"
        "        let context = GTKNavigationContext(\n"
        "            stack: stackOp,\n"
        "            headerBar: headerBarOp,\n"
        "            backButton: backButton,\n"
        "            stateNamespace: navigationStateNamespace\n"
        "        )",
    )
if "func navigationDestinationStateNamespace(for value: AnyHashable) -> String" not in text:
    text = text.replace(
        "    // MARK: - Path binding sync\n",
        "    func navigationDestinationStateNamespace(for value: AnyHashable) -> String {\n"
        "        \"\\(stateNamespace)::NavigationDestination[\\(String(reflecting: value))]\"\n"
        "    }\n\n"
        "    // MARK: - Path binding sync\n",
    )
text = text.replace(
    "        push(title: title, toolbarItems: resolved.toolbarItems) {\n"
    "            resolved.widget\n"
    "        }",
    "        push(\n"
    "            title: title,\n"
    "            toolbarItems: resolved.toolbarItems,\n"
    "            stateNamespace: navigationDestinationStateNamespace(for: value)\n"
    "        ) {\n"
    "            resolved.widget\n"
    "        }",
)
if "context.navigationDestinationStateNamespace(for: value)" not in text:
    text = text.replace(
        "                let widget = gtkRenderView(destView)\n"
        "                setCurrentEnvironment(prevEnv)",
        "                let widget = gtkWithForcedStateIdentityNamespace(\n"
        "                    context.navigationDestinationStateNamespace(for: value)\n"
        "                ) {\n"
        "                    gtkRenderView(destView)\n"
        "                }\n"
        "                setCurrentEnvironment(prevEnv)",
    )
if "gtkResumeViewHostLifecycleForVisibleSubtree(widget)" not in text:
    text = text.replace(
        "        gtk_stack_set_visible_child_name(stack, name)\n"
        "        updateHeaderBar()",
        "        gtk_stack_set_visible_child_name(stack, name)\n"
        "        gtkResumeViewHostLifecycleForVisibleSubtree(widget)\n"
        "        g_idle_add({ userData -> gboolean in\n"
        "            let widgetRef = Unmanaged<WidgetRef>.fromOpaque(userData!).takeRetainedValue()\n"
        "            if gtk_swift_is_widget(widgetRef.widget) != 0 {\n"
        "                gtkResumeViewHostLifecycleForVisibleSubtree(widgetRef.widget)\n"
        "            }\n"
        "            return 0\n"
        "        }, Unmanaged.passRetained(WidgetRef(widget)).toOpaque())\n"
        "        updateHeaderBar()",
        1,
    )
if "gtkSetNavigationPageInteractive" not in text:
    text = text.replace(
        "        gtkConfigureNavigationPageToFillAllocation(widget)\n"
        "        gtk_stack_add_named(stack, widget, name)",
        "        gtkConfigureNavigationPageToFillAllocation(widget)\n"
        "        if let current = entries.last {\n"
        "            gtkSetNavigationPageInteractive(current.widget, false)\n"
        "        }\n"
        "        gtkSetNavigationPageInteractive(widget, true)\n"
        "        gtk_stack_add_named(stack, widget, name)",
        1,
    )
    text = text.replace(
        "        let previous = entries.last!\n\n"
        "        // Restore previous entry's toolbar widgets",
        "        let previous = entries.last!\n"
        "        gtkSetNavigationPageInteractive(removed.widget, false)\n"
        "        gtkSetNavigationPageInteractive(previous.widget, true)\n\n"
        "        // Restore previous entry's toolbar widgets",
        1,
    )
    text = text.replace(
        "        // Add root as first stack entry\n"
        "        gtk_stack_add_named(stackOp, rootWidget, \"nav-root\")",
        "        // Add root as first stack entry\n"
        "        gtkSetNavigationPageInteractive(rootWidget, true)\n"
        "        gtk_stack_add_named(stackOp, rootWidget, \"nav-root\")",
        1,
    )
    text = text.replace(
        "private func gtkConfigureNavigationPageToFillAllocation(_ widget: UnsafeMutablePointer<GtkWidget>) {\n"
        "    gtk_widget_set_hexpand(widget, 1)\n"
        "    gtk_widget_set_vexpand(widget, 1)\n"
        "    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)\n"
        "    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)\n"
        "}\n\n"
        "private func gtkNavigationDisableButtonChildTargeting(_ widget: UnsafeMutablePointer<GtkWidget>) {",
        "private func gtkConfigureNavigationPageToFillAllocation(_ widget: UnsafeMutablePointer<GtkWidget>) {\n"
        "    gtk_widget_set_hexpand(widget, 1)\n"
        "    gtk_widget_set_vexpand(widget, 1)\n"
        "    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)\n"
        "    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)\n"
        "}\n\n"
        "private func gtkSetNavigationPageInteractive(_ widget: UnsafeMutablePointer<GtkWidget>, _ isInteractive: Bool) {\n"
        "    gtk_widget_set_can_target(widget, isInteractive ? 1 : 0)\n"
        "}\n\n"
        "private func gtkNavigationDisableButtonChildTargeting(_ widget: UnsafeMutablePointer<GtkWidget>) {",
        1,
    )
if "gtkSwiftNavigationPageInteractivityMarker" not in text:
    text = text.replace(
        "import SwiftOpenUI\nimport Foundation\n\n",
        "import SwiftOpenUI\nimport Foundation\n\n"
        "private let gtkSwiftNavigationPageInteractivityMarker = \"gtk-swift-navigation-page-interactive\"\n"
        "private let gtkSwiftNavigationPageInteractiveValue = UnsafeMutableRawPointer(bitPattern: 1)\n"
        "private let gtkSwiftNavigationPageInactiveValue = UnsafeMutableRawPointer(bitPattern: 2)\n\n",
        1,
    )
if "g_object_set_data(\n        gobject,\n        gtkSwiftNavigationPageInteractivityMarker" not in text:
    text = text.replace(
        "private func gtkSetNavigationPageInteractive(_ widget: UnsafeMutablePointer<GtkWidget>, _ isInteractive: Bool) {\n"
        "    gtk_widget_set_can_target(widget, isInteractive ? 1 : 0)\n"
        "}\n",
        "private func gtkSetNavigationPageInteractive(_ widget: UnsafeMutablePointer<GtkWidget>, _ isInteractive: Bool) {\n"
        "    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)\n"
        "    g_object_set_data(\n"
        "        gobject,\n"
        "        gtkSwiftNavigationPageInteractivityMarker,\n"
        "        isInteractive ? gtkSwiftNavigationPageInteractiveValue : gtkSwiftNavigationPageInactiveValue\n"
        "    )\n"
        "    gtk_widget_set_can_target(widget, isInteractive ? 1 : 0)\n"
        "}\n",
        1,
    )
if "env.refreshInjectedObjectsFromRegistry()" not in text:
    text = text.replace(
        "            var env = capturedEnv\n"
        "            env[NavigateKey.self] = NavigateAction(",
        "            var env = capturedEnv\n"
        "            env.refreshInjectedObjectsFromRegistry()\n"
        "            env[NavigateKey.self] = NavigateAction(",
        1,
    )
    text = text.replace(
        "                var env = capturedEnv\n"
        "                env[NavigateKey.self] = NavigateAction(",
        "                var env = capturedEnv\n"
        "                env.refreshInjectedObjectsFromRegistry()\n"
        "                env[NavigateKey.self] = NavigateAction(",
        1,
    )
if "GTKNavigationContextEnvironmentKey" not in text:
    marker = "\nprivate let gtkNavigationPathSyncTickCallback"
    helper = '''\nprivate struct GTKNavigationContextEnvironmentKey: EnvironmentKey {\n    static let defaultValue: GTKNavigationContext? = nil\n}\n\nprivate func gtkEnvironmentWithNavigationContext(\n    _ base: EnvironmentValues,\n    context: GTKNavigationContext\n) -> EnvironmentValues {\n    var env = base\n    env[GTKNavigationContextEnvironmentKey.self] = context\n    env[NavigateKey.self] = NavigateAction(\n        push: { [weak context] value in context?.pushValue(value) },\n        pop: { [weak context] in context?.pop() },\n        popToRoot: { [weak context] in context?.popToRoot() }\n    )\n    return env\n}\n\nprivate func gtkEnvironmentWithNavigationDestinationDismiss(\n    _ base: EnvironmentValues,\n    context: GTKNavigationContext\n) -> EnvironmentValues {\n    var env = base\n    env.dismiss = DismissAction(handler: { [weak context] in\n        context?.pop()\n    }, debugName: "gtk navigation destination")\n    return env\n}\n'''
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTK navigation context tick-callback shape was not recognized")
    text = text.replace(marker, helper + marker, 1)
if "gtkEnvironmentWithNavigationDestinationDismiss" not in text:
    marker = "\nprivate let gtkNavigationPathSyncTickCallback"
    helper = '''\nprivate func gtkEnvironmentWithNavigationDestinationDismiss(\n    _ base: EnvironmentValues,\n    context: GTKNavigationContext\n) -> EnvironmentValues {\n    var env = base\n    env.dismiss = DismissAction(handler: { [weak context] in\n        context?.pop()\n    }, debugName: "gtk navigation destination")\n    return env\n}\n'''
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTK navigation destination dismiss insertion point was not recognized")
    text = text.replace(marker, helper + marker, 1)
if "getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]" not in text:
    text = text.replace(
        "    guard let ptr = pthread_getspecific(_navContextKey) else { return nil }\n"
        "    return Unmanaged<GTKNavigationContext>.fromOpaque(ptr).takeUnretainedValue()",
        "    if let ptr = pthread_getspecific(_navContextKey) {\n"
        "        return Unmanaged<GTKNavigationContext>.fromOpaque(ptr).takeUnretainedValue()\n"
        "    }\n"
        "    return getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]",
        1,
    )
    text = text.replace(
        "    _currentNavContext\n",
        "    _currentNavContext ?? getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]\n",
        1,
    )
if "let env = gtkEnvironmentWithNavigationContext(prevEnv, context: context)" not in text:
    text = text.replace(
        "        var env = getCurrentEnvironment()\n"
        "        env[NavigateKey.self] = NavigateAction(\n"
        "            push: { [weak context] value in context?.pushValue(value) },\n"
        "            pop: { [weak context] in context?.pop() },\n"
        "            popToRoot: { [weak context] in context?.popToRoot() }\n"
        "        )\n"
        "        let prevEnv = getCurrentEnvironment()\n",
        "        let prevEnv = getCurrentEnvironment()\n"
        "        let env = gtkEnvironmentWithNavigationContext(prevEnv, context: context)\n",
        1,
    )
if "env = gtkEnvironmentWithNavigationContext(env, context: context)" not in text:
    text = text.replace(
        "        env.refreshInjectedObjectsFromRegistry()\n"
        "        env[NavigateKey.self] = NavigateAction(\n"
        "            push: { [weak context] value in context?.pushValue(value) },\n"
        "            pop: { [weak context] in context?.pop() },\n"
        "            popToRoot: { [weak context] in context?.popToRoot() }\n"
        "        )",
        "        env.refreshInjectedObjectsFromRegistry()\n"
        "        env = gtkEnvironmentWithNavigationContext(env, context: context)",
        1,
    )
    text = text.replace(
        "                env.refreshInjectedObjectsFromRegistry()\n"
        "                env[NavigateKey.self] = NavigateAction(\n"
        "                    push: { [weak context] value in context?.pushValue(value) },\n"
        "                    pop: { [weak context] in context?.pop() },\n"
        "                    popToRoot: { [weak context] in context?.popToRoot() }\n"
        "                )",
        "                env.refreshInjectedObjectsFromRegistry()\n"
        "                env = gtkEnvironmentWithNavigationContext(env, context: context)",
        1,
    )
for old_nav_destination_env, new_nav_destination_env, error_message in [
    (
        "        env = gtkEnvironmentWithNavigationContext(env, context: context)\n"
        "        setCurrentEnvironment(env)\n"
        "        let destView = destination()",
        "        env = gtkEnvironmentWithNavigationContext(env, context: context)\n"
        "        env = gtkEnvironmentWithNavigationDestinationDismiss(env, context: context)\n"
        "        setCurrentEnvironment(env)\n"
        "        let destView = destination()",
        "SwiftOpenUI GTK isPresented destination environment shape was not recognized",
    ),
    (
        "                env = gtkEnvironmentWithNavigationContext(env, context: context)\n"
        "                setCurrentEnvironment(env)\n"
        "                let widget = gtkRenderView(destView)",
        "                env = gtkEnvironmentWithNavigationContext(env, context: context)\n"
        "                env = gtkEnvironmentWithNavigationDestinationDismiss(env, context: context)\n"
        "                setCurrentEnvironment(env)\n"
        "                let widget = gtkRenderView(destView)",
        "SwiftOpenUI GTK isPresented destination render environment shape was not recognized",
    ),
    (
        "                env = gtkEnvironmentWithNavigationContext(env, context: context)\n"
        "                setCurrentEnvironment(env)\n"
        "                let destView = destinationBuilder(value)",
        "                env = gtkEnvironmentWithNavigationContext(env, context: context)\n"
        "                env = gtkEnvironmentWithNavigationDestinationDismiss(env, context: context)\n"
        "                setCurrentEnvironment(env)\n"
        "                let destView = destinationBuilder(value)",
        "SwiftOpenUI GTK value destination environment shape was not recognized",
    ),
]:
    if new_nav_destination_env not in text:
        if old_nav_destination_env not in text:
            raise SystemExit(error_message)
        text = text.replace(old_nav_destination_env, new_nav_destination_env, 1)
if "context.flushPendingPresentedDestinations()" not in text and "NavigationPresentedDestinationModifier: GTKRenderable" in text:
    text = text.replace(
        "        context.enqueuePresentedDestination(\n"
        "            stateNamespace: presentedStateNamespace,\n"
        "            isPresented: isPresented,\n"
        "            route: route\n"
        "        )\n\n"
        "        return widget",
        "        context.enqueuePresentedDestination(\n"
        "            stateNamespace: presentedStateNamespace,\n"
        "            isPresented: isPresented,\n"
        "            route: route\n"
        "        )\n"
        "        if !context.entries.isEmpty {\n"
        "            context.flushPendingPresentedDestinations()\n"
        "        }\n\n"
        "        return widget",
        1,
    )
if "NavigationPresentedDestinationModifier: GTKDescribable" not in text and "NavigationPresentedDestinationModifier: GTKRenderable" in text:
    marker = "\nextension TitledView: GTKRenderable"
    describable = '''\nextension NavigationPresentedDestinationModifier: GTKDescribable {\n    public func gtkDescribeNode() -> GTK4DescriptorNode {\n        GTK4DescriptorNode(\n            kind: .composite,\n            typeName: "NavigationPresentedDestinationModifier",\n            props: .text(GTK4TextDescriptor(\n                content: isPresented.wrappedValue ? "presented" : "dismissed"\n            )),\n            children: [gtkDescribeView(content)]\n        )\n    }\n}\n'''
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTK navigation presented destination describable insertion point was not recognized")
    text = text.replace(marker, describable + marker, 1)
text = text.replace(
    "        let sidebarWidget = widgetFromOpaque(gtkRenderView(sidebar))\n"
    "        let detailWidget = gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)",
    "        let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))\n"
    "        let sidebarWidget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!\n"
    "        gtk_widget_set_hexpand(sidebarContentWidget, 1)\n"
    "        gtk_widget_set_halign(sidebarContentWidget, GTK_ALIGN_FILL)\n"
    "        gtk_widget_set_vexpand(sidebarContentWidget, 1)\n"
    "        gtk_widget_set_valign(sidebarContentWidget, GTK_ALIGN_FILL)\n"
    "        gtk_box_append(boxPointer(sidebarWidget), sidebarContentWidget)\n"
    "        let detailWidget = gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)",
)
text = text.replace(
    "        let sidebarWidget = widgetFromOpaque(gtkRenderView(sidebar))\n"
    "        let contentWidget = widgetFromOpaque(gtkRenderView(content))\n"
    "        let detailWidget = widgetFromOpaque(gtkRenderView(detail))",
    "        let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))\n"
    "        let sidebarWidget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!\n"
    "        gtk_widget_set_hexpand(sidebarContentWidget, 1)\n"
    "        gtk_widget_set_halign(sidebarContentWidget, GTK_ALIGN_FILL)\n"
    "        gtk_widget_set_vexpand(sidebarContentWidget, 1)\n"
    "        gtk_widget_set_valign(sidebarContentWidget, GTK_ALIGN_FILL)\n"
    "        gtk_box_append(boxPointer(sidebarWidget), sidebarContentWidget)\n"
    "        let contentWidget = widgetFromOpaque(gtkRenderView(content))\n"
    "        let detailWidget = widgetFromOpaque(gtkRenderView(detail))",
)
helper = '''private func gtkRenderToolbarWidgets<V: View>(from view: V) -> [UnsafeMutablePointer<GtkWidget>] {
    if view is GTKRenderable {
        return [widgetFromOpaque(gtkRenderView(view))]
    }
    if let multi = view as? MultiChildView {
        return multi.children.flatMap { child in
            gtkRenderToolbarWidgets(from: child)
        }
    }
    if V.Body.self != Never.self {
        // View.body is @MainActor (Apple semantics); toolbar rendering only
        // runs on the GTK main loop == the main thread.
        return MainActor.assumeIsolated { gtkRenderToolbarWidgets(from: view.body) }
    }
    return [widgetFromOpaque(gtkRenderView(view))]
}

private func gtkRenderToolbarItemWidgets(_ item: AnyToolbarItem) -> [UnsafeMutablePointer<GtkWidget>] {
    item.renderedViews.flatMap { view in
        gtkRenderToolbarWidgets(from: view)
    }
}

private func gtkBackendEnvironmentValue(_ canonical: String, legacy: String) -> String? {
    let environment = ProcessInfo.processInfo.environment
    return environment[canonical] ?? environment[legacy]
}

private func gtkBackendEnvironmentDouble(_ canonical: String, legacy: String) -> Double? {
    gtkBackendEnvironmentValue(canonical, legacy: legacy).flatMap(Double.init)
}

private var gtkBackendLayoutDebugEnabled: Bool {
    gtkBackendEnvironmentValue(
        "QUILLUI_BACKEND_LAYOUT_DEBUG",
        legacy: "QUILLUI_GTK_LAYOUT_DEBUG"
    ) == "1"
}

private func gtkRequestedDefaultWindowHeight() -> gint {
    guard let height = gtkBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT",
        legacy: "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT"
    ), height > 0
    else {
        return -1
    }
    return gint(height)
}

private func gtkResolvedDefaultSidebarWidth(fallback: Double) -> Double {
    guard let width = gtkBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH",
        legacy: "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"
    ), width > 0
    else {
        if gtkBackendLayoutDebugEnabled {
            print("QuillUI GTK split fallback sidebar width=\\(max(320.0, fallback)) env=nil")
        }
        return max(320.0, fallback)
    }
    let resolved = max(320.0, min(600.0, width * 0.27))
    if gtkBackendLayoutDebugEnabled {
        print("QuillUI GTK split env width=\\(width) sidebar=\\(resolved)")
    }
    return resolved
}

private let gtkProportionalSidebarMapCallback: @convention(c) (gpointer?, gpointer?) -> Void = { widgetPtr, _ in
    guard let widgetPtr else { return }
    let widget = UnsafeMutableRawPointer(widgetPtr).assumingMemoryBound(to: GtkWidget.self)
    let width = Double(gtk_widget_get_width(widget))
    guard width > 0 else { return }
    let sidebarW = max(320.0, min(600.0, width * 0.27))
    gtk_swift_paned_set_position(widget, gint(sidebarW))
}

private let gtkProportionalSidebarTickCallback: GtkTickCallback = { widget, _, _ in
    guard let widget else { return 1 }
    let width = Double(gtk_widget_get_width(widget))
    guard width > 0 else { return 1 }
    let sidebarW = max(320.0, min(600.0, width * 0.27))
    gtk_swift_paned_set_position(widget, gint(sidebarW))
    return 1
}

private func gtkInstallProportionalSidebarPosition(on paned: UnsafeMutablePointer<GtkWidget>) {
    g_signal_connect_data(
        gpointer(paned),
        "map",
        unsafeBitCast(gtkProportionalSidebarMapCallback, to: GCallback.self),
        nil, nil,
        GConnectFlags(rawValue: 0)
    )
    _ = gtk_widget_add_tick_callback(
        paned,
        gtkProportionalSidebarTickCallback,
        nil, nil
    )
}

private func gtkCreateToolbarRow<V: View>(from view: V) -> UnsafeMutablePointer<GtkWidget>? {
    let rawItems = gtkExtractToolbarItems(from: view)
    let config = gtkExtractToolbarConfiguration(from: view)
    let (toolbarItems, hidden) = gtkApplyToolbarConfiguration(items: rawItems, configuration: config)
    guard !hidden, !toolbarItems.isEmpty else { return nil }

    let row = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14)!
    gtk_widget_set_size_request(row, -1, 48)
    gtk_widget_set_hexpand(row, 1)
    gtk_widget_set_halign(row, GTK_ALIGN_FILL)

    for item in toolbarItems where item.placement == .leading {
        for widget in gtkRenderToolbarItemWidgets(item) {
            gtk_box_append(boxPointer(row), widget)
        }
    }

    let trailingCluster = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14)!
    gtk_widget_set_margin_start(trailingCluster, 620)

    for item in toolbarItems where item.placement != .leading {
        for widget in gtkRenderToolbarItemWidgets(item) {
            gtk_box_append(boxPointer(trailingCluster), widget)
        }
    }
    gtk_box_append(boxPointer(row), trailingCluster)

    return row
}

private func gtkWrapWithToolbarRow<V: View>(
    _ contentWidget: UnsafeMutablePointer<GtkWidget>,
    toolbarSource view: V
) -> UnsafeMutablePointer<GtkWidget> {
    guard let toolbarRow = gtkCreateToolbarRow(from: view) else {
        return contentWidget
    }

    let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
    gtk_box_append(boxPointer(box), toolbarRow)
    gtk_box_append(boxPointer(box), gtk_separator_new(GTK_ORIENTATION_HORIZONTAL))
    gtk_box_append(boxPointer(box), contentWidget)
    gtk_widget_set_hexpand(box, 1)
    gtk_widget_set_vexpand(box, 1)
    gtk_widget_set_hexpand(contentWidget, 1)
    gtk_widget_set_vexpand(contentWidget, 1)
    return box
}

private func gtkApplyFixedSplitColumnWidth(_ widget: UnsafeMutablePointer<GtkWidget>, width: Double) {
    let pixelWidth = gint(width)
    gtk_widget_set_size_request(widget, pixelWidth, gtkRequestedDefaultWindowHeight())
    let typeName = String(cString: g_type_name(gtk_swift_get_widget_type(widget)))
    if typeName == "GtkScrolledWindow" {
        let scrolledOp = OpaquePointer(widget)
        gtk_scrolled_window_set_min_content_width(scrolledOp, pixelWidth)
        gtk_scrolled_window_set_max_content_width(scrolledOp, pixelWidth)
    }
}

private func gtkConfigureFixedSplitColumn(_ widget: UnsafeMutablePointer<GtkWidget>, width: Double) {
    gtkApplyFixedSplitColumnWidth(widget, width: width)
    gtk_widget_set_hexpand(widget, 0)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_vexpand(widget, 1)
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
}

private func gtkCreateFixedSplitColumnContainer(
    child: UnsafeMutablePointer<GtkWidget>,
    width: Double
) -> UnsafeMutablePointer<GtkWidget> {
    let scrolled = gtk_scrolled_window_new()!
    let scrolledOp = OpaquePointer(scrolled)
    gtk_scrolled_window_set_policy(scrolledOp, GTK_POLICY_EXTERNAL, GTK_POLICY_EXTERNAL)
    gtk_scrolled_window_set_has_frame(scrolledOp, 0)
    gtk_scrolled_window_set_propagate_natural_width(scrolledOp, 0)
    gtk_scrolled_window_set_propagate_natural_height(scrolledOp, 0)
    gtkConfigureFixedSplitColumn(scrolled, width: width)

    gtk_widget_set_hexpand(child, 1)
    gtk_widget_set_halign(child, GTK_ALIGN_FILL)
    gtk_widget_set_vexpand(child, 1)
    gtk_widget_set_valign(child, GTK_ALIGN_FILL)
    gtk_scrolled_window_set_child(scrolledOp, child)
    return scrolled
}

private func gtkConfigureFillingSplitColumn(_ widget: UnsafeMutablePointer<GtkWidget>) {
    gtk_widget_set_hexpand(widget, 1)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_vexpand(widget, 1)
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
}

private func gtkCreateSplitDivider() -> UnsafeMutablePointer<GtkWidget> {
    let divider = gtk_separator_new(GTK_ORIENTATION_VERTICAL)!
    gtk_widget_set_size_request(divider, 1, gtkRequestedDefaultWindowHeight())
    applyCSSToWidget(divider, properties: "background: #d1d2cf; min-width: 1px;")
    return divider
}

private let gtkFixedSplitSidebarTickCallback: GtkTickCallback = { widget, _, userData in
    guard let widget, let userData else { return 1 }
    let sidebar = Unmanaged<WidgetRef>.fromOpaque(userData).takeUnretainedValue().widget
    let width = Double(gtk_widget_get_width(widget))
    guard width > 0 else { return 1 }
    let sidebarW = max(320.0, min(600.0, width * 0.27))
    gtkApplyFixedSplitColumnWidth(sidebar, width: sidebarW)
    gtk_widget_queue_resize(sidebar)
    gtk_widget_queue_resize(widget)
    if gtkBackendLayoutDebugEnabled {
        print("QuillUI GTK split allocated width=\\(width) sidebar=\\(sidebarW)")
    }
    return 1
}

private func gtkInstallProportionalFixedSidebar(
    on splitBox: UnsafeMutablePointer<GtkWidget>,
    sidebarWidget: UnsafeMutablePointer<GtkWidget>
) {
    _ = gtk_widget_add_tick_callback(
        splitBox,
        gtkFixedSplitSidebarTickCallback,
        Unmanaged.passRetained(WidgetRef(sidebarWidget)).toOpaque(),
        { userData in
            if let userData {
                Unmanaged<WidgetRef>.fromOpaque(userData).release()
            }
        }
    )
}

private func gtkCreateTwoColumnSplitBox(
    sidebarWidget: UnsafeMutablePointer<GtkWidget>,
    detailWidget: UnsafeMutablePointer<GtkWidget>,
    sidebarWidth: Double
) -> UnsafeMutablePointer<GtkWidget> {
    let splitBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    gtkConfigureFixedSplitColumn(sidebarWidget, width: sidebarWidth)
    applyCSSToWidget(sidebarWidget, properties: "background: #e8e9e6;")
    gtkConfigureFillingSplitColumn(detailWidget)

    gtk_box_append(boxPointer(splitBox), sidebarWidget)
    gtk_box_append(boxPointer(splitBox), gtkCreateSplitDivider())
    gtk_box_append(boxPointer(splitBox), detailWidget)
    gtkConfigureFillingSplitColumn(splitBox)
    gtkInstallProportionalFixedSidebar(on: splitBox, sidebarWidget: sidebarWidget)
    return splitBox
}

private func gtkCreateThreeColumnSplitBox(
    sidebarWidget: UnsafeMutablePointer<GtkWidget>,
    contentWidget: UnsafeMutablePointer<GtkWidget>,
    detailWidget: UnsafeMutablePointer<GtkWidget>,
    sidebarWidth: Double,
    contentWidth: Double
) -> UnsafeMutablePointer<GtkWidget> {
    let splitBox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    gtkConfigureFixedSplitColumn(sidebarWidget, width: sidebarWidth)
    gtkConfigureFixedSplitColumn(contentWidget, width: contentWidth)
    applyCSSToWidget(sidebarWidget, properties: "background: #e8e9e6;")
    applyCSSToWidget(contentWidget, properties: "background: #f6f6f4;")
    gtkConfigureFillingSplitColumn(detailWidget)

    gtk_box_append(boxPointer(splitBox), sidebarWidget)
    gtk_box_append(boxPointer(splitBox), gtkCreateSplitDivider())
    gtk_box_append(boxPointer(splitBox), contentWidget)
    gtk_box_append(boxPointer(splitBox), gtkCreateSplitDivider())
    gtk_box_append(boxPointer(splitBox), detailWidget)
    gtkConfigureFillingSplitColumn(splitBox)
    gtkInstallProportionalFixedSidebar(on: splitBox, sidebarWidget: sidebarWidget)
    return splitBox
}

private func gtkApplyFixedSplitVisibility(
    _ visibility: NavigationSplitViewVisibility,
    sidebar: UnsafeMutablePointer<GtkWidget>,
    content: UnsafeMutablePointer<GtkWidget>?
) {
    switch visibility {
    case .automatic, .all:
        gtk_widget_set_visible(sidebar, 1)
        if let content = content { gtk_widget_set_visible(content, 1) }
    case .doubleColumn:
        gtk_widget_set_visible(sidebar, 1)
        if let content = content { gtk_widget_set_visible(content, 0) }
    case .detailOnly:
        gtk_widget_set_visible(sidebar, 0)
        if let content = content { gtk_widget_set_visible(content, 0) }
    }
}

'''
environment_helper = '''private func gtkBackendEnvironmentValue(_ canonical: String, legacy: String) -> String? {
    let environment = ProcessInfo.processInfo.environment
    return environment[canonical] ?? environment[legacy]
}

private func gtkBackendEnvironmentDouble(_ canonical: String, legacy: String) -> Double? {
    gtkBackendEnvironmentValue(canonical, legacy: legacy).flatMap(Double.init)
}

private var gtkBackendLayoutDebugEnabled: Bool {
    gtkBackendEnvironmentValue(
        "QUILLUI_BACKEND_LAYOUT_DEBUG",
        legacy: "QUILLUI_GTK_LAYOUT_DEBUG"
    ) == "1"
}

'''
if "gtkRenderToolbarWidgets<V: View>" not in text:
    text = text.replace("private func gtkInstallToolbar<V: View>", helper + "private func gtkInstallToolbar<V: View>")
if "gtkBackendEnvironmentValue(_ canonical" not in text:
    text = text.replace("private func gtkRequestedDefaultWindowHeight() -> gint", environment_helper + "private func gtkRequestedDefaultWindowHeight() -> gint", 1)
text = text.replace(
    '''    guard let rawHeight = ProcessInfo.processInfo.environment["QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT"],
          let height = Double(rawHeight),
          height > 0
''',
    '''    guard let height = gtkBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_HEIGHT",
        legacy: "QUILLUI_GTK_DEFAULT_WINDOW_HEIGHT"
    ), height > 0
''',
)
text = text.replace(
    '''    let environment = ProcessInfo.processInfo.environment
    guard let rawWidth = environment["QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"],
          let width = Double(rawWidth),
          width > 0
''',
    '''    guard let width = gtkBackendEnvironmentDouble(
        "QUILLUI_BACKEND_DEFAULT_WINDOW_WIDTH",
        legacy: "QUILLUI_GTK_DEFAULT_WINDOW_WIDTH"
    ), width > 0
''',
)
text = text.replace('ProcessInfo.processInfo.environment["QUILLUI_GTK_LAYOUT_DEBUG"] == "1"', "gtkBackendLayoutDebugEnabled")
text = text.replace('environment["QUILLUI_GTK_LAYOUT_DEBUG"] == "1"', "gtkBackendLayoutDebugEnabled")
if "gtkRenderToolbarItemWidgets(_ item: AnyToolbarItem)" not in text:
    text = text.replace(
        "private func gtkCreateToolbarRow<V: View>",
        '''private func gtkRenderToolbarItemWidgets(_ item: AnyToolbarItem) -> [UnsafeMutablePointer<GtkWidget>] {
    item.renderedViews.flatMap { view in
        gtkRenderToolbarWidgets(from: view)
    }
}

private func gtkCreateToolbarRow<V: View>''',
    )
text = text.replace("gtkRenderToolbarWidgets(from: item.wrapped)", "gtkRenderToolbarItemWidgets(item)")
text = text.replace(
    "gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), -1)",
    "gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), gtkRequestedDefaultWindowHeight())",
)
text = text.replace(
    "gtk_widget_set_size_request(sidebarWidget, gint(minW), -1)",
    "gtk_widget_set_size_request(sidebarWidget, gint(max(minW, sidebarW)), gtkRequestedDefaultWindowHeight())",
)
text = text.replace(
    "gtk_widget_set_size_request(sidebarWidget, gint(minW), gtkRequestedDefaultWindowHeight())",
    "gtk_widget_set_size_request(sidebarWidget, gint(max(minW, sidebarW)), gtkRequestedDefaultWindowHeight())",
)
if "gtk_widget_set_size_request(detailWidget, -1, gtkRequestedDefaultWindowHeight())" not in text:
    text = text.replace(
        "        gtk_widget_set_valign(detailWidget, GTK_ALIGN_FILL)\n",
        "        gtk_widget_set_valign(detailWidget, GTK_ALIGN_FILL)\n"
        "        gtk_widget_set_size_request(detailWidget, -1, gtkRequestedDefaultWindowHeight())\n",
        1,
    )

old_toolbar_loop = '''    for item in toolbarItems {
        let itemWidget = widgetFromOpaque(gtkRenderAnyView(item.wrapped))
        switch item.placement {
        case .leading:
            gtk_header_bar_pack_start(headerBarOp, itemWidget)
        case .primaryAction, .trailing:
            gtk_header_bar_pack_end(headerBarOp, itemWidget)
        }
    }
'''
new_toolbar_loop = '''    for item in toolbarItems {
        for itemWidget in gtkRenderToolbarItemWidgets(item) {
            switch item.placement {
            case .leading:
                gtk_header_bar_pack_start(headerBarOp, itemWidget)
            case .primaryAction, .trailing:
                gtk_header_bar_pack_end(headerBarOp, itemWidget)
            }
        }
    }
'''
if "for itemWidget in gtkRenderToolbarItemWidgets(item)" not in text:
    text = text.replace(old_toolbar_loop, new_toolbar_loop, 1)

if "gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), -1)" not in text:
    text = text.replace(
        "        let sidebarWidget = widgetFromOpaque(gtkRenderView(sidebar))\n"
        "        let detailWidget = widgetFromOpaque(gtkRenderView(detail))",
        "        let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))\n"
        "        let sidebarWidget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!\n"
        "        gtk_widget_set_hexpand(sidebarContentWidget, 1)\n"
        "        gtk_widget_set_halign(sidebarContentWidget, GTK_ALIGN_FILL)\n"
        "        gtk_widget_set_vexpand(sidebarContentWidget, 1)\n"
        "        gtk_widget_set_valign(sidebarContentWidget, GTK_ALIGN_FILL)\n"
        "        gtk_box_append(boxPointer(sidebarWidget), sidebarContentWidget)\n"
        "        let detailWidget = gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)\n"
        "        gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), -1)",
    )
    text = text.replace(
        "        let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))\n"
        "        let contentW = gtkExtractColumnWidth(from: content) ?? 250.0",
        "        let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))\n"
        "        gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), -1)\n"
        "        let contentW = gtkExtractColumnWidth(from: content) ?? 250.0",
    )
if "gtk_widget_set_vexpand(sidebarWidget, 1)" not in text:
    text = text.replace(
        "        gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), -1)\n",
        "        gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), -1)\n"
        "        gtk_widget_set_hexpand(sidebarWidget, 1)\n"
        "        gtk_widget_set_halign(sidebarWidget, GTK_ALIGN_FILL)\n"
        "        gtk_widget_set_vexpand(sidebarWidget, 1)\n"
        "        gtk_widget_set_valign(sidebarWidget, GTK_ALIGN_FILL)\n"
        "        applyCSSToWidget(sidebarWidget, properties: \"background: #e8e9e6; border-right: 1px solid #d1d2cf;\")\n"
        "        gtk_widget_set_vexpand(detailWidget, 1)\n"
        "        gtk_widget_set_valign(detailWidget, GTK_ALIGN_FILL)\n",
        1,
    )
text = text.replace(
    "gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), -1)",
    "gtk_widget_set_size_request(sidebarWidget, gint(sidebarW), gtkRequestedDefaultWindowHeight())",
)
two_column_start = text.find("    private func gtkCreateTwoColumnWidget() -> OpaquePointer {")
three_column_start = text.find("    private func gtkCreateThreeColumnWidget() -> OpaquePointer {")
if two_column_start >= 0 and three_column_start > two_column_start:
    two_column = '''    private func gtkCreateTwoColumnWidget() -> OpaquePointer {
        let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))
        let sidebarMinW = gtkExtractColumnWidthProvider(from: sidebar)?.columnMinWidth ?? 0
        let resolvedSidebarW = max(sidebarMinW, sidebarW)

        let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))
        let sidebarWidget = gtkCreateFixedSplitColumnContainer(
            child: sidebarContentWidget,
            width: resolvedSidebarW
        )

        let detailWidget = gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)
        let splitBox = gtkCreateTwoColumnSplitBox(
            sidebarWidget: sidebarWidget,
            detailWidget: detailWidget,
            sidebarWidth: resolvedSidebarW
        )

        if let visibility = columnVisibility {
            gtkApplyFixedSplitVisibility(visibility.wrappedValue,
                                         sidebar: sidebarWidget,
                                         content: nil)
        }

        return opaqueFromWidget(splitBox)
    }

'''
    text = text[:two_column_start] + two_column + text[three_column_start:]

three_column_start = text.find("    private func gtkCreateThreeColumnWidget() -> OpaquePointer {")
column_width_view_start = text.find("\n}\n\nextension NavigationSplitViewColumnWidthView", three_column_start)
if three_column_start >= 0 and column_width_view_start > three_column_start:
    three_column = '''    private func gtkCreateThreeColumnWidget() -> OpaquePointer {
        let sidebarW = max(gtkExtractColumnWidth(from: sidebar) ?? 0, gtkResolvedDefaultSidebarWidth(fallback: Double(sidebarWidth)))
        let contentW = gtkExtractColumnWidth(from: content) ?? 250.0
        let sidebarMinW = gtkExtractColumnWidthProvider(from: sidebar)?.columnMinWidth ?? 0
        let contentMinW = gtkExtractColumnWidthProvider(from: content)?.columnMinWidth ?? 0
        let resolvedSidebarW = max(sidebarMinW, sidebarW)
        let resolvedContentW = max(contentMinW, contentW)

        let sidebarContentWidget = widgetFromOpaque(gtkRenderView(sidebar))
        let sidebarWidget = gtkCreateFixedSplitColumnContainer(
            child: sidebarContentWidget,
            width: resolvedSidebarW
        )

        let contentWidget = gtkCreateFixedSplitColumnContainer(
            child: widgetFromOpaque(gtkRenderView(content)),
            width: resolvedContentW
        )
        let detailWidget = gtkWrapWithToolbarRow(widgetFromOpaque(gtkRenderView(detail)), toolbarSource: detail)
        let splitBox = gtkCreateThreeColumnSplitBox(
            sidebarWidget: sidebarWidget,
            contentWidget: contentWidget,
            detailWidget: detailWidget,
            sidebarWidth: resolvedSidebarW,
            contentWidth: resolvedContentW
        )

        if let visibility = columnVisibility {
            gtkApplyFixedSplitVisibility(visibility.wrappedValue,
                                         sidebar: sidebarWidget,
                                         content: contentWidget)
        }

        return opaqueFromWidget(splitBox)
    }
'''
    text = text[:three_column_start] + three_column + text[column_width_view_start:]

if "gtkInstallProportionalSidebarPosition(on: paned)" not in text:
    text = text.replace(
        "        gtk_swift_paned_set_position(paned, gint(sidebarW))\n",
        "        gtk_swift_paned_set_position(paned, gint(sidebarW))\n"
        "        gtkInstallProportionalSidebarPosition(on: paned)\n",
        1,
    )
if "gtkInstallProportionalSidebarPosition(on: innerPaned)" not in text:
    text = text.replace(
        "        gtk_swift_paned_set_position(innerPaned, gint(sidebarW))\n",
        "        gtk_swift_paned_set_position(innerPaned, gint(sidebarW))\n"
        "        gtkInstallProportionalSidebarPosition(on: innerPaned)\n",
        1,
    )
if "gtk_widget_set_size_request(detailWidget, -1, gtkRequestedDefaultWindowHeight())" not in text:
    text = text.replace(
        "        gtk_widget_set_valign(detailWidget, GTK_ALIGN_FILL)\n",
        "        gtk_widget_set_valign(detailWidget, GTK_ALIGN_FILL)\n"
        "        gtk_widget_set_size_request(detailWidget, -1, gtkRequestedDefaultWindowHeight())\n",
        1,
    )

def replace_navigation_once(marker, old, new, error):
    global text
    if marker in text:
        return
    if old not in text:
        raise SystemExit(error)
    text = text.replace(old, new, 1)


replace_navigation_once(
    "private(set) var nativeWidgetTreeIsAlive = true",
    "    private var pendingPresentedDestinations: [GTKPendingPresentedNavigationDestination] = []\n",
    "    private var pendingPresentedDestinations: [GTKPendingPresentedNavigationDestination] = []\n"
    "    private(set) var nativeWidgetTreeIsAlive = true\n",
    "SwiftOpenUI GTK navigation native-lifecycle property insertion point was not recognized",
)
replace_navigation_once(
    "func invalidateNativeWidgetTree()",
    "        self.stateNamespace = stateNamespace\n"
    "    }\n\n"
    "    /// Push a new view onto the navigation stack.",
    "        self.stateNamespace = stateNamespace\n"
    "    }\n\n"
    "    deinit {\n"
    "        invalidateNativeWidgetTree()\n"
    "    }\n\n"
    "    func invalidateNativeWidgetTree() {\n"
    "        guard nativeWidgetTreeIsAlive else { return }\n"
    "        nativeWidgetTreeIsAlive = false\n"
    "        for entry in entries {\n"
    "            releaseToolbarWidgetReferences(in: entry)\n"
    "        }\n"
    "        entries.removeAll()\n"
    "        representedPath.removeAll()\n"
    "        pendingPresentedDestinations.removeAll()\n"
    "        presentedDestinationBindings.removeAll()\n"
    "    }\n\n"
    "    /// Push a new view onto the navigation stack.",
    "SwiftOpenUI GTK navigation native-lifecycle method insertion point was not recognized",
)
replace_navigation_once(
    "guard nativeWidgetTreeIsAlive else {\n            return stateNamespace ?? self.stateNamespace",
    "    ) -> String {\n"
    "        let name = \"nav-\\(nameCounter)\"",
    "    ) -> String {\n"
    "        guard nativeWidgetTreeIsAlive else {\n"
    "            return stateNamespace ?? self.stateNamespace\n"
    "        }\n"
    "        let name = \"nav-\\(nameCounter)\"",
    "SwiftOpenUI GTK navigation push lifecycle guard insertion point was not recognized",
)
for marker, old, new, error in [
    (
        "func pushValue(_ value: AnyHashable, persist: Bool = true) -> Bool {\n        guard nativeWidgetTreeIsAlive",
        "func pushValue(_ value: AnyHashable, persist: Bool = true) -> Bool {\n"
        "        guard let resolved",
        "func pushValue(_ value: AnyHashable, persist: Bool = true) -> Bool {\n"
        "        guard nativeWidgetTreeIsAlive else { return false }\n"
        "        guard let resolved",
        "SwiftOpenUI GTK navigation value-push lifecycle guard insertion point was not recognized",
    ),
    (
        ") -> Bool {\n        guard nativeWidgetTreeIsAlive else { return false }\n        guard case let .destination",
        ") -> Bool {\n"
        "        guard case let .destination",
        ") -> Bool {\n"
        "        guard nativeWidgetTreeIsAlive else { return false }\n"
        "        guard case let .destination",
        "SwiftOpenUI GTK navigation destination lifecycle guard insertion point was not recognized",
    ),
    (
        "func restorePersistedRoutesIfNeeded() {\n        guard nativeWidgetTreeIsAlive",
        "func restorePersistedRoutesIfNeeded() {\n"
        "        guard representedPath",
        "func restorePersistedRoutesIfNeeded() {\n"
        "        guard nativeWidgetTreeIsAlive else { return }\n"
        "        guard representedPath",
        "SwiftOpenUI GTK navigation restore lifecycle guard insertion point was not recognized",
    ),
    (
        "func flushPendingPresentedDestinations() {\n        guard nativeWidgetTreeIsAlive",
        "func flushPendingPresentedDestinations() {\n"
        "        let pending = pendingPresentedDestinations",
        "func flushPendingPresentedDestinations() {\n"
        "        guard nativeWidgetTreeIsAlive else {\n"
        "            pendingPresentedDestinations.removeAll()\n"
        "            return\n"
        "        }\n"
        "        let pending = pendingPresentedDestinations",
        "SwiftOpenUI GTK navigation pending-destination lifecycle guard insertion point was not recognized",
    ),
    (
        "func pop() {\n        guard nativeWidgetTreeIsAlive",
        "func pop() {\n"
        "        guard entries.count > 1 else { return }",
        "func pop() {\n"
        "        guard nativeWidgetTreeIsAlive else { return }\n"
        "        guard entries.count > 1 else { return }",
        "SwiftOpenUI GTK navigation pop lifecycle guard insertion point was not recognized",
    ),
    (
        "func syncFromBoundPath() {\n        guard nativeWidgetTreeIsAlive",
        "func syncFromBoundPath() {\n"
        "        guard !isSyncing else { return }",
        "func syncFromBoundPath() {\n"
        "        guard nativeWidgetTreeIsAlive else { return }\n"
        "        guard !isSyncing else { return }",
        "SwiftOpenUI GTK navigation path-sync lifecycle guard insertion point was not recognized",
    ),
    (
        "private func removeCurrentToolbarWidgets() {\n        guard nativeWidgetTreeIsAlive",
        "private func removeCurrentToolbarWidgets() {\n"
        "        guard let current = entries.last else { return }",
        "private func removeCurrentToolbarWidgets() {\n"
        "        guard nativeWidgetTreeIsAlive else { return }\n"
        "        guard let current = entries.last else { return }",
        "SwiftOpenUI GTK navigation toolbar-removal lifecycle guard insertion point was not recognized",
    ),
    (
        "into entry: inout GTKNavigationEntry\n    ) {\n        guard nativeWidgetTreeIsAlive",
        "into entry: inout GTKNavigationEntry\n"
        "    ) {\n"
        "        for item in toolbarItems",
        "into entry: inout GTKNavigationEntry\n"
        "    ) {\n"
        "        guard nativeWidgetTreeIsAlive else { return }\n"
        "        for item in toolbarItems",
        "SwiftOpenUI GTK navigation toolbar-install lifecycle guard insertion point was not recognized",
    ),
    (
        "func replaceCurrentToolbar(with snapshot: GTKNavigationToolbarSnapshot) {\n        guard nativeWidgetTreeIsAlive",
        "func replaceCurrentToolbar(with snapshot: GTKNavigationToolbarSnapshot) {\n"
        "        guard let current = entries.last else { return }",
        "func replaceCurrentToolbar(with snapshot: GTKNavigationToolbarSnapshot) {\n"
        "        guard nativeWidgetTreeIsAlive else { return }\n"
        "        guard let current = entries.last else { return }",
        "SwiftOpenUI GTK navigation toolbar-refresh lifecycle guard insertion point was not recognized",
    ),
    (
        "private func updateHeaderBar() {\n        guard nativeWidgetTreeIsAlive",
        "private func updateHeaderBar() {\n"
        "        let title = entries.last?.title ?? \"\"",
        "private func updateHeaderBar() {\n"
        "        guard nativeWidgetTreeIsAlive else { return }\n"
        "        let title = entries.last?.title ?? \"\"",
        "SwiftOpenUI GTK navigation header lifecycle guard insertion point was not recognized",
    ),
]:
    replace_navigation_once(marker, old, new, error)

replace_navigation_once(
    "let removed = entries.removeLast()\n        releaseToolbarWidgetReferences(in: removed)",
    "        let removed = entries.removeLast()\n"
    "        clearPresentedDestinationBindingIfNeeded",
    "        let removed = entries.removeLast()\n"
    "        releaseToolbarWidgetReferences(in: removed)\n"
    "        clearPresentedDestinationBindingIfNeeded",
    "SwiftOpenUI GTK navigation popped-toolbar release insertion point was not recognized",
)
replace_navigation_once(
    "private func releaseToolbarWidgetReferences(in entry: GTKNavigationEntry)",
    "    func replaceCurrentToolbar(with snapshot: GTKNavigationToolbarSnapshot) {",
    "    private func releaseToolbarWidgetReferences(in entry: GTKNavigationEntry) {\n"
    "        for item in entry.toolbarWidgets {\n"
    "            g_object_unref(gpointer(item.widget))\n"
    "        }\n"
    "    }\n\n"
    "    func replaceCurrentToolbar(with snapshot: GTKNavigationToolbarSnapshot) {",
    "SwiftOpenUI GTK navigation toolbar-reference release insertion point was not recognized",
)
replace_navigation_once(
    "func gtkTestNavigationContext(",
    "func gtkTestNavigationEntryCount(\n",
    "func gtkTestNavigationContext(\n"
    "    in stack: UnsafeMutablePointer<GtkWidget>\n"
    ") -> GTKNavigationContext? {\n"
    "    guard let data = g_object_get_data(\n"
    "        UnsafeMutableRawPointer(stack).assumingMemoryBound(to: GObject.self),\n"
    "        \"nav-context\"\n"
    "    ) else {\n"
    "        return nil\n"
    "    }\n"
    "    return Unmanaged<GTKNavigationContext>.fromOpaque(data).takeUnretainedValue()\n"
    "}\n\n"
    "func gtkTestNavigationEntryCount(\n",
    "SwiftOpenUI GTK navigation lifecycle test-hook insertion point was not recognized",
)
replace_navigation_once(
    "if context.nativeWidgetTreeIsAlive {\n            return context\n        }\n    }\n    let context = getCurrentEnvironment()",
    "    if let ptr = pthread_getspecific(_navContextKey) {\n"
    "        return Unmanaged<GTKNavigationContext>.fromOpaque(ptr).takeUnretainedValue()\n"
    "    }\n"
    "    return getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]",
    "    if let ptr = pthread_getspecific(_navContextKey) {\n"
    "        let context = Unmanaged<GTKNavigationContext>.fromOpaque(ptr).takeUnretainedValue()\n"
    "        if context.nativeWidgetTreeIsAlive {\n"
    "            return context\n"
    "        }\n"
    "    }\n"
    "    let context = getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]\n"
    "    return context?.nativeWidgetTreeIsAlive == true ? context : nil",
    "SwiftOpenUI GTK pthread navigation-context lifecycle shape was not recognized",
)
replace_navigation_once(
    "if let context = _currentNavContext, context.nativeWidgetTreeIsAlive",
    "    _currentNavContext ?? getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]",
    "    if let context = _currentNavContext, context.nativeWidgetTreeIsAlive {\n"
    "        return context\n"
    "    }\n"
    "    let context = getCurrentEnvironment()[GTKNavigationContextEnvironmentKey.self]\n"
    "    return context?.nativeWidgetTreeIsAlive == true ? context : nil",
    "SwiftOpenUI GTK fallback navigation-context lifecycle shape was not recognized",
)
replace_navigation_once(
    "let context = Unmanaged<GTKNavigationContext>.fromOpaque(userData!).takeRetainedValue()\n"
    "            context.invalidateNativeWidgetTree()",
    "        g_object_set_data_full(gobject, \"nav-context\", retained, { userData in\n"
    "            Unmanaged<GTKNavigationContext>.fromOpaque(userData!).release()\n"
    "        })",
    "        g_object_set_data_full(gobject, \"nav-context\", retained, { userData in\n"
    "            let context = Unmanaged<GTKNavigationContext>.fromOpaque(userData!).takeRetainedValue()\n"
    "            context.invalidateNativeWidgetTree()\n"
    "        })",
    "SwiftOpenUI GTK navigation native-destruction callback shape was not recognized",
)
text = text.replace("        gtkInstallToolbar(from: detail, on: paned)\n\n", "")
if text != original:
    path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

if "gtkSwiftNavigationPageInteractivityMarker" not in text:
    text = text.replace(
        "/// Marker string for indeterminate SwiftUI ProgressView widgets.\n"
        "let gtkSwiftIndeterminateProgressMarker = \"gtk-swift-indeterminate-progress\"\n",
        "/// Marker string for indeterminate SwiftUI ProgressView widgets.\n"
        "let gtkSwiftIndeterminateProgressMarker = \"gtk-swift-indeterminate-progress\"\n"
        "private let gtkSwiftNavigationPageInteractivityMarker = \"gtk-swift-navigation-page-interactive\"\n"
        "private let gtkSwiftNavigationPageInactiveValue = UnsafeMutableRawPointer(bitPattern: 2)\n",
        1,
    )

if "gtkWidgetIsInsideInactiveNavigationPage" not in text:
    text = text.replace(
        "private func gtkIsEmptyViewWidget(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {\n"
        "    gtkHasLayoutMarker(widget, key: gtkSwiftEmptyViewMarker)\n"
        "}\n\n"
        "private func gtkCreateEmptyViewWidget() -> UnsafeMutablePointer<GtkWidget> {\n",
        "private func gtkIsEmptyViewWidget(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {\n"
        "    gtkHasLayoutMarker(widget, key: gtkSwiftEmptyViewMarker)\n"
        "}\n\n"
        "private func gtkWidgetIsInsideInactiveNavigationPage(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {\n"
        "    var current: UnsafeMutablePointer<GtkWidget>? = widget\n"
        "    var depth = 0\n"
        "    while let node = current, depth < 160 {\n"
        "        let gobject = UnsafeMutableRawPointer(node).assumingMemoryBound(to: GObject.self)\n"
        "        if let raw = g_object_get_data(gobject, gtkSwiftNavigationPageInteractivityMarker) {\n"
        "            if raw == gtkSwiftNavigationPageInactiveValue {\n"
        "                return true\n"
        "            }\n"
        "        }\n"
        "        current = gtk_widget_get_parent(node)\n"
        "        depth += 1\n"
        "    }\n"
        "    return false\n"
        "}\n\n"
        "private func gtkCreateEmptyViewWidget() -> UnsafeMutablePointer<GtkWidget> {\n",
        1,
    )

if "guard !gtkWidgetIsInsideInactiveNavigationPage(widget) else { return nil }" not in text:
    text = text.replace(
        "    guard depth < 160 else { return nil }\n"
        "    guard gtk_widget_get_visible(widget) != 0,\n",
        "    guard depth < 160 else { return nil }\n"
        "    guard !gtkWidgetIsInsideInactiveNavigationPage(widget) else { return nil }\n"
        "    guard gtk_widget_get_visible(widget) != 0,\n",
        1,
    )

if "button root skipped inactive navigation page" not in text:
    text = text.replace(
        "    let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0\n",
        "    if gtkWidgetIsInsideInactiveNavigationPage(context.widget) {\n"
        "        gtkDebugLog(\"button root skipped inactive navigation page root@\\(Int(x)),\\(Int(y))\")\n"
        "        return 0\n"
        "    }\n"
        "    let isTopmost = gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0\n",
        1,
    )

if text != original:
    path.write_text(text)
PY

if ! grep -Fq '"textformat.abc"' "$SYMBOLS"; then
  perl -0pi \
    -e 's/(        "calendar":\s+"calendar_today",\n)/$1        "arrow.clockwise":       "refresh",\n        "character.cursor.ibeam": "text_fields",\n        "checkmark.seal.fill":    "verified",\n        "checkmark.square.fill":  "check_box",\n        "chevron.down":           "expand_more",\n        "doc.on.doc":             "content_copy",\n        "ellipsis.circle":        "more_horiz",\n        "folder":                 "folder",\n        "folder.badge.plus":      "create_new_folder",\n        "folder.fill":            "folder",\n        "gearshape":              "settings",\n        "gearshape.fill":         "settings",\n        "info.circle":            "info",\n        "keyboard":               "keyboard",\n        "keyboard.fill":          "keyboard",\n        "lightbulb":              "lightbulb",\n        "lightbulb.circle":       "lightbulb",\n        "lightbulb.circle.fill":  "lightbulb",\n        "line.3.horizontal":      "menu",\n        "lock.shield":            "shield_lock",\n        "shield.lefthalf.filled": "shield",\n/;' \
    -e 's/(        "pencil":\s+"edit",\n)/$1        "arrow.forward.circle.fill": "arrow_circle_right",\n        "paperclip":             "attach_file",\n        "paperplane.fill":       "send",\n/;' \
    -e 's/(        "plus.circle.fill":\s+"add_circle",\n)/$1        "photo":                 "image",\n        "photo.fill":            "image",\n        "questionmark.circle":    "help_outline",\n/;' \
    -e 's/(        "square.and.arrow.up":\s+"share",\n)/$1        "selection.pin.in.out":  "select_all",\n        "space":                 "space_bar",\n        "sidebar.left":           "view_sidebar",\n        "speaker.slash.fill":    "volume_off",\n        "speaker.wave.2.fill":   "volume_up",\n        "speaker.wave.3":        "volume_up",\n        "speaker.wave.3.fill":   "volume_up",\n/;' \
    -e 's/(        "square.and.pencil":\s+"edit",\n)/$1        "square":                "check_box_outline_blank",\n        "square.fill":           "stop",\n        "stop.fill":             "stop",\n/;' \
    -e 's/(        "tag.fill":\s+"label",\n)/$1        "sun.max":               "light_mode",\n        "textformat":            "text_fields",\n        "textformat.abc":        "text_fields",\n        "trash":                 "delete",\n        "water.waves":           "water",\n        "waveform":              "graphic_eq",\n/;' \
    -e 's/(        "xmark.circle.fill":\s+"cancel",\n)/$1        "x.circle.fill":         "cancel",\n        "xmark":                 "close",\n/;' \
    "$SYMBOLS"
fi

python3 - "$SYMBOLS" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

required_symbols = [
    ("arrow.clockwise", "refresh", ["arrow.uturn.clockwise", "calendar"]),
    ("arrow.forward.circle.fill", "arrow_circle_right", ["pencil", "calendar"]),
    ("character.cursor.ibeam", "text_fields", ["calendar"]),
    ("checkmark.seal.fill", "verified", ["checkmark.circle.fill", "checkmark.square.fill", "calendar"]),
    ("chevron.down", "expand_more", ["chevron.right", "calendar"]),
    ("curlybraces", "data_object", ["chevron.down", "calendar"]),
    ("doc.on.doc", "content_copy", ["calendar"]),
    ("doc.text", "description", ["doc.on.doc", "calendar"]),
    ("folder", "folder", ["calendar"]),
    ("folder.badge.plus", "create_new_folder", ["folder", "calendar"]),
    ("gearshape", "settings", ["calendar"]),
    ("gearshape.fill", "settings", ["gearshape", "calendar"]),
    ("info.circle", "info", ["gearshape.fill", "calendar"]),
    ("internaldrive", "hard_drive", ["folder.fill", "folder", "calendar"]),
    ("keyboard", "keyboard", ["info.circle", "calendar"]),
    ("keyboard.fill", "keyboard", ["keyboard", "calendar"]),
    ("lightbulb", "lightbulb", ["info.circle", "calendar"]),
    ("lightbulb.circle", "lightbulb", ["lightbulb", "calendar"]),
    ("lightbulb.circle.fill", "lightbulb", ["lightbulb.circle", "calendar"]),
    ("lock.shield", "shield_lock", ["lock.fill", "lock", "line.3.horizontal", "calendar"]),
    ("paperclip", "attach_file", ["pencil", "calendar"]),
    ("paperplane.fill", "send", ["arrow.forward.circle.fill", "pencil", "calendar"]),
    ("pause.fill", "pause", ["paperplane.fill", "calendar"]),
    ("play.fill", "play_arrow", ["pause.fill", "paperplane.fill", "calendar"]),
    ("photo", "image", ["plus.circle.fill", "calendar"]),
    ("photo.fill", "image", ["photo", "calendar"]),
    ("questionmark.circle", "help_outline", ["info.circle", "calendar"]),
    ("selection.pin.in.out", "select_all", ["square.and.arrow.up", "calendar"]),
    ("server.rack", "dns", ["sidebar.left", "rectangle.stack", "calendar"]),
    ("shield.lefthalf.filled", "shield", ["lock.shield", "lock.open", "line.3.horizontal", "calendar"]),
    ("square", "check_box_outline_blank", ["square.and.pencil", "calendar"]),
    ("square.fill", "stop", ["square", "calendar"]),
    ("textformat", "text_fields", ["tag.fill", "calendar"]),
    ("textformat.abc", "text_fields", ["textformat", "calendar"]),
    ("trash", "delete", ["tag.fill", "calendar"]),
    ("waveform", "graphic_eq", ["water.waves", "calendar"]),
    ("x.circle.fill", "cancel", ["xmark.circle.fill", "calendar"]),
    ("xmark", "close", ["x.circle.fill", "xmark.circle.fill", "calendar"]),
]


def entry(sf_name: str, material_name: str) -> str:
    key = f'"{sf_name}":'
    return f'        {key:<28}"{material_name}",\n'


def add_symbol(source: str, sf_name: str, material_name: str, anchors: list[str]) -> str:
    if f'"{sf_name}"' in source:
        return source
    for anchor in anchors:
        match = re.search(rf'(?m)^\s*"{re.escape(anchor)}":\s+"[^"]+",\n', source)
        if match:
            return source[:match.end()] + entry(sf_name, material_name) + source[match.end():]
    marker = "    ]"
    index = source.rfind(marker)
    if index == -1:
        raise SystemExit("SwiftOpenUI symbol compatibility map closing bracket was not recognized")
    return source[:index] + entry(sf_name, material_name) + source[index:]


for sf_name, material_name, anchors in required_symbols:
    text = add_symbol(text, sf_name, material_name, anchors)


def deduplicate_map_entries(source: str) -> str:
    entry_pattern = re.compile(
        r'(?m)^\s*"(?P<key>(?:\\.|[^"\\])+)":\s*"(?P<value>(?:\\.|[^"\\])*)",\n'
    )
    seen: set[str] = set()
    duplicate_spans: list[tuple[int, int]] = []

    for match in entry_pattern.finditer(source):
        key = match.group("key")
        if key in seen:
            duplicate_spans.append(match.span())
        else:
            seen.add(key)

    for start, end in reversed(duplicate_spans):
        source = source[:start] + source[end:]
    return source


text = deduplicate_map_entries(text)
if text != original:
    path.write_text(text)
PY

# Keep direct glyph rendering in sync with the SF -> Material map.
python3 - "$SYMBOL_CODEPOINTS" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

required_codepoints = [
    ("dns", "0xE875", ["description", "find_in_page", "folder"]),
    ("hard_drive", "0xF80E", ["folder_open", "newspaper", "search"]),
]


def entry(material_name: str, codepoint: str) -> str:
    key = f'"{material_name}":'
    return f'        {key:<22}{codepoint},\n'


def add_codepoint(source: str, material_name: str, codepoint: str, anchors: list[str]) -> str:
    if f'"{material_name}"' in source:
        return source
    for anchor in anchors:
        match = re.search(rf'(?m)^\s*"{re.escape(anchor)}":\s+0x[0-9A-Fa-f]+,\n', source)
        if match:
            return source[:match.end()] + entry(material_name, codepoint) + source[match.end():]
    marker = "    ]"
    index = source.rfind(marker)
    if index == -1:
        raise SystemExit("SwiftOpenUI Material Symbols codepoint table closing bracket was not recognized")
    return source[:index] + entry(material_name, codepoint) + source[index:]


for material_name, codepoint, anchors in required_codepoints:
    text = add_codepoint(text, material_name, codepoint, anchors)


def deduplicate_codepoint_entries(source: str) -> str:
    entry_pattern = re.compile(
        r'(?m)^\s*"(?P<key>(?:\\.|[^"\\])+)":\s+0x[0-9A-Fa-f]+,\n'
    )
    seen: set[str] = set()
    duplicate_spans: list[tuple[int, int]] = []

    for match in entry_pattern.finditer(source):
        key = match.group("key")
        if key in seen:
            duplicate_spans.append(match.span())
        else:
            seen.add(key)

    for start, end in reversed(duplicate_spans):
        source = source[:start] + source[end:]
    return source


text = deduplicate_codepoint_entries(text)
if text != original:
    path.write_text(text)
PY

# Apply QuillPaint integration to GTKRenderer.
python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
original = path.read_text()
text = original

hook_decl = (
    "public var quill_gtk_button_paint_hook: ((OpaquePointer, OpaquePointer, Bool) -> Bool)? = nil\n"
    "public var quill_gtk_text_field_paint_hook: ((OpaquePointer, Bool) -> OpaquePointer?)? = nil\n"
    "public var quill_gtk_text_editor_paint_hook: ((OpaquePointer, OpaquePointer) -> OpaquePointer?)? = nil\n"
    "public var quill_gtk_toggle_paint_hook: ((OpaquePointer, Bool, Bool, String) -> OpaquePointer?)? = nil\n"
    "public var quill_gtk_list_row_paint_hook: ((OpaquePointer, OpaquePointer, Bool, Bool) -> Bool)? = nil\n\n"
)
if "quill_gtk_button_paint_hook" not in text:
    marker = "// MARK: - GTK rendering protocol\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI GTK rendering protocol marker was not recognized")
    text = text.replace(marker, hook_decl + marker, 1)
elif "quill_gtk_text_field_paint_hook" not in text:
    text = text.replace(
        "public var quill_gtk_button_paint_hook: ((OpaquePointer, OpaquePointer, Bool) -> Bool)? = nil\n",
        "public var quill_gtk_button_paint_hook: ((OpaquePointer, OpaquePointer, Bool) -> Bool)? = nil\n"
        "public var quill_gtk_text_field_paint_hook: ((OpaquePointer, Bool) -> OpaquePointer?)? = nil\n",
        1,
    )
if "quill_gtk_text_editor_paint_hook" not in text:
    text = text.replace(
        "public var quill_gtk_text_field_paint_hook: ((OpaquePointer, Bool) -> OpaquePointer?)? = nil\n",
        "public var quill_gtk_text_field_paint_hook: ((OpaquePointer, Bool) -> OpaquePointer?)? = nil\n"
        "public var quill_gtk_text_editor_paint_hook: ((OpaquePointer, OpaquePointer) -> OpaquePointer?)? = nil\n",
        1,
    )
if "quill_gtk_toggle_paint_hook" not in text:
    text = text.replace(
        "public var quill_gtk_text_editor_paint_hook: ((OpaquePointer, OpaquePointer) -> OpaquePointer?)? = nil\n",
        "public var quill_gtk_text_editor_paint_hook: ((OpaquePointer, OpaquePointer) -> OpaquePointer?)? = nil\n"
        "public var quill_gtk_toggle_paint_hook: ((OpaquePointer, Bool, Bool, String) -> OpaquePointer?)? = nil\n",
        1,
    )
if "quill_gtk_list_row_paint_hook" not in text:
    text = text.replace(
        "public var quill_gtk_toggle_paint_hook: ((OpaquePointer, Bool, Bool, String) -> OpaquePointer?)? = nil\n",
        "public var quill_gtk_toggle_paint_hook: ((OpaquePointer, Bool, Bool, String) -> OpaquePointer?)? = nil\n"
        "public var quill_gtk_list_row_paint_hook: ((OpaquePointer, OpaquePointer, Bool, Bool) -> Bool)? = nil\n",
        1,
    )


if "private func gtkDisplayTextContent" not in text:
    view_marker = "// MARK: - View GTK extensions\n\n"
    display_text_helper = '''private func gtkDisplayTextContent(_ text: String) -> String {
    // U+2E31 is a valid word-separator middle dot used by some SwiftUI apps,
    // but common Linux GTK font stacks render it as tofu. U+00B7 preserves the
    // visual intent and is broadly available.
    text.replacingOccurrences(of: "\\u{2E31}", with: "\\u{00B7}")
}

'''
    if view_marker not in text:
        raise SystemExit("SwiftOpenUI View GTK extensions marker was not recognized")
    text = text.replace(view_marker, display_text_helper + view_marker, 1)

if "let displayContent = gtkDisplayTextContent(content)" not in text:
    text_replacements = [
        (
            "        let label = gtk_label_new(content)!\n",
            "        let displayContent = gtkDisplayTextContent(content)\n"
            "        let label = gtk_label_new(displayContent)!\n",
        ),
        (
            "        gtkPrepareRowTextLabel(label, text: content)\n",
            "        gtkPrepareRowTextLabel(label, text: displayContent)\n",
        ),
        (
            "            let escaped = run.text\n"
            "                .replacingOccurrences(of: \"&\", with: \"&amp;\")\n",
            "            let escaped = gtkDisplayTextContent(run.text)\n"
            "                .replacingOccurrences(of: \"&\", with: \"&amp;\")\n",
        ),
    ]
    for old, new in text_replacements:
        if old not in text:
            raise SystemExit("SwiftOpenUI Text GTK display normalization shape was not recognized")
        text = text.replace(old, new, 1)

if "private func gtkMaterialNameForSystemImage" not in text:
    label_marker = "// MARK: - Label GTK extension\n\n"
    label_system_image_helper = '''private func gtkMaterialNameForSystemImage(_ sfName: String) -> String {
    if let materialName = SFSymbolCompatibility.materialName(for: sfName) {
        return materialName
    }
    #if DEBUG
    FileHandle.standardError.write(Data(
        "[SwiftOpenUI] system image \\"\\(sfName)\\" has no Material mapping; rendering placeholder\\n".utf8
    ))
    #endif
    return SFSymbolCompatibility.missingSymbolPlaceholderName
}

'''
    if label_marker not in text:
        raise SystemExit("SwiftOpenUI Label GTK extension marker was not recognized")
    text = text.replace(label_marker, label_marker + label_system_image_helper, 1)

if "private func gtkMaterialSymbolName(forSystemName sfName: String)" not in text:
    label_marker = "// MARK: - Label GTK extension\n\n"
    label_system_symbol_helper = '''private func gtkMaterialSymbolName(forSystemName sfName: String) -> String {
    guard let materialName = SFSymbolCompatibility.materialName(for: sfName) else {
        #if DEBUG
        FileHandle.standardError.write(Data(
            "[SwiftOpenUI] Image(systemName: \\"\\(sfName)\\") has no Material mapping; rendering placeholder\\n".utf8
        ))
        #endif
        return SFSymbolCompatibility.missingSymbolPlaceholderName
    }
    return materialName
}

'''
    if label_marker not in text:
        raise SystemExit("SwiftOpenUI Label GTK extension marker was not recognized")
    text = text.replace(label_marker, label_marker + label_system_symbol_helper, 1)

label_index = text.find("extension Label: GTKRenderable")
if label_index == -1:
    raise SystemExit("SwiftOpenUI Label GTKRenderable extension was not recognized")
label_end = text.find("\n// MARK: - Corner Radius GTK extension", label_index)
if label_end == -1:
    raise SystemExit("SwiftOpenUI Label GTK extension end marker was not recognized")
label_section = text[label_index:label_end]
if (
    "gtkMaterialSymbolName(forSystemName: iconName)" not in label_section
    or "gtk_image_new_from_icon_name(iconName)" in label_section
):
    label_renderer = '''extension Label: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!

        if let iconView {
            gtk_box_append(boxPointer(box), widgetFromOpaque(gtkRenderView(iconView)))
        } else if let iconName = systemImage {
            let materialName = gtkMaterialSymbolName(forSystemName: iconName)
            gtk_box_append(boxPointer(box), gtkRenderMaterialSymbolLabel(materialName, scale: .small))
        } else if let path = imagePath {
            let img = gtk_image_new_from_file(path)!
            gtk_box_append(boxPointer(box), img)
        }

        if let titleView, !(titleView is Text) {
            gtk_box_append(boxPointer(box), widgetFromOpaque(gtkRenderView(titleView)))
        } else {
            let lbl = gtk_label_new(title)!
            gtk_box_append(boxPointer(box), lbl)
        }

        return opaqueFromWidget(box)
    }
}
'''
    text = text[:label_index] + label_renderer + text[label_end:]

image_index = text.find("extension Image: GTKRenderable")
image_end = text.find("\n/// Render a Material Symbols glyph", image_index) if image_index != -1 else -1
if image_index == -1 or image_end == -1:
    raise SystemExit("SwiftOpenUI Image GTKRenderable extension was not recognized")
image_section = text[image_index:image_end]
old_image_lookup = '''            let materialName = SFSymbolCompatibility.materialName(for: sfName)
                ?? SFSymbolCompatibility.missingSymbolPlaceholderName
            #if DEBUG
            if SFSymbolCompatibility.materialName(for: sfName) == nil {
                FileHandle.standardError.write(Data(
                    "[SwiftOpenUI] Image(systemName: \\"\\(sfName)\\") has no Material mapping; rendering placeholder\\n".utf8
                ))
            }
            #endif
'''
if old_image_lookup in image_section:
    image_section = image_section.replace(
        old_image_lookup,
        "            let materialName = gtkMaterialSymbolName(forSystemName: sfName)\n",
        1,
    )
    text = text[:image_index] + image_section + text[image_end:]

material_ligature_renderer = '''    let escapedName = gtkEscapeMarkup(name)
    let markup = """
        <span font_family="\\(familyName)" font_size="\\(scale.pointSize * 1000)">\\(escapedName)</span>
        """
    gtk_swift_label_set_markup(label, markup)
'''
material_codepoint_renderer = '''    let codepoint = MaterialSymbolsCodepoints.codepoint(for: name)
        ?? MaterialSymbolsCodepoints.missingGlyphCodepoint
    let glyph = Unicode.Scalar(codepoint).map(String.init) ?? "?"
    let escapedGlyph = gtkEscapeMarkup(glyph)
    let glyphPointSize = gtkMaterialSymbolGlyphPointSize(for: scale)
    let markup = """
        <span font_family="\\(familyName)" font_size="\\(glyphPointSize * 1000)">\\(escapedGlyph)</span>
        """
    gtk_swift_label_set_markup(label, markup)
'''
if material_ligature_renderer in text:
    text = text.replace(material_ligature_renderer, material_codepoint_renderer, 1)
elif "let glyphPointSize = gtkMaterialSymbolGlyphPointSize(for: scale)" not in text:
    raise SystemExit("SwiftOpenUI Material Symbols GTK renderer shape was not recognized")

if "private func gtkMaterialSymbolGlyphPointSize(for scale: ImageScale) -> Int" not in text:
    material_family_marker = "/// Material Symbols Rounded font family name, resolved via SwiftOpenUISymbols.\n"
    material_glyph_size_helper = '''private func gtkMaterialSymbolGlyphPointSize(for scale: ImageScale) -> Int {
    switch scale {
    case .small:
        return scale.pointSize
    case .medium, .large:
        return max(1, Int((Double(scale.pointSize) * 0.8).rounded()))
    }
}

'''

    if material_family_marker not in text:
        raise SystemExit("SwiftOpenUI Material Symbols family marker was not recognized")
    text = text.replace(material_family_marker, material_glyph_size_helper + material_family_marker, 1)

if "private func gtkFontCSS(_ font: Font)" not in text:
    font_helper_marker = '''private func gtkCSSRGBA(_ color: Color) -> String {
    let red = Int((color.red * 255).rounded())
    let green = Int((color.green * 255).rounded())
    let blue = Int((color.blue * 255).rounded())
    return "rgba(\\(red), \\(green), \\(blue), \\(color.alpha))"
}

// MARK: - GTK rendering protocol
'''
    font_helper_addition = '''let gtkSwiftFontMonospacedMarker = "gtk-swift-font-monospaced"
let gtkSwiftFontRoundedMarker = "gtk-swift-font-rounded"
let gtkSwiftFontSerifMarker = "gtk-swift-font-serif"

private let gtkFontDescendantSelectors = [
    "entry",
    "entry text",
    "passwordentry",
    "passwordentry text",
    "textview",
    "textview text"
]

private func gtkFontCSS(_ font: Font) -> (properties: String, designMarker: String?) {
    var declarations: [String] = []
    var designMarker: String?

    func appendWeight(_ weight: FontWeight) {
        declarations.append("font-weight: \\(gtkFontWeightCSS(weight));")
    }

    func appendDesign(_ design: FontDesign) {
        guard let family = gtkFontFamilyCSS(design) else { return }
        declarations.append("font-family: \\(family);")
        designMarker = gtkFontDesignMarker(design)
    }

    switch font {
    case .largeTitle:
        declarations.append("font-size: 28px;")
    case .title:
        declarations.append("font-size: 24px;")
    case .title2:
        declarations.append("font-size: 20px;")
        declarations.append("font-weight: bold;")
    case .title3:
        declarations.append("font-size: 18px;")
    case .headline:
        declarations.append("font-weight: bold;")
    case .subheadline:
        declarations.append("font-size: 12px;")
        declarations.append("font-weight: bold;")
    case .body:
        declarations.append("font-size: 14px;")
    case .callout:
        declarations.append("font-size: 12px;")
    case .footnote:
        declarations.append("font-size: 10px;")
    case .caption:
        declarations.append("font-size: 12px;")
    case .caption2:
        declarations.append("font-size: 10px;")
        declarations.append("font-weight: bold;")
    case .custom(let size, let weight, let design):
        declarations.append("font-size: \\(gtkFontSizeCSS(size))px;")
        appendWeight(weight)
        appendDesign(design)
    }

    return (declarations.joined(separator: " "), designMarker)
}

private func gtkFontSizeCSS(_ size: Double) -> String {
    let rounded = size.rounded()
    if abs(size - rounded) < 0.001 {
        return "\\(Int(rounded))"
    }
    return String(format: "%.2f", size)
}

private func gtkFontWeightCSS(_ weight: FontWeight) -> Int {
    switch weight {
    case .ultraLight: return 100
    case .thin: return 200
    case .light: return 300
    case .regular: return 400
    case .medium: return 500
    case .semibold: return 600
    case .bold: return 700
    case .heavy: return 800
    case .black: return 900
    }
}

private func gtkFontFamilyCSS(_ design: FontDesign) -> String? {
    switch design {
    case .default:
        return nil
    case .monospaced:
        return #""SF Mono", Menlo, Monaco, Consolas, "Liberation Mono", monospace"#
    case .rounded:
        return #""SF Pro Rounded", "Nunito", Cantarell, sans-serif"#
    case .serif:
        return #"Georgia, "Times New Roman", serif"#
    }
}

private func gtkFontDesignMarker(_ design: FontDesign) -> String? {
    switch design {
    case .default:
        return nil
    case .monospaced:
        return gtkSwiftFontMonospacedMarker
    case .rounded:
        return gtkSwiftFontRoundedMarker
    case .serif:
        return gtkSwiftFontSerifMarker

    }
}

'''
    if font_helper_marker in text:
        text = text.replace(font_helper_marker, font_helper_addition + font_helper_marker, 1)
    else:
        protocol_marker = "// MARK: - GTK rendering protocol\n"
        if protocol_marker not in text:
            raise SystemExit("SwiftOpenUI font CSS helper insertion marker was not recognized")
        text = text.replace(protocol_marker, font_helper_addition + protocol_marker, 1)

if "private func gtkTabViewShouldShowSwitcher" not in text:
    tab_index = text.find("extension TabView: GTKRenderable")
    if tab_index == -1:
        raise SystemExit("SwiftOpenUI TabView GTKRenderable extension was not recognized")
    tab_helper = '''private func gtkTabViewShouldShowSwitcher(_ tabs: [AnyTab]) -> Bool {
    tabs.count > 1 && tabs.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

'''
    text = text[:tab_index] + tab_helper + text[tab_index:]

if "if gtkTabViewShouldShowSwitcher(tabs)" not in text:
    old_tab_switcher = '''        let switcher = gtk_stack_switcher_new()!
        gtk_swift_stack_switcher_set_stack(switcher, stack)

        let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_box_append(boxPointer(vbox), switcher)
'''
    new_tab_switcher = '''        let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        if gtkTabViewShouldShowSwitcher(tabs) {
            let switcher = gtk_stack_switcher_new()!
            gtk_swift_stack_switcher_set_stack(switcher, stack)
            gtk_box_append(boxPointer(vbox), switcher)
        }
'''
    if old_tab_switcher not in text:
        raise SystemExit("SwiftOpenUI TabView GTK switcher shape was not recognized")
    text = text.replace(old_tab_switcher, new_tab_switcher, 1)

font_modified_index = text.find("extension FontModifiedView: GTKRenderable")
font_modified_end = text.find("\nextension ", font_modified_index + 1) if font_modified_index != -1 else -1
if font_modified_index != -1:
    if font_modified_end == -1:
        font_modified_end = len(text)
    font_modified_section = text[font_modified_index:font_modified_end]
    if "descendantSelectors: gtkFontDescendantSelectors" not in font_modified_section:
        old_font_body = '''        let css: String
        switch font {
        case .largeTitle:  css = "font-size: 28px;"
        case .title:       css = "font-size: 24px;"
        case .title2:      css = "font-size: 20px; font-weight: bold;"
        case .title3:      css = "font-size: 18px;"
        case .headline:    css = "font-weight: bold;"
        case .subheadline: css = "font-size: 12px; font-weight: bold;"
        case .body:        css = "font-size: 14px;"
        case .callout:     css = "font-size: 12px;"
        case .footnote:    css = "font-size: 10px;"
        case .caption:     css = "font-size: 12px;"
        case .caption2:    css = "font-size: 10px; font-weight: bold;"
        case .custom(let size, _, _): css = "font-size: \\(Int(size))px;"
        }
        applyCSSToWidget(widget, properties: css)
'''
        new_font_body = '''        let css = gtkFontCSS(font)
        applyCSSToWidget(
            widget,
            properties: css.properties,
            descendantSelectors: gtkFontDescendantSelectors
        )
        if let designMarker = css.designMarker {
            gtk_widget_add_css_class(widget, designMarker)
        }
'''
        if old_font_body not in font_modified_section:
            raise SystemExit("SwiftOpenUI FontModifiedView font CSS shape was not recognized")
        font_modified_section = font_modified_section.replace(old_font_body, new_font_body, 1)
        text = text[:font_modified_index] + font_modified_section + text[font_modified_end:]


if "private final class GTKTextBindingIdleUpdate" not in text:
    text_binding_helper = '''private final class GTKTextBindingIdleUpdate {
    let binding: Binding<String>
    let value: String

    init(binding: Binding<String>, value: String) {
        self.binding = binding
        self.value = value
    }

    func apply() {
        if binding.wrappedValue != value {
            binding.wrappedValue = value
        }
    }
}

private var gtkPendingTextBindingUpdate: GTKTextBindingIdleUpdate?
private var gtkPendingTextBindingSourceID: guint = 0

func gtkFlushPendingTextBindingUpdate() {
    if gtkPendingTextBindingSourceID != 0 {
        g_source_remove(gtkPendingTextBindingSourceID)
        gtkPendingTextBindingSourceID = 0
    }
    let pending = gtkPendingTextBindingUpdate
    gtkPendingTextBindingUpdate = nil
    pending?.apply()
}

/// Debounced entry->binding writes. Writing the binding on every keystroke
/// schedules a rebuild per keystroke, and any host whose plan is not
/// narrow-eligible then tears down the focused entry mid-typing — the rest
/// of the typed keys land on whatever GTK focuses next (Space activates it).
/// One pending write replaces the previous and flushes after a typing pause,
/// or eagerly before any app action, keyboard shortcut, or submit runs
/// (actions read the model, never the entry). Same-field edits always keep a
/// prefix relation between successive values; unrelated values mean a
/// different field, so the
/// previous field's pending write flushes first and is never lost.
private func gtkScheduleTextBindingUpdate(_ binding: Binding<String>, value: String) {
    if let pending = gtkPendingTextBindingUpdate,
       !value.hasPrefix(pending.value), !pending.value.hasPrefix(value) {
        gtkFlushPendingTextBindingUpdate()
    }
    if gtkPendingTextBindingSourceID != 0 {
        g_source_remove(gtkPendingTextBindingSourceID)
        gtkPendingTextBindingSourceID = 0
    }
    gtkPendingTextBindingUpdate = GTKTextBindingIdleUpdate(binding: binding, value: value)
    gtkPendingTextBindingSourceID = g_timeout_add(250, { _ -> gboolean in
        gtkPendingTextBindingSourceID = 0
        let pending = gtkPendingTextBindingUpdate
        gtkPendingTextBindingUpdate = nil
        pending?.apply()
        return 0
    }, nil)
}

'''
    helper_marker = "// MARK: - GTK rendering protocol\n"
    if helper_marker not in text:
        raise SystemExit("SwiftOpenUI TextField idle binding helper insertion marker was not recognized")
    text = text.replace(helper_marker, text_binding_helper + helper_marker, 1)

# Trees where GTKTextBindingIdleUpdate is already committed skip the helper
# block above; upgrade their committed idle-based scheduler to the debounced
# version in place (no-op once applied).
if "func gtkFlushPendingTextBindingUpdate" not in text:
    old_idle_scheduler = '''private func gtkScheduleTextBindingUpdate(_ binding: Binding<String>, value: String) {
    let context = Unmanaged.passRetained(
        GTKTextBindingIdleUpdate(binding: binding, value: value)
    ).toOpaque()
    g_idle_add({ userData -> gboolean in
        guard let userData else { return 0 }
        let context = Unmanaged<GTKTextBindingIdleUpdate>.fromOpaque(userData).takeRetainedValue()
        context.apply()
        return 0
    }, context)
}
'''
    new_debounced_scheduler = '''private var gtkPendingTextBindingUpdate: GTKTextBindingIdleUpdate?
private var gtkPendingTextBindingSourceID: guint = 0

func gtkFlushPendingTextBindingUpdate() {
    if gtkPendingTextBindingSourceID != 0 {
        g_source_remove(gtkPendingTextBindingSourceID)
        gtkPendingTextBindingSourceID = 0
    }
    let pending = gtkPendingTextBindingUpdate
    gtkPendingTextBindingUpdate = nil
    pending?.apply()
}

/// Debounced entry->binding writes. Writing the binding on every keystroke
/// schedules a rebuild per keystroke, and any host whose plan is not
/// narrow-eligible then tears down the focused entry mid-typing — the rest
/// of the typed keys land on whatever GTK focuses next (Space activates it).
/// One pending write replaces the previous and flushes after a typing pause,
/// or eagerly before any app action, keyboard shortcut, or submit runs
/// (actions read the model, never the entry). Same-field edits always keep a
/// prefix relation between successive values; unrelated values mean a
/// different field, so the
/// previous field's pending write flushes first and is never lost.
private func gtkScheduleTextBindingUpdate(_ binding: Binding<String>, value: String) {
    if let pending = gtkPendingTextBindingUpdate,
       !value.hasPrefix(pending.value), !pending.value.hasPrefix(value) {
        gtkFlushPendingTextBindingUpdate()
    }
    if gtkPendingTextBindingSourceID != 0 {
        g_source_remove(gtkPendingTextBindingSourceID)
        gtkPendingTextBindingSourceID = 0
    }
    gtkPendingTextBindingUpdate = GTKTextBindingIdleUpdate(binding: binding, value: value)
    gtkPendingTextBindingSourceID = g_timeout_add(250, { _ -> gboolean in
        gtkPendingTextBindingSourceID = 0
        let pending = gtkPendingTextBindingUpdate
        gtkPendingTextBindingUpdate = nil
        pending?.apply()
        return 0
    }, nil)
}
'''
    if old_idle_scheduler not in text:
        raise SystemExit("SwiftOpenUI TextField idle scheduler upgrade shape was not recognized")
    text = text.replace(old_idle_scheduler, new_debounced_scheduler, 1)

# Button actions read the model, never the entry — flush the debounced
# entry->binding write before scheduling any action so Save/submit always
# observes the typed text. (No-op once applied.)
old_schedule_action_entry = '''private func gtkScheduleButtonAction(_ box: GTKButtonActionBox, source: String) {
    let now = Date().timeIntervalSinceReferenceDate'''
new_schedule_action_entry = '''private func gtkScheduleButtonAction(_ box: GTKButtonActionBox, source: String) {
    gtkFlushPendingTextBindingUpdate()
    let now = Date().timeIntervalSinceReferenceDate'''
if "gtkFlushPendingTextBindingUpdate()\n    let now" not in text:
    if old_schedule_action_entry not in text:
        raise SystemExit("SwiftOpenUI Button action flush insertion shape was not recognized")
    text = text.replace(old_schedule_action_entry, new_schedule_action_entry, 1)

# All deferred UI actions read Swift model state, not GTK entry buffers. Flush
# the debounced text write in the central action-environment wrapper so custom
# labels, gestures, menus, toggles, and file-import controls see the same typed
# value as Button/submit paths. (No-op once applied.)
old_bound_action_flush = '''func bindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return {
        let previousEnvironment = getCurrentEnvironment()
'''
new_bound_action_flush = '''func bindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return {
        gtkFlushPendingTextBindingUpdate()
        let previousEnvironment = getCurrentEnvironment()
'''
if (
    "func bindActionToCurrentEnvironment(_ action:" in text
    and "private final class GTKDeferredAction<Value>" not in text
    and "return {\n        gtkFlushPendingTextBindingUpdate()" not in text
):
    if old_bound_action_flush not in text:
        raise SystemExit("SwiftOpenUI action binding flush insertion shape was not recognized")
    text = text.replace(old_bound_action_flush, new_bound_action_flush, 1)

old_bound_value_action_flush = '''func bindActionToCurrentEnvironment<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return { value in
        let previousEnvironment = getCurrentEnvironment()
'''
new_bound_value_action_flush = '''func bindActionToCurrentEnvironment<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return { value in
        gtkFlushPendingTextBindingUpdate()
        let previousEnvironment = getCurrentEnvironment()
'''
if (
    "func bindActionToCurrentEnvironment<T>" in text
    and "private final class GTKDeferredAction<Value>" not in text
    and "return { value in\n        gtkFlushPendingTextBindingUpdate()" not in text
):
    if old_bound_value_action_flush not in text:
        raise SystemExit("SwiftOpenUI value action binding flush insertion shape was not recognized")
    text = text.replace(old_bound_value_action_flush, new_bound_value_action_flush, 1)

# Refresh scoped object captures before a deferred action runs. GTK's native
# callbacks first enter a MainActor task so task-local storage has a real task
# owner and child Tasks inherit the same environment across suspension.
old_bound_action_environment_refresh = '''func bindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return {
        gtkFlushPendingTextBindingUpdate()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(capturedEnvironment)
        defer { setCurrentEnvironment(previousEnvironment) }
        if let capturedPresentationDismissAction {
            swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                action()
            }
        } else {
            action()
        }
    }
}
'''
intermediate_bound_action_environment_refresh = '''func bindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return {
        gtkFlushPendingTextBindingUpdate()
        var environment = capturedEnvironment
        environment.refreshInjectedObjectsFromRegistry()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previousEnvironment) }
        if let capturedPresentationDismissAction {
            swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                action()
            }
        } else {
            action()
        }
    }
}
'''
task_local_bound_action_environment_refresh = '''func bindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return {
        gtkFlushPendingTextBindingUpdate()
        var environment = capturedEnvironment
        environment.refreshInjectedObjectsFromRegistry()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previousEnvironment) }
        withSynchronousTaskEnvironment(environment) {
            if let capturedPresentationDismissAction {
                swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                    action()
                }
            } else {
                action()
            }
        }
    }
}
'''
new_bound_action_environment_refresh = '''private final class GTKDeferredAction<Value>: @unchecked Sendable {
    private let capturedEnvironment: EnvironmentValues
    private let capturedPresentationDismissAction: (() -> Void)?
    private let action: (Value) -> Void

    init(
        environment: EnvironmentValues,
        presentationDismissAction: (() -> Void)?,
        action: @escaping (Value) -> Void
    ) {
        capturedEnvironment = environment
        capturedPresentationDismissAction = presentationDismissAction
        self.action = action
    }

    func schedule(_ value: Value) {
        let invocation = GTKDeferredActionInvocation(action: self, value: value)
        Task { @MainActor [invocation] in
            invocation.run()
        }
    }

    @MainActor
    fileprivate func run(_ value: Value) {
        gtkFlushPendingTextBindingUpdate()
        var environment = capturedEnvironment
        environment.refreshInjectedObjectsFromRegistry()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previousEnvironment) }
        withSynchronousTaskEnvironment(environment) {
            if let capturedPresentationDismissAction {
                swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                    action(value)
                }
            } else {
                action(value)
            }
        }
    }
}

private final class GTKDeferredActionInvocation<Value>: @unchecked Sendable {
    private let action: GTKDeferredAction<Value>
    private let value: Value

    init(action: GTKDeferredAction<Value>, value: Value) {
        self.action = action
        self.value = value
    }

    @MainActor
    func run() {
        action.run(value)
    }
}

/// Capture the current environment at registration time and restore it around
/// a deferred callback that may read `@Environment(...)`. Native GTK callbacks
/// have no Swift task, so enter a MainActor task before opening task-local
/// scopes. See `docs/architecture/deferred-callback-environment-binding.md`.
func bindActionToCurrentEnvironment(_ action: @escaping () -> Void) -> () -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let deferredAction = GTKDeferredAction<Void>(
        environment: capturedEnvironment,
        presentationDismissAction: swiftOpenUIResolvePresentationDismissAction(
            in: capturedEnvironment
        ),
        action: { _ in action() }
    )
    return { deferredAction.schedule(()) }
}
'''
if new_bound_action_environment_refresh not in text:
    if old_bound_action_environment_refresh in text:
        old_bound_action_source = old_bound_action_environment_refresh
    elif intermediate_bound_action_environment_refresh in text:
        old_bound_action_source = intermediate_bound_action_environment_refresh
    elif task_local_bound_action_environment_refresh in text:
        old_bound_action_source = task_local_bound_action_environment_refresh
    else:
        raise SystemExit("SwiftOpenUI refreshed action binding shape was not recognized")
    text = text.replace(
        old_bound_action_source,
        new_bound_action_environment_refresh,
        1,
    )

old_bound_value_action_environment_refresh = '''func bindActionToCurrentEnvironment<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return { value in
        gtkFlushPendingTextBindingUpdate()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(capturedEnvironment)
        defer { setCurrentEnvironment(previousEnvironment) }
        if let capturedPresentationDismissAction {
            swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                action(value)
            }
        } else {
            action(value)
        }
    }
}
'''
intermediate_bound_value_action_environment_refresh = '''func bindActionToCurrentEnvironment<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return { value in
        gtkFlushPendingTextBindingUpdate()
        var environment = capturedEnvironment
        environment.refreshInjectedObjectsFromRegistry()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previousEnvironment) }
        if let capturedPresentationDismissAction {
            swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                action(value)
            }
        } else {
            action(value)
        }
    }
}
'''
task_local_bound_value_action_environment_refresh = '''func bindActionToCurrentEnvironment<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let capturedPresentationDismissAction = swiftOpenUIResolvePresentationDismissAction(
        in: capturedEnvironment
    )
    return { value in
        gtkFlushPendingTextBindingUpdate()
        var environment = capturedEnvironment
        environment.refreshInjectedObjectsFromRegistry()
        let previousEnvironment = getCurrentEnvironment()
        setCurrentEnvironment(environment)
        defer { setCurrentEnvironment(previousEnvironment) }
        withSynchronousTaskEnvironment(environment) {
            if let capturedPresentationDismissAction {
                swiftOpenUIWithPresentationDismissAction(capturedPresentationDismissAction) {
                    action(value)
                }
            } else {
                action(value)
            }
        }
    }
}
'''
new_bound_value_action_environment_refresh = '''func bindActionToCurrentEnvironment<T>(_ action: @escaping (T) -> Void) -> (T) -> Void {
    let capturedEnvironment = getCurrentEnvironment()
    let deferredAction = GTKDeferredAction<T>(
        environment: capturedEnvironment,
        presentationDismissAction: swiftOpenUIResolvePresentationDismissAction(
            in: capturedEnvironment
        ),
        action: action
    )
    return { value in deferredAction.schedule(value) }
}
'''
if new_bound_value_action_environment_refresh not in text:
    if old_bound_value_action_environment_refresh in text:
        old_bound_value_action_source = old_bound_value_action_environment_refresh
    elif intermediate_bound_value_action_environment_refresh in text:
        old_bound_value_action_source = intermediate_bound_value_action_environment_refresh
    elif task_local_bound_value_action_environment_refresh in text:
        old_bound_value_action_source = task_local_bound_value_action_environment_refresh
    else:
        raise SystemExit("SwiftOpenUI refreshed value action binding shape was not recognized")
    text = text.replace(
        old_bound_value_action_source,
        new_bound_value_action_environment_refresh,
        1,
    )

text = text.replace(
    "includeValueWhenUnidentified: Bool = true",
    "includeValueWhenUnidentified: Bool = false",
)

text = text.replace(
    "includeValueWhenUnidentified: Bool = true",
    "includeValueWhenUnidentified: Bool = false",
)

if "case .quillPaintMacDefault:" not in text:
    extension_index = text.find("extension Button: GTKRenderable")
    if extension_index == -1:
        raise SystemExit("SwiftOpenUI Button GTKRenderable extension was not recognized")
    create_index = text.find("    public func gtkCreateWidget() -> OpaquePointer {", extension_index)
    if create_index == -1:
        raise SystemExit("SwiftOpenUI Button gtkCreateWidget shape was not recognized")
    start = text.find("        let button: UnsafeMutablePointer<GtkWidget>", create_index)
    end = text.find("        let boundAction = bindActionToCurrentEnvironment(action)", start)
    if start == -1 or end == -1:
        raise SystemExit("SwiftOpenUI Button setup shape was not recognized")

    replacement = '''        let button: UnsafeMutablePointer<GtkWidget>
        let childWidget: UnsafeMutablePointer<GtkWidget>
        var buttonWantsHExpand = false
        var buttonWantsVExpand = false

        button = gtk_button_new()!
        if let textLabel = label as? Text {
            childWidget = widgetFromOpaque(textLabel.gtkCreateWidget())
        } else {
            childWidget = widgetFromOpaque(gtkRenderView(label))
            if gtk_widget_get_hexpand(childWidget) != 0 {
                buttonWantsHExpand = true
                gtk_widget_set_halign(childWidget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(childWidget) != 0 {
                buttonWantsVExpand = true
                gtk_widget_set_valign(childWidget, GTK_ALIGN_FILL)
            }
        }

        let buttonStyleType = getCurrentEnvironment().buttonStyle
        let handledByQuillPaint: Bool
        switch buttonStyleType {
        case .quillPaintMacDefault:
            handledByQuillPaint = quill_gtk_button_paint_hook?(OpaquePointer(button), OpaquePointer(childWidget), true) ?? false
        case .quillPaintMacBordered:
            handledByQuillPaint = quill_gtk_button_paint_hook?(OpaquePointer(button), OpaquePointer(childWidget), false) ?? false
        case let .quillPaintMacListRow(isSelected, drawsIdleBackground):
            handledByQuillPaint = quill_gtk_list_row_paint_hook?(
                OpaquePointer(button),
                OpaquePointer(childWidget),
                isSelected,
                drawsIdleBackground
            ) ?? false
        default:
            handledByQuillPaint = false
        }

        if !handledByQuillPaint {
            let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
            gtk_button_set_child(btnPtr, childWidget)
            gtkDisableButtonChildTargeting(childWidget)
            if styleContext != nil || !(label is Text) {
                // Remove GTK default button border/padding so custom-styled
                // labels (with .background/.frame) render cleanly.
                applyCSSToWidget(button, properties: """
                    background: transparent;
                    background-color: transparent;
                    background-image: none;
                    border: none;
                    border-radius: 0;
                    box-shadow: none;
                    outline: none;
                    padding: 0;
                    min-height: 0;
                    min-width: 0;
                    text-shadow: none;
                    """)
            }

            switch buttonStyleType {
            case .plain:
                gtk_widget_add_css_class(button, "flat")
                applyCSSToWidget(button, properties: """
                    background: transparent;
                    background-color: transparent;
                    background-image: none;
                    border: none;
                    border-radius: 0;
                    box-shadow: none;
                    outline: none;
                    padding: 0;
                    min-height: 0;
                    min-width: 0;
                    text-shadow: none;
                    """)
            case .borderedProminent:
                applyCSSToWidget(
                    button,
                    properties: """
                        background-color: #3584e4;
                        background-image: none;
                        color: white;
                        border: none;
                        border-radius: 6px;
                        padding: 6px 12px;
                        box-shadow: none;
                        text-shadow: none;
                        min-height: 0;
                        """,
                    disabledProperties: """
                        background-color: rgba(53, 132, 228, 0.4);
                        color: rgba(255, 255, 255, 0.7);
                        """
                )
            case .bordered:
                applyCSSToWidget(button, properties: """
                    border: 1px solid @borders; border-radius: 6px;
                    padding: 6px 12px;
                    """)
            case .automatic, .quillPaintMacDefault, .quillPaintMacBordered, .quillPaintMacListRow(_, _):
                break
            }
        }

        gtk_widget_set_hexpand(button, buttonWantsHExpand ? 1 : 0)
        gtk_widget_set_vexpand(button, buttonWantsVExpand ? 1 : 0)
        gtk_widget_set_halign(button, buttonWantsHExpand ? GTK_ALIGN_FILL : GTK_ALIGN_START)
        gtk_widget_set_valign(button, buttonWantsVExpand ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)

'''
    text = text[:start] + replacement + text[end:]

if "case let .quillPaintMacListRow(isSelected, drawsIdleBackground):" not in text:
    bordered_case = '''            case .quillPaintMacBordered:
                handledByQuillPaint = quill_gtk_button_paint_hook?(OpaquePointer(button), OpaquePointer(childWidget), false) ?? false
'''
    list_row_case = '''            case .quillPaintMacBordered:
                handledByQuillPaint = quill_gtk_button_paint_hook?(OpaquePointer(button), OpaquePointer(childWidget), false) ?? false
            case let .quillPaintMacListRow(isSelected, drawsIdleBackground):
                handledByQuillPaint = quill_gtk_list_row_paint_hook?(
                    OpaquePointer(button),
                    OpaquePointer(childWidget),
                    isSelected,
                    drawsIdleBackground
                ) ?? false
'''
    if bordered_case not in text:
        raise SystemExit("SwiftOpenUI Button QuillPaint bordered case was not recognized")
    text = text.replace(bordered_case, list_row_case, 1)

if ".quillPaintMacListRow(_, _)" not in text:
    if "            case .automatic:\n                break // default GTK button styling\n" in text:
        text = text.replace(
            "            case .automatic:\n                break // default GTK button styling\n",
            "            case .automatic, .quillPaintMacListRow(_, _):\n                break // default GTK button styling\n",
            1,
        )
    elif "            case .automatic, .quillPaintMacDefault, .quillPaintMacBordered:\n                break\n" in text:
        text = text.replace(
            "            case .automatic, .quillPaintMacDefault, .quillPaintMacBordered:\n                break\n",
            "            case .automatic, .quillPaintMacDefault, .quillPaintMacBordered, .quillPaintMacListRow(_, _):\n                break\n",
            1,
        )
    else:
        raise SystemExit("SwiftOpenUI Button fallback style case was not recognized")

button_extension_index = text.find("extension Button: GTKRenderable")
if button_extension_index == -1:
    raise SystemExit("SwiftOpenUI Button GTKRenderable extension was not recognized")
button_child_set = "            gtk_button_set_child(btnPtr, childWidget)\n"
button_child_index = text.find(button_child_set, button_extension_index)
if button_child_index == -1:
    raise SystemExit("SwiftOpenUI Button child install shape was not recognized")
button_targeting_call = "            gtkDisableButtonChildTargeting(childWidget)\n"
button_targeting_window = text[
    button_child_index: button_child_index + len(button_child_set) + len(button_targeting_call) + 80
]
if button_targeting_call not in button_targeting_window:
    insert_index = button_child_index + len(button_child_set)
    text = text[:insert_index] + button_targeting_call + text[insert_index:]

text_field_index = text.find("extension TextField: GTKRenderable")
if text_field_index == -1:
    raise SystemExit("SwiftOpenUI TextField GTKRenderable extension was not recognized")
text_field_end = text.find("\nextension ", text_field_index + 1)
if text_field_end == -1:
    text_field_end = len(text)

if (
    '"changed"' not in text[text_field_index:text_field_end]
    and "gtk_entry_buffer_get_text" in text[text_field_index:text_field_end]
):
    style_comment = "        // Apply text field style from environment\n"
    style_index = text.find(style_comment, text_field_index, text_field_end)
    if style_index == -1:
        raise SystemExit("SwiftOpenUI TextField changed-signal insert shape was not recognized")
    text_field_changed_signal = '''        // GtkEntry also emits "changed" as a GtkEditable; keep this in sync with
        // SecureField so user edits always reach SwiftUI bindings before dismissal.
        let changedBox = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
        g_signal_connect_data(
            gpointer(entry),
            "changed",
            unsafeBitCast({ (editable: gpointer?, userData: gpointer?) in
                let box = Unmanaged<StringClosureBox>.fromOpaque(userData!).takeUnretainedValue()
                let cStr = gtk_editable_get_text(OpaquePointer(editable))!
                box.closure(String(cString: cStr))
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            changedBox,
            { (userData: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
                Unmanaged<StringClosureBox>.fromOpaque(userData!).release()
            },
            GConnectFlags(rawValue: 0)
        )

'''
    text = text[:style_index] + text_field_changed_signal + text[style_index:]
    text_field_end = text.find("\nextension ", text_field_index + 1)
    if text_field_end == -1:
        text_field_end = len(text)

text_field_section = text[text_field_index:text_field_end]
direct_update = '''        let box = Unmanaged.passRetained(StringClosureBox { newText in
            // Avoid feedback loop: only set if value actually changed
            if binding.wrappedValue != newText {
                binding.wrappedValue = newText
            }
        }).toOpaque()
'''
idle_update = '''        let box = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
'''
if direct_update in text_field_section:
    text = (
        text[:text_field_index]
        + text_field_section.replace(direct_update, idle_update, 1)
        + text[text_field_end:]
    )
    text_field_end = text.find("\nextension ", text_field_index + 1)
    if text_field_end == -1:
        text_field_end = len(text)
    text_field_section = text[text_field_index:text_field_end]

direct_changed_update = '''        let changedBox = Unmanaged.passRetained(StringClosureBox { newText in
            if binding.wrappedValue != newText {
                binding.wrappedValue = newText
            }
        }).toOpaque()
'''
idle_changed_update = '''        let changedBox = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
'''
if direct_changed_update in text_field_section:
    text = (
        text[:text_field_index]
        + text_field_section.replace(direct_changed_update, idle_changed_update, 1)
        + text[text_field_end:]
    )
    text_field_end = text.find("\nextension ", text_field_index + 1)
    if text_field_end == -1:
        text_field_end = len(text)

if "var useQuillPaintTextField = false" not in text[text_field_index:text_field_end]:
    style_var = "        let textFieldStyleType = getCurrentEnvironment().textFieldStyle\n"
    style_index = text.find(style_var, text_field_index)
    if style_index == -1:
        raise SystemExit("SwiftOpenUI TextField style variable shape was not recognized")
    return_index = text.find("        gtkApplyEnabledState(to: entry)", style_index)
    if return_index == -1:
        raise SystemExit("SwiftOpenUI TextField enabled-state shape was not recognized")
    insert_index = style_index + len(style_var)
    text = text[:insert_index] + "        var useQuillPaintTextField = false\n" + text[insert_index:]
    return_index = text.find("        gtkApplyEnabledState(to: entry)", insert_index)
    automatic_case = "        case .automatic, .roundedBorder:\n"
    case_index = text.find(automatic_case, insert_index, return_index)
    if case_index == -1:
        raise SystemExit("SwiftOpenUI TextField automatic style case was not recognized")
    body_index = case_index + len(automatic_case)
    for old_body in (
        "            break // default GTK entry styling\n",
        "            break\n",
    ):
        if text.startswith(old_body, body_index):
            text = text[:body_index] + "            useQuillPaintTextField = true\n" + text[body_index + len(old_body):]
            break
    else:
        raise SystemExit("SwiftOpenUI TextField automatic style body was not recognized")
    text_field_end = text.find("\nextension ", text_field_index + 1)
    if text_field_end == -1:
        text_field_end = len(text)

if "quill_gtk_text_field_paint_hook?" not in text[text_field_index:text_field_end]:
    old_text_field_return = '''        gtkApplyEnabledState(to: entry)
        return opaqueFromWidget(entry)
'''
    new_text_field_return = '''        gtkApplyEnabledState(to: entry)
        if useQuillPaintTextField,
           let paintedEntry = quill_gtk_text_field_paint_hook?(
               OpaquePointer(entry),
               textFieldStyleType == .roundedBorder
           ) {
            return paintedEntry
        }
        return opaqueFromWidget(entry)
'''
    return_index = text.find(old_text_field_return, text_field_index)
    if return_index == -1:
        raise SystemExit("SwiftOpenUI TextField return shape was not recognized")
    text = text[:return_index] + new_text_field_return + text[return_index + len(old_text_field_return):]

secure_field_index = text.find("extension SecureField: GTKRenderable")
secure_field_hook_call = "quill_gtk_text_field_paint_hook?(OpaquePointer(entry), true)"
secure_field_end = text.find("\nextension ", secure_field_index + 1) if secure_field_index != -1 else -1
if secure_field_end == -1:
    secure_field_end = len(text)
if secure_field_index != -1 and secure_field_hook_call not in text[secure_field_index:secure_field_end]:
    old_secure_field_return = '''        gtkApplyEnabledState(to: entry)
        return opaqueFromWidget(entry)
'''
    new_secure_field_return = '''        gtkApplyEnabledState(to: entry)
        if let paintedEntry = quill_gtk_text_field_paint_hook?(OpaquePointer(entry), true) {
            return paintedEntry
        }
        return opaqueFromWidget(entry)
'''
    return_index = text.find(old_secure_field_return, secure_field_index)
    if return_index == -1:
        raise SystemExit("SwiftOpenUI SecureField return shape was not recognized")
    text = text[:return_index] + new_secure_field_return + text[return_index + len(old_secure_field_return):]

text_editor_index = text.find("extension TextEditor: GTKRenderable")
text_editor_end = text.find("\nextension ", text_editor_index + 1) if text_editor_index != -1 else -1
if text_editor_end == -1:
    text_editor_end = len(text)
text_editor_section = text[text_editor_index:text_editor_end]
direct_text_editor_update = '''        let box = Unmanaged.passRetained(StringClosureBox { newText in
            if newText != binding.wrappedValue {
                binding.wrappedValue = newText
            }
        }).toOpaque()
'''
idle_text_editor_update = '''        let box = Unmanaged.passRetained(StringClosureBox { newText in
            gtkScheduleTextBindingUpdate(binding, value: newText)
        }).toOpaque()
'''
if direct_text_editor_update in text_editor_section:
    text = (
        text[:text_editor_index]
        + text_editor_section.replace(direct_text_editor_update, idle_text_editor_update, 1)
        + text[text_editor_end:]
    )
    text_editor_end = text.find("\nextension ", text_editor_index + 1)
    if text_editor_end == -1:
        text_editor_end = len(text)
    text_editor_section = text[text_editor_index:text_editor_end]
old_text_editor_options = '''        gtk_text_view_set_wrap_mode(textViewPtr, GTK_WRAP_WORD_CHAR)
'''
if (
    "gtk_text_view_set_accepts_tab(textViewPtr, 1)" not in text_editor_section
    and old_text_editor_options in text_editor_section
):
    new_text_editor_options = '''        gtk_text_view_set_wrap_mode(textViewPtr, GTK_WRAP_WORD_CHAR)
        gtk_text_view_set_accepts_tab(textViewPtr, 1)
'''
    text = (
        text[:text_editor_index]
        + text_editor_section.replace(old_text_editor_options, new_text_editor_options, 1)
        + text[text_editor_end:]
    )
    text_editor_end = text.find("\nextension ", text_editor_index + 1)
    if text_editor_end == -1:
        text_editor_end = len(text)
    text_editor_section = text[text_editor_index:text_editor_end]
if "quill_gtk_text_editor_paint_hook?" not in text[text_editor_index:text_editor_end]:
    old_text_editor_return = '''        gtkApplyEnabledState(to: textView)
        return opaqueFromWidget(scrolled)
'''
    new_text_editor_return = '''        gtkApplyEnabledState(to: textView)
        if let paintedEditor = quill_gtk_text_editor_paint_hook?(
            OpaquePointer(scrolled),
            OpaquePointer(textView)
        ) {
            return paintedEditor
        }
        return opaqueFromWidget(scrolled)
'''
    if text_editor_index == -1:
        raise SystemExit("SwiftOpenUI TextEditor GTKRenderable extension was not recognized")
    return_index = text.find(old_text_editor_return, text_editor_index)
    if return_index == -1:
        raise SystemExit("SwiftOpenUI TextEditor return shape was not recognized")
    text = text[:return_index] + new_text_editor_return + text[return_index + len(old_text_editor_return):]

picker_index = text.find("extension Picker: GTKRenderable")
if picker_index == -1:
    raise SystemExit("SwiftOpenUI Picker GTKRenderable extension was not recognized")
if "extension Picker: GTKRenderable, GTKDescribable" not in text:
    text = text.replace(
        "extension Picker: GTKRenderable {",
        "extension Picker: GTKRenderable, GTKDescribable {",
        1,
    )
    picker_index = text.find("extension Picker: GTKRenderable")
picker_end = text.find("\nextension ", picker_index + 1)
if picker_end == -1:
    picker_end = len(text)
picker_section = text[picker_index:picker_end]
if 'typeName: "Picker"' not in picker_section:
    old_picker_describe_marker = '''        gtkApplyEnabledState(to: widgetFromOpaque(widget))
        return widget
    }

    /// True iff the caller wrapped us in `.labelsHidden()`. The
'''
    new_picker_describe_marker = '''        gtkApplyEnabledState(to: widgetFromOpaque(widget))
        return widget
    }

    public func gtkDescribeNode() -> GTK4DescriptorNode {
        GTK4DescriptorNode(
            kind: .composite,
            typeName: "Picker",
            props: .text(GTK4TextDescriptor(
                content: "\\(label)|\\(selected)|\\(style)|\\(options.joined(separator: "\\u{1f}"))"
            ))
        )
    }

    /// True iff the caller wrapped us in `.labelsHidden()`. The
'''
    if old_picker_describe_marker not in picker_section:
        raise SystemExit("SwiftOpenUI Picker GTK descriptor insertion shape was not recognized")
    text = (
        text[:picker_index]
        + picker_section.replace(old_picker_describe_marker, new_picker_describe_marker, 1)
        + text[picker_end:]
    )
picker_index = text.find("extension Picker: GTKRenderable")
picker_end = text.find("\nextension ", picker_index + 1)
if picker_end == -1:
    picker_end = len(text)
picker_section = text[picker_index:picker_end]
if "gtk_swift_drop_down_new(stringList)" not in picker_section:
    old_dropdown_model = '''        let cStrings: [UnsafeMutablePointer<CChar>?] = options.map { strdup($0) } + [nil]

        let dropdown = cStrings.withUnsafeBufferPointer { buf -> UnsafeMutablePointer<GtkWidget> in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { ptr in
                gtk_drop_down_new_from_strings(ptr)!
            }
        }

        for cStr in cStrings { cStr.map { free($0) } }

        let dropdownOp = OpaquePointer(dropdown)
'''
    new_dropdown_model = '''        let stringList = gtk_swift_string_list_new()!
        for option in options {
            gtk_swift_string_list_append(stringList, option)
        }

        let dropdown = gtk_swift_drop_down_new(stringList)!
        let dropdownOp = OpaquePointer(dropdown)
'''
    if old_dropdown_model not in picker_section:
        raise SystemExit("SwiftOpenUI Picker dropdown model shape was not recognized")
    text = (
        text[:picker_index]
        + picker_section.replace(old_dropdown_model, new_dropdown_model, 1)
        + text[picker_end:]
    )

picker_index = text.find("extension Picker: GTKRenderable")
picker_end = text.find("\nextension ", picker_index + 1)
if picker_end == -1:
    picker_end = len(text)
picker_section = text[picker_index:picker_end]
if "guard options.indices.contains(newIndex), newIndex != clampedSelection else" not in picker_section:
    old_picker_callback = '''        if let onChanged = onChanged {
            let box = Unmanaged.passRetained(IntClosureBox(onChanged)).toOpaque()
            g_signal_connect_data(
'''
    new_picker_callback = '''        if let onChanged = onChanged {
            let boundOnChanged = bindActionToCurrentEnvironment(onChanged)
            let box = Unmanaged.passRetained(IntClosureBox { newIndex in
                guard options.indices.contains(newIndex), newIndex != clampedSelection else {
                    return
                }
                boundOnChanged(newIndex)
            }).toOpaque()
            g_signal_connect_data(
'''
    if old_picker_callback not in picker_section:
        raise SystemExit("SwiftOpenUI Picker dropdown callback shape was not recognized")
    text = (
        text[:picker_index]
        + picker_section.replace(old_picker_callback, new_picker_callback, 1)
        + text[picker_end:]
    )

picker_index = text.find("extension Picker: GTKRenderable")
picker_end = text.find("\nextension ", picker_index + 1)
if picker_end == -1:
    picker_end = len(text)
picker_section = text[picker_index:picker_end]
if "let boundOnChanged = onChanged.map { bindActionToCurrentEnvironment($0) }" not in picker_section:
    old_segment_callback = '''        for (index, button) in buttons.enumerated() {
            if let onChanged = onChanged {
                let box = Unmanaged.passRetained(
                    SegmentClosureBox(index: index, closure: onChanged)
                ).toOpaque()
'''
    new_segment_callback = '''        let boundOnChanged = onChanged.map { bindActionToCurrentEnvironment($0) }
        for (index, button) in buttons.enumerated() {
            if let boundOnChanged = boundOnChanged {
                let box = Unmanaged.passRetained(
                    SegmentClosureBox(index: index, closure: boundOnChanged)
                ).toOpaque()
'''
    if old_segment_callback not in picker_section:
        raise SystemExit("SwiftOpenUI Picker segmented callback shape was not recognized")
    text = (
        text[:picker_index]
        + picker_section.replace(old_segment_callback, new_segment_callback, 1)
        + text[picker_end:]
    )

toggle_index = text.find("extension Toggle: GTKRenderable")
if toggle_index == -1:
    raise SystemExit("SwiftOpenUI Toggle GTKRenderable extension was not recognized")
toggle_end = text.find("\nextension ", toggle_index + 1)
if toggle_end == -1:
    toggle_end = len(text)
toggle_section = text[toggle_index:toggle_end]

old_check_create = '''        let check = label.isEmpty
            ? gtk_check_button_new()!
            : gtk_check_button_new_with_label(label)!
'''
new_check_create = '''        let check = label.isEmpty || quill_gtk_toggle_paint_hook != nil
            ? gtk_check_button_new()!
            : gtk_check_button_new_with_label(label)!
'''
if old_check_create in toggle_section:
    create_index = text.find(old_check_create, toggle_index, toggle_end)
    text = text[:create_index] + new_check_create + text[create_index + len(old_check_create):]
    toggle_end = text.find("\nextension ", toggle_index + 1)
    if toggle_end == -1:
        toggle_end = len(text)

toggle_section = text[toggle_index:toggle_end]
if "quill_gtk_toggle_paint_hook?(" not in toggle_section:
    old_check_return = '''        gtkApplyEnabledState(to: check)
        return opaqueFromWidget(check)
'''
    new_check_return = '''        gtkApplyEnabledState(to: check)
        if let paintedToggle = quill_gtk_toggle_paint_hook?(
            OpaquePointer(check),
            isOn.wrappedValue,
            false,
            label
        ) {
            return paintedToggle
        }
        return opaqueFromWidget(check)
'''
    return_index = text.find(old_check_return, toggle_index, toggle_end)
    if return_index == -1:
        raise SystemExit("SwiftOpenUI Toggle check-button return shape was not recognized")
    text = text[:return_index] + new_check_return + text[return_index + len(old_check_return):]
    toggle_end = text.find("\nextension ", toggle_index + 1)
    if toggle_end == -1:
        toggle_end = len(text)

    old_switch_return = '''        if label.isEmpty {
            gtkApplyEnabledState(to: sw)
            return opaqueFromWidget(sw)
        }

'''
    new_switch_return = '''        gtkApplyEnabledState(to: sw)
        if let paintedToggle = quill_gtk_toggle_paint_hook?(
            OpaquePointer(sw),
            isOn.wrappedValue,
            true,
            label
        ) {
            return paintedToggle
        }

        if label.isEmpty {
            return opaqueFromWidget(sw)
        }

'''
    return_index = text.find(old_switch_return, toggle_index, toggle_end)
    if return_index == -1:
        raise SystemExit("SwiftOpenUI Toggle switch return shape was not recognized")
    text = text[:return_index] + new_switch_return + text[return_index + len(old_switch_return):]

if "remainingTotalTicks: Int" not in text:
    old_scroll_retry_context = '''private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let anchor: UnitPoint?
    var remainingTicks: Int

    init(target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?, remainingTicks: Int = 180) {
        self.target = target
        self.anchor = anchor
        self.remainingTicks = remainingTicks
    }
}
'''
    new_scroll_retry_context = '''private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let anchor: UnitPoint?
    var remainingTicks: Int
    var remainingTotalTicks: Int

    init(target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?, remainingTicks: Int = 180, remainingTotalTicks: Int = 600) {
        self.target = target
        self.anchor = anchor
        self.remainingTicks = remainingTicks
        self.remainingTotalTicks = remainingTotalTicks
    }
}
'''
    if old_scroll_retry_context not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader retry context shape was not recognized")
    text = text.replace(old_scroll_retry_context, new_scroll_retry_context, 1)

if "@discardableResult\nprivate func gtkApplyScrollTo" not in text:
    old_apply_signature = '''private func gtkApplyScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
'''
    new_apply_signature = '''@discardableResult
private func gtkApplyScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) -> Bool {
    guard gtk_swift_is_widget(target) != 0 else { return false }
'''
    if old_apply_signature not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader apply result signature shape was not recognized")
    text = text.replace(old_apply_signature, new_apply_signature, 1)
    if "if applied { return }" in text:
        text = text.replace("            if applied { return }\n", "            if applied { return true }\n", 1)
    else:
        raise SystemExit("SwiftOpenUI ScrollViewReader apply result return shape was not recognized")
    old_apply_footer = '''        parent = gtk_widget_get_parent(scrolled)
    }
}

private func gtkScheduleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
'''
    new_apply_footer = '''        parent = gtk_widget_get_parent(scrolled)
    }
    return false
}

private func gtkScheduleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
'''
    if old_apply_footer not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader apply result footer shape was not recognized")
    text = text.replace(old_apply_footer, new_apply_footer, 1)

if (
    "let applied = gtkApplyScrollTo(context.target, anchor: context.anchor)" not in text
    and "let applied = gtkApplyScrollTo(target, anchor: context.anchor)" not in text
):
    old_scroll_retry_tick = '''        gtkApplyScrollTo(context.target, anchor: context.anchor)
        context.remainingTicks -= 1
        if context.remainingTicks > 0 { return 1 }
'''
    new_scroll_retry_tick = '''        let applied = gtkApplyScrollTo(context.target, anchor: context.anchor)
        if applied {
            context.remainingTicks -= 1
        }
        context.remainingTotalTicks -= 1
        if context.remainingTicks > 0 && context.remainingTotalTicks > 0 { return 1 }
'''
    if old_scroll_retry_tick not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader retry tick shape was not recognized")
    text = text.replace(old_scroll_retry_tick, new_scroll_retry_tick, 1)

if "let requiresVerticalAnchor = anchorPoint.y > 0.0" not in text:
    old_scroll_axis_success = '''            let anchorPoint = anchor ?? .top
            var applied = false
            if let vadjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(vadjustment)
                let upper = gtk_adjustment_get_upper(vadjustment)
                let pageSize = gtk_adjustment_get_page_size(vadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(vadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                    if anchorPoint.y >= 1.0 {
                        gtk_adjustment_set_value(vadjustment, maxValue)
                    } else {
                        let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                        gtk_adjustment_set_value(
                            vadjustment,
                            gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                        )
                    }
                    applied = true
                }
            }

            if let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(hadjustment)
                let upper = gtk_adjustment_get_upper(hadjustment)
                let pageSize = gtk_adjustment_get_page_size(hadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(hadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetWidth = max(1.0, Double(gtk_widget_get_width(target)))
                    let desired = currentValue + targetX - ((pageSize - targetWidth) * anchorPoint.x)
                    gtk_adjustment_set_value(
                        hadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                    applied = true
                }
            }
            if applied { return true }
'''
    new_scroll_axis_success = '''            let anchorPoint = anchor ?? .top
            let requiresVerticalAnchor = anchorPoint.y > 0.0
            var verticalApplied = false
            var horizontalApplied = false
            if let vadjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(vadjustment)
                let upper = gtk_adjustment_get_upper(vadjustment)
                let pageSize = gtk_adjustment_get_page_size(vadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(vadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetHeight = max(1.0, Double(gtk_widget_get_height(target)))
                    if anchorPoint.y >= 1.0 {
                        gtk_adjustment_set_value(vadjustment, maxValue)
                    } else {
                        let desired = currentValue + targetY - ((pageSize - targetHeight) * anchorPoint.y)
                        gtk_adjustment_set_value(
                            vadjustment,
                            gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                        )
                    }
                    verticalApplied = true
                }
            }

            if let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
                let lower = gtk_adjustment_get_lower(hadjustment)
                let upper = gtk_adjustment_get_upper(hadjustment)
                let pageSize = gtk_adjustment_get_page_size(hadjustment)
                if upper - lower > pageSize + 1.0 {
                    let currentValue = gtk_adjustment_get_value(hadjustment)
                    let maxValue = max(lower, upper - pageSize)
                    let targetWidth = max(1.0, Double(gtk_widget_get_width(target)))
                    let desired = currentValue + targetX - ((pageSize - targetWidth) * anchorPoint.x)
                    gtk_adjustment_set_value(
                        hadjustment,
                        gtkClampScrollValue(desired, lower: lower, upper: maxValue)
                    )
                    horizontalApplied = true
                }
            }
            if requiresVerticalAnchor {
                if verticalApplied { return true }
            } else if verticalApplied || horizontalApplied {
                return true
            }
'''
    if old_scroll_axis_success not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader axis-specific success shape was not recognized")
    text = text.replace(old_scroll_axis_success, new_scroll_axis_success, 1)

if "let targetID: AnyHashable?" not in text:
    old_scroll_id_context = '''private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let anchor: UnitPoint?
    var remainingTicks: Int
    var remainingTotalTicks: Int

    init(target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?, remainingTicks: Int = 180, remainingTotalTicks: Int = 600) {
        self.target = target
        self.anchor = anchor
        self.remainingTicks = remainingTicks
        self.remainingTotalTicks = remainingTotalTicks
    }
}
'''
    new_scroll_id_context = '''private final class GTKScrollToContext {
    let target: UnsafeMutablePointer<GtkWidget>
    let targetID: AnyHashable?
    let anchor: UnitPoint?
    var remainingTicks: Int
    var remainingTotalTicks: Int

    init(target: UnsafeMutablePointer<GtkWidget>, targetID: AnyHashable? = nil, anchor: UnitPoint?, remainingTicks: Int = 180, remainingTotalTicks: Int = 600) {
        self.target = target
        self.targetID = targetID
        self.anchor = anchor
        self.remainingTicks = remainingTicks
        self.remainingTotalTicks = remainingTotalTicks
    }
}
'''
    if old_scroll_id_context not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader ID-refresh context shape was not recognized")
    text = text.replace(old_scroll_id_context, new_scroll_id_context, 1)

if "private func gtkScheduleScrollTo(id: AnyHashable? = nil, _ target" not in text:
    text = text.replace(
        '''private func gtkScheduleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
''',
        '''private func gtkScheduleScrollTo(id: AnyHashable? = nil, _ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, targetID: id, anchor: anchor)
''',
        1,
    )
    text = text.replace(
        '''        guard gtk_swift_is_widget(context.target) != 0 else {
            g_object_unref(gpointer(context.target))
            unmanaged.release()
            return 0
        }
        let applied = gtkApplyScrollTo(context.target, anchor: context.anchor)
''',
        '''        let target = context.targetID.flatMap { gtkScrollTargetRegistry[$0] } ?? context.target
        guard gtk_swift_is_widget(target) != 0 else {
            g_object_unref(gpointer(context.target))
            unmanaged.release()
            return 0
        }
        let applied = gtkApplyScrollTo(target, anchor: context.anchor)
''',
        1,
    )
elif "context.targetID.flatMap { gtkScrollTargetRegistry[$0] } ?? context.target" not in text:
    raise SystemExit("SwiftOpenUI ScrollViewReader ID-refresh retry shape was not recognized")

if "private func gtkScheduleIdleScrollTo(id: AnyHashable? = nil, _ target" not in text:
    text = text.replace(
        '''private func gtkScheduleIdleScrollTo(_ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, anchor: anchor)
''',
        '''private func gtkScheduleIdleScrollTo(id: AnyHashable? = nil, _ target: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    guard gtk_swift_is_widget(target) != 0 else { return }
    g_object_ref(gpointer(target))
    let context = GTKScrollToContext(target: target, targetID: id, anchor: anchor)
''',
        1,
    )
    text = text.replace(
        '''        guard gtk_swift_is_widget(context.target) != 0 else { return 0 }
        gtkApplyOrScheduleScrollTo(context.target, anchor: context.anchor)
''',
        '''        let target = context.targetID.flatMap { gtkScrollTargetRegistry[$0] } ?? context.target
        guard gtk_swift_is_widget(target) != 0 else { return 0 }
        gtkApplyOrScheduleScrollTo(id: context.targetID, target, anchor: context.anchor)
''',
        1,
    )
elif "gtkApplyOrScheduleScrollTo(id: context.targetID, target, anchor: context.anchor)" not in text:
    raise SystemExit("SwiftOpenUI ScrollViewReader ID-refresh idle shape was not recognized")

if "private func gtkApplyOrScheduleScrollTo(id: AnyHashable? = nil, _ widget" not in text:
    text = text.replace(
        '''private func gtkApplyOrScheduleScrollTo(_ widget: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    gtkApplyScrollTo(widget, anchor: anchor)
    gtkScheduleScrollTo(widget, anchor: anchor)
}
''',
        '''private func gtkApplyOrScheduleScrollTo(id: AnyHashable? = nil, _ widget: UnsafeMutablePointer<GtkWidget>, anchor: UnitPoint?) {
    gtkApplyScrollTo(widget, anchor: anchor)
    gtkScheduleScrollTo(id: id, widget, anchor: anchor)
}
''',
        1,
    )
elif "gtkScheduleScrollTo(id: id, widget, anchor: anchor)" not in text:
    raise SystemExit("SwiftOpenUI ScrollViewReader ID-refresh schedule shape was not recognized")

text = text.replace(
    "gtkScheduleIdleScrollTo(widget, anchor: request.anchor)",
    "gtkScheduleIdleScrollTo(id: id, widget, anchor: request.anchor)",
)

if "gtkRegisterScrollTarget(id: AnyHashable(id), widget: wrapper)" not in text:
    old_id_view_scroll_target = '''extension IdView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        gtkRegisterScrollTarget(id: AnyHashable(id), widget: widget)
        return opaqueFromWidget(widget)
    }
}
'''
    new_id_view_scroll_target = '''extension IdView: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let widget = widgetFromOpaque(gtkRenderView(content))
        let wrapper = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_box_append(boxPointer(wrapper), widget)
        gtkPropagateSingleChildLayoutMarkers(from: [widget], to: wrapper)
        if gtk_widget_get_hexpand(widget) != 0 {
            gtk_widget_set_hexpand(wrapper, 1)
            gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        }
        if gtk_widget_get_vexpand(widget) != 0 {
            gtk_widget_set_vexpand(wrapper, 1)
            gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
        }
        gtkRegisterScrollTarget(id: AnyHashable(id), widget: wrapper)
        return opaqueFromWidget(wrapper)
    }
}
'''
    if old_id_view_scroll_target not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader ID target wrapper shape was not recognized")
    text = text.replace(old_id_view_scroll_target, new_id_view_scroll_target, 1)

if "gtkSwiftVerticalScrollViewMarker" not in text:
    if 'let gtkSwiftLayoutHelperMarker = "gtk-swift-layout-helper"\n' in text:
        scroll_marker_constants = '''let gtkSwiftLayoutHelperMarker = "gtk-swift-layout-helper"
'''
        scroll_marker_replacement = '''let gtkSwiftLayoutHelperMarker = "gtk-swift-layout-helper"
/// Marker string for SwiftUI ScrollView widgets that should receive
/// ScrollViewReader target adjustments.
let gtkSwiftScrollViewMarker = "gtk-swift-scroll-view"
/// Marker string for vertical SwiftUI ScrollViews.
let gtkSwiftVerticalScrollViewMarker = "gtk-swift-vertical-scroll-view"
'''
        text = text.replace(scroll_marker_constants, scroll_marker_replacement, 1)
    elif 'let gtkSwiftDividerMarker = "gtk-swift-divider"\n' in text:
        scroll_marker_constants = '''let gtkSwiftDividerMarker = "gtk-swift-divider"
'''
        scroll_marker_replacement = '''let gtkSwiftDividerMarker = "gtk-swift-divider"
let gtkSwiftScrollViewMarker = "gtk-swift-scroll-view"
let gtkSwiftVerticalScrollViewMarker = "gtk-swift-vertical-scroll-view"
'''
        text = text.replace(scroll_marker_constants, scroll_marker_replacement, 1)
    else:
        raise SystemExit("SwiftOpenUI ScrollViewReader scroll-view marker constant shape was not recognized")

    scroll_marker_helper_anchor = '''private func gtkSetLayoutMarker(_ widget: UnsafeMutablePointer<GtkWidget>, key: String) {
    let gobject = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    g_object_set_data(gobject, key, UnsafeMutableRawPointer(bitPattern: 1))
}

'''
    scroll_marker_helper = '''private func gtkMarkSwiftUIScrollView(
    _ widget: UnsafeMutablePointer<GtkWidget>,
    hasVerticalAxis: Bool
) {
    gtkSetLayoutMarker(widget, key: gtkSwiftScrollViewMarker)
    if hasVerticalAxis {
        gtkSetLayoutMarker(widget, key: gtkSwiftVerticalScrollViewMarker)
    }
}

private func gtkIsSwiftUIVerticalScrollView(_ widget: UnsafeMutablePointer<GtkWidget>) -> Bool {
    gtkHasLayoutMarker(widget, key: gtkSwiftVerticalScrollViewMarker)
}

'''
    if scroll_marker_helper_anchor not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader scroll-view marker helper shape was not recognized")
    text = text.replace(scroll_marker_helper_anchor, scroll_marker_helper_anchor + scroll_marker_helper, 1)

if "gtkMarkSwiftUIScrollView(scrolled, hasVerticalAxis: axes.contains(.vertical))" not in text:
    scroll_view_create_anchor = '''        let scrolled = gtk_scrolled_window_new()!
        let scrolledOp = OpaquePointer(scrolled)
'''
    scroll_view_create_replacement = '''        let scrolled = gtk_scrolled_window_new()!
        gtkMarkSwiftUIScrollView(scrolled, hasVerticalAxis: axes.contains(.vertical))
        let scrolledOp = OpaquePointer(scrolled)
'''
    if scroll_view_create_anchor not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader scroll-view marker install shape was not recognized")
    text = text.replace(scroll_view_create_anchor, scroll_view_create_replacement, 1)

if "var fallbackVerticalApplied = false" not in text:
    old_apply_parent = '''    var parent = gtk_widget_get_parent(target)
    while let scrolled = parent {
'''
    new_apply_parent = '''    var fallbackVerticalApplied = false
    var parent = gtk_widget_get_parent(target)
    while let scrolled = parent {
'''
    if old_apply_parent not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader fallback scroll parent shape was not recognized")
    text = text.replace(old_apply_parent, new_apply_parent, 1)

    old_apply_coordinates = '''            var targetX = 0.0
            var targetY = 0.0
            guard gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0 else {
                parent = gtk_widget_get_parent(scrolled)
                continue
            }

            let anchorPoint = anchor ?? .top
            let requiresVerticalAnchor = anchorPoint.y > 0.0
'''
    new_apply_coordinates = '''            let anchorPoint = anchor ?? .top
            let requiresVerticalAnchor = anchorPoint.y > 0.0
            let isSwiftUIVerticalScrollView = gtkIsSwiftUIVerticalScrollView(scrolled)
            var targetX = 0.0
            var targetY = 0.0
            let hasTargetCoordinates = gtk_widget_translate_coordinates(target, scrolled, 0, 0, &targetX, &targetY) != 0
            if !hasTargetCoordinates && anchorPoint.y < 1.0 {
                parent = gtk_widget_get_parent(scrolled)
                continue
            }

'''
    if old_apply_coordinates not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader fallback scroll coordinate shape was not recognized")
    text = text.replace(old_apply_coordinates, new_apply_coordinates, 1)

    old_apply_horizontal = '''            if let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
'''
    new_apply_horizontal = '''            if hasTargetCoordinates,
               !isSwiftUIVerticalScrollView,
               let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
'''
    if old_apply_horizontal not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader fallback scroll horizontal shape was not recognized")
    text = text.replace(old_apply_horizontal, new_apply_horizontal, 1)

    old_apply_return = '''            if requiresVerticalAnchor {
                if verticalApplied { return true }
            } else if verticalApplied || horizontalApplied {
                return true
            }
'''
    new_apply_return = '''            if requiresVerticalAnchor {
                if verticalApplied && isSwiftUIVerticalScrollView { return true }
                if verticalApplied { fallbackVerticalApplied = true }
            } else if verticalApplied || horizontalApplied {
                return true
            }
'''
    if old_apply_return not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader fallback scroll return shape was not recognized")
    text = text.replace(old_apply_return, new_apply_return, 1)

    old_apply_footer = '''    }
    return false
}
'''
    new_apply_footer = '''    }
    return fallbackVerticalApplied
}
'''
    if old_apply_footer not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader fallback scroll footer shape was not recognized")
    text = text.replace(old_apply_footer, new_apply_footer, 1)
elif "isSwiftUIVerticalScrollView" not in text or "return fallbackVerticalApplied" not in text:
    raise SystemExit("SwiftOpenUI ScrollViewReader fallback scroll shape was not recognized")

if "gtk_swift_attach_context_popover(widget, popover)" not in text:
    old_context_popover = '''        let popover = gtk_swift_popover_menu_new_from_model(menuModel)!
        gtk_widget_set_parent(popover, widget)

        // Attach action group to the content widget so menu items can resolve actions
        gtk_swift_widget_insert_action_group(widget, "menu", gpointer(actionGroup))
'''
    new_context_popover = '''        let popover = gtk_swift_popover_menu_new_from_model(menuModel)!
        gtk_swift_attach_context_popover(widget, popover)

        // Attach action group to the content widget so menu items can resolve actions
        gtk_swift_widget_insert_action_group(widget, "menu", gpointer(actionGroup))
        g_object_unref(gpointer(actionGroup))
        g_object_unref(menuModel)
'''
    if old_context_popover not in text:
        raise SystemExit("SwiftOpenUI GTK context-menu popover ownership shape was not recognized")
    text = text.replace(old_context_popover, new_context_popover, 1)
elif "g_object_unref(gpointer(actionGroup))" not in text or "g_object_unref(menuModel)" not in text:
    raise SystemExit("SwiftOpenUI GTK context-menu GObject ownership shape was not recognized")

if "!isSwiftUIVerticalScrollView,\n               let hadjustment = gtk_scrolled_window_get_hadjustment" not in text:
    old_vertical_scroll_horizontal_guard = '''            if hasTargetCoordinates, let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
'''
    new_vertical_scroll_horizontal_guard = '''            if hasTargetCoordinates,
               !isSwiftUIVerticalScrollView,
               let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
'''
    if old_vertical_scroll_horizontal_guard not in text:
        raise SystemExit("SwiftOpenUI ScrollViewReader vertical horizontal guard shape was not recognized")
    text = text.replace(old_vertical_scroll_horizontal_guard, new_vertical_scroll_horizontal_guard, 1)

if text != original:
    path.write_text(text)
PY
