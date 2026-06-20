// QuillRealComponentPreview.swift -- real Signal conversation components on Linux.
//
// This file is symlinked into Signal's disposable app target by
// scripts/quill-signal-prep-app.sh. It intentionally lives in the SignalApp
// module at build time so renderer smoke tests can use Signal's internal
// CVItemModel / CVRootComponent / CVCellView pipeline instead of a handcrafted
// conversation mock.

public import Foundation
public import LibSignalClient
public import SignalServiceKit
public import SignalUI
public import UIKit

@MainActor
public enum QuillSignalRealComponentPreview {
    public static func makeViewController() -> UIViewController {
        let width: CGFloat = 520
        let builder = QuillSignalRealComponentBuilder(width: width)
        let renderItems = builder.makeRenderItems()

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.frame = CGRect(x: 24, y: 28, width: width, height: 220)
        stack.accessibilityIdentifier = "qclass:qrealcomponentstack"

        for renderItem in renderItems {
            let cellView = CVCellView()
            cellView.frame = CGRect(origin: .zero, size: renderItem.cellSize)
            cellView.accessibilityIdentifier = "qclass:qrealcvcell"
            cellView.configure(renderItem: renderItem, componentDelegate: builder.componentDelegate)
            stack.addArrangedSubview(cellView)
        }

        let title = UILabel()
        title.text = "Real Signal CVComponents"
        title.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        title.textColor = UIColor.Signal.label

        let subtitle = UILabel()
        subtitle.text = "Rendered through CVItemModel -> CVRootComponent -> CVCellView -> GTK."
        subtitle.font = UIFont.systemFont(ofSize: 13)
        subtitle.textColor = UIColor.Signal.secondaryLabel
        subtitle.numberOfLines = 0

        let header = UIStackView(arrangedSubviews: [title, subtitle])
        header.axis = .vertical
        header.spacing = 4
        header.frame = CGRect(x: 24, y: 24, width: width, height: 48)

        let root = UIView(frame: CGRect(x: 0, y: 0, width: width + 48, height: 300))
        root.backgroundColor = .white
        root.addSubview(header)
        stack.frame.origin.y = 96
        stack.frame.size.height = 320
        root.addSubview(stack)
        root.frame.size.height = 460

        let vc = UIViewController()
        vc.view = root
        return vc
    }
}

@MainActor
private final class QuillSignalPreviewComponentDelegate: NSObject, CVComponentDelegate {
    let backingView = UIView()

    var view: UIView! {
        backingView
    }

    func enqueueReload() {}

    func enqueueReloadWithoutCaches() {}

    func beginCellAnimation(maximumDuration: TimeInterval) -> () -> Void {
        _ = maximumDuration
        return {}
    }
}

@MainActor
private final class QuillSignalRealComponentBuilder {
    let componentDelegate = QuillSignalPreviewComponentDelegate()

    private let width: CGFloat
    private let thread: TSContactThread
    private let associatedData: ThreadAssociatedData
    private let conversationStyle: ConversationStyle
    private let mediaCache = CVMediaCache()

    init(width: CGFloat) {
        self.width = width
        self.thread = TSContactThread(
            uniqueId: "quill-signal-real-component-preview",
            contactUUID: nil,
            contactPhoneNumber: "+15555550100",
        )
        self.associatedData = ThreadAssociatedData.quillPreview(threadUniqueId: thread.uniqueId)
        self.conversationStyle = ConversationStyle(
            type: .default,
            thread: thread,
            viewWidth: width,
            hasWallpaper: false,
            shouldDimWallpaperInDarkMode: false,
            chatColor: PaletteChatColor.ultramarine.colorSetting,
            isStandaloneRenderItem: true,
        )
    }

    func makeRenderItems() -> [CVRenderItem] {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let dateInteraction = DateHeaderInteraction(thread: thread, timestamp: timestamp)
        let unreadInteraction = UnreadIndicatorInteraction(
            thread: thread,
            timestamp: timestamp + 1,
            receivedAtTimestamp: timestamp + 1,
        )

        return [
            makeDateHeader(interaction: dateInteraction),
            makeTextMessage(
                text: "Hey, can you check the Linux render pass? The bubble should wrap like Signal.",
                incoming: true,
            ),
            makeTextMessage(
                text: "On it. This is a real CVComponentMessage, not a handmade preview row.",
                incoming: false,
            ),
            makeUnreadIndicator(interaction: unreadInteraction),
        ]
    }

    private func makeDateHeader(interaction: TSInteraction) -> CVRenderItem {
        let itemViewState = CVItemViewState.Builder()
        itemViewState.dateHeaderState = CVComponentDateHeader.buildState(interaction: interaction)
        let itemModel = makeItemModel(
            interaction: interaction,
            componentState: .quillPreviewDateHeaderState(),
            itemViewState: itemViewState.build(),
        )
        let dateHeaderState = itemModel.itemViewState.dateHeaderState ?? CVComponentDateHeader.buildState(interaction: interaction)
        let component = CVComponentDateHeader(itemModel: itemModel, dateHeaderState: dateHeaderState)
        return makeRenderItem(itemModel: itemModel, rootComponent: component)
    }

    private func makeUnreadIndicator(interaction: TSInteraction) -> CVRenderItem {
        let itemModel = makeItemModel(
            interaction: interaction,
            componentState: .quillPreviewUnreadIndicatorState(),
            itemViewState: CVItemViewState.Builder().build(),
        )
        let component = CVComponentUnreadIndicator(itemModel: itemModel)
        return makeRenderItem(itemModel: itemModel, rootComponent: component)
    }

    private func makeTextMessage(text: String, incoming: Bool) -> CVRenderItem {
        let messageBody = QuillSignalPreviewValidatedMessageBody(text)
        let interaction: TSInteraction = if incoming {
            MockIncomingMessage(
                messageBody: messageBody,
                thread: thread,
                authorAci: Aci(fromUUID: UUID(uuidString: "00000000-0000-4000-8000-000000000111")!),
            )
        } else {
            MockOutgoingMessage(messageBody: messageBody, thread: thread)
        }

        let displayableText = DisplayableText.quillPreviewPlainText(text)
        let componentState = CVComponentState.quillPreviewTextMessageState(displayableText: displayableText)
        let snapshot = CVViewStateSnapshot.mockSnapshotForStandaloneItems(
            coreState: coreState,
            spoilerReveal: SpoilerRevealState(),
        )
        let itemViewState = CVItemViewState.Builder()
        itemViewState.accessibilityAuthorName = incoming ? "Quill Preview" : nil
        itemViewState.shouldHideFooter = true
        itemViewState.isFirstInCluster = true
        itemViewState.isLastInCluster = true
        itemViewState.bodyTextState = CVComponentBodyText.buildState(
            interaction: interaction,
            bodyText: componentState.bodyText!,
            viewStateSnapshot: snapshot,
            hasPendingMessageRequest: false,
        )
        let itemModel = makeItemModel(
            interaction: interaction,
            componentState: componentState,
            itemViewState: itemViewState.build(),
        )
        let component = CVComponentMessage(itemModel: itemModel)
        return makeRenderItem(itemModel: itemModel, rootComponent: component)
    }

    private func makeItemModel(
        interaction: TSInteraction,
        componentState: CVComponentState,
        itemViewState: CVItemViewState,
    ) -> CVItemModel {
        CVItemModel(
            interaction: interaction,
            thread: thread,
            threadAssociatedData: associatedData,
            componentState: componentState,
            itemViewState: itemViewState,
            coreState: coreState,
        )
    }

    private var coreState: CVCoreState {
        CVCoreState(conversationStyle: conversationStyle, mediaCache: mediaCache)
    }

    private func makeRenderItem(itemModel: CVItemModel, rootComponent: CVRootComponent) -> CVRenderItem {
        let measurement = CVCellMeasurement.Builder()
        measurement.cellSize = rootComponent.measure(maxWidth: width, measurementBuilder: measurement)
        return CVRenderItem(
            itemModel: itemModel,
            rootComponent: rootComponent,
            cellMeasurement: measurement.build(),
        )
    }
}

private struct QuillSignalPreviewValidatedMessageBody: ValidatedInlineMessageBody {
    let inlinedBody: MessageBody

    init(_ text: String) {
        self.inlinedBody = MessageBody(text: text, ranges: .empty)
    }
}
