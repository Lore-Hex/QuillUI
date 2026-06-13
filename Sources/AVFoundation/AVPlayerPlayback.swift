// AVPlayer / AVPlayerItem playback-control surface -- the members SignalUI's
// AV layer drives (SignalUI/AV/AudioPlayer.swift + VideoPlayer.swift): rate,
// volume, currentTime(), playImmediately(atRate:), timeControlStatus, the
// tolerance seek, AVPlayerItem(asset:)/asset/duration/currentTime(), and
// AVPlayerItem.didPlayToEndTimeNotification.
//
// HONEST STATUS: playback is INERT on Linux (no AV backend yet -- same posture
// as the asset machinery in AVFoundation.swift). `rate`/`volume` round-trip
// (Signal saves and restores them across mute/scrub) but drive no audio or
// video; times report zero. Real playback needs a GStreamer/FFmpeg backend.
//
// AVPlayer/AVPlayerItem are final classes declared in AVFoundation.swift (a
// file other surfaces own), so the new members live in extensions here, with
// the stored state in an identity-keyed side table. Side-table entries hold a
// weak back-reference so a recycled allocation address can never inherit a
// previous player's state, and dead entries are swept on insertion.

import Foundation
import CoreMedia

#if os(Linux)

private final class AVPlayerSideState {
    weak var owner: AnyObject?
    var rate: Float = 0
    var volume: Float = 1
    init(owner: AnyObject) { self.owner = owner }
}

private final class AVPlayerItemSideState {
    weak var owner: AnyObject?
    var asset: AVAsset?
    init(owner: AnyObject) { self.owner = owner }
}

private final class AVPlaybackSideTables: @unchecked Sendable {
    static let shared = AVPlaybackSideTables()

    private let lock = NSLock()
    private var players: [ObjectIdentifier: AVPlayerSideState] = [:]
    private var items: [ObjectIdentifier: AVPlayerItemSideState] = [:]

    func state(for player: AVPlayer) -> AVPlayerSideState {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(player)
        if let existing = players[id], existing.owner === player {
            return existing
        }
        sweepLocked()
        let fresh = AVPlayerSideState(owner: player)
        players[id] = fresh
        return fresh
    }

    func state(for item: AVPlayerItem) -> AVPlayerItemSideState {
        lock.lock()
        defer { lock.unlock() }
        let id = ObjectIdentifier(item)
        if let existing = items[id], existing.owner === item {
            return existing
        }
        sweepLocked()
        let fresh = AVPlayerItemSideState(owner: item)
        items[id] = fresh
        return fresh
    }

    private func sweepLocked() {
        players = players.filter { $0.value.owner != nil }
        items = items.filter { $0.value.owner != nil }
    }
}

extension AVPlayer {
    public convenience init(playerItem item: AVPlayerItem?) {
        self.init()
        self.currentItem = item
    }

    /// Playback rate (0 = paused, 1 = normal speed). Round-trips but is inert.
    public var rate: Float {
        get { AVPlaybackSideTables.shared.state(for: self).rate }
        set { AVPlaybackSideTables.shared.state(for: self).rate = newValue }
    }

    /// Output volume (0...1). Round-trips but is inert.
    public var volume: Float {
        get { AVPlaybackSideTables.shared.state(for: self).volume }
        set { AVPlaybackSideTables.shared.state(for: self).volume = newValue }
    }

    public func currentTime() -> CMTime {
        currentItem?.currentTime() ?? .zero
    }

    public func playImmediately(atRate rate: Float) {
        self.rate = rate
    }

    public func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime) {
        _ = (toleranceBefore, toleranceAfter)
        seek(to: time)
    }

    @discardableResult
    public func addPeriodicTimeObserver(
        forInterval interval: CMTime,
        queue: DispatchQueue?,
        using block: @escaping (CMTime) -> Void
    ) -> Any {
        _ = (interval, queue, block)
        return UUID()
    }

    public func removeTimeObserver(_ observer: Any) {
        _ = observer
    }

    public enum TimeControlStatus: Int, Sendable {
        case paused
        case waitingToPlayAtSpecifiedRate
        case playing
    }

    /// Derived from `rate`, mirroring the real player's steady states (the
    /// waiting state never occurs -- nothing buffers on Linux).
    public var timeControlStatus: TimeControlStatus {
        rate == 0 ? .paused : .playing
    }
}

extension AVPlayerItem {
    public convenience init(asset: AVAsset) {
        self.init(url: (asset as? AVURLAsset)?.url)
        AVPlaybackSideTables.shared.state(for: self).asset = asset
    }

    public convenience init(asset: AVAsset, automaticallyLoadedAssetKeys: [String]?) {
        self.init(asset: asset)
        _ = automaticallyLoadedAssetKeys
    }

    /// The asset this item was created from. Items created via `init(url:)`
    /// lazily wrap their URL in an AVURLAsset (cached for identity stability).
    public var asset: AVAsset {
        let state = AVPlaybackSideTables.shared.state(for: self)
        if let existing = state.asset {
            return existing
        }
        let made: AVAsset = url.map { AVURLAsset(url: $0) } ?? AVAsset()
        state.asset = made
        return made
    }

    /// Inert: assets report zero duration on Linux (see AVAsset).
    public var duration: CMTime { asset.duration }

    /// Inert: nothing plays, so the playhead stays at zero.
    public func currentTime() -> CMTime { .zero }

    public static var didPlayToEndTimeNotification: Notification.Name {
        .AVPlayerItemDidPlayToEndTime
    }
}

#endif
