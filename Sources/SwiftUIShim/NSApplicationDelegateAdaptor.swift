#if os(Linux)
import Foundation
import AppKit

// NSApplicationDelegateAdaptor — Apple ships this in SwiftUI (not AppKit), so
// it lives in the SwiftUI shim, which depends on the AppKit shadow.

/// SwiftUI's `@NSApplicationDelegateAdaptor` property wrapper, with Apple's
/// exact declaration shape: generic over `NSObject & NSApplicationDelegate`,
/// `init(_ delegateType:)` with the type defaulted, and a single shared
/// delegate instance behind `wrappedValue`.
///
/// Instantiation caveat: on Apple platforms the adaptor constructs the
/// delegate via the ObjC runtime. Here `delegateType.init()` cannot compile —
/// swift-corelibs-foundation declares `NSObject.init()` without `required`,
/// so a generic metatype can't be instantiated (the same wall as
/// `NSTableView.dequeueReusableCell`; see `QuillReusableView` in QuillAppKit).
/// The adaptor therefore instantiates the delegate only when the type opts in
/// to `QuillReusableView` (one `required init()` — a future app-lowering pass
/// can add the conformance mechanically), and otherwise records no instance.
/// Reading `wrappedValue` without an instance traps with guidance; apps that
/// declare the adaptor but never read the property — SolderScope's pattern —
/// compile and run. Delegate lifecycle callbacks are wired by the app runner
/// once one exists for this target; the adaptor itself never touches
/// `NSApplication.shared` so it stays initializable from a nonisolated
/// `App.init()` (this declaration intentionally omits Apple's `@MainActor`
/// isolation until the App-lifecycle lowering settles).
@propertyWrapper
public struct NSApplicationDelegateAdaptor<DelegateType> where DelegateType: NSObject, DelegateType: NSApplicationDelegate {
    /// The single delegate instance, when the type could be constructed.
    private let instance: DelegateType?

    /// The delegate type the app registered; preserved so the app runner can
    /// construct/wire the delegate once generic construction is possible.
    let delegateType: DelegateType.Type

    public init(_ delegateType: DelegateType.Type = DelegateType.self) {
        self.delegateType = delegateType
        if let creatable = delegateType as? any QuillReusableView.Type {
            self.instance = creatable.init() as? DelegateType
        } else {
            self.instance = nil
        }
    }

    public var wrappedValue: DelegateType {
        guard let instance else {
            fatalError("""
                @NSApplicationDelegateAdaptor could not construct \
                \(String(describing: delegateType)) on Linux: corelibs \
                NSObject.init() is not `required`, so generic metatype \
                construction is unavailable. Conform the delegate to \
                QuillReusableView (a `required init()`) to opt in, or avoid \
                reading the wrapped delegate property.
                """)
        }
        return instance
    }
}
#endif
