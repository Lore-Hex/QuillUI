// QuillCascadeStubs.swift — AUTO-GENERATED (cumulative).
public import Foundation
public import Photos
public import UIKit
public import LibSignalClient
public import SignalServiceKit
public import SignalUI

struct ApplePayButton { }
class AttachmentKeyboard: UIInputView {
    weak var delegate: AttachmentKeyboardDelegate?

    init() {
        super.init(frame: .zero, inputViewStyle: .keyboard)
    }

    init(delegate: AttachmentKeyboardDelegate?) {
        self.delegate = delegate
        super.init(frame: .zero, inputViewStyle: .keyboard)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}
protocol AttachmentKeyboardDelegate: AnyObject { }
enum BadgeIssueSheetAction {
    case dismiss
    case openDonationView
}
protocol BadgeIssueSheetDelegate: AnyObject { }
struct BadgeIssueSheetState {
    enum Mode {
        case giftBadgeExpired(hasCurrentSubscription: Bool)
        case giftNotRedeemed(fullName: String)
    }
}
class BadgeIssueSheet: UIViewController {
    weak var delegate: BadgeIssueSheetDelegate?

    init(badge: ProfileBadge, mode: BadgeIssueSheetState.Mode) {
        _ = (badge, mode)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
class BadgeGiftingThanksSheet: UIViewController {
    init(thread: TSContactThread, badge: ProfileBadge) {
        _ = (thread, badge)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
class BadgeGiftingAlreadyRedeemedSheet: UIViewController {
    init(badge: ProfileBadge, shortName: String) {
        _ = (badge, shortName)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
class BadgeThanksSheet: UIViewController {
    enum ThanksType {
        case giftReceived(shortName: String, notNowAction: () -> Void, incomingMessage: TSIncomingMessage)
    }

    init(newBadge: ProfileBadge, thanksType: ThanksType, oldBadgesSnapshot: ProfileBadgesSnapshot) {
        _ = (newBadge, thanksType, oldBadgesSnapshot)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
enum BadgeThanksSheetPresenter {
    static func fromGlobalsWithSneakyTransaction(successMode: DonationReceiptCredentialResultStore.Mode) -> BadgeThanksSheetPresenter? {
        _ = successMode
        return nil
    }

    func presentAndRecordBadgeThanks(
        from viewController: UIViewController,
        animateNavChanges: Bool,
        completion: @escaping () -> Void
    ) {
        _ = (viewController, animateNavChanges)
        completion()
    }

    func presentAndRecordBadgeThanks(fromViewController viewController: UIViewController) async {
        _ = viewController
    }
}
final class CVEmptyComponentView: NSObject, CVComponentView {
    let rootView = UIView()
    var isDedicatedCellView = false
    func setIsCellVisible(_ isCellVisible: Bool) { _ = isCellVisible }
    func reset() {}
}
class CVComponentGenericAttachment: CVComponentBase, CVComponent {
    let genericAttachment: CVComponentState.GenericAttachment
    var componentKey: CVComponentKey { .genericAttachment }

    init(itemModel: CVItemModel, genericAttachment: CVComponentState.GenericAttachment) {
        self.genericAttachment = genericAttachment
        super.init(itemModel: itemModel)
    }

    func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVEmptyComponentView()
    }

    func configureForRendering(
        componentView: CVComponentView,
        cellMeasurement: CVCellMeasurement,
        componentDelegate: CVComponentDelegate,
    ) {}

    func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        _ = (maxWidth, measurementBuilder)
        return .zero
    }
}
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

    init?(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }
}
class EmojiPickerSheet: UIViewController {
    init(message: String?, allowReactionConfiguration: Bool, completion: @escaping (Emoji?) -> Void) {
        _ = (message, allowReactionConfiguration, completion)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
class GroupDescriptionPreviewView: UIView {
    var descriptionText: String?
    var groupName: String?
    var font: UIFont?
    var textColor: UIColor?
    var textAlignment: NSTextAlignment = .natural
    var numberOfLines: Int = 0

    init(shouldDeactivateConstraints: Bool = false) {
        _ = shouldDeactivateConstraints
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(config: CVLabelConfig) {
        descriptionText = String(describing: config.text)
        font = config.font
        textColor = config.textColor
        numberOfLines = config.numberOfLines
        if let textAlignment = config.textAlignment {
            self.textAlignment = textAlignment
        }
    }
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
nonisolated class MockGroupThread: TSGroupThread {
    nonisolated init(groupModel: TSGroupModelV2) {
        super.init(uniqueId: "MockGroupThread", groupModel: groupModel)
    }

    nonisolated required init(inheritableDecoder decoder: any Decoder) throws {
        try super.init(inheritableDecoder: decoder)
    }
}

nonisolated class MockIncomingMessage: TSIncomingMessage {
    nonisolated init(messageBody: ValidatedInlineMessageBody, thread: TSThread, authorAci: Aci) {
        let builder = TSIncomingMessageBuilder.withDefaultValues(
            thread: thread,
            authorAci: authorAci,
            messageBody: messageBody,
            read: true
        )
        super.init(incomingMessageWithBuilder: builder)
    }

    nonisolated required init?(coder: NSCoder) {
        nil
    }

    nonisolated required init() {
        fatalError("init() is unavailable for MockIncomingMessage.")
    }
}

nonisolated class MockOutgoingMessage: TSOutgoingMessage {
    nonisolated init(messageBody: ValidatedInlineMessageBody?, thread: TSThread) {
        let builder = TSOutgoingMessageBuilder.withDefaultValues(
            thread: thread,
            messageBody: messageBody
        )
        super.init(outgoingMessageWith: builder, recipientAddressStates: [:])
    }

    nonisolated required init?(coder: NSCoder) {
        nil
    }

    nonisolated required init() {
        fatalError("init() is unavailable for MockOutgoingMessage.")
    }
}
protocol NameCollisionResolutionDelegate: AnyObject { }
class NameCollisionResolutionViewController: UIViewController {
    init(collisionFinder: Any, collisionDelegate: NameCollisionResolutionDelegate) {
        _ = (collisionFinder, collisionDelegate)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present(fromViewController viewController: UIViewController) {
        viewController.present(self, animated: true)
    }
}
struct OsExpiry {
    var enforcedAfter: Date
    var minimumIosMajorVersion: Int
}
protocol PaymentsHistoryItem { }
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

    func deleteThreadWithConfirmation(threadViewModel: ThreadViewModel, completion: (() -> Void)? = nil) {
        _ = threadViewModel
        completion?()
    }

    func toggleThreadIsArchived(threadViewModel: ThreadViewModel) {
        _ = threadViewModel
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
