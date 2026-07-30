import AuthenticationServices
import CoreTransferable
import Foundation
import AppKit
import QuillSwiftUICompatibility
import SwiftOpenUI
import UIKit

#if os(Linux)
public extension UIColor {
    convenience init(_ color: Color) {
        self.init(
            red: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: CGFloat(color.alpha)
        )
    }
}

public extension Color {
    init(_ color: NSColor) {
        self.init(
            red: Double(color._red),
            green: Double(color._green),
            blue: Double(color._blue),
            opacity: Double(color._alpha)
        )
    }
}

public struct WebAuthenticationSessionAction: Sendable {
    public init() {}

    public func authenticate(using url: URL, callbackURLScheme: String?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let holder = QuillWebAuthenticationSessionHolder()
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackURLScheme) { callbackURL, error in
                holder.session = nil
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? URLError(.userAuthenticationRequired))
                }
            }
            holder.session = session

            guard session.start() else {
                holder.session = nil
                continuation.resume(throwing: URLError(.userAuthenticationRequired))
                return
            }
        }
    }
}

private final class QuillWebAuthenticationSessionHolder: @unchecked Sendable {
    var session: ASWebAuthenticationSession?
}

private struct WebAuthenticationSessionKey: EnvironmentKey {
    static let defaultValue = WebAuthenticationSessionAction()
}

@MainActor
@propertyWrapper
public struct UIApplicationDelegateAdaptor<Delegate> {
    private let value: Delegate?

    public init() {
        guard
            let factory = Delegate.self as? any QuillUIApplicationDelegateFactory.Type,
            let delegate = factory.quillMakeUIApplicationDelegate() as? Delegate
        else {
            value = nil
            return
        }

        value = delegate
        if let applicationDelegate = delegate as? any UIApplicationDelegate {
            SwiftOpenUIAppLifecycle.registerPostInitialization {
                _ = applicationDelegate.application(
                    UIApplication.shared,
                    didFinishLaunchingWithOptions: nil
                )
            }
        }
    }

    public var wrappedValue: Delegate {
        get {
            guard let value else {
                fatalError(
                    "UIApplicationDelegateAdaptor could not construct its Linux runtime delegate. "
                    + "Run the generic QuillUI source lowerer or conform the delegate to "
                    + "QuillUIApplicationDelegateFactory."
                )
            }
            return value
        }
    }
}

private struct OpenURLKey: EnvironmentKey {
    static let defaultValue = OpenURLAction()
}

public extension EnvironmentValues {
    var openURL: OpenURLAction {
        get { self[OpenURLKey.self] }
        set { self[OpenURLKey.self] = newValue }
    }

    var webAuthenticationSession: WebAuthenticationSessionAction {
        get { self[WebAuthenticationSessionKey.self] }
        set { self[WebAuthenticationSessionKey.self] = newValue }
    }
}

private final class SwiftUIShimImageDataCache: @unchecked Sendable {
    static let shared = SwiftUIShimImageDataCache()

    private let lock = NSLock()
    private var urlsByContent: [Data: URL] = [:]

    func fileURL(for data: Data) -> URL {
        lock.withLock {
            if let existing = urlsByContent[data],
               FileManager.default.fileExists(atPath: existing.path) {
                return existing
            }

            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("QuillUIImages", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            let url = directory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("png")
            try? data.write(to: url, options: [.atomic])
            urlsByContent[data] = url
            return url
        }
    }
}

public extension Image {
    @_disfavoredOverload
    init(_ name: String, bundle: Bundle? = nil) {
        if let path = QuillResourceLookup.path(
            forResource: name,
            candidateExtensions: QuillResourceLookup.commonImageExtensions,
            in: bundle
        ) {
            self.init(filePath: path)
        } else {
            self.init(resource: name)
        }
    }

    init(_ resource: ImageResource) {
        self.init(resource.name)
    }

    init(nsImage: NSImage) {
        if let data = nsImage.data, !data.isEmpty {
            self.init(filePath: SwiftUIShimImageDataCache.shared.fileURL(for: data).path)
        } else {
            self.init(systemName: "photo")
        }
    }

    init(uiImage: UIImage) {
        if let data = uiImage.data, !data.isEmpty {
            self.init(filePath: SwiftUIShimImageDataCache.shared.fileURL(for: data).path)
        } else {
            self.init(systemName: "photo")
        }
    }
}

public struct DropInfo {
    public init() {}

    public func itemProviders(for contentTypes: [UTType]) -> [NSItemProvider] {
        _ = contentTypes
        return []
    }
}

public enum DropOperation: Sendable {
    case copy
    case move
    case cancel
}

public struct DropProposal: Sendable {
    public var operation: DropOperation

    public init(operation: DropOperation) {
        self.operation = operation
    }
}

public protocol DropDelegate {
    func performDrop(info: DropInfo) -> Bool
}

public extension DropDelegate {
    func performDrop(info: DropInfo) -> Bool {
        _ = info
        return false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        _ = info
        return nil
    }

    func dropEntered(info: DropInfo) {
        _ = info
    }
}

public extension View {
    func keyboardType(_ type: UIKeyboardType) -> KeyboardTypeView<Self, UIKeyboardType> {
        KeyboardTypeView(content: self, keyboardType: type)
    }

    func onDrag(_ data: @escaping () -> NSItemProvider) -> Self {
        _ = data
        return self
    }

    func onDrop(of supportedContentTypes: [UTType], delegate: some DropDelegate) -> Self {
        _ = supportedContentTypes
        _ = delegate
        return self
    }

    @_disfavoredOverload
    func onDrop(
        of supportedContentTypes: [UTType],
        isTargeted: Binding<Bool>? = nil,
        perform action: @escaping ([NSItemProvider]) -> Bool
    ) -> Self {
        _ = supportedContentTypes
        _ = isTargeted
        _ = action
        return self
    }

    func contextMenu<SelectionValue: Hashable>(
        forSelectionType selectionType: SelectionValue.Type,
        @MenuBuilder menu: @escaping (Set<SelectionValue>) -> [MenuElement],
        primaryAction: ((Set<SelectionValue>) -> Void)? = nil
    ) -> ContextMenuView<Self> {
        _ = selectionType
        _ = primaryAction
        return contextMenu {
            menu([])
        }
    }

    func onCopyCommand(_ action: @escaping () -> [NSItemProvider]) -> Self {
        _ = action
        return self
    }

    func onDeleteCommand(perform action: @escaping () -> Void) -> Self {
        _ = action
        return self
    }

}
#endif
