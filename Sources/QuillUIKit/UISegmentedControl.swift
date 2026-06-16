import Foundation
import QuillFoundation
import CoreGraphics

/// A horizontal control made of multiple segments, each functioning as a
/// discrete button. A Linux reimplementation of Apple's `UISegmentedControl`.
///
/// This is part of the QuillUIKit module, so it references the sibling
/// `UIControl`, `UIImage`, `UIColor`, etc. types directly (no `import UIKit`).
@MainActor
open class UISegmentedControl: UIControl {

    /// Sentinel value returned by (and assignable to) `selectedSegmentIndex`
    /// when no segment is selected.
    public static let noSegment: Int = -1

    /// Internal model for a single segment. A segment carries an optional
    /// title and/or image plus its enabled/width state, mirroring the
    /// pieces of state Apple exposes through the per-segment accessors.
    private struct Segment {
        var title: String?
        var image: UIImage?
        var isEnabled: Bool = true
        var width: CGFloat = 0   // 0 means "size automatically"
    }

    /// Backing store of segments, ordered left-to-right.
    private var segments: [Segment] = []

    /// Per-state title text attributes, keyed by the raw value of
    /// `UIControl.State` (since `UIControl.State` is an OptionSet and not
    /// itself Hashable in a dictionary-key-friendly way everywhere).
    private var titleTextAttributesByState: [UInt: [NSAttributedString.Key: Any]] = [:]

    // MARK: - Public configuration

    /// The number of segments the control has. Computed from the internal
    /// segment array.
    open var numberOfSegments: Int {
        return segments.count
    }

    /// The index of the selected segment, or `UISegmentedControl.noSegment`
    /// (`-1`) if no segment is selected.
    open var selectedSegmentIndex: Int = UISegmentedControl.noSegment

    /// The tint color used to highlight the currently selected segment.
    open var selectedSegmentTintColor: UIColor?

    /// When `true`, each segment's width is determined by its content;
    /// when `false`, segments are sized equally.
    open var apportionsSegmentWidthsByContent: Bool = false

    /// When `true`, the control does not retain the most-recently-selected
    /// segment as the active segment after the touch ends (momentary mode).
    open var isMomentary: Bool = false

    // MARK: - Initializers

    /// Creates a segmented control with no segments.
    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    /// Convenience no-argument initializer.
    public convenience init() {
        self.init(frame: .zero)
    }

    /// Creates a segmented control and populates it from an array of items.
    /// Each item should be either a `String` (used as a segment title) or a
    /// `UIImage` (used as a segment image). Other types are inserted as an
    /// empty segment, matching the forgiving behavior of UIKit.
    public convenience init(items: [Any]?) {
        self.init(frame: .zero)
        guard let items = items else { return }
        for (index, item) in items.enumerated() {
            if let title = item as? String {
                insertSegment(withTitle: title, at: index, animated: false)
            } else if let image = item as? UIImage {
                insertSegment(with: image, at: index, animated: false)
            } else {
                segments.insert(Segment(), at: min(index, segments.count))
            }
        }
        // Apple selects no segment by default for the items initializer.
        selectedSegmentIndex = UISegmentedControl.noSegment
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Inserting & removing segments

    /// Inserts a segment with the given title at the specified index.
    open func insertSegment(withTitle title: String?, at segment: Int, animated: Bool) {
        let clampedIndex = clampInsertionIndex(segment)
        segments.insert(Segment(title: title, image: nil), at: clampedIndex)
    }

    /// Inserts a segment showing the given image at the specified index.
    open func insertSegment(with image: UIImage?, at segment: Int, animated: Bool) {
        let clampedIndex = clampInsertionIndex(segment)
        segments.insert(Segment(title: nil, image: image), at: clampedIndex)
    }

    /// Removes the segment at the specified index.
    open func removeSegment(at segment: Int, animated: Bool) {
        guard segments.indices.contains(segment) else { return }
        segments.remove(at: segment)
        // Keep the selected index sane after removal.
        if segments.isEmpty {
            selectedSegmentIndex = UISegmentedControl.noSegment
        } else if selectedSegmentIndex >= segments.count {
            selectedSegmentIndex = UISegmentedControl.noSegment
        }
    }

    /// Removes all segments from the control.
    open func removeAllSegments() {
        segments.removeAll()
        selectedSegmentIndex = UISegmentedControl.noSegment
    }

    // MARK: - Segment titles & images

    /// Sets the title of the segment at the given index.
    open func setTitle(_ title: String?, forSegmentAt segment: Int) {
        guard segments.indices.contains(segment) else { return }
        segments[segment].title = title
        segments[segment].image = nil
    }

    /// Returns the title of the segment at the given index, or `nil`.
    open func titleForSegment(at segment: Int) -> String? {
        guard segments.indices.contains(segment) else { return nil }
        return segments[segment].title
    }

    /// Sets the image of the segment at the given index.
    open func setImage(_ image: UIImage?, forSegmentAt segment: Int) {
        guard segments.indices.contains(segment) else { return }
        segments[segment].image = image
        segments[segment].title = nil
    }

    /// Returns the image of the segment at the given index, or `nil`.
    open func imageForSegment(at segment: Int) -> UIImage? {
        guard segments.indices.contains(segment) else { return nil }
        return segments[segment].image
    }

    // MARK: - Segment enabled & width

    /// Enables or disables the segment at the given index.
    open func setEnabled(_ enabled: Bool, forSegmentAt segment: Int) {
        guard segments.indices.contains(segment) else { return }
        segments[segment].isEnabled = enabled
    }

    /// Returns whether the segment at the given index is enabled.
    open func isEnabledForSegment(at segment: Int) -> Bool {
        guard segments.indices.contains(segment) else { return false }
        return segments[segment].isEnabled
    }

    /// Sets the width of the segment at the given index. A width of `0`
    /// indicates the segment should be sized automatically.
    open func setWidth(_ width: CGFloat, forSegmentAt segment: Int) {
        guard segments.indices.contains(segment) else { return }
        segments[segment].width = width
    }

    /// Returns the width of the segment at the given index.
    open func widthForSegment(at segment: Int) -> CGFloat {
        guard segments.indices.contains(segment) else { return 0 }
        return segments[segment].width
    }

    // MARK: - Title text attributes

    /// Sets the text attributes used to draw segment titles for the given
    /// control state.
    open func setTitleTextAttributes(_ attributes: [NSAttributedString.Key: Any]?, for state: UIControl.State) {
        if let attributes = attributes {
            titleTextAttributesByState[state.rawValue] = attributes
        } else {
            titleTextAttributesByState.removeValue(forKey: state.rawValue)
        }
    }

    /// Returns the text attributes used to draw segment titles for the given
    /// control state, or `nil` if none have been set.
    open func titleTextAttributes(for state: UIControl.State) -> [NSAttributedString.Key: Any]? {
        return titleTextAttributesByState[state.rawValue]
    }

    // MARK: - Helpers

    /// Clamps a requested insertion index into the valid `0...count` range so
    /// callers can pass `numberOfSegments` to append without crashing.
    private func clampInsertionIndex(_ index: Int) -> Int {
        if index < 0 { return 0 }
        if index > segments.count { return segments.count }
        return index
    }
}
