// CMTime operator/Comparable surface -- on Apple the CoreMedia Swift overlay
// gives CMTime `+`/`-` operators and Comparable conformance; SignalUI's
// VideoPlayer relies on both (`avPlayer.currentTime() - CMTime(...)`,
// `max(time, .zero)` / `min(boundedTime, duration)` when bounding a seek).
// Delegates to the existing CMTimeAdd/CMTimeSubtract/CMTimeCompare in
// CoreMedia.swift so there is one arithmetic implementation.

extension CMTime {
    public static func + (lhs: CMTime, rhs: CMTime) -> CMTime {
        CMTimeAdd(lhs, rhs)
    }

    public static func - (lhs: CMTime, rhs: CMTime) -> CMTime {
        CMTimeSubtract(lhs, rhs)
    }
}

extension CMTime: Comparable {
    public static func < (lhs: CMTime, rhs: CMTime) -> Bool {
        CMTimeCompare(lhs, rhs) < 0
    }
}
