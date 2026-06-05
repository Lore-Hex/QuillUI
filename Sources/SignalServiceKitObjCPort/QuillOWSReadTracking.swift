//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// Faithful Swift port of Messages/OWSReadTracking.h (ObjC, excluded on Linux):
// the OWSReceiptCircumstance enum and the OWSReadTracking protocol, conformed by
// the read-tracking interactions (TSErrorMessage, TSInfoMessage, TSIncomingMessage,
// TSCall, ...).
//
import Foundation

public enum OWSReceiptCircumstance: Int {
    case onLinkedDevice = 0
    case onLinkedDeviceWhilePendingMessageRequest = 1
    case onThisDevice = 2
    case onThisDeviceWhilePendingMessageRequest = 3
}

/// Some interactions track read/unread status (incoming messages, call
/// notifications, error messages, ...).
public protocol OWSReadTracking: NSObjectProtocol {

    /// Has the local user seen the interaction? (ObjC: `read`, getter `wasRead`.)
    var wasRead: Bool { get }

    var uniqueId: String { get }
    var expireStartedAt: UInt64 { get }
    var sortId: UInt64 { get }
    var uniqueThreadId: String { get }

    /// Used both for responding to a remote read receipt and for local activity.
    func markAsRead(atTimestamp readTimestamp: UInt64,
                    thread: TSThread,
                    circumstance: OWSReceiptCircumstance,
                    shouldClearNotifications: Bool,
                    transaction: DBWriteTransaction)
}
