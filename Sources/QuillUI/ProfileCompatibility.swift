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

// `Window` is provided by SwiftOpenUI on Linux (already re-
// exported by QuillUI via `@_exported import SwiftOpenUI`).
// A duplicate stub here caused "ambiguous use of
// 'init(_:id:content:)'" in generated Enchanted source. Drop
// it and rely on SwiftOpenUI's complete implementation.

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
