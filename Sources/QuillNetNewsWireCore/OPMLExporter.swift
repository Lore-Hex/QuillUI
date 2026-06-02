import Foundation

/// OPML 2.0 subscription-list serializer — the counterpart to
/// `OPMLImporter`. Produces a minimal but valid OPML document
/// that round-trips back through the importer to the same
/// `[Feed]` list, modulo the optional list title.
///
/// Format choices:
///   - Outputs a flat `<body>` of `<outline type="rss" ...>` rows
///     because the current `Feed` type doesn't carry folder
///     membership; the sidebar-folder iteration will introduce a
///     grouped overload that walks a folder tree.
///   - Escapes XML-special characters in both attribute values
///     (text, title, xmlUrl) so feed titles with `&`, `<`, `>`,
///     or quotes survive export.
///   - Sets `type="rss"` even for Atom feeds: upstream
///     NetNewsWire treats `type="rss"` as the generic "fetch this
///     URL as a feed" marker, regardless of underlying format.
public enum OPMLExporter {

    /// Default head title used when the caller doesn't supply one.
    /// Mirrors upstream NetNewsWire's exported-OPML wording.
    public static let defaultTitle = "Subscriptions"

    public static func export(feeds: [Feed], title: String? = nil) -> String {
        let headTitle = title ?? defaultTitle
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(escapeAttribute(headTitle))</title>
          </head>
          <body>

        """
        for feed in feeds {
            let text = escapeAttribute(feed.title)
            let url = escapeAttribute(feed.url)
            out.append("    <outline type=\"rss\" text=\"\(text)\" title=\"\(text)\" xmlUrl=\"\(url)\"/>\n")
        }
        out.append("  </body>\n</opml>\n")
        return out
    }

    public static func exportData(feeds: [Feed], title: String? = nil) -> Data {
        Data(export(feeds: feeds, title: title).utf8)
    }

    /// Tree-preserving export: walks an OPMLImporter.Folder
    /// hierarchy and emits nested `<outline>` group wrappers
    /// for each named subfolder, with `<outline type="rss" />`
    /// leaves inside. The unnamed root folder's name is NOT
    /// emitted as a wrapper (its feeds + subfolders inline
    /// directly under `<body>`); named subfolders become group
    /// outlines per OPML 2.0 conventions. Round-trips back
    /// through OPMLImporter.parseTree with the same structure.
    public static func exportTree(
        root: OPMLImporter.Folder,
        title: String? = nil
    ) -> String {
        let headTitle = title ?? defaultTitle
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>\(escapeAttribute(headTitle))</title>
          </head>
          <body>

        """
        // Root's own feeds inline first, then named subfolders
        // as group outlines. Same depth-first walk OPMLImporter
        // would round-trip back into a Folder tree.
        appendFolderContents(root, indent: "    ", into: &out)
        out.append("  </body>\n</opml>\n")
        return out
    }

    public static func exportTreeData(
        root: OPMLImporter.Folder,
        title: String? = nil
    ) -> Data {
        Data(exportTree(root: root, title: title).utf8)
    }

    private static func appendFolderContents(
        _ folder: OPMLImporter.Folder,
        indent: String,
        into out: inout String
    ) {
        for feed in folder.feeds {
            let text = escapeAttribute(feed.title)
            let url = escapeAttribute(feed.url)
            out.append("\(indent)<outline type=\"rss\" text=\"\(text)\" title=\"\(text)\" xmlUrl=\"\(url)\"/>\n")
        }
        for sub in folder.subfolders {
            let name = escapeAttribute(sub.name)
            out.append("\(indent)<outline text=\"\(name)\" title=\"\(name)\">\n")
            appendFolderContents(sub, indent: indent + "  ", into: &out)
            out.append("\(indent)</outline>\n")
        }
    }

    /// Minimal XML-attribute escape: covers the five
    /// predefined entities so the resulting attribute is
    /// well-formed regardless of feed-title contents.
    static func escapeAttribute(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count)
        for ch in raw {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&apos;")
            default: out.append(ch)
            }
        }
        return out
    }
}
