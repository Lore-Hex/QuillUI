#if os(Linux)
import CGTK
import Foundation
import SwiftOpenUI
import BackendGTK4

private final class QuillGTKToolbarClosureBox {
    let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }
}

private final class QuillGTKMenuActionBox {
    var actions: [QuillGTKToolbarClosureBox] = []
    var actionsByTitle: [String: QuillGTKToolbarClosureBox] = [:]
}

private final class QuillGTKToolbarAutomationBox {
    let commandDirectoryPath: String
    let actionBox: QuillGTKMenuActionBox

    init(commandDirectoryPath: String, actionBox: QuillGTKMenuActionBox) {
        self.commandDirectoryPath = commandDirectoryPath
        self.actionBox = actionBox
    }
}

private enum QuillGTKToolbarMenuAutomation {
    static let commandDirectoryEnvironmentKey = "QUILLUI_GTK_TOOLBAR_ACTION_COMMAND_DIR"

    static func installIfNeeded(actionBox: QuillGTKMenuActionBox) {
        guard let commandDirectoryPath = ProcessInfo.processInfo.environment[commandDirectoryEnvironmentKey],
              !commandDirectoryPath.isEmpty
        else {
            return
        }

        let automationBox = QuillGTKToolbarAutomationBox(
            commandDirectoryPath: commandDirectoryPath,
            actionBox: actionBox
        )
        let retained = Unmanaged.passRetained(automationBox).toOpaque()
        g_timeout_add(100, { userData -> gboolean in
            guard let userData else { return 1 }
            let automationBox = Unmanaged<QuillGTKToolbarAutomationBox>
                .fromOpaque(userData)
                .takeUnretainedValue()
            QuillGTKToolbarMenuAutomation.poll(automationBox)
            return 1
        }, retained)
    }

    private static func poll(_ automationBox: QuillGTKToolbarAutomationBox) {
        let directoryURL = URL(fileURLWithPath: automationBox.commandDirectoryPath)
        guard let commandURLs = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for commandURL in commandURLs {
            let resourceValues = try? commandURL.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues?.isDirectory != true,
                  let title = try? String(contentsOf: commandURL, encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                continue
            }

            if QuillChatCopy.performRememberedCommand(title) {
                try? FileManager.default.removeItem(at: commandURL)
                continue
            }

            if QuillChatCopy.isRememberedCommandTitle(title),
               shouldDeferRememberedCommand(commandURL)
            {
                continue
            }

            guard let action = automationBox.actionBox.actionsByTitle[title] else {
                continue
            }

            try? FileManager.default.removeItem(at: commandURL)
            action.closure()
        }
    }

    private static func shouldDeferRememberedCommand(_ commandURL: URL) -> Bool {
        let commandAge = (try? commandURL.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate)
            .map { Date().timeIntervalSince($0) } ?? 0
        return commandAge < 2
    }
}

struct QuillGTKToolbarIconButton: View, PrimitiveView, GTKRenderable {
    typealias Body = Never

    var systemImage: String
    var showsChevron: Bool
    var width: CGFloat
    var action: () -> Void

    var body: Never { fatalError("QuillGTKToolbarIconButton is a primitive view") }

    func gtkCreateWidget() -> OpaquePointer {
        let button = gtk_button_new()!
        gtk_widget_set_size_request(button, gint(Int(width)), 30)
        gtk_widget_set_halign(button, GTK_ALIGN_CENTER)
        gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(button, "flat")
        gtk_button_set_child(
            toolbarButtonPointer(button),
            makeToolbarGlyphChild(systemImage: systemImage, showsChevron: showsChevron)
        )
        applyToolbarControlCSS(to: button, className: "quill-toolbar-icon-button")
        connectToolbarButton(button, action: action)
        return OpaquePointer(button)
    }
}

struct QuillGTKToolbarMenuButton: View, PrimitiveView, GTKRenderable {
    typealias Body = Never

    var systemImage: String
    var showsChevron: Bool
    var width: CGFloat
    var actions: [QuillMenuAction]

    var body: Never { fatalError("QuillGTKToolbarMenuButton is a primitive view") }

    func gtkCreateWidget() -> OpaquePointer {
        let button = gtk_menu_button_new()!
        gtk_widget_set_size_request(button, gint(Int(width)), 30)
        gtk_widget_set_halign(button, GTK_ALIGN_CENTER)
        gtk_widget_set_valign(button, GTK_ALIGN_CENTER)
        gtk_widget_add_css_class(button, "flat")
        gtk_swift_menu_button_set_always_show_arrow(button, 0)
        gtk_swift_menu_button_set_child(button, makeToolbarGlyphChild(
            systemImage: systemImage,
            showsChevron: showsChevron
        ))
        applyToolbarControlCSS(to: button, className: "quill-toolbar-menu-button")

        let actionGroup = g_simple_action_group_new()!
        let menuModel = gtk_swift_menu_new()!
        let actionBox = QuillGTKMenuActionBox()
        var actionIndex = 0

        buildMenuModel(
            actions: actions,
            menu: menuModel,
            actionGroup: actionGroup,
            actionBox: actionBox,
            actionIndex: &actionIndex
        )

        let popover = gtk_swift_popover_menu_new_from_model(menuModel)!
        gtk_swift_menu_button_set_popover(button, popover)
        gtk_swift_widget_insert_action_group(button, "menu", gpointer(actionGroup))
        gtk_swift_widget_insert_action_group(popover, "menu", gpointer(actionGroup))

        let retained = Unmanaged.passRetained(actionBox).toOpaque()
        let gobject = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GObject.self)
        g_object_set_data_full(gobject, "quill-toolbar-menu-actions", retained) { userData in
            guard let userData else { return }
            Unmanaged<QuillGTKMenuActionBox>.fromOpaque(userData).release()
        }
        QuillGTKToolbarMenuAutomation.installIfNeeded(actionBox: actionBox)

        return OpaquePointer(button)
    }

    private func buildMenuModel(
        actions: [QuillMenuAction],
        menu: gpointer,
        actionGroup: UnsafeMutablePointer<GSimpleActionGroup>,
        actionBox: QuillGTKMenuActionBox,
        actionIndex: inout Int
    ) {
        var sections: [[QuillMenuAction]] = [[]]
        for action in actions {
            if case .divider = action.kind {
                sections.append([])
            } else {
                sections[sections.count - 1].append(action)
            }
        }

        if sections.count <= 1 {
            for action in actions {
                guard case .item = action.kind else { continue }
                addMenuAction(
                    action,
                    to: menu,
                    actionGroup: actionGroup,
                    actionBox: actionBox,
                    actionIndex: &actionIndex
                )
            }
        } else {
            for section in sections where !section.isEmpty {
                let sectionMenu = gtk_swift_menu_new()!
                for action in section {
                    addMenuAction(
                        action,
                        to: sectionMenu,
                        actionGroup: actionGroup,
                        actionBox: actionBox,
                        actionIndex: &actionIndex
                    )
                }
                gtk_swift_menu_append_section(menu, nil, sectionMenu)
            }
        }
    }

    private func addMenuAction(
        _ action: QuillMenuAction,
        to menu: gpointer,
        actionGroup: UnsafeMutablePointer<GSimpleActionGroup>,
        actionBox: QuillGTKMenuActionBox,
        actionIndex: inout Int
    ) {
        let actionName = "action\(actionIndex)"
        actionIndex += 1

        let gAction = g_simple_action_new(actionName, nil)!
        gtk_swift_action_set_enabled(gpointer(gAction), action.isDisabled ? 0 : 1)

        let box = QuillGTKToolbarClosureBox {
            action.perform()
        }
        actionBox.actions.append(box)
        actionBox.actionsByTitle[action.title] = box
        let boxPointer = Unmanaged.passUnretained(box).toOpaque()

        g_signal_connect_data(
            gpointer(gAction),
            "activate",
            unsafeBitCast({ (_: gpointer?, _: gpointer?, userData: gpointer?) in
                guard let userData else { return }
                Unmanaged<QuillGTKToolbarClosureBox>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .closure()
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
            boxPointer,
            nil,
            GConnectFlags(rawValue: 0)
        )

        gtk_swift_action_map_add_action(gpointer(actionGroup), gpointer(gAction))
        gtk_swift_menu_append(menu, action.title, "menu.\(actionName)")
    }
}

struct QuillGTKDesktopChatToolbar: View, PrimitiveView, GTKRenderable {
    typealias Body = Never

    var modelActions: [QuillMenuAction]
    var optionsActions: [QuillMenuAction]
    var onNewConversation: () -> Void

    var body: Never { fatalError("QuillGTKDesktopChatToolbar is a primitive view") }

    func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 14)!
        gtk_widget_set_size_request(box, -1, 32)
        gtk_widget_set_halign(box, GTK_ALIGN_END)
        gtk_widget_set_valign(box, GTK_ALIGN_CENTER)
        gtk_widget_set_hexpand(box, 0)
        gtk_widget_set_vexpand(box, 0)

        appendToolbarWidget(QuillGTKToolbarMenuButton(
            systemImage: "chevron.down",
            showsChevron: false,
            width: 30,
            actions: modelActions
        ).gtkCreateWidget(), to: box)
        appendToolbarWidget(QuillGTKToolbarMenuButton(
            systemImage: "ellipsis",
            showsChevron: true,
            width: 42,
            actions: optionsActions
        ).gtkCreateWidget(), to: box)
        appendToolbarWidget(QuillGTKToolbarIconButton(
            systemImage: "square.and.pencil",
            showsChevron: false,
            width: 30,
            action: onNewConversation
        ).gtkCreateWidget(), to: box)

        return OpaquePointer(box)
    }
}

private struct QuillGTKToolbarGlyph {
    var materialName: String
    var pointSize: Int
    var width: Int
}

private func makeToolbarGlyphChild(
    systemImage: String,
    showsChevron: Bool
) -> UnsafeMutablePointer<GtkWidget> {
    let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    gtk_widget_set_halign(box, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(box, GTK_ALIGN_CENTER)
    gtk_widget_add_css_class(box, "quill-toolbar-glyph-box")

    for glyph in toolbarGlyphs(systemImage: systemImage, showsChevron: showsChevron) {
        gtk_box_append(toolbarBoxPointer(box), makeToolbarGlyphLabel(glyph))
    }

    return box
}

private func toolbarGlyphs(
    systemImage: String,
    showsChevron: Bool
) -> [QuillGTKToolbarGlyph] {
    switch systemImage {
    case "arrow.clockwise":
        return [QuillGTKToolbarGlyph(materialName: "refresh", pointSize: 24, width: 24)]
    case "books.vertical":
        return [QuillGTKToolbarGlyph(materialName: "library_books", pointSize: 24, width: 25)]
    case "sparkles":
        return [QuillGTKToolbarGlyph(materialName: "auto_awesome", pointSize: 24, width: 25)]
    case "gearshape":
        return [QuillGTKToolbarGlyph(materialName: "settings", pointSize: 24, width: 24)]
    case "line.3.horizontal.decrease.circle":
        var glyphs = [QuillGTKToolbarGlyph(materialName: "filter_list", pointSize: 24, width: 24)]
        if showsChevron {
            glyphs.append(QuillGTKToolbarGlyph(materialName: "expand_more", pointSize: 16, width: 15))
        }
        return glyphs
    case "chevron.down":
        return [QuillGTKToolbarGlyph(materialName: "expand_more", pointSize: 20, width: 22)]
    case "ellipsis":
        var glyphs = [QuillGTKToolbarGlyph(materialName: "more_horiz", pointSize: 24, width: 24)]
        if showsChevron {
            glyphs.append(QuillGTKToolbarGlyph(materialName: "expand_more", pointSize: 16, width: 15))
        }
        return glyphs
    case "square.and.pencil":
        return [QuillGTKToolbarGlyph(materialName: "edit", pointSize: 26, width: 27)]
    default:
        return [QuillGTKToolbarGlyph(
            materialName: QuillSystemSymbol.compatibleName(systemImage),
            pointSize: 22,
            width: 24
        )]
    }
}

private func makeToolbarGlyphLabel(_ glyph: QuillGTKToolbarGlyph) -> UnsafeMutablePointer<GtkWidget> {
    let label = gtk_label_new(nil)!
    gtk_widget_set_size_request(label, gint(glyph.width), gint(glyph.pointSize + 2))
    gtk_widget_set_halign(label, GTK_ALIGN_CENTER)
    gtk_widget_set_valign(label, GTK_ALIGN_CENTER)
    gtk_widget_add_css_class(label, "quill-toolbar-symbol")
    gtk_swift_label_set_markup(label, toolbarGlyphMarkup(glyph))
    return label
}

private func toolbarGlyphMarkup(_ glyph: QuillGTKToolbarGlyph) -> String {
    let familyName = toolbarEscapeMarkup("Material Symbols Rounded")
    let materialName = toolbarEscapeMarkup(glyph.materialName)
    return """
    <span font_family="\(familyName)" font_size="\(glyph.pointSize * 1000)" foreground="#3A3A3C">\(materialName)</span>
    """
}

private func toolbarEscapeMarkup(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

private func toolbarButtonPointer(_ widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkButton> {
    UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkButton.self)
}

private func toolbarBoxPointer(_ widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkBox> {
    UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GtkBox.self)
}

private func appendToolbarWidget(_ child: OpaquePointer, to box: UnsafeMutablePointer<GtkWidget>) {
    gtk_box_append(toolbarBoxPointer(box), toolbarWidgetPointer(child))
}

private func toolbarWidgetPointer(_ pointer: OpaquePointer) -> UnsafeMutablePointer<GtkWidget> {
    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: GtkWidget.self)
}

private func connectToolbarButton(
    _ button: UnsafeMutablePointer<GtkWidget>,
    action: @escaping () -> Void
) {
    let box = Unmanaged.passRetained(QuillGTKToolbarClosureBox(action)).toOpaque()
    g_signal_connect_data(
        gpointer(button),
        "clicked",
        unsafeBitCast({ (_: gpointer?, userData: gpointer?) in
            guard let userData else { return }
            Unmanaged<QuillGTKToolbarClosureBox>.fromOpaque(userData)
                .takeUnretainedValue()
                .closure()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        box,
        { userData, _ in
            guard let userData else { return }
            Unmanaged<QuillGTKToolbarClosureBox>.fromOpaque(userData).release()
        },
        GConnectFlags(rawValue: 0)
    )
}

private func applyToolbarControlCSS(to widget: UnsafeMutablePointer<GtkWidget>, className: String) {
    let css = """
    .\(className),
    button.\(className),
    menubutton.\(className),
    menubutton.\(className) > button,
    menubutton.\(className) button {
        background: transparent;
        border: none;
        box-shadow: none;
        padding: 0 2px;
        min-height: 28px;
        min-width: 28px;
        color: #3A3A3C;
        -gtk-icon-shadow: none;
        text-shadow: none;
    }
    .\(className):hover,
    button.\(className):hover,
    menubutton.\(className):hover,
    menubutton.\(className) > button:hover,
    menubutton.\(className) button:hover {
        background: rgba(0, 0, 0, 0.06);
        border-radius: 5px;
    }
    .quill-toolbar-glyph-box,
    .quill-toolbar-symbol {
        background: transparent;
        color: #3A3A3C;
        padding: 0;
        margin: 0;
    }
    """

    let provider = gtk_css_provider_new()!
    gtk_css_provider_load_from_string(provider, css)
    if let display = gtk_widget_get_display(widget) {
        gtk_swift_add_css_provider_to_display(
            display,
            provider,
            UInt32(GTK_STYLE_PROVIDER_PRIORITY_USER)
        )
    }
    gtk_widget_add_css_class(widget, className)
    g_object_unref(gpointer(provider))
}
#endif
