// QuillAppStubs.swift — Linux stand-ins for Signal app types whose defining
// files live in iOS-only subsystems pruned from the conversation-rendering slice
// (calling, donations, device transfer, the iPad split-view shell). They exist so
// the kept conversation/message code resolves and compiles; none of them is
// instantiated on the render path. Started empty and grown member-by-member as the
// build reports "has no member" — kept deliberately minimal.
//
// Symlinked into the disposable .upstream app tree's QuillPort/ by
// quill-signal-prep-app.sh so the canonical app source stays untouched.

public import Foundation
public import UIKit
public import LibSignalClient
public import SignalServiceKit
public import SignalUI

// MARK: - App-level namespaces and singleton entry points

enum Signal {
    enum DonationJobError: Error {
        case timeout
    }
}

final class SignalApp {
    enum AppSettingsMode {
        case linkedDevices
    }

    static let shared = SignalApp()

    func presentConversationForAddress(
        _ address: SignalServiceAddress,
        action: ConversationViewAction = .compose,
        animated: Bool
    ) {
        _ = (address, action, animated)
    }

    func presentConversationForThread(
        threadUniqueId: String,
        action: ConversationViewAction = .none,
        animated: Bool
    ) {
        _ = (threadUniqueId, action, animated)
    }

    func dismissAllModals(animated: Bool, completion: (() -> Void)? = nil) {
        _ = animated
        _ = completion
    }

    func showAppSettings(mode: AppSettingsMode) {
        _ = mode
    }

    func showCameraCaptureView(_ completion: @escaping (UINavigationController) -> Void) {
        _ = completion
    }

    func showExportDatabaseUI(from viewController: UIViewController) {
        _ = viewController
    }

    func resetAppDataAndExit(keyFetcher: GRDBKeyFetcher) {
        _ = keyFetcher
    }
}

public enum PaymentsOutdatedClientSheetTitle {
    case cantSendPayment
}

// MARK: - Calling (Calls/ pruned: needs WebRTC/CallKit)

class CallService {
    let callServiceState = CallServiceState()
}

class CallServiceState {
    var currentCall: SignalCall?

    func addObserver(_ observer: CallServiceStateObserver, syncStateImmediately: Bool) {
        _ = observer
        _ = syncStateImmediately
    }
}

class SignalCall {
    enum Mode {
        case groupThread(Any)
        case other

        func matches(_ other: Mode) -> Bool {
            switch (self, other) {
            case let (.groupThread(lhs), .groupThread(rhs)):
                return String(describing: lhs) == String(describing: rhs)
            case (.other, .other):
                return true
            default:
                return false
            }
        }
    }

    var mode: Mode = .other
}
struct CallStarter {}
typealias CallLink = SignalUI.CallLink

// MARK: - Donations (pruned: needs PassKit/StoreKit donation flow)

class DonateViewController: UIViewController {
    enum PreferredDonateMode {
        case oneTime
    }

    enum FinishResult {
        case completedDonation(UIViewController, DonationReceiptCredentialResultStore.Mode)
        case monthlySubscriptionCancelled(UIViewController, String)
    }

    init(
        preferredDonateMode: PreferredDonateMode,
        completion: @escaping (FinishResult) -> Void
    ) {
        _ = preferredDonateMode
        _ = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

// MARK: - App shell / misc subsystems pruned for the render slice

class ConversationSplitViewController: UISplitViewController {
    func closeSelectedConversation(animated: Bool) {
        _ = animated
    }
}
class CameraCaptureSession {}
class ProvisioningManager {}
class QuickRestoreManager {}
struct DeviceProvisioningURL {
    enum LinkType {
        case linkDevice
        case quickRestore
    }

    let linkType: LinkType

    init?(urlString: String) {
        linkType = urlString.contains("quick") ? .quickRestore : .linkDevice
    }
}
class BackupAttachmentDownloadTracker {}

// MARK: - AppEnvironment services pruned with app shell subsystems

class AppEnvironment {
    static let shared = AppEnvironment()

    let callService = CallService()
    let cvAudioPlayerRef = CVAudioPlayer()
    let windowManagerRef = QuillWindowManager()
    let speechManagerRef = QuillSpeechManager()

    var avatarHistoryManager: AvatarHistoryManager {
        fatalError("Avatar history is unavailable in the Quill Signal render slice.")
    }
}

class QuillWindowManager {
    var rootWindow = UIWindow()
    var shouldShowCallView = false
    var isScreenBlockActive = false
}

class QuillSpeechManager {
    var isSpeaking = false
}

class ChatListViewController {
    static let clearSearch = Notification.Name("ChatListViewController.clearSearch")
}

// MARK: - Background task runner surface

enum BGProcessingTaskStartCondition {
    case asSoonAsPossible
    case never
}

protocol BGProcessingTaskRunner: AnyObject {
    static var taskIdentifier: String { get }
    static var logPrefix: String? { get }
    static var requiresNetworkConnectivity: Bool { get }
    static var requiresExternalPower: Bool { get }

    func run() async throws(CancellationError)
    func startCondition() -> BGProcessingTaskStartCondition
}

extension BGProcessingTaskRunner {
    func runInBatches(
        willBegin: () -> Void,
        runNextBatch: () async -> Bool
    ) async throws(CancellationError) {
        willBegin()
        while await runNextBatch() {}
    }
}

// MARK: - Attachment share/save surfaces

enum AttachmentSharing {
    static func showShareUI(for attachments: [ShareableAttachment], sender: Any?) {
        _ = (attachments, sender)
    }

    static func showShareUI(for url: URL, sender: Any?) {
        _ = (url, sender)
    }

    static func showShareUI(for text: String, sender: Any?) {
        _ = (text, sender)
    }
}

enum AttachmentSaving {
    static func saveToPhotoLibrary(referencedAttachmentStreams: [ReferencedAttachmentStream]) {
        _ = referencedAttachmentStreams
    }
}

extension Array where Element == ReferencedAttachmentStream {
    func asShareableAttachments() throws -> [ShareableAttachment] { [] }
}

// MARK: - Push / debug / device-transfer / backups / quick-restore services
// (defining files pruned: they import PushKit / CocoaLumberjack / Multipeer /
//  BackgroundTasks, or live under the pruned Backups/DeviceTransfer/QuickRestore
//  subsystems). Empty stand-ins; members grown build-driven where still referenced.

class PushRegistrationManager {}
class DebugLogDumper {
    static func preLaunch() -> DebugLogDumper {
        DebugLogDumper()
    }
}

struct DebugLogs {
    let dumper: DebugLogDumper

    init(dumper: DebugLogDumper) {
        self.dumper = dumper
    }

    func promptToSubmitLogs(from viewController: UIViewController, supportTag: String?) {
        _ = (viewController, supportTag)
    }
}
class BackupAttachmentUploadTracker {}
class BackupSettingsViewController: UIViewController {}
class BackupEnablingManager {}
class BackupDisablingManager {}
class DeviceTransferService {}
protocol DeviceTransferServiceProtocol {}
class DeviceTransferCoordinator {}
class DeviceTransferStatusViewController: UIViewController {}
class OutgoingDeviceRestorePresenter {}
class BaseQuickRestoreQRCodeViewController: UIViewController {}
class EnterAccountEntropyPoolViewController: UIViewController {}
class CapturePreviewView: UIView {}
class LocationPicker: UIViewController {
    weak var delegate: LocationPickerDelegate?
}

protocol LocationPickerDelegate: AnyObject {
    func didPickLocation(_ locationPicker: LocationPicker, location: Location)
    func locationPickerDidCancel()
}

extension LocationPickerDelegate {
    func didPickLocation(_ locationPicker: LocationPicker, location: Location) {
        _ = locationPicker
        _ = location
    }

    func locationPickerDidCancel() {}
}

struct Location {
    var messageText: String { "" }

    func prepareAttachment() async throws -> SendableAttachment {
        throw NSError(domain: "QuillSignalLocation", code: 1)
    }
}

// MARK: - Donation / share / payment helpers

enum DonationViewsUtil {
    static func attemptToContinueActiveIDEALDonation(
        type: Stripe.IDEALCallbackType,
        databaseStorage: SDSDatabaseStorage
    ) async -> Bool {
        _ = (type, databaseStorage)
        return false
    }

    static func restartAndCompleteInterruptedIDEALDonation(
        type: Stripe.IDEALCallbackType,
        rootViewController: UIViewController,
        databaseStorage: SDSDatabaseStorage,
        appReadiness: AppReadinessSetter
    ) async throws {
        _ = (type, rootViewController, databaseStorage, appReadiness)
        throw Signal.DonationJobError.timeout
    }
}

enum ShareActivityUtil {
    static func present(
        activityItems: [Any],
        from viewController: UIViewController,
        sourceView: UIView?,
        completion: (() -> Void)? = nil
    ) {
        _ = (activityItems, viewController, sourceView, completion)
    }
}

extension OWSActionSheets {
    static func showPaymentsOutdatedClientSheet(title: PaymentsOutdatedClientSheetTitle) {
        _ = title
    }
}

struct PaymentsHistoryModelItem: PaymentsHistoryItem {
    let paymentModel: TSPaymentModel
    let displayName: String

    init(paymentModel: TSPaymentModel, displayName: String) {
        self.paymentModel = paymentModel
        self.displayName = displayName
    }
}

struct ArchivedPaymentHistoryItem: PaymentsHistoryItem {
    let archivedPayment: ArchivedPayment
    let address: SignalServiceAddress
    let displayName: String
    let interaction: TSInteraction

    init?(
        archivedPayment: ArchivedPayment,
        address: SignalServiceAddress,
        displayName: String,
        interaction: TSInteraction
    ) {
        self.archivedPayment = archivedPayment
        self.address = address
        self.displayName = displayName
        self.interaction = interaction
    }
}

extension CallStrings {
    public static var joinGroupCall: String {
        OWSLocalizedString(
            "JOIN_GROUP_CALL",
            comment: "Button title for joining a group call.",
        )
    }

    public static var joinCallPillButtonTitle: String { joinGroupCall }
}

class AppSettingsViewController: UIViewController {
    static func inModalNavigationController(appReadiness: AppReadinessSetter) -> OWSNavigationController {
        _ = appReadiness
        return OWSNavigationController(rootViewController: AppSettingsViewController())
    }
}

extension TypedItemProvider {
    static func buildVisualMediaAttachment(
        forItemProvider itemProvider: Any,
        attachmentLimits: OutgoingAttachmentLimits
    ) async throws -> PreviewableAttachment {
        _ = (itemProvider, attachmentLimits)
        throw SignalAttachmentError.invalidFileFormat
    }
}

// MARK: - Calling glue still referenced from kept code (Calls/ pruned)

protocol CallServiceStateObserver: AnyObject {}
class CallViewControllerWindowReference {}
struct CallTarget {}
class CallLinkProfileKeySharingManager {}

// MARK: - Pruned app-only controllers and utility namespaces

enum InMemorySettings {
    static var spinningConversationTitle = false
}

struct ProfileSheetSheetCoordinator {
    let address: SignalServiceAddress
    let groupViewHelper: GroupViewHelper?
    let spoilerState: SpoilerRenderState
    let memberLabel: MemberLabelForRendering?

    init(
        address: SignalServiceAddress,
        groupViewHelper: GroupViewHelper?,
        spoilerState: SpoilerRenderState,
        memberLabel: MemberLabelForRendering? = nil
    ) {
        self.address = address
        self.groupViewHelper = groupViewHelper
        self.spoilerState = spoilerState
        self.memberLabel = memberLabel
    }

    func presentAppropriateSheet(from viewController: UIViewController) {
        _ = viewController
    }
}

enum LegacyGroupLearnMoreUI {
    enum Sheet {
        case explainUnsupportedLegacyGroups
    }

    static func presentActionSheet(for sheet: Sheet, from viewController: UIViewController) {
        _ = (sheet, viewController)
    }
}

enum RegistrationUtils {
    static func showReregistrationUI(
        fromViewController viewController: UIViewController,
        appReadiness: AppReadinessSetter
    ) {
        _ = (viewController, appReadiness)
    }
}

class SendPaymentViewController: UIViewController {
    static func presentFromConversationView(
        _ conversationViewController: ConversationViewController,
        delegate: SendPaymentViewDelegate,
        recipientAddress: SignalServiceAddress,
        initialPaymentAmount: Any?,
        isOutgoingTransfer: Bool
    ) {
        _ = (conversationViewController, delegate, recipientAddress, initialPaymentAmount, isOutgoingTransfer)
    }
}

class NewPollViewController2: UIViewController {
    weak var sendDelegate: PollSendDelegate?
}

class StoryPageViewController: UIViewController {
    init(context: StoryContext, spoilerState: SpoilerRenderState) {
        _ = (context, spoilerState)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

struct QuillSpamReport {
    func submit(using networkManager: Any) async throws {
        _ = networkManager
    }
}

enum ReportSpamUIUtils {
    static func successfulReportText(didBlock: Bool) -> String {
        didBlock
            ? OWSLocalizedString("REPORT_SPAM_AND_BLOCK_SUCCESS", comment: "Spam report success text.")
            : OWSLocalizedString("REPORT_SPAM_SUCCESS", comment: "Spam report success text.")
    }

    static func createReportSpamActionSheet(
        forThread thread: TSThread,
        isBlocked: Bool,
        declineMessageRequest: @escaping (OutgoingMessageRequestResponseSyncMessage.ResponseType) -> Void
    ) -> ActionSheetController {
        _ = (thread, isBlocked, declineMessageRequest)
        return ActionSheetController()
    }

    static func insertSpamReportMessage(in thread: TSThread, tx: DBWriteTransaction) -> QuillSpamReport? {
        _ = (thread, tx)
        return nil
    }
}

class ConversationSettingsViewController: UIViewController {
    weak var conversationSettingsViewDelegate: ConversationSettingsViewDelegate?
    var showVerificationOnAppear = false

    init(
        threadViewModel: ThreadViewModel,
        isSystemContact: Bool,
        spoilerState: SpoilerRenderState,
        memberLabelCoordinator: MemberLabelCoordinator?
    ) {
        _ = (threadViewModel, isSystemContact, spoilerState, memberLabelCoordinator)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func buildMemberRequestsAndInvitesView() -> UIViewController? {
        nil
    }

    static func muteUnmuteMenu(
        for threadViewModel: ThreadViewModel,
        actionExecuted: @escaping () -> Void
    ) -> UIMenu {
        _ = threadViewModel
        actionExecuted()
        return UIMenu()
    }
}

class AllMediaViewController: UIViewController {
    init(thread: TSThread, spoilerState: SpoilerRenderState, name: String?) {
        _ = (thread, spoilerState, name)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

enum SafetyTipsSheet {
    static func makeSmsCodeRequestedSheet(
        timestampMs: UInt64,
        fromViewController viewController: UIViewController
    ) -> ActionSheetController {
        _ = (timestampMs, viewController)
        return ActionSheetController()
    }
}

class PaymentsSettingsViewController: UIViewController {
    enum Mode {
        case standalone
    }

    init(mode: Mode, appReadiness: AppReadinessSetter) {
        _ = (mode, appReadiness)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

enum GroupCallViewController {
    static func presentLobby(for callLink: CallLink) {
        _ = callLink
    }
}

enum GroupLinkViewUtils {
    static func linkMode(
        isGroupInviteLinkEnabled: Bool,
        approveNewMembers: Bool
    ) -> GroupsV2LinkMode {
        guard isGroupInviteLinkEnabled else {
            return .disabled
        }
        return approveNewMembers ? .enabledWithApproval : .enabledWithoutApproval
    }

    static func updateLinkMode(
        groupModelV2: TSGroupModelV2,
        linkMode: GroupsV2LinkMode,
        fromViewController viewController: UIViewController,
        completion: @escaping () -> Void
    ) {
        _ = (groupModelV2, linkMode, viewController)
        completion()
    }

    static func showShareLinkAlert(
        groupModelV2: TSGroupModelV2,
        fromViewController viewController: UIViewController,
        sendMessageController: SendMessageController
    ) {
        _ = (groupModelV2, viewController, sendMessageController)
    }
}

enum ExperienceUpgrade {
    case introducingPins
}

enum ExperienceUpgradeManager {
    static func clearExperienceUpgrade(_ experienceUpgrade: ExperienceUpgrade, transaction: DBWriteTransaction) {
        _ = (experienceUpgrade, transaction)
    }
}

class NewGroupMembersViewController: UIViewController {}

func AudioServicesPlaySystemSound(_ soundID: UInt32) {
    _ = soundID
}

extension TSContactThread {
    var canCall: Bool { true }
}

extension TSGroupThread {
    var canCall: Bool { !isTerminatedGroup }
}

extension ConversationViewController: MessageActionsDelegate, CVComponentDelegate {
    var conversationSplitViewController: ConversationSplitViewController? {
        splitViewController as? ConversationSplitViewController
    }

    var spoilerState: SpoilerRenderState {
        viewState.spoilerState
    }

    var isCurrentCallForThread: Bool {
        guard let groupThread = thread as? TSGroupThread else {
            return false
        }
        return AppEnvironment.shared.callService.callServiceState.currentCall?.mode.matches(.groupThread(groupThread.groupId)) ?? false
    }

    var canCall: Bool {
        Self.canCall(threadViewModel: threadViewModel)
    }

    func refreshCallState() {
        updateBarButtonItems()
    }

    func startIndividualAudioCall() {}

    func startIndividualVideoCall() {}

    func showGroupLobbyOrActiveCall() {}

    func handleUrl(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    func enqueueReload() {
        loadCoordinator.enqueueReload()
    }

    func handleActionUnpin(message: TSMessage, modalDelegate: UIViewController) {
        _ = (message, modalDelegate)
    }

    func handleActionUnpinAsync(message: TSMessage) async {
        _ = message
    }

    func showFingerprint(address: SignalServiceAddress) {
        FingerprintViewController.present(for: address.aci, from: self)
    }

    func didTapCallLink(_ callLink: CallLink) {
        didTapJoinCallLinkCall(callLink: callLink)
    }
}

public enum QuillSignalAppModuleProbe {
    public static var hasConversationViewController: Bool {
        _ = ConversationViewController.self
        return true
    }
}

extension MessageActionsDelegate {
    func messageActionsShowDetailsForItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsReplyToItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsForwardItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsStartedSelect(initialItem itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsDeleteItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsSpeakItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsStopSpeakingItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsEditItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsShowPaymentDetails(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsEndPoll(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func messageActionsChangePinStatus(_ itemViewModel: CVItemViewModelImpl, pin: Bool) { _ = (itemViewModel, pin) }
}

extension AudioMessageViewDelegate {
    func enqueueReloadWithoutCaches() {}
    func beginCellAnimation(maximumDuration: TimeInterval) -> EndCellAnimation {
        _ = maximumDuration
        return {}
    }
}

extension CVPollVoteDelegate {
    func didTapVoteOnPoll(poll: OWSPoll, optionIndex: UInt32, isUnvote: Bool) {
        _ = (poll, optionIndex, isUnvote)
    }
}

extension CVComponentDelegate {
    var hasPendingMessageRequest: Bool { false }
    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }
    var selectionState: CVSelectionState { CVSelectionState() }

    func didTapBodyTextItem(_ item: CVTextLabel.Item) { _ = item }
    func didLongPressBodyTextItem(_ item: CVTextLabel.Item) { _ = item }
    func didTapSystemMessageItem(_ item: CVTextLabel.Item) { _ = item }
    func didTapCollapseSet(collapseSetId: String) { _ = collapseSetId }
    func didDoubleTapTextViewItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func didLongPressTextViewItem(_ cell: CVCell, itemViewModel: CVItemViewModelImpl, shouldAllowMessageSendActions: Bool) { _ = (cell, itemViewModel, shouldAllowMessageSendActions) }
    func didLongPressMediaViewItem(_ cell: CVCell, itemViewModel: CVItemViewModelImpl, shouldAllowMessageSendActions: Bool) { _ = (cell, itemViewModel, shouldAllowMessageSendActions) }
    func didLongPressQuote(_ cell: CVCell, itemViewModel: CVItemViewModelImpl, shouldAllowMessageSendActions: Bool) { _ = (cell, itemViewModel, shouldAllowMessageSendActions) }
    func didLongPressSystemMessage(_ cell: CVCell, itemViewModel: CVItemViewModelImpl) { _ = (cell, itemViewModel) }
    func didLongPressSticker(_ cell: CVCell, itemViewModel: CVItemViewModelImpl, shouldAllowMessageSendActions: Bool) { _ = (cell, itemViewModel, shouldAllowMessageSendActions) }
    func didLongPressPaymentMessage(_ cell: CVCell, itemViewModel: CVItemViewModelImpl, shouldAllowMessageSendActions: Bool) { _ = (cell, itemViewModel, shouldAllowMessageSendActions) }
    func didLongPressPoll(_ cell: CVCell, itemViewModel: CVItemViewModelImpl, shouldAllowMessageSendActions: Bool) { _ = (cell, itemViewModel, shouldAllowMessageSendActions) }
    func didChangeLongPress(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func didEndLongPress(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func didCancelLongPress(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func willBecomeVisibleWithSkippedDownloads(_ message: TSMessage) { _ = message }
    func didTapSkippedDownloads(_ message: TSMessage) { _ = message }
    func didCancelDownload(_ message: TSMessage, attachmentId: Attachment.IDType) { _ = (message, attachmentId) }
    func didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func didTapSenderAvatar(_ interaction: TSInteraction) { _ = interaction }
    func shouldAllowMessageSendActionsForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { _ = itemViewModel; return true }
    func didTapReactions(reactionState: InteractionReactionState, message: TSMessage) { _ = (reactionState, message) }
    func didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func didTapUndownloadableMedia() {}
    func didTapUndownloadableGenericFile() {}
    func didTapUndownloadableOversizeText() {}
    func didTapUndownloadableAudio() {}
    func didTapUndownloadableSticker() {}
    func didTapBrokenVideo() {}
    func didTapBodyMedia(itemViewModel: CVItemViewModelImpl, attachment: ReferencedAttachment, imageView: UIView) { _ = (itemViewModel, attachment, imageView) }
    func didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction { _ = attachment; return .default }
    func didTapQuotedReply(_ quotedReply: QuotedReplyModel) { _ = quotedReply }
    func didTapLinkPreview(url: URL) { _ = url }
    func didTapContactShare(_ contactShare: ContactShareViewModel) { _ = contactShare }
    func didTapSendMessage(to phoneNumbers: [String]) { _ = phoneNumbers }
    func didTapSendInvite(toContactShare contactShare: ContactShareViewModel) { _ = contactShare }
    func didTapAddToContacts(contactShare: ContactShareViewModel) { _ = contactShare }
    func didTapStickerPack(_ stickerPackInfo: StickerPackInfo) { _ = stickerPackInfo }
    func didTapPayment(_ payment: PaymentsHistoryItem) { _ = payment }
    func didTapGroupInviteLink(url: URL) { _ = url }
    func didTapProxyLink(url: URL) { _ = url }
    func didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func didTapShowEditHistory(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func willWrapGift(_ messageUniqueId: String) -> Bool { _ = messageUniqueId; return true }
    func willShakeGift(_ messageUniqueId: String) -> Bool { _ = messageUniqueId; return true }
    func willUnwrapGift(_ itemViewModel: CVItemViewModelImpl) { _ = itemViewModel }
    func didTapGiftBadge(_ itemViewModel: CVItemViewModelImpl, profileBadge: ProfileBadge, isExpired: Bool, isRedeemed: Bool) { _ = (itemViewModel, profileBadge, isExpired, isRedeemed) }
    func didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) { _ = address }
    func didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) { _ = address }
    func didTapSessionRefreshMessage(_ message: TSErrorMessage) { _ = message }
    func didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) { _ = errorMessage }
    func didTapIndividualCall(_ call: TSCall) { _ = call }
    func didTapLearnMoreMissedCallFromBlockedContact(_ call: TSCall) { _ = call }
    func didTapGroupCall() {}
    func didTapPendingOutgoingMessage(_ message: TSOutgoingMessage) { _ = message }
    func didTapFailedMessage(_ message: TSMessage) { _ = message }
    func didTapGroupMigrationLearnMore() {}
    func didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) { _ = groupModel }
    func didTapViewGroupDescription(newGroupDescription: String) { _ = newGroupDescription }
    func didTapNameEducation(type: SafetyTipsType) { _ = type }
    func didTapShowConversationSettings() {}
    func didTapShowConversationSettingsAndShowMemberRequests() {}
    func didTapBlockRequest(groupModel: TSGroupModelV2, requesterName: String, requesterAci: Aci) { _ = (groupModel, requesterName, requesterAci) }
    func didTapShowUpgradeAppUI() {}
    func didTapUpdateSystemContact(_ address: SignalServiceAddress, newNameComponents: PersonNameComponents) { _ = (address, newNameComponents) }
    func didTapPhoneNumberChange(aci: Aci, phoneNumberOld: String, phoneNumberNew: String) { _ = (aci, phoneNumberOld, phoneNumberNew) }
    func didTapViewOnceAttachment(_ interaction: TSInteraction) { _ = interaction }
    func didTapViewOnceExpired(_ interaction: TSInteraction) { _ = interaction }
    func didTapContactName(thread: TSContactThread) { _ = thread }
    func didTapUnknownThreadWarningGroup() {}
    func didTapUnknownThreadWarningContact() {}
    func didTapDeliveryIssueWarning(_ message: TSErrorMessage) { _ = message }
    func didTapActivatePayments() {}
    func didTapSendPayment() {}
    func didTapThreadMergeLearnMore(phoneNumber: String) { _ = phoneNumber }
    func didTapReportSpamLearnMore() {}
    func didTapMessageRequestAcceptedOptions() {}
    func didTapJoinCallLinkCall(callLink: CallLink) { _ = callLink }
    func didTapViewVotes(poll: OWSPoll) { _ = poll }
    func didTapViewPoll(pollInteractionUniqueId: String) { _ = pollInteractionUniqueId }
    func didTapViewPinnedMessage(pinnedMessageUniqueId: String) { _ = pinnedMessageUniqueId }
    func didTapSafetyTips() {}
}

// MARK: - Generated-asset + Foundation typealiases corelibs lacks

public typealias NSInteger = Int
struct ImageResource {}

extension UIImage {
    static var check: UIImage { UIImage(named: "check") ?? UIImage() }
    static var pinSlash: UIImage { UIImage(named: "pin-slash") ?? UIImage() }
    static var pin: UIImage { UIImage(named: "pin") ?? UIImage() }
    static var pinFill: UIImage { UIImage(named: "pin-fill") ?? UIImage() }
    static var chatArrow: UIImage { UIImage(named: "chat-arrow") ?? UIImage() }
    static var listBullet: UIImage { UIImage(named: "list-bullet") ?? UIImage() }
    static var personQuestionmarkCompact: UIImage { UIImage(named: "person-questionmark-compact") ?? UIImage() }
    static var groupQuestionmarkCompact: UIImage { UIImage(named: "group-questionmark-compact") ?? UIImage() }
    static var tag22: UIImage { UIImage(named: "tag-22") ?? UIImage() }
}

extension Optional where Wrapped == UIImage {
    static var check: UIImage? { UIImage.check }
    static var pinSlash: UIImage? { UIImage.pinSlash }
    static var pin: UIImage? { UIImage.pin }
    static var pinFill: UIImage? { UIImage.pinFill }
    static var chatArrow: UIImage? { UIImage.chatArrow }
    static var listBullet: UIImage? { UIImage.listBullet }
    static var personQuestionmarkCompact: UIImage? { UIImage.personQuestionmarkCompact }
    static var groupQuestionmarkCompact: UIImage? { UIImage.groupQuestionmarkCompact }
    static var tag22: UIImage? { UIImage.tag22 }
}
