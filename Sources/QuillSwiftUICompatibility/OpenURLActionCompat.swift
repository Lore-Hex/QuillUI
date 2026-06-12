import Foundation
import SwiftOpenUI

// SwiftUI's `OpenURLAction` lives here (rather than in QuillUI) so it is
// visible both to QuillUI — which `@_exported import`s QuillSwiftUICompatibility
// — and to vendored real source via the SwiftUI shim, which re-exports this
// module. Vendored apps (e.g. the IceCubes Router) use the nested `Result` as
// a url-handler return type.
public struct OpenURLAction: @unchecked Sendable {
    /// The outcome a URL handler reports back to `openURL`. Mirrors SwiftUI's
    /// `OpenURLAction.Result`.
    public struct Result: Sendable, Equatable {
        enum Kind: Sendable, Equatable { case handled, discarded, systemAction(URL?) }
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

    private let handler: @MainActor (URL) -> Result

    public init(handler: @escaping @MainActor (URL) -> Result = OpenURLAction.defaultHandler) {
        self.handler = handler
    }

    public init(handler: @escaping @MainActor (URL) -> Bool) {
        self.handler = { url in handler(url) ? .handled : .discarded }
    }

    @discardableResult
    @MainActor
    public func callAsFunction(_ url: URL) -> Result {
        handler(url)
    }

    @MainActor
    public static func defaultHandler(_ url: URL) -> Result {
        #if os(Linux)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
        process.arguments = [url.absoluteString]
        do {
            try process.run()
            return .handled
        } catch {
            return .discarded
        }
        #else
        return .discarded
        #endif
    }
}
