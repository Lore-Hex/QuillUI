import sys
from pathlib import Path


def patch_renderer(renderer_path: str) -> None:
    path = Path(renderer_path)
    text = path.read_text()

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

    text_field_index = text.find("extension TextField: GTKRenderable")
    if text_field_index == -1:
        raise SystemExit("SwiftOpenUI TextField GTKRenderable extension was not recognized")
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
                text = (
                    text[:body_index]
                    + "            useQuillPaintTextField = true\n"
                    + text[body_index + len(old_body):]
                )
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

    path.write_text(text)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: patch-swiftopenui-quillpaint.py <renderer_path>")
        sys.exit(1)
    patch_renderer(sys.argv[1])
