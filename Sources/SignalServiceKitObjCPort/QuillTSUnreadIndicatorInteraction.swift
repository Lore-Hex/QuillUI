//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// TSUnreadIndicatorInteraction.h (DEPRECATED) -- a bare TSInteraction subclass
// that marked the unread boundary in a conversation. It adds no columns; its
// SDS designated initializer is identical to TSInteraction's, so it overrides
// and forwards to super. Only the SDS init has Swift callers.
//
import Foundation

open class TSUnreadIndicatorInteraction: TSInteraction {

    @available(*, unavailable, message: "Use a designated initializer.")
    public required init() {
        fatalError("init() is unavailable for TSUnreadIndicatorInteraction.")
    }

    @available(*, unavailable, message: "TSUnreadIndicatorInteraction is not NSCoder-archived.")
    public required init?(coder: NSCoder) {
        fatalError("init?(coder:) is unavailable for TSUnreadIndicatorInteraction.")
    }

    public override init(grdbId: Int64,
                         uniqueId: String,
                         receivedAtTimestamp: UInt64,
                         sortId: UInt64,
                         timestamp: UInt64,
                         uniqueThreadId: String) {
        super.init(grdbId: grdbId,
                   uniqueId: uniqueId,
                   receivedAtTimestamp: receivedAtTimestamp,
                   sortId: sortId,
                   timestamp: timestamp,
                   uniqueThreadId: uniqueThreadId)
    }
}
