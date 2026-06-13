@_exported import QuillFoundation

#if os(Linux)
public let MPMediaItemPropertyTitle = "title"
public let MPMediaItemPropertyPlaybackDuration = "playbackDuration"
public let MPNowPlayingInfoPropertyElapsedPlaybackTime = "elapsedPlaybackTime"

public enum MPRemoteCommandHandlerStatus: Int, Sendable {
    case success
    case noSuchContent
    case noActionableNowPlayingItem
    case deviceNotFound
    case commandFailed
}

open class MPRemoteCommandEvent: NSObject {}

open class MPChangePlaybackPositionCommandEvent: MPRemoteCommandEvent {
    public let positionTime: TimeInterval

    public init(positionTime: TimeInterval = 0) {
        self.positionTime = positionTime
        super.init()
    }
}

@MainActor open class MPRemoteCommand: NSObject {
    public typealias Handler = (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus

    open var isEnabled = false
    private var handlers: [Handler] = []

    @discardableResult
    open func addTarget(handler: @escaping Handler) -> Any {
        handlers.append(handler)
        return handlers.count - 1
    }

    open func removeTarget(_ target: Any?) {
        if target == nil {
            handlers.removeAll()
        }
    }

    @discardableResult
    public func quillPerform(event: MPRemoteCommandEvent = MPRemoteCommandEvent()) -> MPRemoteCommandHandlerStatus {
        handlers.last?(event) ?? .commandFailed
    }
}

@MainActor public final class MPChangePlaybackPositionCommand: MPRemoteCommand {
    @discardableResult
    public func quillPerform(positionTime: TimeInterval) -> MPRemoteCommandHandlerStatus {
        quillPerform(event: MPChangePlaybackPositionCommandEvent(positionTime: positionTime))
    }
}

@MainActor public final class MPRemoteCommandCenter: NSObject {
    private static let sharedCenter = MPRemoteCommandCenter()

    public let playCommand = MPRemoteCommand()
    public let pauseCommand = MPRemoteCommand()
    public let changePlaybackPositionCommand = MPChangePlaybackPositionCommand()

    public static func shared() -> MPRemoteCommandCenter {
        sharedCenter
    }
}

@MainActor public final class MPNowPlayingInfoCenter: NSObject {
    private static let sharedCenter = MPNowPlayingInfoCenter()

    public var nowPlayingInfo: [String: Any]?

    public static func `default`() -> MPNowPlayingInfoCenter {
        sharedCenter
    }
}
#endif
