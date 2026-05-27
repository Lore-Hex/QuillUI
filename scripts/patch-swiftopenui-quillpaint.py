import os
import sys

def patch_renderer(renderer_path):
    with open(renderer_path, 'r') as f:
        text = f.read()

    # 1. Add hook declaration at the top
    hook_decl = 'public var quill_gtk_button_paint_hook: ((OpaquePointer, OpaquePointer, Bool) -> Bool)? = nil\n'
    if hook_decl not in text and 'extension Text' in text:
        text = hook_decl + text

    # 2. Patch Button.gtkCreateWidget
    # We want to insert the hook call after the button and label widget are created.
    # The original code handles Text separately from custom views.
    
    old_button_create = '''    public func gtkCreateWidget() -> OpaquePointer {
        let button: UnsafeMutablePointer<GtkWidget>
        var buttonWantsHExpand = false
        var buttonWantsVExpand = false

        if let textLabel = label as? Text {
            // Simple text label — use native label button
            button = gtk_button_new_with_label(textLabel.content)!
        } else {'''
    
    new_button_create = '''    public func gtkCreateWidget() -> OpaquePointer {
        let button: UnsafeMutablePointer<GtkWidget>
        let labelWidget: UnsafeMutablePointer<GtkWidget>
        var buttonWantsHExpand = false
        var buttonWantsVExpand = false

        if let textLabel = label as? Text {
            button = gtk_button_new()!
            labelWidget = widgetFromOpaque(textLabel.gtkCreateWidget())
        } else {
            labelWidget = widgetFromOpaque(gtkRenderView(label))
            button = gtk_button_new()!
        }

        let isDefault = getCurrentEnvironment().buttonStyle == .borderedProminent
        if let hook = quill_gtk_button_paint_hook, hook(OpaquePointer(button), OpaquePointer(labelWidget), isDefault) {
             // Handled by hook
        } else {
            if let textLabel = label as? Text {
                // Fallback for Text if hook declined
                gtk_button_set_child(UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self), labelWidget)
            } else {'''

    # This is tricky because the 'else' block continues.
    # Let's try a different approach: replace the whole block.
    
    start_match = '    public func gtkCreateWidget() -> OpaquePointer {'
    # Find the extension Button block
    btn_ext_index = text.find('extension Button: GTKRenderable')
    if btn_ext_index != -1:
        create_widget_index = text.find(start_match, btn_ext_index)
        if create_widget_index != -1:
             # Find the end of the if-else block
             # The block we want to replace ends with:
             #             gtk_widget_set_valign(childWidget, GTK_ALIGN_FILL)
             #         }
             #         // Remove GTK default button border/padding
             
             end_match = '            // Remove GTK default button border/padding'
             end_index = text.find(end_match, create_widget_index)
             if end_index != -1:
                 # We also need to include the next few lines of applyCSSToWidget
                 # and the closing brace of the else block.
                 
                 # Actually, let's just replace from 'let button' to the end of the if/else.
                 
                 target_block_start = text.find('let button:', create_widget_index)
                 # Find the end of the if/else block.
                 # It ends after the applyCSSToWidget(...) call.
                 target_block_end = text.find('        }', end_index) + 9 # include the closing brace and newline
                 
                 new_block = '''        let button: UnsafeMutablePointer<GtkWidget>
        let labelWidget: UnsafeMutablePointer<GtkWidget>
        var buttonWantsHExpand = false
        var buttonWantsVExpand = false

        if let textLabel = label as? Text {
            button = gtk_button_new()!
            labelWidget = widgetFromOpaque(textLabel.gtkCreateWidget())
        } else {
            labelWidget = widgetFromOpaque(gtkRenderView(label))
            button = gtk_button_new()!
            if gtk_widget_get_hexpand(labelWidget) != 0 {
                buttonWantsHExpand = true
                gtk_widget_set_halign(labelWidget, GTK_ALIGN_FILL)
            }
            if gtk_widget_get_vexpand(labelWidget) != 0 {
                buttonWantsVExpand = true
                gtk_widget_set_valign(labelWidget, GTK_ALIGN_FILL)
            }
        }

        let isDefault = getCurrentEnvironment().buttonStyle == .borderedProminent
        if let hook = quill_gtk_button_paint_hook, hook(OpaquePointer(button), OpaquePointer(labelWidget), isDefault) {
            // Handled by hook (QuillPaint)
        } else {
            let btnPtr = UnsafeMutableRawPointer(button).assumingMemoryBound(to: GtkButton.self)
            gtk_button_set_child(btnPtr, labelWidget)
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
        }
'''
                 text = text[:target_block_start] + new_block + text[target_block_end:]

    with open(renderer_path, 'w') as f:
        f.write(text)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: patch_quillpaint.py <renderer_path>")
        sys.exit(1)
    patch_renderer(sys.argv[1])
