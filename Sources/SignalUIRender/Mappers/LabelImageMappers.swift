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
        // The typed GtkLabel setters below take a `GtkLabel*`, which bridges to
        // Swift as `OpaquePointer` — SwiftOpenUI wraps the GtkWidget pointer the
        // same way (`OpaquePointer(label)`) before calling gtk_label_set_*.
        let labelPtr = OpaquePointer(widget)

        let text = label.text ?? ""

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

        // Backgrounds / corner radius / border are CALayer concerns the shared
        // CSS path owns.
        ctx.applyLayerStyle(widget, view)
        return widget
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
        let text = view.quillRenderedText ?? ""

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
           !bytes.isEmpty {
            setPaintable(picturePtr, from: bytes)
            applyContentMode(widget, picturePtr: picturePtr, contentMode: imageView.contentMode)
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

    /// Decode `bytes` (PNG/JPEG/GIF/WebP/…) into a GdkTexture and set it as the
    /// picture's paintable. GdkTexture conforms to GdkPaintable, so the same
    /// pointer is handed straight to `gtk_picture_set_paintable`.
    private static func setPaintable(_ picturePtr: OpaquePointer, from bytes: Data) {
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
            return
        }
        defer { g_object_unref(gpointer(texture)) }

        // GdkTexture is-a GdkPaintable; the loader hands back the paintable.
        gtk_picture_set_paintable(picturePtr, texture)
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
    let fontDesc = "Sans \(Int(pointSize.rounded()))"
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

    tokens.append(String(Int(font.pointSize.rounded())))
    return tokens.joined(separator: " ")
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
