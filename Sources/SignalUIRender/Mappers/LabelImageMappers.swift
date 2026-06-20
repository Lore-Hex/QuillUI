// LabelImageMappers.swift
// ========================
// GTK4 mappers for two leaf UIKit views — UILabel and UIImageView — in the
// UIKit→GTK4 renderer that lets Signal-iOS's real UIKit views display on Linux.
//
// Both conform to the FIXED `UIViewGtkMapper` contract (declared in this target):
// `handles(_:)` is a cheap type test the dispatcher uses to pick a mapper, and
// `make(_:_:)` builds the concrete GtkWidget. The render context (`ctx`) lets a
// mapper recurse into child views, measure text, and apply CALayer-style chrome
// (background / corner radius / border) via the shared CSS path.
//
// The GTK4 C idioms here mirror the PROVEN code in
// `third_party/SwiftOpenUI/Sources/Backend/GTK4` (GtkLabel + Pango markup, the
// GtkPicture content-fit pattern) and `Sources/QuillUI/GdkPixbufTranscode.swift`
// / `Sources/CGtk4/shim.h` (decoding arbitrary image bytes through GTK's texture
// loader). We stay inside the contract's pinned `CGTK` umbrella module, calling
// the raw `gtk_*` / `gdk_*` / `g_*` functions it re-exports rather than adding
// new C shims.

import CGTK            // UnsafeMutablePointer<GtkWidget>, all gtk_* / gdk_* / g_* C functions
import QuillUIKit      // UIView, UILabel, UIImageView (UIView.ContentMode)
import UIKit       // UIFont (+ UILabel.font accessor), UIColor/UIImage aliases, NSTextAlignment
import QuillFoundation // NSTextAlignment, RSColor/RSImage (the Linux UIColor/UIImage)
import Foundation

// NOTE(contract): the task spec lists only `import CGTK` + `import QuillUIKit`,
// but on Linux the styled-leaf surface actually lives in the shim modules:
//   • `UILabel.font` is layered onto QuillUIKit's storage slot by UIKitShim
//     (UIFontExtras.swift), so the typed `font` accessor is only visible with
//     `import UIKit`.
//   • `UIColor`/`UIImage` are typealiases to `RSColor`/`RSImage` declared in
//     QuillFoundation; `NSTextAlignment` likewise lives in QuillFoundation
//     (NSTextLayoutShared.swift).
// Importing these is purely additive — no contract type is redefined here.

// MARK: - UILabel

/// Maps `UILabel` to a `GtkLabel`.
///
/// Text comes from `label.text`. Color and font are emitted as Pango markup
/// (`<span foreground='#RRGGBB' font='Family Weight Size'>…</span>`) so a single
/// `gtk_label_set_markup` styles the whole run — the same approach SwiftOpenUI's
/// `Text` renderer uses for colored runs. Wrapping / line-count come from
/// `numberOfLines`, and horizontal placement from `textAlignment`.
public enum UILabelGtkMapper: UIViewGtkMapper {
    public static func handles(_ view: UIView) -> Bool {
        view is UILabel
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        guard let label = view as? UILabel else {
            // handles(_:) gates this; an empty label keeps the renderer total.
            return gtk_label_new(nil)
        }

        let widget: GtkWidgetPtr = gtk_label_new(nil)
        applyLabelContent(to: widget, label: label)
        installLabelMutationBridge(widget, label: label)
        // Backgrounds / corner radius / border are CALayer concerns the shared
        // CSS path owns.
        ctx.applyLayerStyle(widget, view)
        return widget
    }

    private static func applyLabelContent(to widget: GtkWidgetPtr, label: UILabel) {
        // The typed GtkLabel setters below take a `GtkLabel*`, which bridges to
        // Swift as `OpaquePointer` — SwiftOpenUI wraps the GtkWidget pointer the
        // same way (`OpaquePointer(label)`) before calling gtk_label_set_*.
        let labelPtr = OpaquePointer(widget)
        let text = visibleText(from: label.attributedText?.string ?? label.text ?? "")

        // Color + font are carried by Pango markup. If we have neither a custom
        // color nor a font worth spelling out we fall back to plain text so the
        // label inherits the ambient GTK theme color (matching SwiftOpenUI's
        // "plain Text keeps the fast path" behavior).
        if let markup = pangoMarkup(for: text, font: label.font, color: label.textColor) {
            markup.withCString { gtk_label_set_markup(labelPtr, $0) }
        } else {
            text.withCString { gtk_label_set_text(labelPtr, $0) }
        }

        applyLineWrapping(labelPtr, numberOfLines: label.numberOfLines)
        applyAlignment(labelPtr, alignment: label.textAlignment)
    }

    private static func installLabelMutationBridge(_ widget: GtkWidgetPtr, label: UILabel) {
        label.quillSetViewMutationHandler("SignalUIRender.labelContent") { updatedView in
            guard let updatedLabel = updatedView as? UILabel else { return }
            applyLabelContent(to: widget, label: updatedLabel)
            gtk_widget_queue_resize(widget)
        }
    }

    /// Configure wrap + line cap from `numberOfLines`.
    /// - `1`  → single line, no wrap (UIKit's default).
    /// - `0`  → unlimited wrapping.
    /// - `n>1`→ wrap, capped at `n` lines.
    private static func applyLineWrapping(_ labelPtr: OpaquePointer, numberOfLines: Int) {
        if numberOfLines == 1 {
            gtk_label_set_wrap(labelPtr, 0)
            gtk_label_set_lines(labelPtr, 1)
            return
        }

        gtk_label_set_wrap(labelPtr, 1)
        // Word-then-char wrapping matches SwiftOpenUI's multi-line labels and
        // avoids mid-word overflow when a single token is wider than the box.
        gtk_label_set_wrap_mode(labelPtr, PANGO_WRAP_WORD_CHAR)

        if numberOfLines == 0 {
            // Unlimited: -1 tells GtkLabel not to cap the line count.
            gtk_label_set_lines(labelPtr, -1)
        } else {
            gtk_label_set_lines(labelPtr, gint(numberOfLines))
        }
    }

    /// Map `NSTextAlignment` onto GtkLabel's xalign (the float 0…1 anchor) and
    /// justify (how wrapped lines fill). UIKit's `.natural` resolves to leading
    /// (left) in LTR, which is also GTK's natural default.
    private static func applyAlignment(_ labelPtr: OpaquePointer, alignment: NSTextAlignment) {
        switch alignment {
        case .center:
            gtk_label_set_xalign(labelPtr, 0.5)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_CENTER)
        case .right:
            gtk_label_set_xalign(labelPtr, 1.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_RIGHT)
        case .justified:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_FILL)
        case .left, .natural:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_LEFT)
        @unknown default:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_LEFT)
        }
    }
}

// MARK: - Custom-Drawn Text UIView

/// Maps custom `UIView.draw(_:)` text views that publish generic Quill renderer
/// metadata. Signal's `CVTextLabel.Label` uses this path: it is fileprivate and
/// draws from TextKit, so the renderer cannot name the type or read its private
/// storage directly.
public enum CustomDrawnTextGtkMapper: UIViewGtkMapper {
    public static func handles(_ view: UIView) -> Bool {
        view.quillRenderedText != nil
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let widget: GtkWidgetPtr = gtk_label_new(nil)
        let labelPtr = OpaquePointer(widget)
        let text = visibleText(from: view.quillRenderedText ?? "")

        if let markup = pangoMarkup(
            for: text,
            pointSize: view.quillRenderedTextPointSize,
            color: view.quillRenderedTextColor,
        ) {
            markup.withCString { gtk_label_set_markup(labelPtr, $0) }
        } else {
            text.withCString { gtk_label_set_text(labelPtr, $0) }
        }

        applyLineWrapping(labelPtr, numberOfLines: view.quillRenderedTextNumberOfLines)
        applyAlignment(labelPtr, alignment: view.quillRenderedTextAlignment)
        ctx.applyLayerStyle(widget, view)
        return widget
    }

    private static func applyLineWrapping(_ labelPtr: OpaquePointer, numberOfLines: Int) {
        if numberOfLines == 1 {
            gtk_label_set_wrap(labelPtr, 0)
            gtk_label_set_lines(labelPtr, 1)
            return
        }

        gtk_label_set_wrap(labelPtr, 1)
        gtk_label_set_wrap_mode(labelPtr, PANGO_WRAP_WORD_CHAR)
        gtk_label_set_lines(labelPtr, numberOfLines == 0 ? -1 : gint(numberOfLines))
    }

    private static func applyAlignment(_ labelPtr: OpaquePointer, alignment: NSTextAlignment) {
        switch alignment {
        case .center:
            gtk_label_set_xalign(labelPtr, 0.5)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_CENTER)
        case .right:
            gtk_label_set_xalign(labelPtr, 1.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_RIGHT)
        case .justified:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_FILL)
        case .left, .natural:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_LEFT)
        @unknown default:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_LEFT)
        }
    }
}

// MARK: - UITextView

/// Maps `UITextView` and subclasses such as Signal's `LinkingTextView` to
/// either a wrapped label (static explanatory/link text) or a real `GtkEntry`
/// (editable composer/input text). The editable branch preserves UIKit delegate
/// callbacks through `UITextView.quillReplaceCharacters`.
public enum UITextViewGtkMapper: UIViewGtkMapper {
    public static func handles(_ view: UIView) -> Bool {
        guard let textView = view as? UITextView else { return false }
        let text = textView.attributedText?.string ?? textView.text ?? ""
        return !text.isEmpty || textView.subviews.isEmpty || shouldRenderEditable(textView)
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        guard let textView = view as? UITextView else {
            return gtk_label_new(nil)
        }

        if shouldRenderEditable(textView) {
            return makeEditable(textView, ctx)
        }

        let widget: GtkWidgetPtr = gtk_label_new(nil)
        applyTextViewLabelContent(to: widget, textView: textView)
        installTextViewLabelMutationBridge(widget, textView: textView)
        ctx.applyLayerStyle(widget, view)
        return widget
    }

    private static func applyTextViewLabelContent(to widget: GtkWidgetPtr, textView: UITextView) {
        let labelPtr = OpaquePointer(widget)
        let attributedText = textView.attributedText
        let text = visibleText(from: attributedText?.string ?? textView.text ?? "")
        let attributes = attributedText.flatMap { text in
            text.length > 0 ? text.attributes(at: 0, effectiveRange: nil) : nil
        }
        let font = attributes?[.font] as? UIFont ?? textView.font
        let color = attributes?[.foregroundColor] as? UIColor ?? textView.textColor
        let alignment = (attributes?[.paragraphStyle] as? NSParagraphStyle)?.alignment ?? textView.textAlignment

        if let markup = pangoMarkup(for: text, font: font, color: color) {
            markup.withCString { gtk_label_set_markup(labelPtr, $0) }
        } else {
            text.withCString { gtk_label_set_text(labelPtr, $0) }
        }

        gtk_label_set_wrap(labelPtr, 1)
        gtk_label_set_wrap_mode(labelPtr, PANGO_WRAP_WORD_CHAR)
        gtk_label_set_lines(labelPtr, -1)
        applyAlignment(labelPtr, alignment: alignment)
    }

    private static func installTextViewLabelMutationBridge(_ widget: GtkWidgetPtr, textView: UITextView) {
        textView.quillSetViewMutationHandler("SignalUIRender.textViewLabelContent") { updatedView in
            guard let updatedTextView = updatedView as? UITextView else { return }
            applyTextViewLabelContent(to: widget, textView: updatedTextView)
            gtk_widget_queue_resize(widget)
        }
    }

    private static func applyAlignment(_ labelPtr: OpaquePointer, alignment: NSTextAlignment) {
        switch alignment {
        case .center:
            gtk_label_set_xalign(labelPtr, 0.5)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_CENTER)
        case .right:
            gtk_label_set_xalign(labelPtr, 1.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_RIGHT)
        case .justified:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_FILL)
        case .left, .natural:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_LEFT)
        @unknown default:
            gtk_label_set_xalign(labelPtr, 0.0)
            gtk_label_set_justify(labelPtr, GTK_JUSTIFY_LEFT)
        }
    }

    private static func makeEditable(_ textView: UITextView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let entry = gtk_entry_new()!
        let widget: GtkWidgetPtr = entry
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_halign(widget, GTK_ALIGN_FILL)
        gtk_widget_set_valign(widget, GTK_ALIGN_CENTER)
        gtk_widget_set_can_focus(widget, 1)
        gtk_widget_set_focusable(widget, 1)
        gtk_widget_set_sensitive(widget, textView.isUserInteractionEnabled ? 1 : 0)

        let text = textView.attributedText?.string ?? textView.text ?? ""
        if !text.isEmpty {
            quillSignalTextViewEntrySetText(UnsafeMutableRawPointer(widget), text)
        }
        if let placeholder = placeholderText(for: textView) {
            quillSignalTextViewEntrySetPlaceholder(UnsafeMutableRawPointer(widget), placeholder)
        }

        applyEditableStyle(widget, textView: textView)
        quillSignalConnectTextViewEntrySignals(UnsafeMutableRawPointer(widget), textView: textView)
        installEditableTextViewMutationBridge(widget, textView: textView)
        ctx.applyLayerStyle(widget, textView)
        return widget
    }

    private static func installEditableTextViewMutationBridge(_ widget: GtkWidgetPtr, textView: UITextView) {
        let rawWidget = UnsafeMutableRawPointer(widget)
        textView.quillSetViewMutationHandler("SignalUIRender.textViewEntryContent") { updatedView in
            guard let updatedTextView = updatedView as? UITextView else { return }
            let nextText = updatedTextView.attributedText?.string ?? updatedTextView.text ?? ""
            if quillSignalTextViewEntryGetText(rawWidget) != nextText {
                quillSignalTextViewEntrySetText(rawWidget, nextText)
            }
            if let placeholder = placeholderText(for: updatedTextView) {
                quillSignalTextViewEntrySetPlaceholder(rawWidget, placeholder)
            }
            gtk_widget_set_sensitive(widget, updatedTextView.isUserInteractionEnabled ? 1 : 0)
            gtk_widget_queue_resize(widget)
        }
    }

    private static func shouldRenderEditable(_ textView: UITextView) -> Bool {
        guard textView.isEditable else { return false }
        let typeName = String(describing: type(of: textView))
        if typeName.contains("LinkingTextView") {
            return false
        }
        if placeholderText(for: textView) != nil {
            return true
        }
        if typeName.localizedCaseInsensitiveContains("input")
            || typeName.localizedCaseInsensitiveContains("composer") {
            return true
        }
        let text = textView.attributedText?.string ?? textView.text ?? ""
        return textView.subviews.isEmpty && (text.isEmpty || textView.frame.height <= 80)
    }

    private static func placeholderText(for textView: UITextView) -> String? {
        for subview in textView.subviews {
            guard let label = subview as? UILabel else { continue }
            let text = visibleText(from: label.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func applyEditableStyle(_ widget: GtkWidgetPtr, textView: UITextView) {
        "signal-uikit-text-view-entry".withCString {
            gtk_widget_add_css_class(widget, $0)
        }

        let provider = gtk_css_provider_new()
        var css = """
        .signal-uikit-text-view-entry {
            background: transparent;
            border: none;
            box-shadow: none;
            outline: none;
            padding: 0;
            min-height: 0;
        }
        .signal-uikit-text-view-entry text {
            background: transparent;
        }
        """
        if let color = textView.textColor, let hex = uiColorHex(color) {
            css += "\n.signal-uikit-text-view-entry { color: \(hex); }"
        }
        css.withCString { gtk_css_provider_load_from_string(provider, $0) }
        if let display = gtk_widget_get_display(widget) {
            gtk_style_context_add_provider_for_display(
                display,
                OpaquePointer(provider),
                guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
            )
        }
    }
}

// MARK: - UIImageView

/// Maps `UIImageView` to a `GtkPicture` (GTK4's scalable image widget — it honors
/// its allocation and scales the texture, unlike the fixed-size GtkImage).
///
/// `imageView.image` is the Linux `RSImage`, whose backing bytes are exposed via
/// `pngData()` (the original PNG/JPEG/… container bytes captured at
/// `RSImage(data:)`). We decode those bytes into a `GdkTexture` and install it as
/// the picture's paintable, mirroring `Sources/CGtk4/shim.h`'s
/// `quill_gtk_image_set_from_bytes`. With no bytes (placeholder / synthesized
/// images, whose `cgImage` is always nil on Linux) the picture stays empty.
public enum UIImageViewGtkMapper: UIViewGtkMapper {
    public static func handles(_ view: UIView) -> Bool {
        view is UIImageView
    }

    public static func make(_ view: UIView, _ ctx: UIKitGtkRenderContext) -> GtkWidgetPtr {
        let widget: GtkWidgetPtr = gtk_picture_new()
        // GtkPicture setters take a `GtkPicture*`, which bridges to Swift as
        // `OpaquePointer`; the widget-level expansion setters take `GtkWidget*`.
        let picturePtr = OpaquePointer(widget)

        if let imageView = view as? UIImageView,
           let image = imageView.image,
           let bytes = imageData(from: image),
           !bytes.isEmpty,
           setPaintable(picturePtr, from: bytes) {
            applyContentMode(widget, picturePtr: picturePtr, contentMode: imageView.contentMode)
        } else if let imageView = view as? UIImageView,
                  let fallback = fallbackSymbol(for: imageView) {
            let label = fallbackLabel(text: fallback, for: imageView)
            ctx.applyLayerStyle(label, view)
            applyFallbackStyle(to: label, imageView: imageView)
            return label
        } else {
            // No loadable image: leave the picture empty but still let it shrink
            // so it doesn't force a large natural size into the layout.
            gtk_picture_set_can_shrink(picturePtr, 1)
        }

        ctx.applyLayerStyle(widget, view)
        return widget
    }

    /// Pull the original encoded bytes out of the image. `pngData()` on Linux's
    /// `RSImage` returns the bytes the image was constructed from (it does not
    /// re-encode — `cgImage` is always nil), which is exactly what GTK's loader
    /// wants. `dataRepresentation()` is the same store; we try it as a fallback.
    private static func imageData(from image: UIImage) -> Data? {
        image.pngData() ?? image.dataRepresentation()
    }

    private static func fallbackSymbol(for imageView: UIImageView) -> String? {
        let image = imageView.image
        let rawName = image?.quillSystemSymbolName ?? image?.quillResourceName ?? ""
        let name = rawName.lowercased()
        let size = imageView.bounds.size != .zero ? imageView.bounds.size : imageView.frame.size
        let isAvatar = size.width >= 44 && size.height >= 44 && imageView.layer.cornerRadius > 0

        if isAvatar {
            return "?"
        }
        if name.contains("plus") || name.contains("add") || name.contains("attachment") || name.contains("paperclip") {
            return "+"
        }
        if name.contains("check") {
            return "✓"
        }
        if name.contains("message_status") {
            return name.contains("sent") ? "✓" : "•"
        }
        if name.contains("chevron-down") { return "⌄" }
        if name.contains("arrow-up") || name.contains("send") || name.contains("paperplane") { return "↑" }
        if name.contains("reply") { return "↩" }
        if name.contains("chevron") || name.contains("arrow") || name.contains("send") || name.contains("paperplane") {
            return "›"
        }
        if name.contains("mic") || name.contains("audio") || name.contains("voice") {
            return "●"
        }
        if name.contains("camera") || name.contains("photo") || name.contains("image") {
            return "▣"
        }
        if name.contains("keyboard") {
            return "⌨"
        }
        if name.contains("sticker") || name.contains("emoji") {
            return "☺"
        }
        if name == "at" || name.contains("mention") {
            return "@"
        }
        if name.contains("info") || name.contains("question") {
            return "?"
        }
        if name.contains("more") || name.contains("ellipsis") {
            return "..."
        }
        if !name.isEmpty {
            return "•"
        }
        return nil
    }

    private static func fallbackLabel(text: String, for imageView: UIImageView) -> GtkWidgetPtr {
        let widget: GtkWidgetPtr = gtk_label_new(nil)
        let labelPtr = OpaquePointer(widget)
        let size = imageView.bounds.size != .zero ? imageView.bounds.size : imageView.frame.size
        let isAvatar = size.width >= 44 && size.height >= 44 && imageView.layer.cornerRadius > 0
        let pointSize = isAvatar ? 24 : 15
        let color = isAvatar ? "#5F6673" : "#6B6B70"
        let escaped = escapeMarkup(text)
        let markup = "<span font='Sans Bold \(pointSize)' foreground='\(color)'>\(escaped)</span>"
        markup.withCString { gtk_label_set_markup(labelPtr, $0) }
        gtk_label_set_xalign(labelPtr, 0.5)
        gtk_label_set_yalign(labelPtr, 0.5)
        gtk_label_set_justify(labelPtr, GTK_JUSTIFY_CENTER)
        if size.width > 0 || size.height > 0 {
            gtk_widget_set_size_request(
                widget,
                size.width > 0 ? gint(size.width) : -1,
                size.height > 0 ? gint(size.height) : -1
            )
        }
        gtk_widget_set_halign(widget, GTK_ALIGN_CENTER)
        gtk_widget_set_valign(widget, GTK_ALIGN_CENTER)
        return widget
    }

    private static func applyFallbackStyle(to widget: GtkWidgetPtr, imageView: UIImageView) {
        let size = imageView.bounds.size != .zero ? imageView.bounds.size : imageView.frame.size
        let isAvatar = size.width >= 44 && size.height >= 44 && imageView.layer.cornerRadius > 0
        var rules: [String] = []
        if isAvatar {
            rules.append("background-color: #E3E7EE;")
            let radius = max(1, Int((min(size.width, size.height) / 2).rounded()))
            rules.append("border-radius: \(radius)px;")
        }
        guard !rules.isEmpty else { return }

        fallbackStyleCounter += 1
        let cls = "qimagefallback\(fallbackStyleCounter)"
        let css = ".\(cls) { \(rules.joined(separator: " ")) }"
        let provider = gtk_css_provider_new()
        css.withCString { gtk_css_provider_load_from_string(provider, $0) }
        if let display = gdk_display_get_default() {
            gtk_style_context_add_provider_for_display(
                display,
                OpaquePointer(provider),
                guint(GTK_STYLE_PROVIDER_PRIORITY_APPLICATION)
            )
        }
        cls.withCString { gtk_widget_add_css_class(widget, $0) }
        g_object_unref(provider)
    }

    /// Decode `bytes` (PNG/JPEG/GIF/WebP/…) into a GdkTexture and set it as the
    /// picture's paintable. GdkTexture conforms to GdkPaintable, so the same
    /// pointer is handed straight to `gtk_picture_set_paintable`.
    ///
    /// Returns false for template/PDF assets that GTK's raster loader cannot
    /// decode, letting the caller fall back to the image's preserved resource
    /// name instead of leaving a blank widget.
    private static func setPaintable(_ picturePtr: OpaquePointer, from bytes: Data) -> Bool {
        let texture: OpaquePointer? = bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> OpaquePointer? in
            guard let base = raw.baseAddress, raw.count > 0 else { return nil }
            // g_bytes_new copies the buffer, so it is safe to free `bytes` after
            // this closure returns.
            guard let gbytes = g_bytes_new(base, gsize(raw.count)) else { return nil }
            defer { g_bytes_unref(gbytes) }

            var error: UnsafeMutablePointer<GError>? = nil
            let tex = gdk_texture_new_from_bytes(gbytes, &error)
            if let error {
                g_error_free(error)
                return nil
            }
            return tex
        }

        guard let texture else {
            // Undecodable bytes: keep the picture empty rather than crashing.
            gtk_picture_set_can_shrink(picturePtr, 1)
            return false
        }
        defer { g_object_unref(gpointer(texture)) }

        // GdkTexture is-a GdkPaintable; the loader hands back the paintable.
        gtk_picture_set_paintable(picturePtr, texture)
        return true
    }

    /// Translate `UIView.ContentMode` into GtkPicture's content-fit + expansion.
    /// GtkPicture exposes a coarser model than UIKit (fill / contain / cover /
    /// scale-down), so several UIKit modes collapse onto the nearest fit. The
    /// positional modes (center/top/…) have no scaling, so we keep the natural
    /// size (contain, no expansion) and let the widget's align handle placement.
    private static func applyContentMode(
        _ widget: GtkWidgetPtr,
        picturePtr: OpaquePointer,
        contentMode: UIView.ContentMode
    ) {
        switch contentMode {
        case .scaleToFill, .redraw:
            // Stretch to fill, ignoring aspect ratio (UIKit's default).
            gtk_picture_set_content_fit(picturePtr, GTK_CONTENT_FIT_FILL)
            gtk_picture_set_can_shrink(picturePtr, 1)
            expandToFill(widget)

        case .scaleAspectFit:
            gtk_picture_set_content_fit(picturePtr, GTK_CONTENT_FIT_CONTAIN)
            gtk_picture_set_can_shrink(picturePtr, 1)
            expandToFill(widget)

        case .scaleAspectFill:
            gtk_picture_set_content_fit(picturePtr, GTK_CONTENT_FIT_COVER)
            gtk_picture_set_can_shrink(picturePtr, 1)
            expandToFill(widget)

        case .center, .top, .bottom, .left, .right,
             .topLeft, .topRight, .bottomLeft, .bottomRight:
            // No scaling: render at natural size and let alignment position it.
            gtk_picture_set_content_fit(picturePtr, GTK_CONTENT_FIT_CONTAIN)
            gtk_picture_set_can_shrink(picturePtr, 0)

        @unknown default:
            gtk_picture_set_content_fit(picturePtr, GTK_CONTENT_FIT_CONTAIN)
            gtk_picture_set_can_shrink(picturePtr, 1)
            expandToFill(widget)
        }
    }

    /// Let a scaling picture expand into and fill its parent's allocation,
    /// matching SwiftOpenUI's resizable-image setup.
    private static func expandToFill(_ picture: GtkWidgetPtr) {
        gtk_widget_set_hexpand(picture, 1)
        gtk_widget_set_vexpand(picture, 1)
        gtk_widget_set_halign(picture, GTK_ALIGN_FILL)
        gtk_widget_set_valign(picture, GTK_ALIGN_FILL)
    }
}

// MARK: - UIColor → hex, UIFont → Pango (file-local helpers)

/// Build Pango markup for a label run, or `nil` when neither a custom color nor a
/// meaningful font is present (so the caller can take the plain-text fast path
/// and inherit the theme).
///
/// The text is markup-escaped first (Pango's parser is XML-ish). The span
/// carries `foreground='#RRGGBB'` from the color and a `font='…'` description
/// built from the UIFont. Alpha is dropped: Pango's `foreground` is opaque, and
/// label text is effectively always full-opacity in this surface.
private func pangoMarkup(for text: String, font: UIFont?, color: UIColor?) -> String? {
    let hex = color.flatMap(hexString(from:))
    let fontDesc = font.flatMap(pangoFontDescription(from:))

    // Nothing to style → let the caller use gtk_label_set_text.
    guard hex != nil || fontDesc != nil else { return nil }

    let escaped = escapeMarkup(text)
    var attrs = ""
    if let hex { attrs += " foreground='\(hex)'" }
    if let fontDesc { attrs += " font='\(fontDesc)'" }
    return "<span\(attrs)>\(escaped)</span>"
}

private func pangoMarkup(for text: String, pointSize: CGFloat, color: UIColor?) -> String? {
    let hex = color.flatMap(hexString(from:))
    let fontDesc = "Sans \(pangoPointSize(fromUIKitPointSize: pointSize))"
    let escaped = escapeMarkup(text)
    var attrs = " font='\(fontDesc)'"
    if let hex { attrs += " foreground='\(hex)'" }
    return "<span\(attrs)>\(escaped)</span>"
}

/// UIColor → `#RRGGBB`. On Linux `UIColor` is `RSColor`, whose
/// `getRed(_:green:blue:alpha:)` always succeeds; we read the components and
/// quantize each channel to 8 bits. (Mirrors SwiftOpenUI's `String(format:)`
/// hex packing in `Text.pangoMarkup`.)
private func hexString(from color: UIColor) -> String? {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    func channel(_ v: CGFloat) -> Int { max(0, min(255, Int((v * 255).rounded()))) }
    return String(format: "#%02X%02X%02X", channel(r), channel(g), channel(b))
}

/// UIFont → a Pango font description string, e.g. `"Sans Bold Italic 17"`.
///
/// Pango parses a trailing integer/float as the point size and leading tokens as
/// family + style. The Linux `UIFont` is inert (no real font engine), so we map:
///   • family  — the system font (`.AppleSystemUIFont` and friends) → "Sans",
///               which Pango aliases to the default UI font; any other
///               `fontName` is passed through verbatim as the family.
///   • style   — `Bold` / `Italic` from the descriptor's symbolic traits.
///   • size    — `pointSize`, rounded to a whole point.
private func pangoFontDescription(from font: UIFont) -> String {
    var tokens: [String] = []

    tokens.append(pangoFamily(from: font.fontName))

    let traits = font.fontDescriptor.symbolicTraits
    if traits.contains(.traitBold) { tokens.append("Bold") }
    if traits.contains(.traitItalic) { tokens.append("Italic") }

    tokens.append(String(pangoPointSize(fromUIKitPointSize: font.pointSize)))
    return tokens.joined(separator: " ")
}

private func pangoPointSize(fromUIKitPointSize pointSize: CGFloat) -> Int {
    max(1, Int((pointSize * 0.80).rounded()))
}

/// Map a UIFont name to a Pango family. The shim's system fonts start with a dot
/// (`.AppleSystemUIFont`, `.AppleSystemUIFontRounded-Regular`) — none of which
/// exist as Pango families — so route them to "Sans" (Pango's portable UI-font
/// alias). Real named fonts pass through unchanged.
private func pangoFamily(from fontName: String) -> String {
    fontName.hasPrefix(".") || fontName.isEmpty ? "Sans" : fontName
}

/// Pango-markup-safe escape for the four characters its parser treats specially.
/// Mirrors SwiftOpenUI's `gtkEscapeMarkup`.
private func escapeMarkup(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "'": out += "&apos;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}

private var fallbackStyleCounter = 0

private func visibleText(from text: String) -> String {
    String(text.unicodeScalars.filter { scalar in
        !(0xE000...0xF8FF).contains(Int(scalar.value))
    })
}
