// QuillCascadeStubs.swift — AUTO-GENERATED (cumulative).
import Foundation
import Photos
import UIKit
import SignalServiceKit
import SignalUI

struct ApplePayButton { }
struct AttachmentKeyboard { }
protocol AttachmentKeyboardDelegate: AnyObject { }
enum BadgeIssueSheetAction {
    case dismiss
    case openDonationView
}
protocol BadgeIssueSheetDelegate: AnyObject { }
struct BadgeIssueSheetState { }
struct CVComponentGenericAttachment { }
class ChatHistoryContextMenuInteraction: ContextMenuInteraction {
    let itemViewModel: CVItemViewModelImpl
    let thread: TSThread
    let messageActions: [MessageAction]
    let keyboardWasActive: Bool
    var contextMenuVisible = false

    init(
        delegate: ContextMenuInteractionDelegate,
        itemViewModel: CVItemViewModelImpl,
        thread: TSThread,
        messageActions: [MessageAction],
        initiatingGestureRecognizer: UIGestureRecognizer,
        keyboardWasActive: Bool
    ) {
        self.itemViewModel = itemViewModel
        self.thread = thread
        self.messageActions = messageActions
        self.keyboardWasActive = keyboardWasActive
        _ = initiatingGestureRecognizer
        super.init(delegate: delegate)
    }

    func initiateContextMenuGesture(locationInView: CGPoint, presentImmediately: Bool) {
        _ = locationInView
        contextMenuVisible = presentImmediately
    }

    func cancelPresentationGesture() {
        contextMenuVisible = false
    }

    func dismissMenu(animated: Bool, completion: @escaping () -> Void) {
        _ = animated
        contextMenuVisible = false
        completion()
    }
}

class ContactShareViewHelper {
    weak var delegate: ContactShareViewHelperDelegate?

    func sendMessage(to phoneNumbers: [String], from viewController: UIViewController) {
        _ = phoneNumbers
        _ = viewController
    }

    func audioCall(to phoneNumbers: [String], from viewController: UIViewController) {
        _ = phoneNumbers
        _ = viewController
    }

    func videoCall(to phoneNumbers: [String], from viewController: UIViewController) {
        _ = phoneNumbers
        _ = viewController
    }

    func showInviteContact(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        _ = contactShare
        _ = viewController
    }

    func showAddToContactsPrompt(contactShare: ContactShareViewModel, from viewController: UIViewController) {
        _ = contactShare
        _ = viewController
    }
}
protocol ContactShareViewHelperDelegate: AnyObject { }
class ContextMenuAction {
    struct Attributes: OptionSet {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }

        static let destructive = Attributes(rawValue: 1 << 0)
        static let disabled = Attributes(rawValue: 1 << 1)
    }

    let title: String
    let image: UIImage?
    let attributes: Attributes
    let handler: (ContextMenuAction) -> Void

    init(
        title: String,
        image: UIImage?,
        attributes: Attributes = [],
        handler: @escaping (ContextMenuAction) -> Void
    ) {
        self.title = title
        self.image = image
        self.attributes = attributes
        self.handler = handler
    }
}

class ContextMenu {
    let actions: [ContextMenuAction]

    init(_ actions: [ContextMenuAction]) {
        self.actions = actions
    }
}

class ContextMenuConfiguration {
    typealias ActionProvider = ([ContextMenuAction]) -> ContextMenu?

    let identifier: NSCopying?
    let actionProvider: ActionProvider

    init(identifier: NSCopying?, actionProvider: @escaping ActionProvider) {
        self.identifier = identifier
        self.actionProvider = actionProvider
    }
}

class ContextMenuInteraction: NSObject, UIInteraction {
    weak var view: UIView?
    weak var delegate: ContextMenuInteractionDelegate?

    init(delegate: ContextMenuInteractionDelegate?) {
        self.delegate = delegate
        super.init()
    }
}

protocol ContextMenuInteractionDelegate: AnyObject {
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> ContextMenuConfiguration?

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration
    ) -> ContextMenuTargetedPreview?

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        willDisplayMenuForConfiguration configuration: ContextMenuConfiguration
    )

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        willEndForConfiguration configuration: ContextMenuConfiguration
    )

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        didEndForConfiguration configuration: ContextMenuConfiguration
    )
}

extension ContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> ContextMenuConfiguration? {
        _ = interaction
        _ = location
        return nil
    }

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: ContextMenuConfiguration
    ) -> ContextMenuTargetedPreview? {
        _ = interaction
        _ = configuration
        return nil
    }

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        willDisplayMenuForConfiguration configuration: ContextMenuConfiguration
    ) {
        _ = interaction
        _ = configuration
    }

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        willEndForConfiguration configuration: ContextMenuConfiguration
    ) {
        _ = interaction
        _ = configuration
    }

    func contextMenuInteraction(
        _ interaction: ContextMenuInteraction,
        didEndForConfiguration configuration: ContextMenuConfiguration
    ) {
        _ = interaction
        _ = configuration
    }
}

class ContextMenuTargetedPreview {
    enum Alignment {
        case center
        case left
        case right
    }

    let view: UIView
    let alignment: Alignment
    let accessoryViews: [ContextMenuTargetedPreviewAccessory]
    var auxiliaryView: UIView?

    init?(
        view: UIView,
        alignment: Alignment = .center,
        accessoryViews: [ContextMenuTargetedPreviewAccessory] = []
    ) {
        self.view = view
        self.alignment = alignment
        self.accessoryViews = accessoryViews
    }
}

class ContextMenuTargetedPreviewAccessory {
    struct AccessoryAlignment {
        enum Edge {
            case leading
            case trailing
            case top
            case bottom
        }

        enum Attachment {
            case interior
            case exterior
        }

        let alignments: [(Edge, Attachment)]
        let alignmentOffset: CGPoint

        init(alignments: [(Edge, Attachment)], alignmentOffset: CGPoint = .zero) {
            self.alignments = alignments
            self.alignmentOffset = alignmentOffset
        }
    }

    let accessoryView: UIView
    let accessoryAlignment: AccessoryAlignment
    var animateAccessoryPresentationAlongsidePreview = false

    init(accessoryView: UIView, accessoryAlignment: AccessoryAlignment) {
        self.accessoryView = accessoryView
        self.accessoryAlignment = accessoryAlignment
    }
}

class ContextMenuReactionBarAccessory: ContextMenuTargetedPreviewAccessory {
    var didSelectReactionHandler: ((TSMessage, String, Bool) -> Void)?

    init(thread: TSThread, itemViewModel: CVItemViewModelImpl) {
        _ = thread
        _ = itemViewModel
        super.init(
            accessoryView: UIView(),
            accessoryAlignment: AccessoryAlignment(alignments: [(.bottom, .interior)])
        )
    }
}

enum ConversationSettingsPresentationMode {
    case `default`
    case showAllMedia
    case showMemberRequests
    case showVerification
}
protocol ConversationSettingsViewDelegate: AnyObject { }
class DonationSettingsViewController: UIViewController { }
enum Emoji: String {
    case angry = "😠"
    case neutralFace = "😐"
    case slightlyFrowningFace = "🙁"
    case slightlySmilingFace = "🙂"
    case smiley = "😃"
}
struct EmojiPickerSheet { }
class GroupDescriptionPreviewView: UIView {
    var descriptionText: String?
    var groupName: String?
    var font: UIFont?
    var textColor: UIColor?
}
class GroupDescriptionViewController: UIViewController { }
protocol GroupDescriptionViewControllerDelegate: AnyObject { }
class GroupViewHelper {
    weak var delegate: GroupViewHelperDelegate?

    init(threadViewModel: ThreadViewModel, memberLabelCoordinator: MemberLabelCoordinator?) {
        _ = threadViewModel
        _ = memberLabelCoordinator
    }
}
protocol GroupViewHelperDelegate: AnyObject { }
enum Media {
    struct GalleryItem {
        let message: TSMessage
        let referencedAttachment: ReferencedAttachment
    }

    case gallery(GalleryItem)
}

struct RoundedCorners {
    var topLeft: CGFloat
    var topRight: CGFloat
    var bottomLeft: CGFloat
    var bottomRight: CGFloat

    static func all(_ radius: CGFloat) -> RoundedCorners {
        RoundedCorners(topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius)
    }

    var isAllCornerRadiiEqual: Bool {
        topLeft == topRight && topLeft == bottomLeft && topLeft == bottomRight
    }
}

enum MediaViewShape {
    case rectangle(CGFloat)
    case variableRoundedCorners(RoundedCorners)
}

struct MediaPresentationContext {
    static let animationDuration: TimeInterval = 0.2

    let mediaView: UIView
    let presentationFrame: CGRect
    let mediaViewShape: MediaViewShape
    let clippingAreaInsets: UIEdgeInsets
    var mediaOverlayViews: [UIView] = []

    init(
        mediaView: UIView,
        presentationFrame: CGRect,
        mediaViewShape: MediaViewShape = .rectangle(0),
        clippingAreaInsets: UIEdgeInsets
    ) {
        self.mediaView = mediaView
        self.presentationFrame = presentationFrame
        self.mediaViewShape = mediaViewShape
        self.clippingAreaInsets = clippingAreaInsets
    }
}
protocol MediaPresentationContextProvider: AnyObject { }
class MessageDetailViewController: UIViewController { }
protocol MessageDetailViewDelegate: AnyObject { }
struct MessageReactionPicker { }
protocol MessageReactionPickerDelegate: AnyObject { }
protocol MockConversationDelegate: AnyObject { }
class MockConversationView: UIView {
    struct MockModel {
        enum Item {
            case date
            case incoming(text: String)
            case outgoing(text: String)
        }

        var items: [Item]
    }

    var model: MockModel?
    var customChatColor: ColorOrGradientSetting?
    var hasWallpaper = false
    weak var delegate: MockConversationDelegate?

    init(model: MockModel, hasWallpaper: Bool = false, customChatColor: ColorOrGradientSetting?) {
        self.model = model
        self.hasWallpaper = hasWallpaper
        self.customChatColor = customChatColor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
struct MockIncomingMessage { }
struct MockOutgoingMessage { }
protocol NameCollisionResolutionDelegate: AnyObject { }
class NameCollisionResolutionViewController: UIViewController { }
struct OsExpiry {
    var enforcedAfter: Date
    var minimumIosMajorVersion: Int
}
struct PaymentsHistoryItem { }
struct PaypalButton { }
protocol PollSendDelegate: AnyObject { }
enum SafetyTipsType {
    case contact
    case group
}
protocol SendMediaNavDataSource: AnyObject { }
protocol SendMediaNavDelegate: AnyObject { }
class SendMediaNavigationController: OWSNavigationController {
    weak var sendMediaNavDelegate: SendMediaNavDelegate?
    weak var sendMediaNavDataSource: SendMediaNavDataSource?
    let attachmentLimits: OutgoingAttachmentLimits

    init(attachmentLimits: OutgoingAttachmentLimits) {
        self.attachmentLimits = attachmentLimits
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    static func showingApprovalWithPickedLibraryMedia(
        asset: PHAsset,
        attachment: PreviewableAttachment,
        hasQuotedReplyDraft: Bool,
        attachmentLimits: OutgoingAttachmentLimits,
        delegate: SendMediaNavDelegate?,
        dataSource: SendMediaNavDataSource?
    ) -> SendMediaNavigationController {
        _ = asset
        _ = attachment
        _ = hasQuotedReplyDraft
        let controller = SendMediaNavigationController(attachmentLimits: attachmentLimits)
        controller.sendMediaNavDelegate = delegate
        controller.sendMediaNavDataSource = dataSource
        return controller
    }

    static func showingCameraFirst(
        hasQuotedReplyDraft: Bool,
        attachmentLimits: OutgoingAttachmentLimits
    ) -> SendMediaNavigationController {
        _ = hasQuotedReplyDraft
        return SendMediaNavigationController(attachmentLimits: attachmentLimits)
    }

    static func showingNativePicker(
        hasQuotedReplyDraft: Bool,
        attachmentLimits: OutgoingAttachmentLimits
    ) -> SendMediaNavigationController {
        _ = hasQuotedReplyDraft
        return SendMediaNavigationController(attachmentLimits: attachmentLimits)
    }
}
protocol SendPaymentViewDelegate: AnyObject { }
struct ShareableAttachment { }
protocol ThreadContextualActionProvider: AnyObject { }
extension ThreadContextualActionProvider {
    func deleteThreadWithConfirmation(_ thread: TSThread, fromViewController: UIViewController, completion: (() -> Void)? = nil) {
        _ = thread
        _ = fromViewController
        completion?()
    }

    func toggleThreadIsArchived(_ thread: TSThread, fromViewController: UIViewController) {
        _ = thread
        _ = fromViewController
    }
}
struct UpgradableDevice {
    var iosMajorVersion: Int

    func canUpgrade(to minimumIosMajorVersion: Int) -> Bool {
        iosMajorVersion < minimumIosMajorVersion
    }
}

struct ViewControllerContext {
    static var shared: ViewControllerContext {
        ViewControllerContext(
            db: SSKEnvironment.shared.databaseStorageRef,
            editManager: DependenciesBridge.shared.editManager
        )
    }

    let db: any DB
    let editManager: EditManager
}

private var quillMessageActionAccessibilityLabels: [ObjectIdentifier: String] = [:]

extension MessageAction {
    var accessibilityLabel: String? {
        get { quillMessageActionAccessibilityLabels[ObjectIdentifier(self)] }
        set { quillMessageActionAccessibilityLabels[ObjectIdentifier(self)] = newValue }
    }
}
