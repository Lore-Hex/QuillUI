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

    nonisolated public static func acceptedInteractionDebugSummary() throws -> String {
        try SSKEnvironment.shared.databaseStorageRef.read { tx in
            let thread = try acceptedThread(transaction: tx)
            return try interactionDebugSummary(threadUniqueId: thread.uniqueId, database: tx.database)
        }
    }

    public static func injectAcceptedIncomingMessage(_ text: String, in viewController: UIViewController) async throws -> String {
        guard let cvc = viewController as? ConversationViewController else {
            throw QuillSignalRealConversationProbeError.unexpectedViewController(String(describing: type(of: viewController)))
        }

        let interactionUniqueId = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx throws(QuillSignalRealConversationProbeError) in
            let thread = try acceptedThread(transaction: tx)
            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            let message = TSIncomingMessageBuilder.withDefaultValues(
                thread: thread,
                timestamp: now,
                receivedAtTimestamp: now,
                authorAci: acceptedContactAci,
                authorE164: acceptedContactE164,
                messageBody: QuillSignalSeedMessageBody(text),
                read: false,
                serverTimestamp: now,
                serverDeliveryTimestamp: now,
                serverGuid: "quill-real-conversation-accepted-injected-\(UUID().uuidString)",
                wasReceivedByUD: false,
            )
            .build()
            message.anyInsert(transaction: tx)
            return message.uniqueId
        }

        cvc.loadCoordinator.enqueueReload(
            scrollAction: CVScrollAction(action: .bottomForNewMessage, isAnimated: false)
        )

        for _ in 0..<80 {
            cvc.view.layoutIfNeeded()
            if cvc.renderItems.contains(where: { $0.interactionUniqueId == interactionUniqueId }) {
                cvc.collectionView.reloadData()
                return try acceptedInteractionDebugSummary()
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        throw QuillSignalRealConversationProbeError.injectedMessageDidNotRender(
            interactionUniqueId: interactionUniqueId,
            renderItems: cvc.renderItems.count,
        )
    }

    public static func settlePendingRequestContinuation(in viewController: UIViewController) async throws -> String {
        guard let cvc = viewController as? ConversationViewController else {
            throw QuillSignalRealConversationProbeError.unexpectedViewController(String(describing: type(of: viewController)))
        }

        for _ in 0..<100 {
            if try pendingRequestDebugSummary(cvc: cvc).dbPending == false {
                SUIEnvironment.shared.quillInstallRenderLinkPreviewFetcher(QuillSignalRenderLinkPreviewFetcher())
                cvc.isInPreviewPlatter = false
            }
            cvc.loadCoordinator.enqueueReload(
                scrollAction: CVScrollAction(action: .bottomForNewMessage, isAnimated: false)
            )
            cvc.view.layoutIfNeeded()
            cvc.collectionView.reloadData()
            cvc.ensureBottomViewType()
            cvc.inputToolbar?.scrollToBottom()

            let summary = try pendingRequestDebugSummary(cvc: cvc)
            if summary.dbPending == false,
               summary.viewModelPending == false,
               summary.bottomViewType == "inputToolbar",
               summary.hasInputToolbar {
                return summary.description
            }

            try await Task.sleep(nanoseconds: 30_000_000)
        }

        throw QuillSignalRealConversationProbeError.pendingRequestDidNotSettle(
            summary: try pendingRequestDebugSummary(cvc: cvc).description,
        )
    }

    private nonisolated static func acceptedThread(transaction tx: DBReadTransaction) throws(QuillSignalRealConversationProbeError) -> TSContactThread {
        let contactAddress = SignalServiceAddress(
            serviceId: Aci(fromUUID: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!),
            e164: E164("+15555550112")!
        )
        guard let thread = TSContactThread.getWithContactAddress(contactAddress, transaction: tx) else {
            throw QuillSignalRealConversationProbeError.missingSeedThread
        }
        return thread
    }

    private static func pendingRequestDebugSummary(cvc: ConversationViewController) throws -> PendingRequestDebugSummary {
        let dbPending = try SSKEnvironment.shared.databaseStorageRef.read { tx throws(QuillSignalRealConversationProbeError) in
            guard let thread = TSContactThread.getWithContactAddress(SeedMode.pendingRequest.contactAddress, transaction: tx) else {
                throw .missingSeedThread
            }
            return thread.hasPendingMessageRequest(transaction: tx)
        }
        return PendingRequestDebugSummary(
            dbPending: dbPending,
            viewModelPending: cvc.threadViewModel.hasPendingMessageRequest,
            bottomViewType: String(describing: cvc.bottomViewType),
            hasInputToolbar: cvc.inputToolbar != nil,
        )
    }

    private nonisolated static func interactionDebugSummary(threadUniqueId: String, database: Database) throws -> String {
        let bodies = try String.fetchAll(
            database,
            sql: """
                SELECT COALESCE(body, '')
                FROM \(InteractionRecord.databaseTableName)
                WHERE uniqueThreadId = ?
                ORDER BY timestamp ASC, id ASC
                """,
            arguments: [threadUniqueId],
        )
        let bodyList = bodies.map { "\"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }.joined(separator: ", ")
        return "count=\(bodies.count) bodies=[\(bodyList)]"
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
            if SSKEnvironment.shared.profileManagerRef.localProfileKey(tx: tx) == nil {
                let keyData = Data((0..<Int(Aes256Key.keyByteLength)).map { UInt8($0 + 1) })
                SSKEnvironment.shared.profileManagerRef.setLocalProfileKey(
                    Aes256Key(data: keyData)!,
                    userProfileWriter: .localUser,
                    transaction: tx,
                )
            }

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
    case unexpectedViewController(String)
    case injectedMessageDidNotRender(interactionUniqueId: String, renderItems: Int)
    case pendingRequestDidNotSettle(summary: String)

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
        case let .unexpectedViewController(typeName):
            return "Expected ConversationViewController, received \(typeName)."
        case let .injectedMessageDidNotRender(interactionUniqueId, renderItems):
            return "Injected incoming message did not render (interactionUniqueId=\(interactionUniqueId), renderItems=\(renderItems))."
        case let .pendingRequestDidNotSettle(summary):
            return "Pending request did not settle after Continue (\(summary))."
        }
    }
}

private struct PendingRequestDebugSummary: CustomStringConvertible {
    let dbPending: Bool
    let viewModelPending: Bool
    let bottomViewType: String
    let hasInputToolbar: Bool

    var description: String {
        "dbPending=\(dbPending) viewModelPending=\(viewModelPending) bottomViewType=\(bottomViewType) hasInputToolbar=\(hasInputToolbar)"
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
            return "Hey, I just sent this from the seeded Signal storage path."
        case .accepted:
            return "Hey, can you review the latest Signal render on Linux?"
        }
    }

    var outgoingText: String {
        switch self {
        case .pendingRequest:
            return "It is rendering through the real ConversationViewController."
        case .accepted:
            return "Yes. The real conversation view, message bubbles, and composer are on screen now."
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
