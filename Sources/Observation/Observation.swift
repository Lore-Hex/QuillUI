import Foundation

#if os(Linux)
@_exported import Combine

@attached(member)
@attached(memberAttribute)
@attached(extension, conformances: Observable)
public macro Observable() = #externalMacro(module: "QuillDataMacros", type: "QuillObservableMacro")

@attached(peer)
public macro ObservationIgnored() = #externalMacro(module: "QuillDataMacros", type: "QuillAttributeMacro")

public protocol Observable: ObservableObject {}

@discardableResult
public func withObservationTracking<T>(
    _ apply: () throws -> T,
    onChange: @escaping @Sendable () -> Void
) rethrows -> T {
    _ = onChange
    return try apply()
}
#endif
