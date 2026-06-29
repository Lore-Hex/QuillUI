import Foundation

#if os(Linux)
#if !QUILLUI_NO_OBSERVATION_MACROS
@attached(member)
public macro Observable() = #externalMacro(module: "QuillDataMacros", type: "QuillObservableMacro")

@attached(peer)
public macro ObservationIgnored() = #externalMacro(module: "QuillDataMacros", type: "QuillAttributeMacro")
#endif

public protocol Observable {}

@discardableResult
public func withObservationTracking<T>(
    _ apply: () throws -> T,
    onChange: @escaping @Sendable () -> Void
) rethrows -> T {
    _ = onChange
    return try apply()
}
#endif
