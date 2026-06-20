// QuillRealConversationProbe.swift -- DB-backed Signal conversation smoke.
//
// Symlinked into the disposable Signal app target by quill-signal-prep-app.sh.
// This deliberately exercises Signal's real ConversationViewController load path
// against a real SDSDatabaseStorage seed instead of hand-building preview cells.

public import Foundation
public import GRDB
public import LibSignalClient
public import SignalServiceKit
public import SignalUI
public import UIKit

@MainActor
public enum QuillSignalRealConversationProbe {
    private static let localAci = Aci(fromUUID: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
    private static let localPni = Pni(fromUUID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)
    fileprivate static let contactAci = Aci(fromUUID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    fileprivate static let acceptedContactAci = Aci(fromUUID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!)
    private static let localE164 = E164("+15555550100")!
    fileprivate static let contactE164 = E164("+15555550111")!
    fileprivate static let acceptedContactE164 = E164("+15555550112")!

    public static func makeViewController(width: CGFloat = 760, height: CGFloat = 720) async throws -> UIViewController {
        try await makeViewController(mode: .pendingRequest, width: width, height: height)
    }

    public static func makeAcceptedViewController(width: CGFloat = 760, height: CGFloat = 720) async throws -> UIViewController {
        try await makeViewController(mode: .accepted, width: width, height: height)
    }

    private static func makeViewController(mode: SeedMode, width: CGFloat, height: CGFloat) async throws -> UIViewController {
        let bootstrap = try await quillBootstrapSignalRenderEnvironment()
        if mode.shouldShowInputToolbar {
            SUIEnvironment.shared.quillInstallRenderLinkPreviewFetcher(QuillSignalRenderLinkPreviewFetcher())
        }
        try await seedConversationIfNeeded(bootstrap: bootstrap, mode: mode)

        let cvc = try bootstrap.databaseStorage.read { tx throws(QuillSignalRealConversationProbeError) in
            let contactAddress = mode.contactAddress
            guard let thread = TSContactThread.getWithContactAddress(contactAddress, transaction: tx) else {
                throw .missingSeedThread
            }
            let threadViewModel = ThreadViewModel(thread: thread, forChatList: false, transaction: tx)
            let cvc = ConversationViewController.load(
                appReadiness: bootstrap.appReadiness,
                threadViewModel: threadViewModel,
                action: .none,
                focusMessageId: nil,
                tx: tx,
            )
            cvc.previewSetup()
            return cvc
        }

        try await prepareForRender(cvc: cvc, mode: mode, width: width, height: height)
        return cvc as UIViewController
    }

    private static func seedConversationIfNeeded(bootstrap: QuillSignalRenderBootstrap, mode: SeedMode) async throws {
        try await bootstrap.databaseStorage.awaitableWrite { tx throws(QuillSignalRealConversationProbeError) in
            guard let localIdentifiersSetter = bootstrap.dependenciesBridge.tsAccountManager as? LocalIdentifiersSetter else {
                throw .missingLocalIdentifiersSetter
            }

            localIdentifiersSetter.initializeLocalIdentifiers(
                e164: localE164,
                aci: localAci,
                pni: localPni,
                deviceId: .primary,
                serverAuthToken: "quill-render-token",
                tx: tx,
            )
            bootstrap.dependenciesBridge.tsAccountManager.setRegistrationId(1234, for: .aci, tx: tx)
            bootstrap.dependenciesBridge.tsAccountManager.setRegistrationId(5678, for: .pni, tx: tx)

            let contactAddress = mode.contactAddress
            let thread = TSContactThread.getOrCreateThread(withContactAddress: contactAddress, transaction: tx)
            ThreadAssociatedData.create(for: thread.uniqueId, transaction: tx)

            guard var recipient = bootstrap.dependenciesBridge.recipientFetcher.fetchOrCreate(address: contactAddress, tx: tx) else {
                throw .missingSeedRecipient
            }
            bootstrap.dependenciesBridge.recipientManager.markAsRegisteredAndSave(
                &recipient,
                shouldUpdateStorageService: false,
                tx: tx,
            )
            bootstrap.dependenciesBridge.nicknameManager.createOrUpdate(
                nicknameRecord: NicknameRecord(
                    recipient: recipient,
                    givenName: mode.contactGivenName,
                    familyName: mode.contactFamilyName,
                    note: nil,
                ),
                updateStorageServiceFor: nil,
                tx: tx,
            )

            if mode.shouldAcceptThread {
                SSKEnvironment.shared.profileManagerRef.addRecipientToProfileWhitelist(
                    &recipient,
                    userProfileWriter: .localUser,
                    tx: tx,
                )
            }

            let interactionCount = (try? Int.fetchOne(
                tx.database,
                sql: "SELECT COUNT(*) FROM \(InteractionRecord.databaseTableName) WHERE threadUniqueId = ?",
                arguments: [thread.uniqueId],
            )) ?? 0
            guard interactionCount == 0 else {
                return
            }

            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            TSIncomingMessageBuilder.withDefaultValues(
                thread: thread,
                timestamp: now,
                receivedAtTimestamp: now,
                authorAci: mode.contactAci,
                authorE164: mode.contactE164,
                messageBody: QuillSignalSeedMessageBody(mode.incomingText),
                read: true,
                serverTimestamp: now,
                serverDeliveryTimestamp: now,
                serverGuid: "\(mode.serverGuidPrefix)-incoming-1",
                wasReceivedByUD: false,
            )
            .build()
            .anyInsert(transaction: tx)

            TSOutgoingMessageBuilder.withDefaultValues(
                thread: thread,
                timestamp: now + 1,
                receivedAtTimestamp: now + 1,
                messageBody: QuillSignalSeedMessageBody(mode.outgoingText),
            )
            .build(transaction: tx)
            .anyInsert(transaction: tx)
        }

        bootstrap.databaseStorage.read { tx in
            bootstrap.dependenciesBridge.tsAccountManager.warmCaches(tx: tx)
        }
    }

    private static func prepareForRender(cvc: ConversationViewController, mode: SeedMode, width: CGFloat, height: CGFloat) async throws {
        if !cvc.isViewLoaded {
            cvc.loadView()
            if cvc.viewIfLoaded == nil {
                cvc.view = UIView()
            }
            cvc.viewIfLoaded?.frame = CGRect(x: 0, y: 0, width: width, height: height)
            cvc.viewDidLoad()
        }

        if mode.shouldShowInputToolbar {
            cvc.isInPreviewPlatter = false
        }

        cvc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        cvc.collectionView.frame = cvc.view.bounds
        if mode.shouldShowInputToolbar {
            let navigationController = cvc.navigationController ?? UINavigationController(rootViewController: cvc)
            navigationController.view.frame = cvc.view.bounds
            cvc.navigationController = navigationController
        }
        cvc.view.layoutIfNeeded()

        _ = cvc.updateConversationStyle()
        cvc.viewWillAppearDidBegin()
        cvc.isViewVisible = true
        cvc.viewWillAppearForLoad()
        cvc.ensureBottomViewType()
        cvc.inputToolbar?.scrollToBottom()
        cvc.viewWillAppearDidComplete()

        for _ in 0..<80 {
            cvc.view.layoutIfNeeded()
            if !cvc.renderItems.isEmpty {
                cvc.collectionView.reloadData()
                if !cvc.collectionView.visibleCells.isEmpty {
                    return
                }
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        throw QuillSignalRealConversationProbeError.initialRenderDidNotProduceCells(
            renderItems: cvc.renderItems.count,
            visibleCells: cvc.collectionView.visibleCells.count,
            shouldHideContent: cvc.loadCoordinator.shouldHideCollectionViewContent,
        )
    }
}

public enum QuillSignalRealConversationProbeError: Error, CustomStringConvertible {
    case missingLocalIdentifiersSetter
    case missingSeedRecipient
    case missingSeedThread
    case initialRenderDidNotProduceCells(renderItems: Int, visibleCells: Int, shouldHideContent: Bool)

    public var description: String {
        switch self {
        case .missingLocalIdentifiersSetter:
            return "TSAccountManager does not expose LocalIdentifiersSetter."
        case .missingSeedRecipient:
            return "Seeded Signal contact recipient could not be created."
        case .missingSeedThread:
            return "Seeded Signal contact thread could not be reloaded."
        case let .initialRenderDidNotProduceCells(renderItems, visibleCells, shouldHideContent):
            return "Real ConversationViewController did not produce visible cells after its initial load (renderItems=\(renderItems), visibleCells=\(visibleCells), shouldHideContent=\(shouldHideContent))."
        }
    }
}

private struct QuillSignalSeedMessageBody: ValidatedInlineMessageBody {
    let inlinedBody: MessageBody

    init(_ text: String) {
        self.inlinedBody = MessageBody(text: text, ranges: .empty)
    }
}

private enum QuillSignalRenderLinkPreviewError: Error {
    case disabled
}

private struct QuillSignalRenderLinkPreviewFetcher: LinkPreviewFetcher {
    func fetchLinkPreview(for url: URL) async throws -> OWSLinkPreviewDraft {
        _ = url
        throw QuillSignalRenderLinkPreviewError.disabled
    }
}

private enum SeedMode {
    case pendingRequest
    case accepted

    var contactAci: Aci {
        switch self {
        case .pendingRequest:
            return QuillSignalRealConversationProbe.contactAci
        case .accepted:
            return QuillSignalRealConversationProbe.acceptedContactAci
        }
    }

    var contactE164: E164 {
        switch self {
        case .pendingRequest:
            return QuillSignalRealConversationProbe.contactE164
        case .accepted:
            return QuillSignalRealConversationProbe.acceptedContactE164
        }
    }

    var contactAddress: SignalServiceAddress {
        SignalServiceAddress(serviceId: contactAci, e164: contactE164)
    }

    var contactGivenName: String {
        switch self {
        case .pendingRequest:
            return "Maya"
        case .accepted:
            return "Nina"
        }
    }

    var contactFamilyName: String {
        switch self {
        case .pendingRequest:
            return "Rivera"
        case .accepted:
            return "Park"
        }
    }

    var shouldAcceptThread: Bool {
        switch self {
        case .pendingRequest:
            return false
        case .accepted:
            return true
        }
    }

    var shouldShowInputToolbar: Bool {
        switch self {
        case .pendingRequest:
            return false
        case .accepted:
            return true
        }
    }

    var incomingText: String {
        switch self {
        case .pendingRequest:
            return "Hey, this is the real ConversationViewController loading from Signal storage."
        case .accepted:
            return "The accepted-thread path should show Signal's real composer instead of message-request actions."
        }
    }

    var outgoingText: String {
        switch self {
        case .pendingRequest:
            return "And this reply is a real TSOutgoingMessage rendered through CVC."
        case .accepted:
            return "This reply keeps the same real CVC message pipeline while exercising the input toolbar."
        }
    }

    var serverGuidPrefix: String {
        switch self {
        case .pendingRequest:
            return "quill-real-conversation-pending"
        case .accepted:
            return "quill-real-conversation-accepted"
        }
    }
}
