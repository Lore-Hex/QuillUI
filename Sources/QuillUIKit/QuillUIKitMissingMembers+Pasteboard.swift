import Foundation
import CoreGraphics
import QuillFoundation

// Additive surface for QuillUIKit (Linux UIKit reimplementation).
//
// Extensions cannot add stored properties, so each stored property is backed by
// a @MainActor file-private global dictionary keyed by ObjectIdentifier(self).
// Methods are authored as plain extension funcs with minimal/no-op bodies that
// return sensible values, since there is no live UIKit runtime on Linux.

// MARK: - UIPasteboard

nonisolated(unsafe) private var _quillPasteboardNumberOfItems: [ObjectIdentifier: Int] = [:]
nonisolated(unsafe) private var _quillPasteboardTypes: [ObjectIdentifier: [String]] = [:]

public extension UIPasteboard {
    /// Number of items on the pasteboard. Defaults to 0; no live pasteboard
    /// backing on Linux, so this is purely faithful state.
    var numberOfItems: Int {
        get { _quillPasteboardNumberOfItems[ObjectIdentifier(self)] ?? 0 }
        set { _quillPasteboardNumberOfItems[ObjectIdentifier(self)] = newValue }
    }

    /// Representation types present on the pasteboard. Defaults to [].
    var types: [String] {
        get { _quillPasteboardTypes[ObjectIdentifier(self)] ?? [] }
        set { _quillPasteboardTypes[ObjectIdentifier(self)] = newValue }
    }

    /// Sentinel type letting the system pick the best representation.
    /// Matches UIPasteboard.typeAutomatic.
    static var typeAutomatic: String { "com.apple.uikit.pasteboard.automatic" }
}

// MARK: - UIApplication

nonisolated(unsafe) private var _quillIsIdleTimerDisabled: [ObjectIdentifier: Bool] = [:]
nonisolated(unsafe) private var _quillPreferredContentSizeCategory: [ObjectIdentifier: UIContentSizeCategory] = [:]

public extension UIApplication {
    /// Whether the idle (screen-dimming/sleep) timer is disabled. Defaults to
    /// false. No power-management backing on Linux; faithful state only.
    var isIdleTimerDisabled: Bool {
        get { _quillIsIdleTimerDisabled[ObjectIdentifier(self)] ?? false }
        set { _quillIsIdleTimerDisabled[ObjectIdentifier(self)] = newValue }
    }

    /// The app's preferred Dynamic Type content size category. Matches UIKit's
    /// default of `.large`. `UIContentSizeCategory` is a same-module struct.
    var preferredContentSizeCategory: UIContentSizeCategory {
        get { _quillPreferredContentSizeCategory[ObjectIdentifier(self)] ?? .large }
        set { _quillPreferredContentSizeCategory[ObjectIdentifier(self)] = newValue }
    }

    /// Marks the end of a background task. No-op: no UIKit background-task
    /// runtime on Linux. `UIBackgroundTaskIdentifier` is a same-module typealias
    /// for `Int`.
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        // No background execution model on Linux; nothing to tear down.
    }

    /// Objective-C dynamic-dispatch probe. Without an Objective-C runtime on
    /// Linux we cannot answer truthfully, so we report `false`, matching the
    /// conservative "selector not implemented" answer.
    func responds(to selector: Selector?) -> Bool {
        false
    }
}

// MARK: - UICollectionView

public extension UICollectionView {
    /// Deselects the item at the given index path. No-op: no live selection
    /// model drives the renderer here.
    func deselectItem(at indexPath: IndexPath, animated: Bool) {
        // No-op.
    }

    /// Index paths of the currently selected items. Returns nil (UIKit returns
    /// nil when nothing is selected).
    var indexPathsForSelectedItems: [IndexPath]? {
        nil
    }

    /// Animates a group of insert/delete/move/reload operations together.
    /// Runs `updates` synchronously, then signals completion with `true`.
    func performBatchUpdates(_ updates: (() -> Void)?, completion: ((Bool) -> Void)?) {
        updates?()
        completion?(true)
    }

    /// Currently visible cells. Returns [] (no live layout/visibility tracking).
    var visibleCells: [UICollectionViewCell] {
        []
    }
}
