#if os(macOS) || os(iOS) || os(visionOS)
@_exported import SwiftUI
@_exported import Combine
public typealias ButtonStyleConfiguration = SwiftUI.ButtonStyle.Configuration
#else
@_exported import SwiftOpenUI

public typealias QuillObservableObject = SwiftOpenUI.ObservableObject
public typealias QuillPublished = SwiftOpenUI.Published
// ButtonStyleConfiguration is defined locally in UpstreamCompatibility.swift
// for Linux — SwiftOpenUI doesn't ship one.
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

// `MainActor.assumeIsolated` requires a Sendable result on newer
// toolchains, but SwiftUI / SwiftOpenUI view values are intentionally
// not Sendable. Keep the unchecked conformance private and expose only
// the typed view helper below.
private struct QuillUncheckedSendableView<Content: View>: @unchecked Sendable {
    let content: Content
}

public enum QuillMainActorView {
    public static func assumeIsolated<Content: View>(_ content: @MainActor () -> Content) -> Content {
        MainActor.assumeIsolated {
            QuillUncheckedSendableView(content: content())
        }.content
    }
}
