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
    private static let contactAci = Aci(fromUUID: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)
    private static let localE164 = E164("+15555550100")!
    private static let contactE164 = E164("+15555550111")!
    private static let contactAddress = SignalServiceAddress(serviceId: contactAci, e164: contactE164)

    public static func makeViewController(width: CGFloat = 760, height: CGFloat = 720) async throws -> UIViewController {
        let bootstrap = try await quillBootstrapSignalRenderEnvironment()
        try await seedConversationIfNeeded(bootstrap: bootstrap)

        let cvc = try bootstrap.databaseStorage.read { tx throws(QuillSignalRealConversationProbeError) in
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

        try await prepareForRender(cvc: cvc, width: width, height: height)
        return cvc as UIViewController
    }

    private static func seedConversationIfNeeded(bootstrap: QuillSignalRenderBootstrap) async throws {
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

            let thread = TSContactThread.getOrCreateThread(withContactAddress: contactAddress, transaction: tx)
            ThreadAssociatedData.create(for: thread.uniqueId, transaction: tx)

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
                authorAci: contactAci,
                authorE164: contactE164,
                messageBody: QuillSignalSeedMessageBody("Hey, this is the real ConversationViewController loading from Signal storage."),
                read: true,
                serverTimestamp: now,
                serverDeliveryTimestamp: now,
                serverGuid: "quill-real-conversation-incoming-1",
                wasReceivedByUD: false,
            )
            .build()
            .anyInsert(transaction: tx)

            TSOutgoingMessageBuilder.withDefaultValues(
                thread: thread,
                timestamp: now + 1,
                receivedAtTimestamp: now + 1,
                messageBody: QuillSignalSeedMessageBody("And this reply is a real TSOutgoingMessage rendered through CVC."),
            )
            .build(transaction: tx)
            .anyInsert(transaction: tx)
        }

        bootstrap.databaseStorage.read { tx in
            bootstrap.dependenciesBridge.tsAccountManager.warmCaches(tx: tx)
        }
    }

    private static func prepareForRender(cvc: ConversationViewController, width: CGFloat, height: CGFloat) async throws {
        if !cvc.isViewLoaded {
            cvc.loadView()
            if cvc.viewIfLoaded == nil {
                cvc.view = UIView()
            }
            cvc.viewIfLoaded?.frame = CGRect(x: 0, y: 0, width: width, height: height)
            cvc.viewDidLoad()
        }

        cvc.view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        cvc.collectionView.frame = cvc.view.bounds
        cvc.view.layoutIfNeeded()

        _ = cvc.updateConversationStyle()
        cvc.viewWillAppearDidBegin()
        cvc.isViewVisible = true
        cvc.viewWillAppearForLoad()
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
    case missingSeedThread
    case initialRenderDidNotProduceCells(renderItems: Int, visibleCells: Int, shouldHideContent: Bool)

    public var description: String {
        switch self {
        case .missingLocalIdentifiersSetter:
            return "TSAccountManager does not expose LocalIdentifiersSetter."
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
