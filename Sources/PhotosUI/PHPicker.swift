import Foundation
import QuillUIKit

// Linux shim for PhotosUI's `PHPickerViewController` family — the UIKit-style
// (delegate-driven, view-controller) photo picker that predates the SwiftUI
// `PhotosPicker`. Upstream Signal presents `PHPickerViewController` directly
// and conforms to `PHPickerViewControllerDelegate`; these declarations give the
// lowered code real types to instantiate, present, and call back through.
//
// `Any` is sourced from Foundation per Apple's surface (each result
// vends one). No photo library exists on Linux, so nothing is ever picked: the
// types carry faithful state and signatures only.

// MARK: - Filter

// `PHPickerFilter` describes which asset kinds the picker offers. The SwiftUI
// `PhotosPicker` slice already declares the canonical Linux `PHPickerFilter`
// (it is `matching:`'s parameter type there), so on Linux we defer to that one
// to avoid an invalid redeclaration within this module. On every other platform
// this file supplies the same value-semantics API the spec requires.
#if !os(Linux)
public struct PHPickerFilter: Hashable, Sendable {
    private let rawValue: String
    private init(_ rawValue: String) { self.rawValue = rawValue }

    public static let images = PHPickerFilter("images")
    public static let videos = PHPickerFilter("videos")

    public static func any(of filters: [PHPickerFilter]) -> PHPickerFilter {
        PHPickerFilter(filters.map(\.rawValue).joined(separator: ","))
    }
}
#endif

// MARK: - Configuration

/// Knobs handed to `PHPickerViewController(configuration:)`. Apple defaults
/// `selectionLimit` to 1 (single selection) and leaves `filter` nil (all kinds).
public struct PHPickerConfiguration {
    /// Maximum number of items the user may select. 1 by default; 0 means
    /// "no limit" on Apple. The shim never presents UI, so this is pure state.
    public var selectionLimit: Int = 1

    /// Which asset kinds to offer, or nil for all of them.
    public var filter: PHPickerFilter?

    public init() {}
}

// MARK: - Result

/// One picked item. Apple vends an `Any` to load the asset and,
/// optionally, the photo library's local asset identifier.
public struct PHPickerResult {
    /// Provider used to load the selected item's representations.
    public var itemProvider: Any

    /// The picked asset's local identifier, when available.
    public var assetIdentifier: String?

    public init(itemProvider: Any, assetIdentifier: String?) {
        self.itemProvider = itemProvider
        self.assetIdentifier = assetIdentifier
    }
}

// MARK: - Picker view controller

/// UIKit-style photo picker view controller. `open` so callers can subclass it
/// exactly as on Apple; it holds its configuration and a weak delegate that is
/// messaged when picking finishes. No system picker is shown on Linux.
@MainActor
open class PHPickerViewController: UIViewController {
    /// Receives `picker(_:didFinishPicking:)`. Weak to match Apple and to avoid
    /// the presenter <-> picker retain cycle.
    open weak var delegate: (any PHPickerViewControllerDelegate)?

    /// The immutable configuration this picker was created with.
    public let configuration: PHPickerConfiguration

    /// Designated initializer mirroring Apple's `init(configuration:)`.
    public init(configuration: PHPickerConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    // UIViewController declares `public required init?(coder:)`; restate it so
    // this subclass stays constructible from a coder. No nib/storyboard is ever
    // decoded on Linux — supply a default configuration so the stored `let`
    // is initialized before delegating up.
    public required init?(coder: NSCoder) {
        self.configuration = PHPickerConfiguration()
        super.init(coder: coder)
    }
}

// MARK: - Delegate

/// Picker callback protocol. `@MainActor` because the picker and its delegate
/// are UI objects; `AnyObject` so the picker can hold the delegate weakly.
@MainActor
public protocol PHPickerViewControllerDelegate: AnyObject {
    /// Called when the user finishes (selects or cancels). On cancel Apple
    /// passes an empty `results` array.
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult])
}
