import Foundation
import QuillFoundation
import QuillUIKit
import CoreGraphics

// MARK: - UIContentView

/// A view that renders the contents described by a content configuration.
///
/// `UIContentConfiguration` already exists in QuillUIKit as an (empty) marker
/// protocol; this file supplies the surrounding API surface that Signal's cell
/// content-configuration code relies on.
@MainActor
public protocol UIContentView: AnyObject {
    /// The current configuration describing the content of this view.
    var configuration: UIContentConfiguration { get set }
}

// MARK: - UIConfigurationState

/// Marker protocol for objects that describe the state used to resolve a
/// content configuration (selection, highlight, focus, etc.).
///
/// `UICellConfigurationState` (which already exists in QuillUIKit) is the
/// concrete state Signal uses; it can be made to conform to this protocol
/// elsewhere without modifying its declaring file.
@MainActor
public protocol UIConfigurationState {}

// MARK: - UIListContentConfiguration

/// A content configuration for a list-based cell, suitable for table and
/// collection view cells. Mirrors the shape of UIKit's
/// `UIListContentConfiguration`.
public struct UIListContentConfiguration: UIContentConfiguration {

    /// Properties that affect how text is displayed.
    public struct TextProperties {
        /// The color of the text.
        public var color: UIColor
        /// The font of the text.
        public var font: UIFont

        public init(color: UIColor = .label, font: UIFont = .systemFont(ofSize: 17)) {
            self.color = color
            self.font = font
        }
    }

    /// The primary text shown by the content view.
    public var text: String?
    /// The secondary text shown by the content view.
    public var secondaryText: String?
    /// The image shown by the content view.
    public var image: UIImage?

    /// Properties controlling how `text` is rendered.
    public var textProperties: TextProperties

    public init() {
        self.text = nil
        self.secondaryText = nil
        self.image = nil
        self.textProperties = TextProperties()
    }

    /// Returns a configuration appropriate for a plain list cell.
    public static func cell() -> UIListContentConfiguration {
        UIListContentConfiguration()
    }

    /// Creates a view that renders this configuration.
    @MainActor
    public func makeContentView() -> UIView & UIContentView {
        UIListContentView(configuration: self)
    }

    /// Returns a configuration resolved for the given state.
    public func updated(for state: UIConfigurationState) -> UIListContentConfiguration {
        self
    }
}

// MARK: - Backing content view

/// Concrete `UIView & UIContentView` used by
/// `UIListContentConfiguration.makeContentView()`.
@MainActor
private final class UIListContentView: UIView, UIContentView {

    private var appliedConfiguration: UIListContentConfiguration

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let listConfiguration = newValue as? UIListContentConfiguration else { return }
            appliedConfiguration = listConfiguration
            apply(listConfiguration)
        }
    }

    init(configuration: UIListContentConfiguration) {
        self.appliedConfiguration = configuration
        super.init(frame: .zero)
        apply(configuration)
    }

    public required init?(coder: NSCoder) {
        self.appliedConfiguration = UIListContentConfiguration()
        super.init(coder: coder)
    }

    private func apply(_ configuration: UIListContentConfiguration) {
        // Linux has no live UIKit runtime to lay out; storing the resolved
        // configuration is sufficient for the configuration to round-trip.
        self.appliedConfiguration = configuration
    }
}
