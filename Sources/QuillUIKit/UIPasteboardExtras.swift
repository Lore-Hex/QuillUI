// QuillUIKit · UIPasteboard item surface
// ======================================
// The item-array API on UIPasteboard: items / setItems(_:options:) /
// addItems(_:), data(forPasteboardType:), strings, and the OptionsKey
// type. Signal's BodyRangesTextView copy/paste pipeline drives all of it:
// copy clears the board (`setItems([], options: [:])`), writes an archived
// MessageBody under its private UTI
// (`setItems([[Self.pasteboardType: data]], options: [.localOnly: true])`),
// then appends a plain-text representation
// (`addItems([["public.utf8-plain-text": plaintextData]])`); paste reads
// `data(forPasteboardType:)` first and falls back to `strings?.first`.
//
// The UIPasteboard class itself lives in QuillUIKit.swift (this file does
// not own it), so item storage sits in a side table and the members below
// are extension methods. Apple shapes are exact: setItems' options default
// to [:], OptionsKey is the NS_TYPED_ENUM string wrapper with
// expirationDate / localOnly (the UIKit apinotes spelling
// `UIPasteboard.OptionsKey`).
//
// Honest Linux semantics: the pasteboard is REAL within the process —
// items round-trip faithfully, so copy→paste inside the app works — but
// there is no OS pasteboard service, so nothing crosses processes and the
// options (localOnly, expirationDate) gate cross-app sharing that does not
// exist here; they are accepted and ignored. The legacy stored `string`
// property (QuillUIKit.swift) is kept coherent: item writes re-derive it
// from the board's plain-text representation, and `strings` falls back to
// it for call sites that still assign `.string` directly. The one
// remaining seam: assigning `.string` directly does NOT clear previously
// set items (a stored property can't be observed from an extension), so a
// stale typed item could outlive it — Signal's own copy paths always go
// through setItems first, which clears the board.

import QuillFoundation

#if !os(iOS)

/// Side table for pasteboard item arrays, keyed by ObjectIdentifier. Same
/// accepted trade-off as viewPreservesSuperviewLayoutMargins
/// (UIViewMargins.swift). In practice there is exactly one long-lived
/// instance: `UIPasteboard.general`.
@MainActor private var pasteboardItemsTable: [ObjectIdentifier: [[String: Any]]] = [:]

/// The UTIs treated as plain text when coercing item values to String,
/// in preference order (UIKit performs the same coercion when reading
/// `strings` from data-valued items).
private let quillPlainTextTypes: [String] = [
    "public.utf8-plain-text",
    "public.plain-text",
    "public.text",
]

/// Coerces one item's plain-text representation to a String, if it has one.
private func quillPlainText(in item: [String: Any]) -> String? {
    for type in quillPlainTextTypes {
        guard let value = item[type] else { continue }
        if let string = value as? String { return string }
        if let data = value as? Data { return String(data: data, encoding: .utf8) }
    }
    return nil
}

extension UIPasteboard {

    /// Options for setItems(_:options:). Apple's UIPasteboardOption is an
    /// NS_TYPED_ENUM NSString typedef; the apinotes rename it to
    /// `UIPasteboard.OptionsKey` with a struct wrapper — mirrored here
    /// (the UIPageViewController.OptionsKey pattern already in this module).
    public struct OptionsKey: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        /// Value: NSDate — when the items should expire. No cross-process
        /// pasteboard service exists on Linux, so expiry has nothing to
        /// enforce; accepted and ignored.
        public static let expirationDate = OptionsKey(rawValue: "UIPasteboardOptionExpirationDate")

        /// Value: NSNumber (boolean) — keep items off Handoff / Universal
        /// Clipboard. Nothing leaves the process on Linux anyway.
        public static let localOnly = OptionsKey(rawValue: "UIPasteboardOptionLocalOnly")
    }

    /// The full item array: one dictionary per item, keyed by pasteboard
    /// type (UTI). Assignment replaces the board's contents, as on Apple.
    @MainActor public var items: [[String: Any]] {
        get { pasteboardItemsTable[ObjectIdentifier(self)] ?? [] }
        set {
            pasteboardItemsTable[ObjectIdentifier(self)] = newValue
            // Keep the legacy stored `string` (QuillUIKit.swift) coherent
            // with the item model, so `.string` readers (Signal's
            // RegistrationVerificationViewController paste of a code, …)
            // see what item-based copy paths wrote.
            string = newValue.lazy.compactMap(quillPlainText(in:)).first
        }
    }

    /// Replaces the board's contents. `options` gate cross-app sharing
    /// (localOnly) and lifetime (expirationDate) on Apple; with no
    /// cross-process pasteboard on Linux they are accepted and ignored.
    @MainActor public func setItems(_ items: [[String: Any]], options: [UIPasteboard.OptionsKey: Any] = [:]) {
        _ = options
        self.items = items
    }

    /// Appends items to the board without clearing it (Apple semantics:
    /// addItems extends the current contents; setItems replaces them).
    @MainActor public func addItems(_ items: [[String: Any]]) {
        self.items.append(contentsOf: items)
    }

    /// The first item's data for the given pasteboard type. String-valued
    /// entries are coerced to UTF-8 data, matching UIKit's representation
    /// coercion.
    @MainActor public func data(forPasteboardType pasteboardType: String) -> Data? {
        for item in items {
            guard let value = item[pasteboardType] else { continue }
            if let data = value as? Data { return data }
            if let string = value as? String { return Data(string.utf8) }
        }
        return nil
    }

    /// Types for each item in the requested item set. Mirrors UIKit's
    /// `types(forItemSet:)` shape; nil itemSet means every item.
    @MainActor public func types(forItemSet itemSet: IndexSet?) -> [[String]]? {
        let sourceItems = items
        let indexes = itemSet ?? IndexSet(sourceItems.indices)
        let result = indexes.compactMap { index -> [String]? in
            guard sourceItems.indices.contains(index) else { return nil }
            return Array(sourceItems[index].keys)
        }
        return result.isEmpty ? nil : result
    }

    /// Data values for a pasteboard type in the requested item set.
    @MainActor public func data(forPasteboardType pasteboardType: String, inItemSet itemSet: IndexSet?) -> [Data]? {
        let sourceItems = items
        let indexes = itemSet ?? IndexSet(sourceItems.indices)
        let result = indexes.compactMap { index -> Data? in
            guard sourceItems.indices.contains(index),
                  let value = sourceItems[index][pasteboardType] else { return nil }
            if let data = value as? Data { return data }
            if let string = value as? String { return Data(string.utf8) }
            return nil
        }
        return result.isEmpty ? nil : result
    }

    /// Every item's plain-text representation, or nil if the board holds
    /// none (Apple returns nil rather than an empty array). Falls back to
    /// the legacy stored `string` property for boards populated by direct
    /// `.string =` assignment. The setter replaces the board with one
    /// plain-text item per string, as on Apple.
    @MainActor public var strings: [String]? {
        get {
            let collected = items.compactMap(quillPlainText(in:))
            if !collected.isEmpty { return collected }
            if let legacy = string { return [legacy] }
            return nil
        }
        set {
            items = (newValue ?? []).map { ["public.utf8-plain-text": $0] }
        }
    }
}

#endif // !os(iOS)
