import Foundation
import SwiftOpenUI

// SwiftUI's `OpenURLAction` lives here (rather than in QuillUI) so it is
// visible both to QuillUI — which `@_exported import`s QuillSwiftUICompatibility
// — and to vendored real source via the SwiftUI shim, which re-exports this
// module. Vendored apps (e.g. the IceCubes Router) use the nested `Result` as
// a url-handler return type.
public struct OpenURLAction: Sendable {
    /// The outcome a URL handler reports back to `openURL`. Mirrors SwiftUI's
    /// `OpenURLAction.Result`.
    public struct Result: Sendable {
        enum Kind: Sendable { case handled, discarded, systemAction(URL?) }
        let kind: Kind
        private init(_ kind: Kind) { self.kind = kind }

        /// The handler opened the URL itself.
        public static let handled = Result(.handled)
        /// The handler declined to open the URL.
        public static let discarded = Result(.discarded)
        /// Defer to the system's default handling.
        public static let systemAction = Result(.systemAction(nil))
        /// Defer to the system, opening a (possibly rewritten) URL.
        public static func systemAction(_ url: URL?) -> Result { Result(.systemAction(url)) }
    }

    private let handler: @Sendable (URL) -> Bool

    public init(handler: @escaping @Sendable (URL) -> Bool = OpenURLAction.defaultHandler) {
        self.handler = handler
    }

    @discardableResult
    public func callAsFunction(_ url: URL) -> Bool {
        handler(url)
    }

    public static func defaultHandler(_ url: URL) -> Bool {
        #if os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}
