//
// QuillUI Linux shim for `notify` (Darwin libnotify / notify.h). Absent on
// Linux: there is no cross-process Darwin notification bus. SSK's
// DarwinNotificationCenter uses it, so these are inert -- registration hands back
// a non-invalid token and the handler is never invoked; post/state are no-ops.
// notify_status_t is UInt32 (0 == NOTIFY_STATUS_OK). Part of the
// Signal-iOS -> QuillOS port.
//
import Foundation
import Dispatch

public let NOTIFY_STATUS_OK: UInt32 = 0
public let NOTIFY_TOKEN_INVALID: Int32 = -1

@discardableResult
public func notify_post(_ name: UnsafePointer<CChar>!) -> UInt32 {
    _ = name
    return NOTIFY_STATUS_OK
}

@discardableResult
public func notify_register_dispatch(_ name: UnsafePointer<CChar>!,
                                     _ out_token: UnsafeMutablePointer<Int32>!,
                                     _ queue: DispatchQueue,
                                     _ handler: @escaping (Int32) -> Void) -> UInt32 {
    // Inert: no Darwin notification bus on Linux. Hand back a non-invalid token;
    // the handler is never invoked.
    _ = (name, queue, handler)
    out_token?.pointee = 1
    return NOTIFY_STATUS_OK
}

@discardableResult
public func notify_cancel(_ token: Int32) -> UInt32 {
    _ = token
    return NOTIFY_STATUS_OK
}

@discardableResult
public func notify_get_state(_ token: Int32, _ state64: UnsafeMutablePointer<UInt64>!) -> UInt32 {
    _ = token
    state64?.pointee = 0
    return NOTIFY_STATUS_OK
}

public func notify_is_valid_token(_ token: Int32) -> Bool {
    token != NOTIFY_TOKEN_INVALID
}
