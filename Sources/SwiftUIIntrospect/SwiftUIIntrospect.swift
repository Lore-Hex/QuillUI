import SwiftUI
import AppKit

public struct macOSVersion: Hashable, Sendable {
    public var rawValue: String
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let v10_15 = macOSVersion("10.15")
    public static let v10_15_4 = macOSVersion("10.15.4")
    public static let v11 = macOSVersion("11")
    public static let v12 = macOSVersion("12")
    public static let v13 = macOSVersion("13")
    public static let v14 = macOSVersion("14")
    public static let v15 = macOSVersion("15")
}

public struct IntrospectionPlatform<Target>: Sendable {
    public var versions: [macOSVersion]

    public init(versions: [macOSVersion]) {
        self.versions = versions
    }

    public static func macOS(_ versions: macOSVersion...) -> IntrospectionPlatform<Target> {
        IntrospectionPlatform(versions: versions)
    }
}

public struct IntrospectionViewType<Target> {
    public init() {}
}

public extension IntrospectionViewType where Target == NSWindow {
    static var window: IntrospectionViewType<NSWindow> { IntrospectionViewType() }
}

public extension IntrospectionViewType where Target == NSScrollView {
    static var scrollView: IntrospectionViewType<NSScrollView> { IntrospectionViewType() }
}

public extension View {
    func introspect<Target>(
        _ type: IntrospectionViewType<Target>,
        on platform: IntrospectionPlatform<Target>,
        perform action: @escaping (Target) -> Void
    ) -> some View {
        _ = (type, platform, action)
        return self
    }

    func introspect<Target>(
        _ type: IntrospectionViewType<Target>,
        on platform: IntrospectionPlatform<Target>,
        scope: Any,
        perform action: @escaping (Target) -> Void
    ) -> some View {
        _ = scope
        return introspect(type, on: platform, perform: action)
    }
}
