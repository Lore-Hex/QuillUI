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
/// Backends that do apply ligatures (GTK4 / Pango, Web / CSS) don't
/// need this table; they draw the literal name as text and let the
/// font's ligature feature substitute the glyph during shaping.
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
        "data_object":         0xE3B5,
        "content_copy":        0xE14D,
        "create_new_folder":   0xE2CC,
        "delete":              0xE872,
        "description":         0xE873,
        "find_in_page":        0xE880,
        "folder":              0xE2C7,
        "folder_open":         0xE2C8,

        // Search / find
        "search":              0xE8B6,

        // Status / feedback
        "cancel":              0xE5C9,
        "check":               0xE5CA,
        "check_box":           0xE834,
        "check_box_outline_blank": 0xE835,
        "check_circle":        0xE86C,
        "close":               0xE5CD,
        "help_outline":        0xE8FD,
        "info":                0xE88E,
        "stop":                0xE047,
        "verified":            0xEF76,
        "warning":             0xE002,

        // Common actions
        "add":                 0xE145,
        "add_circle":          0xE147,
        "download":            0xF090,
        "edit":                0xE3C9,
        "push_pin":            0xF10D,
        "remove":              0xE15B,
        "remove_circle":       0xE15C,
        "select_all":          0xE162,
        "send":                0xE163,
        "settings":            0xE8B8,
        "share":               0xE80D,

        // People / accounts
        "account_circle":      0xE853,
        "group":               0xE7EF,
        "person":              0xE7FD,

        // UI primitives
        "bookmark":            0xE866,
        "calendar_today":      0xE935,
        "favorite":            0xE87D,
        "favorite_border":     0xE87E,
        "graphic_eq":          0xE1B8,
        "home":                0xE88A,
        "image":               0xE3F4,
        "keyboard":            0xE312,
        "label":               0xE892,
        "link":                0xE157,
        "lock":                0xE897,
        "lock_open":           0xE898,
        "menu":                0xE5D2,
        "mic":                 0xE029,
        "more_horiz":          0xE5D3,
        "notifications":       0xE7F4,
        "schedule":            0xE8B5,
        "star":                0xE838,
        "star_border":         0xE83A,
        "text_fields":         0xE262,
        "visibility":          0xE8F4,
        "visibility_off":      0xE8F5,
        "view_sidebar":        0xF114,
        "water_drop":          0xE798,

        // Media
        "light_mode":          0xE518,
        "pause":               0xE034,
        "play_arrow":          0xE037,
        "space_bar":           0xE256,
        "volume_off":          0xE04F,
        "volume_up":           0xE050,
    ]
}
