#if os(macOS) || os(iOS) || os(visionOS)
@_exported import SwiftUI
@_exported import Combine
#else
@_exported import SwiftOpenUI

public typealias QuillObservableObject = SwiftOpenUI.ObservableObject
public typealias QuillPublished = SwiftOpenUI.Published
#endif

import Foundation

public enum QuillPlatform {
    #if os(Linux)
    public static let name = "Linux"
    #elseif os(macOS)
    public static let name = "macOS"
    #elseif os(iOS)
    public static let name = "iOS"
    #else
    public static let name = "Unknown"
    #endif
}

public enum QuillUIVersion {
    public static let current = "0.1.0"
}
