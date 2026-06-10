import SwiftUI

#if os(Linux)
@_exported import AVFoundation

public struct VideoPlayer: View {
    public init(player: AVPlayer?) {
        _ = player
    }

    public init<VideoOverlay: View>(
        player: AVPlayer?,
        @ViewBuilder videoOverlay: () -> VideoOverlay
    ) {
        _ = player
        _ = videoOverlay()
    }

    public var body: some View { EmptyView() }
}
#endif
