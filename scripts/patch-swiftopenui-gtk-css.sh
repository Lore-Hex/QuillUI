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
TOOLBAR_MODIFIER="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Modifiers/ToolbarModifier.swift"
LAYOUT="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Layout/Layout.swift"
STATE="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/State/State.swift"
CONTROL_STYLE_MODIFIERS="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Modifiers/ControlStyleModifiers.swift"
SYMBOLS="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUISymbols/SFSymbolCompatibility.swift"
SCROLL_VIEW_READER="$SWIFTOPENUI_ROOT/Sources/SwiftOpenUI/Views/ScrollViewReader.swift"
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

if [[ ! -f "$TOOLBAR_MODIFIER" ]]; then
  echo "SwiftOpenUI toolbar modifier was not found at $TOOLBAR_MODIFIER" >&2
  exit 1
fi

if [[ ! -f "$LAYOUT" ]]; then
  echo "SwiftOpenUI layout helpers were not found at $LAYOUT" >&2
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

chmod u+w "$SWIFTOPENUI_MANIFEST" "$RENDERER" "$DESCRIPTOR_TREE" "$GTK_BACKEND" "$GTK_VIEW_HOST" "$NAVIGATION" "$TOOLBAR_MODIFIER" "$LAYOUT" "$SYMBOLS" "$SCROLL_VIEW_READER"
if [[ -f "$GTK_SHIM" ]]; then
  chmod u+w "$GTK_SHIM"
fi
if [[ -f "$STATE" ]]; then
  chmod u+w "$STATE"
fi
if [[ -f "$CONTROL_STYLE_MODIFIERS" ]]; then
  chmod u+w "$CONTROL_STYLE_MODIFIERS"
fi

python3 - "$SWIFTOPENUI_MANIFEST" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

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

text = text.replace('        pkgConfig: "gtk4",\n', "")

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
    raise SystemExit("SwiftOpenUI manifest still declares direct gtk4 pkgConfig")
if text.count(".unsafeFlags(swiftOpenUIGTKSwiftImporterFlags)") < 4:
    raise SystemExit("SwiftOpenUI manifest GTK importer flag patch did not apply")
if ".unsafeFlags(swiftOpenUIGTKLinkerFlags)" not in text:
    raise SystemExit("SwiftOpenUI manifest GTK linker flag patch did not apply")

path.write_text(text)
PY

if [[ -f "$CONTROL_STYLE_MODIFIERS" ]]; then
  python3 - "$CONTROL_STYLE_MODIFIERS" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
needle = """    /// Filled/prominent background.
    case borderedProminent
"""
replacement = """    /// Filled/prominent background.
    case borderedProminent
    /// QuillPaint macOS default button chrome.
    case quillPaintMacDefault
    /// QuillPaint macOS bordered button chrome.
    case quillPaintMacBordered
"""
if "case quillPaintMacDefault" not in text:
    if needle not in text:
        raise SystemExit("SwiftOpenUI ButtonStyleType shape was not recognized")
    text = text.replace(needle, replacement, 1)
path.write_text(text)
PY
fi

if [[ -f "$GTK_SHIM" ]]; then
  python3 - "$GTK_SHIM" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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
path.write_text(text)
PY
fi

python3 - "$SCROLL_VIEW_READER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

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

path.write_text(text)
PY

if [[ -f "$SWIFT_DEPENDENCIES_MAIN_QUEUE" ]]; then
  chmod u+w "$SWIFT_DEPENDENCIES_MAIN_QUEUE"
  python3 - "$SWIFT_DEPENDENCIES_MAIN_QUEUE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
needle = "  import Foundation\n"
insert = """  import Foundation
  #if canImport(OpenCombineDispatch)
    import OpenCombineDispatch
  #endif
"""
if "import OpenCombineDispatch" not in text:
    text = text.replace(needle, insert, 1)
path.write_text(text)
PY
fi

if [[ -f "$SWIFT_DEPENDENCIES_MAIN_RUN_LOOP" ]]; then
  chmod u+w "$SWIFT_DEPENDENCIES_MAIN_RUN_LOOP"
  python3 - "$SWIFT_DEPENDENCIES_MAIN_RUN_LOOP" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
needle = "  import Foundation\n"
insert = """  import Foundation
  #if canImport(OpenCombineFoundation)
    import OpenCombineFoundation
  #endif
"""
if "import OpenCombineFoundation" not in text:
    text = text.replace(needle, insert, 1)
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
text = path.read_text()
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
path.write_text(text)
PY
fi

if [[ -f "$SWIFT_SHARING_APP_STORAGE_KEY" ]]; then
  chmod u+w "$SWIFT_SHARING_APP_STORAGE_KEY"
  python3 - "$SWIFT_SHARING_APP_STORAGE_KEY" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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
path.write_text(text)
PY
fi

if [[ -f "$SWIFT_SHARING_FILE_STORAGE_KEY" ]]; then
  chmod u+w "$SWIFT_SHARING_FILE_STORAGE_KEY"
  python3 - "$SWIFT_SHARING_FILE_STORAGE_KEY" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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

if [[ -d "$GRDB_SOURCE_DIR" ]]; then
  python3 - "$GRDB_SOURCE_DIR" <<'PY'
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
fi

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
text = path.read_text()
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
path.write_text(text)
PY
fi

perl -0pi \
  -e 's/css \+= " object-fit: contain;"/css += ""/g;' \
  -e 's/css \+= " object-fit: cover; overflow: hidden;"/css += " overflow: hidden;"/g;' \
  "$RENDERER"

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    'applyCSSToWidget(entry, properties: "border: none; outline: none; box-shadow: none;")',
    'applyCSSToWidget(entry, properties: "background: transparent; background-color: transparent; border: none; outline: none; box-shadow: none; padding: 0;")',
)

state_identity = '''// MARK: - Stateful view identity

private var gtkStateCache: [String: [AnyStateStorage]] = [:]
private var gtkStateTypeCounters: [String: [String: Int]] = [:]

private var gtkForcedStateIdentityNamespace: String?

private func gtkStateIdentityNamespace() -> String {
    GTKViewHost.getCurrentRebuilding()?.stateIdentityNamespace
        ?? gtkForcedStateIdentityNamespace
        ?? "root"
}

func gtkBeginStateIdentityPass() {
    gtkStateTypeCounters[gtkStateIdentityNamespace()] = [:]
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

/// Runs a deferred render under a captured namespace, starting a fresh
/// counter pass for it so keys inside the subtree are stable per render.
func gtkWithForcedStateIdentityNamespace<T>(_ namespace: String, _ body: () -> T) -> T {
    let previous = gtkForcedStateIdentityNamespace
    gtkForcedStateIdentityNamespace = namespace
    gtkStateTypeCounters[namespace] = [:]
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

    init(widget: UnsafeMutablePointer<GtkWidget>, box: GTKButtonActionBox) {
        self.widget = widget
        self.box = box
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
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
    context.root = root
    context.controller = controller
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
            guard gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0 else { return 0 }
            gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("root-legacy@\\(Int(x)),\\(Int(y))", widget: context.widget))
            return 0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
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

    init(widget: UnsafeMutablePointer<GtkWidget>, box: GTKButtonActionBox) {
        self.widget = widget
        self.box = box
    }

    func removeController() {
        guard let root, let controller else { return }
        gtk_swift_remove_event_controller(root, controller)
        self.root = nil
        self.controller = nil
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

if "private func gtkInstallButtonRootEventFallback" not in text:
    root_install_helper = '''private func gtkInstallButtonRootEventFallback(_ context: GTKButtonRootEventContext) {
    guard context.controller == nil else { return }
    guard let root = gtk_swift_widget_root_widget(context.widget) else { return }

    let controller = gtk_swift_legacy_capture_controller()!
    context.root = root
    context.controller = controller
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
            guard gtk_swift_widget_is_topmost_at_root_point(root, context.widget, x, y) != 0 else { return 0 }
            gtkScheduleButtonAction(context.box, source: gtkButtonDebugSource("root-legacy@\\(Int(x)),\\(Int(y))", widget: context.widget))
            return 0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> gboolean, to: GCallback.self),
        contextPointer,
        nil,
        GConnectFlags(rawValue: 0)
    )
    gtk_swift_add_event_controller(root, controller)
}

'''
    button_marker = "extension Button: GTKRenderable"
    if button_marker not in text:
        raise SystemExit("SwiftOpenUI Button renderer marker was not recognized")
    text = text.replace(button_marker, root_install_helper + button_marker, 1)

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
        let buttonActionBox = Unmanaged.passRetained(GTKButtonActionBox(boundAction)).toOpaque()
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
    root_context_activation = '''        let buttonActionBox = Unmanaged.passRetained(GTKButtonActionBox(boundAction)).toOpaque()
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

if 'gtkScheduleButtonAction(box, source: "legacy")' not in text:
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
    new_parent_flexible_request = '''        let requestWidth = widthMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.width)
        let requestHeight = heightMayGrowWithParent ? -1 : gtkPixelSize(layout.containerSize.height)
        if widthMayGrowWithParent && !heightMayGrowWithParent && childExpV {
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

sheet_overlay_helpers = '''private func gtkSheetPresentationMode() -> String {
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

// Presented root-overlay sheet panels, keyed by the type-derived activeKey.
// Anchors (GTKViewHost containers) are recreated on every parent render, so
// per-anchor g_object data is lost after the first rebuild — a panel tracked
// there could never be dismissed (or deduplicated) again. The activeKey is
// stable across hosts, so a global registry survives parent rebuilds.
private var gtkRootSheetPanels: [String: UnsafeMutablePointer<GtkWidget>] = [:]
private var gtkRootSheetItemIDs: [String: Int] = [:]

private func gtkCurrentRootSheetOverlay() -> OpaquePointer? {
    gtkRootSheetOverlayStack.last
}

private func gtkWithRootSheetOverlay<T>(_ rootOverlay: OpaquePointer, _ body: () -> T) -> T {
    gtkRootSheetOverlayStack.append(rootOverlay)
    defer { _ = gtkRootSheetOverlayStack.popLast() }
    return body()
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
    guard let panel = gtkRootSheetPanels.removeValue(forKey: activeKey) else {
        return
    }
    gtkRootSheetItemIDs[activeKey] = nil
    gtkDebugLog("sheet root dismiss activeKey=\\(activeKey)")
    gtk_widget_unparent(panel)
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
    gtk_widget_set_size_request(panel, gtkSheetDefaultWidth(), gtkSheetDefaultHeight())
    gtk_widget_set_halign(panel, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(panel, GTK_ALIGN_CENTER)
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

private func gtkAttachRootSheetOverlay(
    _ panel: UnsafeMutablePointer<GtkWidget>,
    to rootOverlay: OpaquePointer
) {
    let overlayWidget = UnsafeMutableRawPointer(rootOverlay).assumingMemoryBound(to: GtkWidget.self)
    let previousTop = gtk_widget_get_last_child(overlayWidget)
    gtk_overlay_add_overlay(rootOverlay, panel)
    if let previousTop, previousTop != panel {
        gtk_widget_insert_after(panel, overlayWidget, previousTop)
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
    guard let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) else {
        return
    }
    gtkScheduleSheetEditableFocus(editable)
}

private func gtkFocusSheetEditableWidget(_ widget: UnsafeMutablePointer<GtkWidget>) {
    guard gtk_swift_is_widget(widget) != 0 else { return }
    gtk_widget_set_can_target(widget, 1)
    gtk_widget_set_focusable(widget, 1)
    let grabbed = gtk_swift_root_grab_focus(widget)
    gtkDebugLog("sheet focus widget grab=\\(grabbed) target=\\(gtkButtonDebugSource("editable", widget: widget))")
    if let delegate = gtk_editable_get_delegate(OpaquePointer(widget)) {
        let delegateWidget = UnsafeMutableRawPointer(delegate).assumingMemoryBound(to: GtkWidget.self)
        gtk_widget_set_can_target(delegateWidget, 1)
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
    gtk_overlay_add_overlay(OpaquePointer(overlay), panel)
    return overlay
}

'''
if "private func gtkShouldRenderSheetInWindow" not in text:
    marker = "\nprivate func gtkSheetDataKey"
    if marker not in text:
        raise SystemExit("SwiftOpenUI sheet overlay helper insertion shape was not recognized")
    text = text.replace(marker, "\n" + sheet_overlay_helpers + "private func gtkSheetDataKey", 1)

text = text.replace(
    """    guard let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) else {
        return
    }
    gtkFocusSheetEditableWidget(editable)
}
""",
    """    guard let editable = gtkFindSheetEditable(in: panel, root: root, rootX: rootX, rootY: rootY) else {
        return
    }
    gtkScheduleSheetEditableFocus(editable)
}
""",
)

bool_sheet_overlay = '''        if gtkShouldRenderSheetInWindow() {
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
            guard gtkRootSheetPanels[activeKey] == nil else {
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
            gtkStoreRootPresentationOverlay(rootOverlay, on: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)
            gtkRootSheetPanels[activeKey] = panel
            gtkAttachRootSheetOverlay(panel, to: rootOverlay)
            return opaqueFromWidget(widget)
        }

'''
if "gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget)" not in text:
    bool_marker = "        // Guard against duplicate presentation on rebuild\n"
    if bool_marker not in text:
        raise SystemExit("SwiftOpenUI bool sheet overlay insertion shape was not recognized")
    text = text.replace(bool_marker, bool_sheet_overlay + bool_marker, 1)

item_sheet_overlay = '''        if gtkShouldRenderSheetInWindow() {
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
            if gtkRootSheetPanels[activeKey] != nil {
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
            gtkStoreRootPresentationOverlay(rootOverlay, on: panel)
            gtkStoreRootPresentationOverlay(rootOverlay, on: sheetWidget)
            gtkRootSheetPanels[activeKey] = panel
            gtkAttachRootSheetOverlay(panel, to: rootOverlay)
            return opaqueFromWidget(widget)
        }
        gtkDebugLog("sheet item root unavailable activeKey=\(activeKey)")

'''
if "let itemDismissalConfig = gtkExtractDismissalConfig(from: sheetBuilder(currentItem))" in text and text.count("gtkCreateSheetOverlay(contentWidget: widget, sheetWidget: sheetWidget)") < 2:
    item_marker = "        // Check if the item identity changed while a sheet is already active\n"
    if item_marker not in text:
        raise SystemExit("SwiftOpenUI item sheet overlay insertion shape was not recognized")
    text = text.replace(item_marker, item_sheet_overlay + item_marker, 1)

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
            gtk_widget_set_vexpand(child, 1)
            gtk_widget_set_valign(child, GTK_ALIGN_FILL)
        }
        gtk_scrolled_window_set_child(scrolledOp, child)
'''
if "SwiftUI lays vertical ScrollView content out in the viewport" not in text:
    if old_scroll not in text:
        raise SystemExit("SwiftOpenUI ScrollView child sizing shape was not recognized")
    text = text.replace(old_scroll, new_scroll, 1)

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
        gtk_widget_set_size_request(context.child, width, -1)
        gtk_widget_queue_resize(context.child)
    }
    if context.fillHeight, height > 1, height != context.lastHeight {
        context.lastHeight = height
        gtk_widget_set_size_request(context.child, -1, height)
        gtk_widget_queue_resize(context.child)
    }

    return 1
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
            fillHeight: axes.contains(.horizontal) && !axes.contains(.vertical)
        )
""",
        1,
    )

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
        gtkInstallScrollViewCrossAxisFill(on: scrolled, child: listBox, fillWidth: true, fillHeight: false)
        gtk_widget_set_vexpand(scrolled, 1)
"""
    if old_list_child not in text:
        raise SystemExit("SwiftOpenUI List cross-axis fill shape was not recognized")
    text = text.replace(old_list_child, new_list_child, 1)

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
        } else {
            gtkScheduleOnAppear(boundAction, on: widget)
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
        } else {
            gtkScheduleOnAppear(boundAction, on: widget)
        }
'''
    if current_on_appear_rebuild not in text:
        raise SystemExit("SwiftOpenUI OnAppear lifecycle rebuild shape was not recognized")
    text = text.replace(current_on_appear_rebuild, current_on_appear_scheduled, 1)

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

'''
if "gtkPropagateSingleChildLayoutMarkers" not in text:
    marker = "private func gtkVStackSpacing(_ spacing: Int) -> Int {\n"
    if marker not in text:
        raise SystemExit("SwiftOpenUI layout marker insertion point was not recognized")
    text = text.replace(marker, layout_marker_helper + marker, 1)

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
        for child in multi.children {
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
if "var renderedChildren: [UnsafeMutablePointer<GtkWidget>] = []\n        for child in multi.children" not in text:
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
        for child in multi.children {
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

path.write_text(text)
PY

python3 - "$DESCRIPTOR_TREE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

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
if "Reused buttons stay on the narrow path" not in text:
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
path.write_text(text)
PY

python3 - "$GTK_VIEW_HOST" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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
if "gtkBeginStateIdentityPass()" not in text:
    observation_old = """            withObservationTracking {
                result = buildBody()
            } onChange: { [weak self] in
"""
    observation_new = """            withObservationTracking {
                gtkBeginStateIdentityPass()
                result = buildBody()
            } onChange: { [weak self] in
"""
    fallback_old = """        let result = buildBody()
"""
    fallback_new = """        gtkBeginStateIdentityPass()
        let result = buildBody()
"""
    if observation_old not in text or fallback_old not in text:
        raise SystemExit("SwiftOpenUI GTKViewHost state identity pass shape was not recognized")
    text = text.replace(observation_old, observation_new, 1)
    text = text.replace(fallback_old, fallback_new, 1)
path.write_text(text)
PY

python3 - "$LAYOUT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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
path.write_text(text)
PY

python3 - "$GTK_BACKEND" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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

            let instance = A()
            gtkRenderScene(instance.body, app: appPtr)
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
path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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
path.write_text(text)
PY

python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

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
path.write_text(text)
PY

python3 - "$TOOLBAR_MODIFIER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

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

path.write_text(text)
PY

python3 - "$NAVIGATION" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
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

private func gtkConfigureFixedSplitColumn(_ widget: UnsafeMutablePointer<GtkWidget>, width: Double) {
    gtk_widget_set_size_request(widget, gint(width), gtkRequestedDefaultWindowHeight())
    gtk_widget_set_hexpand(widget, 0)
    gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
    gtk_widget_set_vexpand(widget, 1)
    gtk_widget_set_valign(widget, GTK_ALIGN_FILL)
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
    gtk_widget_set_size_request(sidebar, gint(sidebarW), gtkRequestedDefaultWindowHeight())
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
        let sidebarWidget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(sidebarContentWidget, 1)
        gtk_widget_set_halign(sidebarContentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_vexpand(sidebarContentWidget, 1)
        gtk_widget_set_valign(sidebarContentWidget, GTK_ALIGN_FILL)
        gtk_box_append(boxPointer(sidebarWidget), sidebarContentWidget)

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
        let sidebarWidget = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        gtk_widget_set_hexpand(sidebarContentWidget, 1)
        gtk_widget_set_halign(sidebarContentWidget, GTK_ALIGN_FILL)
        gtk_widget_set_vexpand(sidebarContentWidget, 1)
        gtk_widget_set_valign(sidebarContentWidget, GTK_ALIGN_FILL)
        gtk_box_append(boxPointer(sidebarWidget), sidebarContentWidget)

        let contentWidget = widgetFromOpaque(gtkRenderView(content))
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
text = text.replace("        gtkInstallToolbar(from: detail, on: paned)\n\n", "")
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
text = path.read_text()

required_symbols = [
    ("arrow.clockwise", "refresh", ["arrow.uturn.clockwise", "calendar"]),
    ("arrow.forward.circle.fill", "arrow_circle_right", ["pencil", "calendar"]),
    ("character.cursor.ibeam", "text_fields", ["calendar"]),
    ("checkmark.seal.fill", "verified", ["checkmark.circle.fill", "checkmark.square.fill", "calendar"]),
    ("chevron.down", "expand_more", ["chevron.right", "calendar"]),
    ("curlybraces", "code", ["chevron.down", "calendar"]),
    ("doc.on.doc", "content_copy", ["calendar"]),
    ("doc.text", "description", ["doc.on.doc", "calendar"]),
    ("folder", "folder", ["calendar"]),
    ("folder.badge.plus", "create_new_folder", ["folder", "calendar"]),
    ("gearshape", "settings", ["calendar"]),
    ("gearshape.fill", "settings", ["gearshape", "calendar"]),
    ("info.circle", "info", ["gearshape.fill", "calendar"]),
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
path.write_text(text)
PY

# Apply QuillPaint integration to GTKRenderer.
python3 - "$RENDERER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()

hook_decl = (
    "public var quill_gtk_button_paint_hook: ((OpaquePointer, OpaquePointer, Bool) -> Bool)? = nil\n"
    "public var quill_gtk_text_field_paint_hook: ((OpaquePointer, Bool) -> OpaquePointer?)? = nil\n"
    "public var quill_gtk_text_editor_paint_hook: ((OpaquePointer, OpaquePointer) -> OpaquePointer?)? = nil\n"
    "public var quill_gtk_toggle_paint_hook: ((OpaquePointer, Bool, Bool, String) -> OpaquePointer?)? = nil\n\n"
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
/// or eagerly before any button action runs (actions read the model, never
/// the entry). Same-field edits always keep a prefix relation between
/// successive values; unrelated values mean a different field, so the
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
/// or eagerly before any button action runs (actions read the model, never
/// the entry). Same-field edits always keep a prefix relation between
/// successive values; unrelated values mean a different field, so the
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
        default:
            handledByQuillPaint = false
        }

        if !handledByQuillPaint {
            let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
            gtk_button_set_child(btnPtr, childWidget)
            gtkDisableButtonChildTargeting(childWidget)
            if !(label is Text) {
                // Remove GTK default button border/padding so custom-styled
                // labels (with .background/.frame) render cleanly.
                applyCSSToWidget(button, properties: """
                    border: none;
                    outline: none;
                    padding: 0;
                    min-height: 0;
                    min-width: 0;
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
            case .automatic, .quillPaintMacDefault, .quillPaintMacBordered:
                break
            }
        }

        gtk_widget_set_hexpand(button, buttonWantsHExpand ? 1 : 0)
        gtk_widget_set_vexpand(button, buttonWantsVExpand ? 1 : 0)
        gtk_widget_set_halign(button, buttonWantsHExpand ? GTK_ALIGN_FILL : GTK_ALIGN_START)
        gtk_widget_set_valign(button, buttonWantsVExpand ? GTK_ALIGN_FILL : GTK_ALIGN_CENTER)

'''
    text = text[:start] + replacement + text[end:]

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
            let box = Unmanaged.passRetained(IntClosureBox { newIndex in
                guard options.indices.contains(newIndex), newIndex != clampedSelection else {
                    return
                }
                onChanged(newIndex)
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
    new_apply_horizontal = '''            if hasTargetCoordinates, let hadjustment = gtk_scrolled_window_get_hadjustment(OpaquePointer(scrolled)) {
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

path.write_text(text)
PY
