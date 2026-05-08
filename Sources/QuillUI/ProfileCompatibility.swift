import Foundation
import QuillKit

#if os(macOS) || os(iOS) || os(visionOS)
import SwiftUI
#else
import SwiftOpenUI

public extension View {
    func addCustomHotkeys(_ hotkeys: [QuillHotkeyCombination]) -> Self {
        self
    }
}

public struct Window<Content: View>: Scene {
    public typealias Body = Never

    public let title: String
    public let id: String
    public let content: Content

    public init(_ title: String, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.content = content()
    }

    public var body: Never {
        fatalError("Window is a Linux source-compatibility scene placeholder")
    }
}

public struct QuillCheckForUpdatesMenuItem: View {
    public init() {}

    public var body: some View {
        Button("Check for Updates...") {
            QuillUpdateService.shared.checkForUpdates()
        }
        .disabled(!QuillUpdateService.shared.canCheckForUpdates)
    }
}
#endif
