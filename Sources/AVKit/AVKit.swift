import SwiftUI

#if os(Linux)
import AVFoundation

public struct VideoPlayer: View {
    public init(player: AVPlayer?) {}
    public var body: some View { EmptyView() }
}
#endif
