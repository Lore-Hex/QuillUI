import Foundation

/// Curated SF Symbols → Material Symbols name translation table.
///
/// Non-macOS backends use this to resolve `Image(systemName:)` calls
/// against the bundled Material Symbols Rounded font: the renderer looks
/// the SF name up in `map`, and — if found — renders the corresponding
/// Material glyph through the same path as `Image(material:)`.
///
/// Unmapped SF names fall through to a visible "missing icon" placeholder
/// (`missingSymbolPlaceholderName`) rather than silent failure, so app
/// developers notice and can either pass a name that's already mapped or
/// file/propose an addition to this table.
///
/// ## Policy notes (see docs/architecture/icon-symbols.md M-Symbols-3)
///
/// - **`.fill` variants collapse to their outlined counterpart** for V1.
///   SF distinguishes `folder` vs `folder.fill`; our single committed
///   static font is outlined-only, so both names map to the same Material
///   glyph. Shipping a filled-companion static is tracked as M-Symbols-3b.
/// - **Swift source file, not JSON**, deliberately — compile-time dedup
///   checks, trivial grep/edit workflow, no runtime parse cost.
/// - **Coverage is demand-driven, not comprehensive.** V1 targets
///   Synca's observed usage plus the common SwiftUI-tutorial icon set
///   (~50 entries). Expansion happens one entry at a time as apps
///   request them; mapping each entry is a small product decision.
public enum SFSymbolCompatibility {
    /// Material Symbols glyph rendered when `Image(systemName:)` is given
    /// a name that has no entry in `map`. Chosen to read as "icon
    /// missing" rather than stray text content. `help_outline` is a
    /// boxed-circle question-mark frame in Material Rounded.
    public static let missingSymbolPlaceholderName: String = "help_outline"

    /// Look up the Material Symbols name corresponding to an SF Symbols
    /// name, or nil if the SF name isn't currently mapped.
    public static func materialName(for sfName: String) -> String? {
        map[sfName]
    }

    /// The curated SF→Material map. Keep alphabetized within each
    /// thematic section to make merge conflicts easy to resolve.
    public static let map: [String: String] = [
        // MARK: Navigation / chevrons
        "chevron.backward":       "chevron_left",
        "chevron.down":           "expand_more",
        "chevron.forward":        "chevron_right",
        "chevron.left":           "chevron_left",
        "chevron.right":          "chevron_right",
        "chevron.up":             "expand_less",

        // MARK: Arrows and motion
        "arrow.backward":         "arrow_back",
        "arrow.clockwise":        "refresh",
        "arrow.counterclockwise": "undo",
        "arrow.down.doc":         "download",
        "arrow.down":             "arrow_downward",
        "arrow.forward":          "arrow_forward",
        "arrow.forward.circle.fill": "arrow_circle_right",
        "arrow.left":             "arrow_back",
        "arrow.left.and.right.righttriangle.left.righttriangle.right": "flip",
        "arrow.left.arrow.right": "swap_horiz",
        "arrow.right":            "arrow_forward",
        "arrow.clockwise.circle": "sync",
        "arrow.counterclockwise.circle": "history",
        "arrow.counterclockwise.circle.fill": "history",
        "arrow.triangle.2.circlepath": "sync",
        "arrow.triangle.merge":   "merge_type",
        "arrow.up":               "arrow_upward",
        "arrow.up.and.down.righttriangle.up.righttriangle.down": "swap_vert",
        "arrow.up.arrow.down":    "swap_vert",
        "arrow.up.doc":           "upload_file",
        "arrow.up.right":         "open_in_new",
        "arrow.uturn.backward":   "undo",
        "arrow.uturn.left.square": "undo",

        // MARK: Camera / capture (SolderScope)
        "camera":                 "photo_camera",
        "camera.fill":            "photo_camera",
        "camera.viewfinder":      "photo_camera",
        "line.diagonal":          "draw",
        "pause":                  "pause",
        "record.circle":          "radio_button_checked",
        "rotate.right":           "rotate_right",
        "ruler":                  "straighten",
        "square.stack.3d.up":     "layers",
        "video.slash":            "videocam_off",

        // MARK: File / folder
        "curlybraces":            "data_object",
        "doc":                    "description",
        "doc.fill":               "description",
        "doc.on.doc":             "content_copy",
        "doc.plaintext":          "article",
        "doc.richtext":           "article",
        "doc.text":               "description",
        "doc.text.magnifyingglass": "find_in_page",
        "display":                "desktop_windows",
        "folder":                 "folder",
        "folder.badge.plus":      "create_new_folder",
        "folder.fill":            "folder",
        "plus.rectangle.on.folder": "create_new_folder",
        "trash":                  "delete",
        "trash.fill":             "delete",
        "trash.slash":            "delete_forever",

        // MARK: Search / find
        "magnifyingglass":        "search",
        "magnifyingglass.circle": "search",
        "text.magnifyingglass":   "find_in_page",

        // MARK: Status / feedback
        "checkmark":              "check",
        // SF "circle" is an outline ring (IceCubes content-warning toggle);
        // Material's outline ring is the unchecked radio glyph.
        "circle":                 "radio_button_unchecked",
        "checkmark.circle":       "check_circle",
        "checkmark.circle.fill":  "check_circle",
        "checkmark.seal":         "verified",
        "checkmark.square.fill":  "check_box",
        "checkmark.seal.fill":    "verified",
        "chart.line.uptrend.xyaxis": "trending_up",
        "clock.fill":             "schedule",
        "exclamationmark.circle.fill": "error",
        "exclamationmark.triangle": "warning",
        "exclamationmark.triangle.fill": "warning",
        "info.circle":            "info",
        "lightbulb":                "lightbulb",
        "lightbulb.circle":         "lightbulb",
        "lightbulb.circle.fill":    "lightbulb",
        "info.circle.fill":       "info",
        "questionmark":           "help_outline",
        "questionmark.circle":    "help_outline",
        "square":                 "check_box_outline_blank",
        "square.fill":            "stop",
        "xmark":                  "close",
        "xmark.circle":           "cancel",
        "xmark.circle.fill":      "cancel",
        "xmark.octagon":          "dangerous",
        "xmark.octagon.fill":     "dangerous",
        "x.circle.fill":            "cancel",

        // MARK: Common actions
        "gear":                   "settings",
        "gearshape":              "settings",
        "gearshape.fill":         "settings",
        "hammer":                 "construction",
        "hand.raised.fill":       "front_hand",
        "hand.thumbsdown":        "thumb_down",
        "hand.thumbsup":          "thumb_up",
        "minus":                  "remove",
        "minus.circle":           "remove_circle",
        "minus.rectangle":        "disabled_by_default",
        "paperplane.fill":        "send",
        "pencil":                 "edit",
        "paperclip":                "attach_file",
        "play.circle.fill":       "play_circle",
        "pin":                    "push_pin",
        "pin.fill":               "push_pin",
        "pin.slash":              "keep_off",
        "plus":                   "add",
        "plus.bubble":            "add_comment",
        "plus.circle":            "add_circle",
        "plus.circle.fill":       "add_circle",
        "plus.message":           "add_comment",
        "plus.square.on.square":  "add_box",
        "selection.pin.in.out":   "select_all",
        "slash.circle":           "keyboard_command_key",
        "square.and.arrow.down":  "download",
        "square.and.arrow.up":    "share",
        "square.and.pencil":      "edit",
        "stop.fill":              "stop",

        // MARK: People / accounts
        "person":                 "person",
        "person.2":               "group",
        "person.2.badge.gearshape": "manage_accounts",
        "person.badge.plus":      "person_add",
        "person.crop.circle.badge.checkmark": "how_to_reg",
        "person.crop.circle":     "account_circle",
        "person.fill":            "person",

        // MARK: UI primitives
        "bell":                   "notifications",
        "bell.fill":              "notifications",
        "bookmark":               "bookmark",
        "bubble.left.and.bubble.right": "forum",
        "bubble.left.and.text.bubble.right": "quickreply",
        "brain.head.profile":     "psychology",
        "calendar":               "calendar_today",
        "character.cursor.ibeam":   "text_fields",
        "clock":                  "schedule",
        "clock.arrow.2.circlepath": "history",
        "clock.arrow.circlepath": "history",
        "command":                "keyboard_command_key",
        "clear":                  "backspace",
        "diamond":                "diamond",
        "ellipsis":               "more_horiz",
        "ellipsis.circle":        "more_horiz",
        "keyboard":               "keyboard",
        "keyboard.fill":          "keyboard",
        "line.3.horizontal.decrease": "filter_list",
        "line.3.horizontal.decrease.circle": "filter_list",
        "line.3.horizontal":      "menu",
        "eye":                    "visibility",
        "eye.slash":              "visibility_off",
        "heart":                  "favorite_border",
        "heart.fill":             "favorite",
        "house":                  "home",
        "house.fill":             "home",
        "list.bullet":            "list",
        "list.bullet.rectangle":  "list_alt",
        "photo":                  "image",
        "photo.fill":             "image",
        "photo.on.rectangle.angled": "filter",
        "link":                   "link",
        "lock":                   "lock",
        "lock.fill":              "lock",
        "lock.shield":              "shield_lock",
        "shield.lefthalf.filled":   "shield",
        "mic":                    "mic",
        "number":                 "tag",
        "network.slash":          "wifi_off",
        "point.3.connected.trianglepath.dotted": "account_tree",
        "puzzlepiece.extension":  "extension",
        "q.circle.fill":          "code",
        "quote.bubble":           "format_quote",
        "rectangle.stack.badge.questionmark": "unknown_document",
        "sidebar.left":           "view_sidebar",
        "lock.open":              "lock_open",
        "star":                   "star_border",
        "star.fill":              "star",
        "stop.circle":            "stop_circle",
        "tag":                    "label",
        "tag.fill":               "label",
        "tablecells":             "table",
        "terminal":               "terminal",
        "text.bubble":            "chat_bubble",
        "text.bubble.badge.exclamationmark": "error",
        "text.bubble.badge.plus": "add_comment",
        "text.cursor":            "text_fields",
        "textformat":               "text_fields",
        "textformat.abc":         "text_fields",
        "waveform.path.ecg":      "ecg_heart",
        "wrench.and.screwdriver": "construction",

        // MARK: Social / navigation (Mastodon / IceCubes)
        "arrowshape.turn.up.left": "reply",
        "arrow.2.squarepath":      "repeat",
        "badge.plus.radiowaves.right": "add_circle",
        "dot.radiowaves.right":    "rss_feed",
        "globe":                   "public",
        "globe.americas":          "public",

        // MARK: Media / settings
        "pause.fill":              "pause",
        "play.fill":               "play_arrow",
        "rectangle.on.rectangle":  "content_copy",
        "space":                   "space_bar",
        "speaker.slash.fill":      "volume_off",
        "speaker.wave.2.fill":     "volume_up",
        "speaker.wave.3":          "volume_up",
        "speaker.wave.3.fill":     "volume_up",
        "sun.max":                 "light_mode",
        "water.waves":             "water_drop",
        "waveform":                "graphic_eq",
    ]
}
