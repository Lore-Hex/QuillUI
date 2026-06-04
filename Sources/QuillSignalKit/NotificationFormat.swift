//
// QuillSignalKit — desktop-notification text for an incoming message.
//
// Pure (no I/O) so it is unit-tested directly; the app feeds the result to
// `notify-send`. Own messages and empty bodies produce no notification.
//
import Foundation

public enum NotificationFormat {
    /// Build the (title, body) for a desktop notification, or nil if none should
    /// be shown. No notification for own messages (`fromSelf == true`) or an
    /// empty/missing body. The title is the sender's display name when non-empty,
    /// else "Signal".
    public static func make(
        sender displayName: String?,
        body: String?,
        fromSelf: Bool?
    ) -> (title: String, body: String)? {
        if fromSelf == true { return nil }
        guard let body = body, !body.isEmpty else { return nil }
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (name?.isEmpty == false) ? name! : "Signal"
        return (title, body)
    }
}
