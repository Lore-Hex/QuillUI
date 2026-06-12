// QtOffscreenRender.swift — test helper for rendering a SwiftUI-shaped view
// through the generic Qt renderer into PNG bytes.

#if canImport(CQtBridge)
import CQtBridge
import Foundation
import SwiftOpenUI

@MainActor
public func quillQtRenderViewToPNG<V: View>(
    _ view: V,
    width: Int,
    height: Int
) -> Data? {
    guard width > 0, height > 0 else { return nil }

    let app = qtOpaque(
        quill_qt_bridge_application_create(CommandLine.argc, CommandLine.unsafeArgv)
    )
    qtRegisterBundledIconFont()
    quill_qt_bridge_application_set_stylesheet(qtHandle(app), QtBaselineStyle.qss)

    qtBeginStateIdentityPass()
    let child = qtRenderView(view)
    let root = qtOpaque(quill_qt_bridge_container_create())
    quill_qt_bridge_widget_set_fixed_size(qtHandle(root), Int32(width), Int32(height))
    quill_qt_bridge_widget_add_child(qtHandle(root), qtHandle(child))
    quill_qt_bridge_widget_set_geometry(qtHandle(child), 0, 0, Int32(width), Int32(height))
    quill_qt_bridge_widget_show(qtHandle(root))

    let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("quill-qt-render-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: outputURL) }

    guard quill_qt_bridge_widget_grab_png(qtHandle(root), outputURL.path) != 0 else {
        quill_qt_bridge_widget_delete(qtHandle(root))
        return nil
    }

    let data = try? Data(contentsOf: outputURL)
    quill_qt_bridge_widget_delete(qtHandle(root))
    return data
}

#endif
