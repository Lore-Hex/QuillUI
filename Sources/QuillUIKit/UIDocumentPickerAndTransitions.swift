import Foundation
import QuillFoundation
import CoreGraphics
import UniformTypeIdentifiers

// MARK: - UIDocumentPickerDelegate

@MainActor public protocol UIDocumentPickerDelegate: AnyObject {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL)
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController)
}

extension UIDocumentPickerDelegate {
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {}
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {}
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
}

// MARK: - UIDocumentPickerViewController

@MainActor open class UIDocumentPickerViewController: UIViewController {

    public let contentTypes: [UTType]
    public let asCopy: Bool

    public weak var delegate: (any UIDocumentPickerDelegate)?
    public var allowsMultipleSelection: Bool = false

    public init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool = false) {
        self.contentTypes = contentTypes
        self.asCopy = asCopy
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.contentTypes = []
        self.asCopy = false
        super.init(coder: coder)
    }
}

// MARK: - UIPercentDrivenInteractiveTransition

@MainActor open class UIPercentDrivenInteractiveTransition: NSObject {

    public var completionSpeed: CGFloat = 1.0
    public var completionCurve: Int = 0
    public private(set) var percentComplete: CGFloat = 0.0

    public override init() {
        super.init()
    }

    open func update(_ percentComplete: CGFloat) {
        self.percentComplete = percentComplete
    }

    open func cancel() {}

    open func finish() {}
}

// MARK: - UICoordinateSpace

@MainActor public protocol UICoordinateSpace: AnyObject {
    var bounds: CGRect { get }
    func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint
    func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect
    func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint
    func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect
}

extension UICoordinateSpace {
    public func convert(_ point: CGPoint, to coordinateSpace: any UICoordinateSpace) -> CGPoint {
        return point
    }

    public func convert(_ rect: CGRect, to coordinateSpace: any UICoordinateSpace) -> CGRect {
        return rect
    }

    public func convert(_ point: CGPoint, from coordinateSpace: any UICoordinateSpace) -> CGPoint {
        return point
    }

    public func convert(_ rect: CGRect, from coordinateSpace: any UICoordinateSpace) -> CGRect {
        return rect
    }
}

extension UIView: UICoordinateSpace {}
