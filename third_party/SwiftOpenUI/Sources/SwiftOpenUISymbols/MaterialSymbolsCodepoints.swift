import Foundation

/// Material Symbols name → Unicode codepoint lookup.
///
/// Google publishes each Material Symbols glyph at a Unicode Private Use
/// Area codepoint (the `U+E000…U+F8FF` range Unicode reserves for
/// application-defined glyphs). Backends that can't apply OpenType
/// ligature substitution — notably GDI on Win32 — use this table to
/// draw the glyph directly by its PUA codepoint instead of relying on
/// ligatures.
///
/// GTK4 and Win32 use this table directly so icon labels stay compact
/// even when ligature shaping or test-time font registration is incomplete.
/// Web / CSS can still draw the literal name and let the font's ligature
/// feature substitute the glyph during shaping.
///
/// Coverage is demand-driven: V1 targets every Material name referenced
/// by `SFSymbolCompatibility.map` plus the parity sample. New entries
/// are cheap — one line each, drawn from the upstream
/// `MaterialSymbolsRounded-Regular.codepoints` metadata file shipped
/// alongside the font.
public enum MaterialSymbolsCodepoints {
    /// Look up the Unicode PUA codepoint for a Material Symbols name.
    /// Returns `nil` if the name isn't in the table.
    public static func codepoint(for name: String) -> UInt32? {
        table[name]
    }

    /// Fallback codepoint used when a requested name isn't in the table.
    /// Matches `SFSymbolCompatibility.missingSymbolPlaceholderName`
    /// (`help_outline`) so both unknown SF names and unknown Material
    /// names render the same "icon missing" glyph.
    public static let missingGlyphCodepoint: UInt32 = 0xE8FD  // help_outline

    /// The name → codepoint table. Keep alphabetized within each
    /// thematic section to minimize merge conflicts when extending.
    public static let table: [String: UInt32] = [
        // Navigation / chevrons
        "chevron_left":        0xE5CB,
        "chevron_right":       0xE5CC,
        "expand_less":         0xE5CE,
        "expand_more":         0xE5CF,

        // Arrows and motion
        "arrow_back":          0xE5C4,
        "arrow_circle_right":  0xEAAA,
        "arrow_downward":      0xE5DB,
        "arrow_forward":       0xE5C8,
        "arrow_upward":        0xE5D8,
        "refresh":             0xE5D5,
        "swap_horiz":          0xE8D4,
        "swap_vert":           0xE8D5,
        "sync":                0xE627,
        "undo":                0xE166,

        // File / folder
        "article":             0xEF42,
        "content_copy":        0xE14D,
        "create_new_folder":   0xE2CC,
        "data_object":         0xE3B5,
        "delete":              0xE872,
        "description":         0xE873,
        "dns":                 0xE875,
        "find_in_page":        0xE880,
        "folder":              0xE2C7,
        "folder_open":         0xE2C8,
        "hard_drive":          0xF80E,
        "newspaper":           0xEB81,

        // Search / find
        "search":              0xE8B6,

        // Status / feedback
        "bar_chart":           0xE26B,
        "cancel":              0xE5C9,
        "check":               0xE5CA,
        "check_box":           0xE834,
        "check_box_outline_blank": 0xE835,
        "check_circle":        0xE86C,
        "close":               0xE5CD,
        "help_outline":        0xE8FD,
        "info":                0xE88E,
        "lightbulb":           0xE0F0,
        "radio_button_checked": 0xE837,
        "radio_button_unchecked": 0xE836,
        "stop":                0xE047,
        "trending_up":         0xE8E5,
        "verified":            0xEF76,
        "warning":             0xE002,

        // Common actions
        "add":                 0xE145,
        "add_circle":          0xE147,
        "attach_file":         0xE226,
        "download":            0xF090,
        "draw":                0xE746,
        "edit":                0xE3C9,
        "filter":              0xE3D3,
        "gesture":             0xE155,
        "keep_off":            0xE6F9,
        "magic_button":        0xF136,
        "palette":             0xE3B7,
        "push_pin":            0xF10D,
        "remove":              0xE15B,
        "remove_circle":       0xE15C,
        "repeat":              0xE040,
        "reply":               0xE15E,
        "select_all":          0xE162,
        "send":                0xE163,
        "settings":            0xE8B8,
        "share":               0xE80D,

        // People / accounts
        "account_circle":      0xE853,
        "group":               0xE7EF,
        "person":              0xE7FD,
        "person_add":          0xE7FE,
        "person_remove":       0xEF66,

        // UI primitives
        "alternate_email":     0xE0E6,
        "bookmark":            0xE866,
        "calendar_today":      0xE935,
        "favorite":            0xE87D,
        "favorite_border":     0xE87E,
        "filter_list":         0xE152,
        "format_quote":        0xE244,
        "forum":               0xE0BF,
        "graphic_eq":          0xE1B8,
        "history":             0xE889,
        "home":                0xE88A,
        "image":               0xE3F4,
        "inbox":               0xE156,
        "keyboard":            0xE312,
        "label":               0xE892,
        "layers":              0xE53B,
        "link":                0xE157,
        "list":                0xE896,
        "list_alt":            0xE0EE,
        "lock":                0xE897,
        "lock_open":           0xE898,
        "menu":                0xE5D2,
        "mic":                 0xE029,
        "more_horiz":          0xE5D3,
        "notifications":       0xE7F4,
        "public":              0xE80B,
        "quickreply":          0xEF6C,
        "rss_feed":            0xE0E5,
        "schedule":            0xE8B5,
        "shield":              0xE9E0,
        "shield_lock":         0xF686,
        "star":                0xE838,
        "star_border":         0xE83A,
        "stacks":              0xF500,
        "subtitles":           0xE048,
        "text_fields":         0xE262,
        "visibility":          0xE8F4,
        "visibility_off":      0xE8F5,
        "view_sidebar":        0xF114,
        "water_drop":          0xE798,

        // Media
        "flip":                0xE3E8,
        "light_mode":          0xE518,
        "pause":               0xE034,
        "photo_camera":        0xE412,
        "play_arrow":          0xE037,
        "rotate_right":        0xE41A,
        "space_bar":           0xE256,
        "straighten":          0xE41C,
        "tag":                 0xE9EF,
        "videocam_off":        0xE04C,
        "volume_off":          0xE04F,
        "volume_up":           0xE050,
    ]
}
