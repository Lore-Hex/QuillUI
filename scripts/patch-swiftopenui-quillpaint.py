import sys
from pathlib import Path


def patch_renderer(renderer_path: str) -> None:
    path = Path(renderer_path)
    text = path.read_text()

    hook_decl = "public var quill_gtk_button_paint_hook: ((OpaquePointer, OpaquePointer, Bool) -> Bool)? = nil\n\n"
    if "quill_gtk_button_paint_hook" not in text:
        marker = "// MARK: - GTK rendering protocol\n"
        if marker not in text:
            raise SystemExit("SwiftOpenUI GTK rendering protocol marker was not recognized")
        text = text.replace(marker, hook_decl + marker, 1)

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
            if !(label is Text) {
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
                applyCSSToWidget(button, properties: """
                    border: none; background: none; padding: 0;
                    min-height: 0; min-width: 0;
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

    path.write_text(text)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: patch-swiftopenui-quillpaint.py <renderer_path>")
        sys.exit(1)
    patch_renderer(sys.argv[1])
