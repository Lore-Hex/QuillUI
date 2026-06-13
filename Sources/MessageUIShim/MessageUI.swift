// MessageUI Linux shim. Re-export QuillFoundation/QuillUIKit instead of
// QuillShims to avoid the QuillShims→MessageUI→QuillShims cycle.
@_exported import QuillFoundation
@_exported import QuillUIKit

#if os(Linux)
@MainActor public protocol MFMessageComposeViewControllerDelegate: AnyObject {
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult)
}

public enum MessageComposeResult: Int, Sendable {
    case cancelled
    case sent
    case failed
}

@MainActor open class MFMessageComposeViewController: UIViewController {
    open weak var messageComposeDelegate: MFMessageComposeViewControllerDelegate?
    open var recipients: [String]?
    open var body: String?

    public static func canSendText() -> Bool { false }
}

@MainActor public protocol MFMailComposeViewControllerDelegate: AnyObject {
    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    )
}

public enum MFMailComposeResult: Int, Sendable {
    case cancelled
    case saved
    case sent
    case failed
}

@MainActor open class MFMailComposeViewController: UIViewController {
    open weak var mailComposeDelegate: MFMailComposeViewControllerDelegate?
    open private(set) var bccRecipients: [String]?
    open private(set) var subject: String = ""
    open private(set) var messageBody: String = ""
    open private(set) var messageBodyIsHTML: Bool = false

    public static func canSendMail() -> Bool { false }

    open func setBccRecipients(_ recipients: [String]?) {
        bccRecipients = recipients
    }

    open func setSubject(_ subject: String) {
        self.subject = subject
    }

    open func setMessageBody(_ body: String, isHTML: Bool) {
        messageBody = body
        messageBodyIsHTML = isHTML
    }
}
#endif
