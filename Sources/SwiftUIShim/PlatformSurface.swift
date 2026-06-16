import AuthenticationServices
import CoreTransferable
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

@propertyWrapper
public struct UIApplicationDelegateAdaptor<Delegate> {
    private var value: Delegate?

    public init() {
        value = nil
    }

    public var wrappedValue: Delegate {
        get {
            guard let value else {
                fatalError("UIApplicationDelegateAdaptor has no Linux runtime delegate instance.")
            }
            return value
        }
        set { value = newValue }
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

public extension Image {
    init(uiImage: UIImage) {
        _ = uiImage
        self.init(systemName: "photo")
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

    func fileImporter(
        isPresented: Binding<Bool>,
        allowedContentTypes: [UTType],
        allowsMultipleSelection: Bool = false,
        onCompletion: @escaping (Result<[URL], Error>) -> Void
    ) -> Self {
        _ = isPresented
        _ = allowedContentTypes
        _ = allowsMultipleSelection
        _ = onCompletion
        return self
    }
}
#endif
