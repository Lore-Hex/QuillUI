import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if os(Linux)
import Glibc
#endif
import Testing
import SwiftUI
import SwiftData
import Combine
import UIKit
import AVFoundation
import AudioToolbox
import QuillKit
import QuillFoundation
import ActivityIndicatorView
import MarkdownUI
import Splash
import OllamaKit
import AsyncAlgorithms
import Carbon
import CoreSpotlight
// Scoped: the AppKit shadow supplies kUTTypeData (upstream Telegram pairs
// `import Cocoa` with CoreSpotlight in packages/Spotlight); a full
// `import AppKit` here would collide with the UIKit shim surface.
import let AppKit.kUTTypeData
import Vision
import IOKit
import IOKit.pwr_mgt
import IOKit.usb
@_spi(QuillTesting) import WrappingHStack
import Vortex
import KeyboardShortcuts
import Magnet
import Sparkle
import ServiceManagement
@_spi(QuillTesting) import QuillUI

private final class PausingSpeechDelegate: AVSpeechSynthesizerDelegate {
    var events: [String] = []
    var pauseResult: Bool?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        events.append("start")
        pauseResult = synthesizer.pauseSpeaking(at: .word)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        events.append("finish")
    }
}

private final class CompatibilityLockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func update(_ body: (inout Value) -> Void) {
        lock.withLock {
            body(&storedValue)
        }
    }
}

@MainActor
private final class CollectionViewProbe: UICollectionViewDataSource, UICollectionViewDelegate {
    var requestedCells: [IndexPath] = []
    var displayedCells: [IndexPath] = []
    var cellsByIndexPath: [IndexPath: UICollectionViewCell] = [:]

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        _ = collectionView
        return 2
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        _ = collectionView
        return section + 1
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        requestedCells.append(indexPath)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "compat-cell", for: indexPath)
        let label = UILabel()
        label.text = "S\(indexPath.section) I\(indexPath.item)"
        cell.contentView.addSubview(label)
        cellsByIndexPath[indexPath] = cell
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        _ = (collectionView, cell)
        displayedCells.append(indexPath)
    }
}

@MainActor
private final class MutableCollectionViewProbe: UICollectionViewDataSource, UICollectionViewDelegate {
    var items: [[String]]
    var requestedCells: [IndexPath] = []
    var displayedCells: [IndexPath] = []
    var cellsByIndexPath: [IndexPath: UICollectionViewCell] = [:]

    init(items: [[String]]) {
        self.items = items
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        _ = collectionView
        return items.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        _ = collectionView
        return items[section].count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        requestedCells.append(indexPath)
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "mutable-cell", for: indexPath)
        let label = UILabel()
        label.text = items[indexPath.section][indexPath.item]
        cell.contentView.addSubview(label)
        cellsByIndexPath[indexPath] = cell
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        _ = (collectionView, cell)
        displayedCells.append(indexPath)
    }
}

@MainActor
private final class UIKitTextViewDelegateProbe: NSObject, UITextViewDelegate {
    var allowsChanges = true
    var shouldBeginRequests = 0
    var didBeginRequests = 0
    var shouldChangeRequests = 0
    var changeNotifications = 0
    var selectionNotifications = 0
    var lastRange: NSRange?
    var lastReplacement: String?
    weak var changedTextView: UITextView?

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        _ = textView
        shouldBeginRequests += 1
        return true
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        _ = textView
        didBeginRequests += 1
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        _ = textView
        shouldChangeRequests += 1
        lastRange = range
        lastReplacement = text
        return allowsChanges
    }

    func textViewDidChange(_ textView: UITextView) {
        changeNotifications += 1
        changedTextView = textView
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        _ = textView
        selectionNotifications += 1
    }
}

@MainActor
private final class UIKitTextInputDelegateProbe: UITextInputDelegate {
    var events: [String] = []

    func selectionWillChange(_ textInput: UITextInput?) {
        _ = textInput
        events.append("selectionWill")
    }

    func selectionDidChange(_ textInput: UITextInput?) {
        _ = textInput
        events.append("selectionDid")
    }

    func textWillChange(_ textInput: UITextInput?) {
        _ = textInput
        events.append("textWill")
    }

    func textDidChange(_ textInput: UITextInput?) {
        _ = textInput
        events.append("textDid")
    }
}

// `@MainActor`: many tests here construct MainActor-isolated SwiftUI views
// (WrappingHStack, etc.) whose initializers run a Swift-6 isolation runtime
// check that SIGTRAPs when evaluated off the main actor. Swift Testing runs
// @Test cases on a background pool, so pin the whole suite to the main actor
// rather than relying on a per-function annotation that's easy to miss
// (thirdPartyUIShimsCompile lacked one and crashed the Linux run).
@Suite("Linux compatibility import modules", .serialized)
@MainActor
struct CompatibilityModuleTests {
    private func pngDimensions(_ data: Data) -> (width: UInt32, height: UInt32)? {
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24, Array(data.prefix(8)) == pngMagic else { return nil }

        let bytes = Array(data)
        let width = (UInt32(bytes[16]) << 24) | (UInt32(bytes[17]) << 16)
                  | (UInt32(bytes[18]) << 8)  |  UInt32(bytes[19])
        let height = (UInt32(bytes[20]) << 24) | (UInt32(bytes[21]) << 16)
                   | (UInt32(bytes[22]) << 8)  |  UInt32(bytes[23])
        return (width, height)
    }

    private func wavData(sampleRate: UInt32 = 8_000, channels: UInt16 = 2, frames: UInt32 = 8_000) -> Data {
        let bitsPerSample: UInt16 = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataByteCount = frames * UInt32(blockAlign)
        let riffByteCount = UInt32(36) + dataByteCount
        var data = Data()

        func appendASCII(_ string: String) {
            data.append(contentsOf: string.utf8)
        }
        func appendUInt16(_ value: UInt16) {
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
        }
        func appendUInt32(_ value: UInt32) {
            data.append(UInt8(value & 0xff))
            data.append(UInt8((value >> 8) & 0xff))
            data.append(UInt8((value >> 16) & 0xff))
            data.append(UInt8((value >> 24) & 0xff))
        }

        appendASCII("RIFF")
        appendUInt32(riffByteCount)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(channels)
        appendUInt32(sampleRate)
        appendUInt32(byteRate)
        appendUInt16(blockAlign)
        appendUInt16(bitsPerSample)
        appendASCII("data")
        appendUInt32(dataByteCount)
        data.append(contentsOf: repeatElement(UInt8(0), count: Int(dataByteCount)))
        return data
    }

    @Test("SwiftUI and SwiftData module aliases expose Quill APIs")
    @MainActor
    func swiftUIAndSwiftDataAliasesExposeQuillAPIs() throws {
        _ = Text("Quill")
            .foregroundStyle(Color("label"))
            .matchedGeometryEffect(id: "title", in: Namespace().wrappedValue)
        _ = ModelConfiguration(isStoredInMemoryOnly: true)
        _ = FetchDescriptor<CompatibilityModel>()
        _ = Window("Compatibility", id: "compatibility") {
            Text("Compatibility")
        }
    }

    @Test("UITextView replacement helper notifies delegates and updates selection")
    func uiTextViewReplacementHelperNotifiesDelegatesAndUpdatesSelection() {
        let view = UITextView()
        let delegate = UIKitTextViewDelegateProbe()
        let inputDelegate = UIKitTextInputDelegateProbe()
        view.delegate = delegate
        view.inputDelegate = inputDelegate
        view.text = "Hello world"

        #expect(view.becomeFirstResponder())
        let replaced = view.quillReplaceCharacters(
            in: NSRange(location: 6, length: 5),
            with: "Signal"
        )

        #expect(replaced)
        #expect(view.text == "Hello Signal")
        #expect(view.selectedRange == NSRange(location: 12, length: 0))
        #expect(view.selectedTextRange.map { view.offset(from: view.beginningOfDocument, to: $0.start) } == 12)
        #expect(delegate.shouldBeginRequests == 1)
        #expect(delegate.didBeginRequests == 1)
        #expect(delegate.shouldChangeRequests == 1)
        #expect(delegate.lastRange == NSRange(location: 6, length: 5))
        #expect(delegate.lastReplacement == "Signal")
        #expect(delegate.changeNotifications == 1)
        #expect(delegate.selectionNotifications == 1)
        #expect(delegate.changedTextView === view)
        #expect(inputDelegate.events == ["textWill", "selectionWill", "textDid", "selectionDid"])

        let vetoView = UITextView()
        let vetoDelegate = UIKitTextViewDelegateProbe()
        vetoDelegate.allowsChanges = false
        vetoView.delegate = vetoDelegate
        vetoView.text = "Keep"

        let vetoed = vetoView.quillReplaceCharacters(
            in: NSRange(location: 0, length: 4),
            with: "Drop"
        )

        #expect(!vetoed)
        #expect(vetoView.text == "Keep")
        #expect(vetoDelegate.shouldChangeRequests == 1)
        #expect(vetoDelegate.changeNotifications == 0)

        let editView = UITextView()
        editView.text = "ab"
        editView.selectedRange = NSRange(location: 2, length: 0)
        editView.insertText("c")
        #expect(editView.text == "abc")
        #expect(editView.selectedRange == NSRange(location: 3, length: 0))
        editView.deleteBackward()
        #expect(editView.text == "ab")
        #expect(editView.selectedRange == NSRange(location: 2, length: 0))

        let emojiView = UITextView()
        emojiView.text = "a🙂b"
        emojiView.selectedRange = NSRange(location: "a🙂".utf16.count, length: 0)
        emojiView.deleteBackward()
        #expect(emojiView.text == "ab")
        #expect(emojiView.selectedRange == NSRange(location: 1, length: 0))
    }

    @Test("UINavigationController owns child navigation back references")
    @MainActor
    func uiNavigationControllerOwnsChildBackReferences() {
        let root = UIViewController()
        let nav = UINavigationController(rootViewController: root)

        #expect(root.navigationController === nav)
        #expect(nav.topViewController === root)
        #expect(nav.viewControllers.count == 1)

        let pushed = UIViewController()
        nav.pushViewController(pushed, animated: false)

        #expect(root.navigationController === nav)
        #expect(pushed.navigationController === nav)
        #expect(nav.topViewController === pushed)
        #expect(nav.viewControllers.map(ObjectIdentifier.init) == [ObjectIdentifier(root), ObjectIdentifier(pushed)])

        let popped = nav.popViewController(animated: false)
        #expect(popped === pushed)
        #expect(pushed.navigationController == nil)
        #expect(root.navigationController === nav)
        #expect(nav.topViewController === root)
    }

    @Test("UICollectionView reload materializes data-source cells")
    @MainActor
    func uiCollectionViewReloadMaterializesDataSourceCells() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 180, height: 32)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 240, height: 180),
            collectionViewLayout: layout
        )
        let probe = CollectionViewProbe()
        collectionView.dataSource = probe
        collectionView.delegate = probe

        collectionView.reloadData()

        let first = IndexPath(item: 0, section: 0)
        let last = IndexPath(item: 1, section: 1)

        #expect(probe.requestedCells == [first, IndexPath(item: 0, section: 1), last])
        #expect(probe.displayedCells == probe.requestedCells)
        #expect(collectionView.visibleCells.count == 3)
        #expect(collectionView.cellForItem(at: last) === probe.cellsByIndexPath[last])
        #expect(collectionView.visibleCells.allSatisfy { $0.superview === collectionView })
        #expect(collectionView.visibleCells.allSatisfy { $0.contentView.frame == $0.bounds })

        collectionView.selectItem(at: last, animated: false, scrollPosition: [])
        #expect(collectionView.indexPathsForSelectedItems == [last])
    }

    @Test("UICollectionView batch mutations refresh realized cells and visible geometry")
    @MainActor
    func uiCollectionViewBatchMutationsRefreshSnapshotAndGeometry() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 120, height: 30)
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 120, height: 59),
            collectionViewLayout: layout
        )
        let probe = MutableCollectionViewProbe(items: [["A", "B", "C"]])
        collectionView.dataSource = probe
        collectionView.delegate = probe

        collectionView.reloadData()

        let first = IndexPath(item: 0, section: 0)
        let second = IndexPath(item: 1, section: 0)
        let third = IndexPath(item: 2, section: 0)
        #expect(collectionView.indexPathsForVisibleItems == [first, second])
        #expect(collectionView.visibleCells.count == 2)
        #expect(collectionView.indexPathForItem(at: CGPoint(x: 10, y: 65)) == third)

        collectionView.selectItem(at: second, animated: false, scrollPosition: [])
        collectionView.deselectItem(at: second, animated: false)
        #expect(collectionView.indexPathsForSelectedItems == nil)

        let oldFirstCell = collectionView.cellForItem(at: first)
        probe.items[0][0] = "A*"
        collectionView.reloadItems(at: [first])
        #expect(collectionView.cellForItem(at: first) !== oldFirstCell)

        var batchFinished = false
        let fourth = IndexPath(item: 3, section: 0)
        probe.items[0].append("D")
        collectionView.performBatchUpdates({
            collectionView.insertItems(at: [fourth])
        }, completion: { finished in
            batchFinished = finished
        })

        #expect(batchFinished)
        #expect(collectionView.cellForItem(at: fourth) != nil)

        collectionView.scrollToItem(at: fourth, at: .bottom, animated: false)
        #expect(collectionView.contentOffset.y > 0)
        #expect(collectionView.indexPathsForVisibleItems.contains(fourth))

        probe.items[0].remove(at: 1)
        collectionView.performBatchUpdates({
            collectionView.deleteItems(at: [second])
        }, completion: nil)
        #expect(collectionView.cellForItem(at: IndexPath(item: 2, section: 0)) != nil)
    }

    @Test("UIView frame keeps bounds size and invalidates manual layout")
    @MainActor
    func uiViewFrameKeepsBoundsSizeAndInvalidatesManualLayout() {
        final class LayoutProbeView: UIView {
            var layoutSizes: [CGSize] = []

            override func layoutSubviews() {
                layoutSizes.append(bounds.size)
            }
        }

        let view = LayoutProbeView(frame: CGRect(x: 10, y: 20, width: 120, height: 40))
        #expect(view.bounds.origin == .zero)
        #expect(view.bounds.size == CGSize(width: 120, height: 40))

        view.layoutIfNeeded()
        #expect(view.layoutSizes == [CGSize(width: 120, height: 40)])

        view.bounds.origin = CGPoint(x: 7, y: 9)
        view.frame = CGRect(x: 1, y: 2, width: 200, height: 64)

        #expect(view.bounds.origin == CGPoint(x: 7, y: 9))
        #expect(view.bounds.size == CGSize(width: 200, height: 64))

        view.layoutIfNeeded()
        #expect(view.layoutSizes == [
            CGSize(width: 120, height: 40),
            CGSize(width: 200, height: 64),
        ])
    }

    @Test("UIView layoutIfNeeded applies direct edge constraints")
    @MainActor
    func uiViewLayoutIfNeededAppliesDirectEdgeConstraints() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let child = UIView()
        parent.addSubview(child)

        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: 10),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 5),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -20),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -15),
        ])

        parent.layoutIfNeeded()

        #expect(child.frame == CGRect(x: 5, y: 10, width: 180, height: 90))
        #expect(child.bounds == CGRect(x: 0, y: 0, width: 180, height: 90))
    }

    @Test("UIView layout guides added to a view resolve edge constraints")
    @MainActor
    func uiViewAddedLayoutGuidesResolveEdgeConstraints() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let guide = UILayoutGuide()
        parent.addLayoutGuide(guide)

        let child = UIView()
        parent.addSubview(child)

        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: guide.topAnchor),
            child.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])

        parent.layoutIfNeeded()

        #expect(child.frame == parent.bounds)
    }

    @Test("UIView layout resolves nested child constraints to ancestor anchors")
    @MainActor
    func uiViewLayoutResolvesNestedChildConstraintsToAncestorAnchors() {
        let parent = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
        let child = UIView()
        parent.addSubview(wrapper)
        wrapper.addSubview(child)

        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: 10),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 12),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -14),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -16),
        ])

        parent.layoutIfNeeded()

        #expect(child.frame == CGRect(x: 12, y: 10, width: 174, height: 94))
    }

    @Test("UIView layout uses intrinsic size for edge-pinned controls")
    @MainActor
    func uiViewLayoutUsesIntrinsicSizeForEdgePinnedControls() {
        final class IntrinsicControl: UIControl {
            override var intrinsicContentSize: CGSize {
                CGSize(width: 40, height: 40)
            }
        }

        let root = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 140))
        let primary = IntrinsicControl()
        let secondary = IntrinsicControl()
        root.addSubview(primary)
        root.addSubview(secondary)

        NSLayoutConstraint.activate([
            primary.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -15),
            primary.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            secondary.trailingAnchor.constraint(equalTo: primary.trailingAnchor),
            secondary.bottomAnchor.constraint(equalTo: primary.topAnchor, constant: -30),
        ])

        root.layoutIfNeeded()

        #expect(primary.frame == CGRect(x: 145, y: 76, width: 40, height: 40))
        #expect(secondary.frame == CGRect(x: 145, y: 6, width: 40, height: 40))
    }

    @Test("UIView infers bottom-pinned container height from edge-pinned stack")
    @MainActor
    func uiViewInfersBottomPinnedContainerHeightFromEdgePinnedStack() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        let container = UIView()
        root.addSubview(container)

        let label = UILabel()
        label.text = "Signal bottom bar"
        label.font = UIFont.systemFont(ofSize: 17)

        let detail = UILabel()
        detail.text = "Fitting height comes from arranged subviews."
        detail.font = UIFont.systemFont(ofSize: 13)

        let stack = UIStackView(arrangedSubviews: [label, detail])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        root.layoutIfNeeded()

        #expect(container.frame.width == 240)
        #expect(container.frame.height > 0)
        #expect(container.frame.maxY == 180)
        #expect(stack.frame == container.bounds)
        #expect(label.frame.height > 0)
        #expect(detail.frame.minY > label.frame.maxY)
    }

    @Test("UIView fitting honors minimum child height through layout margins")
    @MainActor
    func uiViewFittingHonorsMinimumChildHeightThroughLayoutMargins() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 240, height: 180))
        let container = UIView()
        container.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        root.addSubview(container)

        let field = UIView()
        container.addSubview(field)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            field.topAnchor.constraint(equalTo: container.layoutMarginsGuide.topAnchor),
            field.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            field.bottomAnchor.constraint(equalTo: container.layoutMarginsGuide.bottomAnchor),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])

        root.layoutIfNeeded()

        #expect(container.frame == CGRect(x: 0, y: 124, width: 240, height: 56))
        #expect(field.frame == CGRect(x: 12, y: 8, width: 216, height: 40))
    }

    @Test("UIStackView lays out arranged labels")
    @MainActor
    func uiStackViewLaysOutArrangedLabels() {
        let first = UILabel()
        first.text = "Signal"
        first.font = UIFont.systemFont(ofSize: 18)

        let second = UILabel()
        second.text = "Linux renderer"
        second.font = UIFont.systemFont(ofSize: 13)

        let stack = UIStackView(arrangedSubviews: [first, second])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 4
        stack.frame = CGRect(x: 0, y: 0, width: 220, height: 80)

        stack.layoutIfNeeded()

        #expect(first.frame.width == 220)
        #expect(first.frame.height > 0)
        #expect(second.frame.width == 220)
        #expect(second.frame.minY > first.frame.maxY)

        let horizontalFirst = UILabel()
        horizontalFirst.text = "Block"
        let horizontalSecond = UILabel()
        horizontalSecond.text = "Continue"
        let horizontal = UIStackView(arrangedSubviews: [horizontalFirst, horizontalSecond])
        horizontal.axis = .horizontal
        horizontal.alignment = .fill
        horizontal.spacing = 8
        let unboundedFit = horizontal.sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))
        #expect(unboundedFit.height > 0)
        #expect(unboundedFit.height < 1_000)
    }

    @Test("UIButton configuration contributes intrinsic stack size")
    @MainActor
    func uiButtonConfigurationContributesIntrinsicStackSize() {
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Accept"
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)

        let button = UIButton(configuration: configuration)
        let fit = button.sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))

        #expect(fit.width > 24)
        #expect(fit.height > 16)

        let stack = UIStackView(arrangedSubviews: [button])
        stack.axis = .horizontal
        stack.alignment = .fill
        let stackFit = stack.sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ))

        #expect(stackFit.height == fit.height)

        stack.frame = CGRect(x: 0, y: 0, width: 160, height: fit.height)
        stack.layoutIfNeeded()

        #expect(button.frame.height == fit.height)
        #expect(button.titleLabel?.frame.height ?? 0 > 0)
        #expect(button.titleLabel?.frame.minX ?? 0 >= 12)
    }

    @Test("Quill localization resolves Apple strings resources")
    @MainActor
    func quillLocalizationResolvesAppleStringsResources() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillLocalizationTests-\(UUID().uuidString)", isDirectory: true)
        let en = root.appendingPathComponent("en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: en, withIntermediateDirectories: true)
        try #"""
        /* Comment */
        "MESSAGE_REQUEST_VIEW_BLOCK_BUTTON" = "Block";
        "ESCAPED_VALUE" = "Line\nTwo";
        """#.write(
            to: en.appendingPathComponent("Localizable.strings"),
            atomically: true,
            encoding: .utf8
        )

        #if os(Linux)
        setenv("QUILLUI_RESOURCE_DIRS", root.path, 1)
        defer { unsetenv("QUILLUI_RESOURCE_DIRS") }
        #endif

        #expect(QuillResourceLookup.localizedString(
            forKey: "MESSAGE_REQUEST_VIEW_BLOCK_BUTTON",
            preferredLocalizations: ["en"]
        ) == "Block")
        #expect(QuillResourceLookup.localizedString(
            forKey: "ESCAPED_VALUE",
            preferredLocalizations: ["en"]
        ) == "Line\nTwo")
        #expect(QuillResourceLookup.localizedString(
            forKey: "MISSING_KEY",
            value: "Fallback",
            preferredLocalizations: ["en"]
        ) == "Fallback")
    }

    @Test("UIVisualEffectView contentView fills bounds")
    @MainActor
    func uiVisualEffectViewContentViewFillsBounds() {
        let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        effectView.frame = CGRect(x: 0, y: 0, width: 180, height: 44)

        effectView.layoutIfNeeded()

        #expect(effectView.contentView.frame == CGRect(x: 0, y: 0, width: 180, height: 44))
    }

    @Test("NSLayoutManager treats huge text container widths as unconstrained")
    @MainActor
    func nsLayoutManagerTreatsHugeTextContainerWidthsAsUnconstrained() {
        let huge = Foundation.CGFloat.greatestFiniteMagnitude
        let layoutManager = UIKit.NSLayoutManager()
        let textContainer = UIKit.NSTextContainer(
            size: CGSize(width: huge, height: huge)
        )
        layoutManager.addTextContainer(textContainer)

        let storage = UIKit.NSTextStorage(
            string: "Signal date header",
            attributes: [.font: UIFont.systemFont(ofSize: 14)]
        )
        storage.addLayoutManager(layoutManager)

        let usedRect = withExtendedLifetime(storage) {
            layoutManager.usedRect(for: textContainer)
        }

        #expect(usedRect.width > 0)
        #expect(usedRect.height > 0)
        #expect(usedRect.width.isFinite)
        #expect(usedRect.height.isFinite)
        let expectedSingleLineWidth = CGFloat(storage.length) * 14 * 0.6
        #expect(usedRect.width <= expectedSingleLineWidth + 0.001)
        #expect(
            layoutManager.glyphIndex(
                for: CGPoint(x: huge, y: huge),
                in: textContainer
            ) == storage.length - 1
        )
    }

    @Test("NSLayoutManager measures attributed storage without reading fragile font attributes")
    @MainActor
    func nsLayoutManagerMeasuresAttributedStorageWithFontAttributes() {
        let layoutManager = UIKit.NSLayoutManager()
        let textContainer = UIKit.NSTextContainer(size: CGSize(width: 180, height: 500))
        layoutManager.addTextContainer(textContainer)

        let storage = UIKit.NSTextStorage(
            string: "Signal thread details",
            attributes: [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.label,
            ]
        )
        storage.addLayoutManager(layoutManager)

        let usedRect = withExtendedLifetime(storage) {
            layoutManager.usedRect(for: textContainer)
        }

        #expect(usedRect.width > 0)
        #expect(usedRect.height > 0)
        #expect(usedRect.width.isFinite)
        #expect(usedRect.height.isFinite)
    }

    @Test("QuillUI fallback modifiers record diagnostics")
    @MainActor
    func quillUIFallbackModifiersRecordDiagnostics() {
        let captured = QuillCompatibilityDiagnostics.shared.captureIsolatedEvents {

        _ = Text("Fallback")
            .symbolEffect(.variableColor, value: true)
            .matchedGeometryEffect(id: "title", in: Namespace().wrappedValue)
            .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
            .mask(Rectangle())
            .mask(Text("Mask"))
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .gesture(DragGesture().onChanged { _ in }.onEnded { _ in })
            .onHover { _ in }
            .focusEffectDisabled(false)
            .edgesIgnoringSafeArea(.top)
            .ignoresSafeArea(.bottom)
            .listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
            .listRowSeparator(.hidden, edges: .vertical)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .minimumScaleFactor(0.5)
            .textSelection(.enabled)
            .keyboardType(.URL)
            .autocapitalization(.never)
            .disableAutocorrection(true)
            .textContentType(.URL)
            .symbolRenderingMode(.hierarchical)

        _ = Text("Icon scaled").imageScale(.large)
        _ = Image(systemName: "photo").renderingMode(.template)
        _ = Form { Text("Field") }.formStyle(.grouped)

#if os(Linux)
        let scaled = Text("Scaled").minimumScaleFactor(0.5)
        #expect(scaled.factor == 0.5)
        #expect(String(describing: type(of: scaled)).contains("MinimumScaleFactorView"))

        let imageScaled = Text("Icon scaled").imageScale(.large)
        #expect(String(describing: type(of: imageScaled)).contains("ImageScaleView"))
        #expect(String(describing: imageScaled.scale).lowercased().contains("large"))

        let symbolMode = Text("Symbol").symbolRenderingMode(.hierarchical)
        #expect(String(describing: type(of: symbolMode)).contains("SymbolRenderingModeView"))
        #expect(String(describing: symbolMode.mode).lowercased().contains("hierarchical"))

        let rowInsets = Text("Row").listRowInsets(EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))
        #expect(String(describing: type(of: rowInsets)).contains("ListRowInsetsView"))
        #expect(rowInsets.insets == EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4))

        let rowSeparator = Text("Row").listRowSeparator(.hidden, edges: .vertical)
        #expect(String(describing: type(of: rowSeparator)).contains("ListRowSeparatorView"))
        #expect(rowSeparator.visibility == .hidden)
        #expect(rowSeparator.edges == .vertical)

        let scrollIndicators = Text("Scroll").scrollIndicators(.hidden)
        #expect(String(describing: type(of: scrollIndicators)).contains("ScrollIndicatorsView"))
        #expect(String(describing: scrollIndicators.visibility).contains("hidden"))

        let scrollBackground = Text("Scroll").scrollContentBackground(.hidden)
        #expect(String(describing: type(of: scrollBackground)).contains("ScrollContentBackgroundView"))
        #expect(scrollBackground.visibility == .hidden)

        let shapedContent = Text("Hit area").contentShape(Rectangle())
        #expect(String(describing: type(of: shapedContent)).contains("ContentShapeView"))
        #expect(String(describing: type(of: shapedContent.shape)).contains("Rectangle"))

        let hitTesting = Text("Hit Test").allowsHitTesting(false)
        #expect(String(describing: type(of: hitTesting)).contains("AllowsHitTestingView"))
        #expect(hitTesting.enabled == false)
        #expect(quillTextLabel(from: hitTesting) == "Hit Test")

        let gestured = Text("Drag").gesture(DragGesture().onChanged { _ in }.onEnded { _ in })
        #expect(String(describing: type(of: gestured)).contains("GestureView"))
        #expect(String(describing: type(of: gestured.gesture)).contains("DragGesture"))
        #expect(quillTextLabel(from: gestured) == "Drag")

        let transitioned = Text("Transition").transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .top)))
        #expect(String(describing: type(of: transitioned)).contains("TransitionView"))
        #expect(String(describing: transitioned.transition).contains("combined"))
        #expect(String(describing: transitioned.transition).contains("opacity"))
        #expect(String(describing: transitioned.transition).contains("scale"))
        #expect(quillTextLabel(from: transitioned) == "Transition")

        let maskedContent = Text("Masked").mask(Text("Mask"))
        #expect(String(describing: type(of: maskedContent)).contains("ViewMaskView"))
        #expect(quillTextLabel(from: maskedContent) == "Masked")
        #expect(quillTextLabel(from: maskedContent.mask) == "Mask")

        var hoverStates: [Bool] = []
        let hoverable = Text("Hover").onHover { hoverStates.append($0) }
        #expect(String(describing: type(of: hoverable)).contains("OnHoverView"))
        hoverable.action(true)
        hoverable.action(false)
        #expect(hoverStates == [true, false])

        let focusEffect = Text("Focus").focusEffectDisabled(false)
        #expect(String(describing: type(of: focusEffect)).contains("FocusEffectDisabledView"))
        #expect(focusEffect.disabled == false)

        let boolFocus = FocusState<Bool>()
        let focusBound = Text("Focus bound").focused(boolFocus)
        #expect(String(describing: type(of: focusBound)).contains("FocusedView"))
        #expect(focusBound.focusState.wrappedValue == false)
        #expect(quillTextLabel(from: focusBound) == "Focus bound")

        let optionalFocus = FocusState<String?>()
        let focusEquals = Text("Field focus").focused(optionalFocus, equals: "prompt")
        #expect(String(describing: type(of: focusEquals)).contains("FocusedEqualsView"))
        #expect(focusEquals.value == "prompt")
        #expect(quillTextLabel(from: focusEquals) == "Field focus")

        let bindingFocus = Text("Binding focus").focused(Binding.constant(true))
        #expect(String(describing: type(of: bindingFocus)).contains("FocusBindingView"))
        #expect(bindingFocus.binding.wrappedValue)
        #expect(quillTextLabel(from: bindingFocus) == "Binding focus")

        let optionalBindingFocus = Text("Optional binding focus")
            .focused(Binding.constant(Optional("chat")), equals: "chat")
        #expect(String(describing: type(of: optionalBindingFocus)).contains("FocusEqualsBindingView"))
        #expect(optionalBindingFocus.value == "chat")
        #expect(optionalBindingFocus.binding.wrappedValue == "chat")
        #expect(quillTextLabel(from: optionalBindingFocus) == "Optional binding focus")

        let legacySafeArea = Text("Legacy Safe Area").edgesIgnoringSafeArea(.top)
        #expect(String(describing: type(of: legacySafeArea)).contains("EdgesIgnoringSafeAreaView"))
        #expect(legacySafeArea.edges == .top)

        let ignoredSafeArea = Text("Safe Area").ignoresSafeArea(.bottom)
        #expect(String(describing: type(of: ignoredSafeArea)).contains("IgnoresSafeAreaView"))
        #expect(ignoredSafeArea.edges == .bottom)

        let selectable = Text("Selectable").textSelection(.enabled)
        #expect(String(describing: type(of: selectable)).contains("TextSelectionView"))
        #expect(String(describing: selectable.selection).contains("enabled"))

        let keyboardTyped = Text("URL").keyboardType(.URL)
        #expect(String(describing: type(of: keyboardTyped)).contains("KeyboardTypeView"))
        #expect(keyboardTyped.keyboardType == .URL)

        let autocapitalized = Text("Lowercase").autocapitalization(.never)
        #expect(String(describing: type(of: autocapitalized)).contains("AutocapitalizationView"))
        #expect(autocapitalized.autocapitalization == .never)

        let autocorrectionDisabled = Text("No correction").disableAutocorrection(true)
        #expect(String(describing: type(of: autocorrectionDisabled)).contains("AutocorrectionDisabledView"))
        #expect(autocorrectionDisabled.disabled == true)

        let typedContent = Text("URL").textContentType(.URL)
        #expect(String(describing: type(of: typedContent)).contains("TextContentTypeView"))
        #expect(typedContent.contentType == .URL)
#endif
        }

        let operations = Set(captured.events.map { $0.operation })
        #expect(operations.isSuperset(of: Set([
            "symbolEffect",
            "matchedGeometryEffect",
            "transition",
            "mask",
            "contentShape",
            "allowsHitTesting",
            "gesture",
            "onHover",
            "focusEffectDisabled",
            "focused",
            "edgesIgnoringSafeArea",
            "ignoresSafeArea",
            "listRowInsets",
            "listRowSeparator",
            "scrollIndicators",
            "scrollContentBackground",
            "minimumScaleFactor",
            "textSelection",
            "keyboardType",
            "autocapitalization",
            "disableAutocorrection",
            "textContentType",
            "imageScale",
            "symbolRenderingMode",
            "renderingMode",
            "formStyle"
        ])))
    }

    @Test("third-party UI packages compile to visible SwiftUI-shaped views")
    func thirdPartyUIShimsCompile() {
        _ = ActivityIndicatorView(isVisible: .constant(true), type: .rotatingDots(count: 5))
        _ = ActivityIndicatorView(isVisible: .constant(true), type: .growingCircle)
        _ = Markdown("# Heading\n\n```swift\nprint(\"Quill\")\n```")
            .markdownCodeSyntaxHighlighter(PlainTextCodeSyntaxHighlighter())
            .markdownTheme(markdownContractTheme)
        let wrapping = WrappingHStack(alignment: .leading, spacing: 12) {
            Text("One")
            Text("Two")
        }
        #expect(wrapping.children.count == 2)
        #expect(wrapping.quillResolvedSpacing == 12)
        #expect(wrapping.quillResolvedAlignment == .leading)
        _ = VortexView(.splash.makeUniqueCopy()) {
            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
        }
        _ = KeyboardShortcuts.Recorder("Keyboard shortcut", name: "togglePanelMode")
        _ = Text("Shortcut").onKeyboardShortcut("togglePanelMode", type: .keyDown) {}
    }

    @Test("AppKit image and KeyboardShortcuts compatibility cover Enchanted full source")
    @MainActor
    func appKitImageAndKeyboardShortcutCompatibility() throws {
        let shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .shift])
        let name = KeyboardShortcuts.Name("togglePanelMode", default: shortcut)
        #expect(name.rawValue == "togglePanelMode")
        #expect(name.defaultShortcut == shortcut)
        #expect(KeyboardShortcuts.Shortcut(.character("p")).key == .character("p"))
        #expect(KeyboardShortcuts.Name("togglePanelMode") == name)

        let result = try AppleCompatibilitySmoke.runAppKitImageSmoke()
        #expect(result.sizeRoundTrip)
        #expect(result.focusBitmapCreated)
        #expect(result.copyDrawReplacesDestination)
        #expect(result.namedImagePlaceholder)
        #expect(result.systemImagePlaceholder)
        #expect(result.workspaceFileIconPlaceholder)
        #expect(result.workspaceContentTypeIconPlaceholder)
        #expect(result.unknownBundleApplicationMissing)
        #expect(result.unknownSchemeApplicationMissing)
        #expect(result.bitmapRepresentationRoundTrip)
        #expect(result.windowTabbingRoundTrip)
        #expect(result.operations.isSuperset(of: Set([
            "NSImage(named:)",
            "NSImage(systemName:)",
            "NSWorkspace.icon(forFile:)",
            "NSWorkspace.icon(forContentType:)",
            "NSWorkspace.urlForApplication(withBundleIdentifier:)",
            "NSWorkspace.urlForApplication(toOpen:)"
        ])))
    }

    @Test("AppKit audio compatibility routes NSSound through QuillKit")
    @MainActor
    func appKitAudioCompatibilityRoutesNSSoundThroughQuillKit() {
        let result = AppleCompatibilitySmoke.runAppKitAudioSmoke()
        #expect(result.dataSoundCreated)
        #expect(result.playSucceeded)
        #expect(result.stopSucceeded)
        #expect(result.playCount == 1)
        #expect(result.stopCount == 1)
        #expect(result.stoppedAfterStop)
        #expect(result.operations.isSuperset(of: Set([
            "audioPlayer.play",
            "audioPlayer.stop"
        ])))
    }

    @Test("AppKit workspace open routes through QuillWorkspace")
    @MainActor
    func appKitWorkspaceOpenRoutesThroughQuillWorkspace() {
        let result = AppleCompatibilitySmoke.runAppKitWorkspaceOpenSmoke()
        let expectedURL = URL(string: "https://example.com/quill-appkit-workspace")!
        #expect(result.directOpenSucceeded)
        #expect(result.configurationOpenSucceeded)
        #expect(result.configurationCompletionSucceeded)
        #expect(result.openedURLs == [expectedURL, expectedURL])
        #expect(result.operations.contains("openURL"))
    }

    @Test("AppKit rect string helpers round-trip common geometry formats")
    @MainActor
    func appKitRectStringHelpersRoundTripCommonFormats() {
        let result = AppleCompatibilitySmoke.runAppKitGeometrySmoke()

        #expect(result.stringRoundTrip)
        #expect(result.bracedFormatParsed)
        #expect(result.flatFormatParsed)
        #expect(result.exponentFormatParsed)
        #expect(result.invalidStringReturnsZero)
    }

    @Test("AppKit appearance smoke covers names and best matches")
    @MainActor
    func appKitAppearanceSmokeCoversNamesAndBestMatches() {
        let result = AppleCompatibilitySmoke.runAppKitAppearanceSmoke()

        #expect(result.namedInitializerStoresName)
        #expect(result.highContrastNamesAreDistinct)
        #expect(result.directBestMatch)
        #expect(result.highContrastDarkFallsBackToDark)
        #expect(result.vibrantLightFallsBackToAqua)
        #expect(result.unknownAppearanceDoesNotInventMatch)
    }

    @Test("AppKit font manager exposes deterministic fallback fonts")
    @MainActor
    func appKitFontManagerExposesDeterministicFallbackFonts() {
        let result = AppleCompatibilitySmoke.runAppKitFontSmoke()

        #expect(result.fontsAreDeterministicAndNonEmpty)
        #expect(result.familiesAreDeterministicAndNonEmpty)
        #expect(result.membersAreDeterministicAndNonEmpty)
        #expect(result.fontsContainCommonMacFaces)
        #expect(result.familiesContainCommonMacFamilies)
        #expect(result.unknownFamilyReturnsNil)
    }

    @Test("AppKit open panel preserves configuration and cancels headless")
    @MainActor
    func appKitOpenPanelPreservesConfigurationAndCancelsHeadless() {
        let result = AppleCompatibilitySmoke.runAppKitOpenPanelSmoke()

        #expect(result.defaultConfigurationMatchesMacShape)
        #expect(result.configurationRoundTrips)
        #expect(result.runModalCancelsHeadless)
        #expect(result.beginReportsCancellation)
        #expect(result.beginSheetReportsCancellation)
        #expect(result.defaultSelectionIsEmpty)
    }

    @Test("AppKit menu popups update delegates and track presentation")
    @MainActor
    func appKitMenuPopupsUpdateDelegatesAndTrackPresentation() {
        let result = AppleCompatibilitySmoke.runAppKitMenuSmoke()

        #expect(result.popupSucceeded)
        #expect(result.trackingBegan)
        #expect(result.rememberedPositioningItem)
        #expect(result.rememberedLocation)
        #expect(result.rememberedView)
        #expect(result.itemMenuBacklinks)
        #expect(result.submenuParentLink)
        #expect(result.replacedSubmenuClearedParentLink)
        #expect(result.clearedSubmenuParentLink)
        #expect(result.autoValidationDisabledItem)
        #expect(result.delegateEvents.isSuperset(of: Set([
            "numberOfItems:2",
            "needsUpdate:Chat",
            "update:Copy:0:false",
            "update:Disabled:1:false",
            "willOpen:Chat"
        ])))
        #expect(result.trackingEnded)
        #expect(result.removedItemClearedMenu)
        #expect(result.removeAllClearedMenus)
    }

    @Test("AppKit controls mirror values and button factories")
    @MainActor
    func appKitControlsMirrorValuesAndButtonFactories() {
        let result = AppleCompatibilitySmoke.runAppKitControlSmoke()

        #expect(result.stringValueUpdatedNumericAndObjectValues)
        #expect(result.numericValuesUpdatedStringAndObjectValues)
        #expect(result.objectValueUpdatedStringAndNumericValues)
        #expect(result.attributedValueUpdatedStringAndNumericValues)
        #expect(result.explicitActionSentToTarget)
        #expect(result.missingActionOrTargetRejected)
        #expect(result.applicationExplicitActionSentToTarget)
        #expect(result.applicationMissingTargetRejected)
        #expect(result.textButtonPreservedTargetActionAndTitle)
        #expect(result.imageButtonPreservedTargetAndAction)
        #expect(result.checkboxFactoryPreservedTargetActionAndTitle)
        #expect(result.radioFactoryPreservedTargetActionAndTitle)
        #expect(result.labelInitializerPreservedLabelTraits)
        #expect(result.wrappingLabelInitializerPreservedWrappingTraits)
        #expect(result.stringInitializerPreservedEditableTraits)
        #expect(result.sliderInitializerPreservedRangeTargetAndAction)
    }

    @Test("AppKit pop-up buttons preserve menu selection state")
    @MainActor
    func appKitPopUpButtonsPreserveMenuSelectionState() {
        let result = AppleCompatibilitySmoke.runAppKitPopUpButtonSmoke()

        #expect(result.firstItemSelectedAfterAdd)
        #expect(result.selectionFollowsIndex)
        #expect(result.invalidSelectionPreservesCurrentItem)
        #expect(result.selectionFollowsTitle)
        #expect(result.selectionFollowsTag)
        #expect(result.removedSelectedItemChoosesAdjacentItem)
        #expect(result.removeAllClearsSelection)
        #expect(result.menuReplacementSelectsFirstItem)
        #expect(result.menuItemBacklinks)
    }

    @Test("AppKit popovers maintain presentation and delegate state")
    @MainActor
    func appKitPopoversMaintainPresentationAndDelegateState() {
        let result = AppleCompatibilitySmoke.runAppKitPopoverSmoke()

        #expect(result.showUpdatedStateAndAnchor)
        #expect(result.repeatedShowUpdatedAnchorWithoutDuplicateCallbacks)
        #expect(result.closeVetoPreservedState)
        #expect(result.performCloseDelegatedToClose)
        #expect(result.redundantCloseIgnored)
    }

    @Test("AppKit toolbars ask delegates and maintain visible items")
    @MainActor
    func appKitToolbarsAskDelegatesAndMaintainVisibleItems() {
        let result = AppleCompatibilitySmoke.runAppKitToolbarSmoke()

        #expect(result.insertedItemsInDelegateOrder)
        #expect(result.delegateSawInsertedFlag)
        #expect(result.visibleItemsFollowItems)
        #expect(result.removedItemUpdatesItems)
        #expect(result.removingSelectedItemClearsSelection)
        #expect(result.outOfRangeRemoveIgnored)
    }

    @Test("AppKit windows maintain controller and child state")
    @MainActor
    func appKitWindowsMaintainControllerAndChildState() {
        let result = AppleCompatibilitySmoke.runAppKitWindowSmoke()

        #expect(result.controllerBacklinksRoundTrip)
        #expect(result.childWindowLinksRoundTrip)
        #expect(result.childReparentClearsPreviousParent)
        #expect(result.childRemovalClearsParent)
        #expect(result.tabbedWindowsRoundTrip)
        #expect(result.applicationTabIdentifierLookup)
        #expect(result.sheetLifecycleRoundTrip)
    }

    @Test("AppKit views maintain hierarchy and window links")
    @MainActor
    func appKitViewsMaintainHierarchyAndWindowLinks() {
        let result = AppleCompatibilitySmoke.runAppKitViewHierarchySmoke()

        #expect(result.addEstablishedLinks)
        #expect(result.addFiredSuperviewCallbacks)
        #expect(result.reparentedWithoutDuplicateBacklinks)
        #expect(result.removalClearedLinks)
        #expect(result.removalFiredSuperviewCallbacks)
        #expect(result.scrollDocumentViewInstalledInClipView)
        #expect(result.scrollContentSubviewFindsEnclosingScrollView)
        #expect(result.scrollDocumentViewClearingRemovedDocument)
        #expect(result.windowContentViewPropagated)
        #expect(result.windowContentViewCleared)
        #expect(result.windowCallbacksReachedSubview)
        #expect(result.frameInitializerEstablishedBounds)
        #expect(result.frameResizeScaledBounds)
        #expect(result.offWindowDisplayInvalidationIgnored)
        #expect(result.windowAttachmentMarksDisplayDirty)
        #expect(result.displayIfNeededCallsViewWillDrawAndClearsNeedsDisplay)
        #expect(result.setNeedsDisplayMarksAncestorDirty)
        #expect(result.displayIfNeededClearsDirtyDescendants)
        #expect(result.forcedDisplayCallsViewWillDrawWhenClean)
        #expect(result.newViewsStartNeedingLayout)
        #expect(result.layoutSubtreeClearsNeedsLayout)
        #expect(result.layoutSubtreeVisitsDirtyDescendants)
        #expect(result.layoutSubtreeSkipsCleanViews)
        #expect(result.layoutSubtreeVisitsDirtyDescendantFromCleanAncestor)
        #expect(result.frameAndBoundsMutationsMarkNeedsLayout)
        #expect(result.hitTestReturnsTopmostVisibleSubview)
        #expect(result.hitTestIgnoresHiddenSubview)
        #expect(result.hitTestRejectsOutsideBounds)
        #expect(result.hitTestReturnsReceiverInsideBounds)
        #expect(result.convertFromDescendantAccumulatesFrameOrigins)
        #expect(result.convertToDescendantSubtractsFrameOrigins)
        #expect(result.convertBetweenSiblingsUsesCommonSuperview)
        #expect(result.convertRectPreservesSize)
        #expect(result.convertNilUsesWindowCoordinates)
        #expect(result.convertScaledBoundsAppliesBoundsTransform)
    }

    @Test("AppKit responders maintain chain and first responder lifecycle")
    @MainActor
    func appKitRespondersMaintainChainAndFirstResponderLifecycle() {
        let result = AppleCompatibilitySmoke.runAppKitResponderSmoke()

        #expect(result.explicitNextResponderRoundTrip)
        #expect(result.viewDefaultResponderChain)
        #expect(result.viewControllerOwnsViewResponder)
        #expect(result.eventForwardingReachesNextResponder)
        #expect(result.makeFirstResponderCallsLifecycle)
        #expect(result.rejectedFirstResponderPreservesCurrent)
        #expect(result.clearingFirstResponderResignsCurrent)
        #expect(result.applicationSendEventDispatchesToFirstResponder)
        #expect(result.applicationSendEventDispatchesMagnifyToFirstResponder)
        #expect(result.applicationCurrentEventTracksDispatch)
        #expect(result.magnifyEventMasksAreAvailable)
        #expect(result.localEventMonitorCanRewriteEvent)
        #expect(result.localEventMonitorCanCancelEvent)
        #expect(result.globalEventMonitorObservesDispatchedEvent)
        #expect(result.removedEventMonitorStopsObserving)
    }

    @Test("AppKit view controllers maintain containment links")
    @MainActor
    func appKitViewControllersMaintainContainmentLinks() {
        let result = AppleCompatibilitySmoke.runAppKitViewControllerContainmentSmoke()

        #expect(result.addEstablishedParentLinks)
        #expect(result.secondChildPreservedOrder)
        #expect(result.removeClearedParentLinks)
        #expect(result.orphanRemoveIgnored)
    }

    @Test("AppKit split views maintain arranged item links")
    @MainActor
    func appKitSplitViewsMaintainArrangedItemLinks() {
        let result = AppleCompatibilitySmoke.runAppKitSplitViewSmoke()

        #expect(result.arrangedSubviewLinks)
        #expect(result.arrangedSubviewRemovalUpdatedOrder)
        #expect(result.defaultDividerMatchesAppKit)
        #expect(result.adjustSubviewsLaysOutTwoPanes)
        #expect(result.setPositionMovesAdjacentPanes)
        #expect(result.setPositionNotifiesDelegate)
        #expect(result.controllerAddedItemsInOrder)
        #expect(result.controllerRemoveClearedLinks)
        #expect(result.factoryBehaviorsRoundTrip)
    }

    @Test("AppKit views maintain tracking areas")
    @MainActor
    func appKitViewsMaintainTrackingAreas() {
        let result = AppleCompatibilitySmoke.runAppKitTrackingAreaSmoke()

        #expect(result.metadataRoundTripped)
        #expect(result.addRecordedTrackingArea)
        #expect(result.unknownRemoveIgnored)
        #expect(result.removeClearedTrackingArea)
    }

    @Test("AppKit text views apply edit APIs and notify delegates")
    @MainActor
    func appKitTextViewsApplyEditApisAndNotifyDelegates() {
        let result = AppleCompatibilitySmoke.runAppKitTextViewEditingSmoke()

        #expect(result.replaceUpdatesStringAndStorage)
        #expect(result.insertUsesSelectedRange)
        #expect(result.attributedInsertUsesStringContents)
        #expect(result.delegateCanVetoChange)
        #expect(result.delegateReceivesChangeAndSelectionNotifications)
    }

    @Test("AppKit table views maintain rows columns and selection")
    @MainActor
    func appKitTableViewsMaintainRowsColumnsAndSelection() {
        let result = AppleCompatibilitySmoke.runAppKitTableSmoke()

        #expect(result.reloadUpdatedRowCount)
        #expect(result.columnLookupAndRemoval)
        #expect(result.multiSelectionRoundTrip)
        #expect(result.singleSelectionAndEmptyRules)
        #expect(result.delegateSelectionNotification)
        #expect(result.rowAndCellViewsCached)
        #expect(result.frameUsesColumnWidthsAndRowHeight)
        #expect(result.rowColumnLookupFromViews)
        #expect(result.rowMutationsPreserveState)
    }

    @Test("AppKit outline views flatten expanded data source items")
    @MainActor
    func appKitOutlineViewsFlattenExpandedDataSourceItems() {
        let result = AppleCompatibilitySmoke.runAppKitOutlineSmoke()

        #expect(result.reloadShowsRootItems)
        #expect(result.expandShowsChildrenAndLevels)
        #expect(result.rowParentAndChildLookup)
        #expect(result.delegateViewsUseItems)
        #expect(result.selectionRoundTrip)
        #expect(result.collapseHidesChildrenAndClearsSelection)
        #expect(result.recursiveExpansionAndCollapse)
    }

    @Test("AppKit documents maintain edit and controller state")
    @MainActor
    func appKitDocumentsMaintainEditAndControllerState() {
        let result = AppleCompatibilitySmoke.runAppKitDocumentSmoke()

        #expect(result.displayNameFollowsFileURL)
        #expect(result.changeCountTracksEditedState)
        #expect(result.windowControllerLinksRoundTrip)
        #expect(result.documentControllerMaintainsCurrentDocument)
        #expect(result.openDocumentCreatesAndReusesDocument)
    }

    @Test("AppKit undo managers maintain action stacks")
    @MainActor
    func appKitUndoManagersMaintainActionStacks() {
        let result = AppleCompatibilitySmoke.runAppKitUndoSmoke()

        #expect(result.singleActionUndoRedoRoundTrip)
        #expect(result.actionNamesRoundTrip)
        #expect(result.disablingRegistrationBlocksActions)
        #expect(result.targetRemovalClearsActions)
        #expect(result.groupedActionsUndoTogether)
        #expect(result.groupedActionsRedoTogether)
    }

    @Test("KeyboardShortcuts persist defaults and user overrides by raw name")
    func keyboardShortcutsPersistDefaultsAndUserOverrides() {
        let defaultShortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
        let overrideShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.command, .shift])
        let name = KeyboardShortcuts.Name("togglePanelMode1", default: defaultShortcut)

        QuillHotkeyService.shared.unregisterAll()
        KeyboardShortcuts.reset(name)
        KeyboardShortcuts.resetAllHandlers()
        #expect(KeyboardShortcuts.getShortcut(for: name) == defaultShortcut)
        #expect(KeyboardShortcuts.Shortcut(.character("p")).key == .character("p"))

        KeyboardShortcuts.setShortcut(overrideShortcut, for: name)
        #expect(KeyboardShortcuts.getShortcut(for: name) == overrideShortcut)
        #expect(KeyboardShortcuts.getShortcut(for: "togglePanelMode1") == overrideShortcut)

        KeyboardShortcuts.reset(name)
        #expect(KeyboardShortcuts.getShortcut(for: name) == defaultShortcut)

        var handledEvents: [String] = []
        _ = Text("Shortcut").onKeyboardShortcut(name, type: .keyDown) {
            handledEvents.append("down")
        }
        #expect(KeyboardShortcuts.trigger(name, type: .keyDown))
        #expect(handledEvents == ["down"])
        #expect(KeyboardShortcuts.trigger(defaultShortcut))
        #expect(handledEvents == ["down", "down"])

        KeyboardShortcuts.setShortcut(overrideShortcut, for: name)
        #expect(!KeyboardShortcuts.trigger(defaultShortcut))
        #expect(KeyboardShortcuts.trigger(overrideShortcut))
        #expect(QuillHotkeyService.shared.trigger(key: "space", modifiers: ["command", "shift"]))
        #expect(handledEvents == ["down", "down", "down", "down"])
        #expect(!KeyboardShortcuts.trigger(name, type: .keyUp))

        _ = Text("Shortcut").onKeyboardShortcut(name, type: .keyUp) {
            handledEvents.append("up")
        }
        #expect(KeyboardShortcuts.trigger(name, type: .keyUp))
        #expect(handledEvents == ["down", "down", "down", "down", "up"])

        KeyboardShortcuts.resetAllHandlers()
        #expect(!KeyboardShortcuts.trigger(name, type: .keyDown))
        #expect(!KeyboardShortcuts.trigger(overrideShortcut))

        KeyboardShortcuts.resetAll()
        QuillHotkeyService.shared.unregisterAll()
    }

    @Test("AVFoundation speech synthesis routes through QuillKit")
    func avFoundationSpeechSynthesisRoutesThroughQuillKit() {
        QuillSpeechBackend.shared.resetSpeechSynthesis()
        QuillSpeechBackend.shared.configureSpeechSynthesisVoices([
            QuillSpeechVoice(identifier: "quill.test.voice", name: "Test Voice", quality: 1)
        ])

        let utterance = AVSpeechUtterance(string: "hello linux")
        let voice = AVSpeechSynthesisVoice(identifier: "quill.test.voice")
        utterance.voice = voice

        #expect(utterance.speechString == "hello linux")
        #expect(voice?.name == "Test Voice")
        #expect(voice?.quality == .enhanced)
        #expect(AVSpeechSynthesisVoice.speechVoices().map(\.identifier) == ["quill.test.voice"])

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)
        #expect(!synthesizer.isSpeaking)
        #expect(!synthesizer.isPaused)
        #expect(synthesizer.stopSpeaking(at: .immediate))

        let pausingDelegate = PausingSpeechDelegate()
        let pausingSynthesizer = AVSpeechSynthesizer()
        pausingSynthesizer.delegate = pausingDelegate
        pausingSynthesizer.speak(AVSpeechUtterance(string: "pause me"))
        #expect(pausingDelegate.events == ["start"])
        #expect(pausingDelegate.pauseResult == true)
        #expect(pausingSynthesizer.isPaused)
        #expect(pausingSynthesizer.isSpeaking)
        #expect(pausingSynthesizer.continueSpeaking())
        #expect(pausingDelegate.events == ["start", "finish"])
        #expect(!pausingSynthesizer.isPaused)
        #expect(!pausingSynthesizer.isSpeaking)
        #expect(!pausingSynthesizer.continueSpeaking())

        QuillSpeechBackend.shared.resetSpeechSynthesis()
    }

    @Test("AVFoundation audio session routes through QuillKit")
    func avFoundationAudioSessionRoutesThroughQuillKit() throws {
        QuillAudioSessionService.shared.reset()
        QuillCompatibilityDiagnostics.shared.clear()

        let session = AVAudioSession.sharedInstance()
        let secondReference = AVAudioSession.sharedInstance()
        #expect(session === secondReference)
        #expect(session.category == .ambient)
        #expect(session.mode == .spokenAudio)
        #expect(session.isActive == false)

        try session.setCategory(.playAndRecord, mode: .videoChat, options: [.allowBluetooth, .defaultToSpeaker])
        #expect(secondReference.category == .playAndRecord)
        #expect(secondReference.mode == .videoChat)
        #expect(secondReference.categoryOptions.contains(.allowBluetooth))
        #expect(secondReference.categoryOptions.contains(.defaultToSpeaker))
        #expect(QuillAudioSessionService.shared.category == .playAndRecord)

        try secondReference.setMode(.measurement)
        #expect(session.mode == .measurement)
        #expect(QuillAudioSessionService.shared.mode == .measurement)

        try session.setActive(true, options: [.notifyOthersOnDeactivation])
        #expect(secondReference.isActive)
        #expect(QuillAudioSessionService.shared.setActiveOptionsRawValue == 1)
        try session.setActive(false)
        #expect(secondReference.isActive == false)

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.contains("audioSession.setCategory"))
        #expect(operations.contains("audioSession.setActive"))
    }

    @Test("AVFoundation audio engine routes graph state through QuillKit")
    func avFoundationAudioEngineRoutesGraphStateThroughQuillKit() throws {
        QuillAudioEngineService.shared.resetAll()
        QuillCompatibilityDiagnostics.shared.clear()

        let engine = AVAudioEngine()
        #expect(engine.isRunning == false)
        #expect(QuillAudioEngineService.shared.engineStates.count == 1)

        engine.prepare()
        try engine.start()
        #expect(engine.isRunning)

        let extraMixer = AVAudioMixerNode()
        engine.attach(extraMixer)
        engine.connect(engine.inputNode, to: engine.mainMixerNode, format: nil)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { _, _ in }

        var state = try #require(QuillAudioEngineService.shared.engineStates.first)
        #expect(state.isPrepared)
        #expect(state.isRunning)
        #expect(state.attachedNodeCount == 1)
        #expect(state.connectionCount == 1)
        #expect(state.tapCount == 1)

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        state = try #require(QuillAudioEngineService.shared.engineStates.first)
        #expect(state.tapCount == 0)
        #expect(state.isRunning == false)

        engine.reset()
        state = try #require(QuillAudioEngineService.shared.engineStates.first)
        #expect(state == QuillAudioEngineState(engineID: state.engineID))

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.contains("audioEngine.prepare"))
        #expect(operations.contains("audioEngine.start"))
        #expect(operations.contains("audioEngine.attach"))
        #expect(operations.contains("audioEngine.connect"))
        #expect(operations.contains("audioEngine.installTap"))
        #expect(operations.contains("audioEngine.removeTap"))
        #expect(operations.contains("audioEngine.stop"))
        #expect(operations.contains("audioEngine.reset"))
    }

    @Test("AVFoundation audio player and system sounds route through QuillKit")
    func avFoundationAudioPlayerAndSystemSoundsRouteThroughQuillKit() throws {
        QuillAudioPlayerService.shared.resetAll()
        QuillCompatibilityDiagnostics.shared.clear()

        let data = wavData()
        let player = try AVAudioPlayer(data: data)
        #expect(player.numberOfChannels == 2)
        #expect(abs(player.duration - 1) < 0.0001)
        #expect(player.prepareToPlay())
        player.currentTime = 0.25
        player.volume = 1.25
        player.numberOfLoops = 2
        #expect(player.play(atTime: 0.5))
        #expect(player.isPlaying)
        #expect(player.currentTime == 0.5)
        #expect(player.volume == 1)
        player.pause()
        #expect(player.isPlaying == false)
        #expect(player.play())
        player.stop()
        #expect(player.isPlaying == false)

        let playerState = try #require(QuillAudioPlayerService.shared.playerStates.first {
            if case .data(byteCount: data.count) = $0.source {
                return true
            }
            return false
        })
        #expect(playerState.isPrepared)
        #expect(playerState.playCount == 2)
        #expect(playerState.pauseCount == 1)
        #expect(playerState.stopCount == 1)
        #expect(playerState.numberOfLoops == 2)

        let soundURL = URL(fileURLWithPath: "/tmp/quill-system-sound.wav")
        var soundID: SystemSoundID = 0
        #expect(AudioServicesCreateSystemSoundID(soundURL, &soundID) == kAudioServicesNoError)
        AudioServicesPlaySystemSound(soundID)
        AudioServicesPlayAlertSound(soundID)
        #expect(AudioServicesAddSystemSoundCompletion(soundID, nil, nil, { _, _ in }, nil) == kAudioServicesNoError)
        AudioServicesRemoveSystemSoundCompletion(soundID)
        #expect(AudioServicesDisposeSystemSoundID(soundID) == kAudioServicesNoError)

        let systemSound = try #require(QuillAudioPlayerService.shared.systemSoundRecords.first {
            $0.soundID == soundID
        })
        #expect(systemSound.url == soundURL)
        #expect(systemSound.playCount == 1)
        #expect(systemSound.alertPlayCount == 1)
        #expect(systemSound.completionRegistrationCount == 0)
        #expect(systemSound.isDisposed)

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.contains("audioPlayer.prepareToPlay"))
        #expect(operations.contains("audioPlayer.play"))
        #expect(operations.contains("audioPlayer.pause"))
        #expect(operations.contains("audioPlayer.stop"))
        #expect(operations.contains("audioSystemSound.create"))
        #expect(operations.contains("audioSystemSound.play"))
        #expect(operations.contains("audioSystemSound.playAlert"))
        #expect(operations.contains("audioSystemSound.addCompletion"))
        #expect(operations.contains("audioSystemSound.removeCompletion"))
        #expect(operations.contains("audioSystemSound.dispose"))
    }

    @Test("Sparkle updater routes through QuillKit")
    func sparkleUpdaterRoutesThroughQuillKit() {
        QuillUpdateService.shared.reset()
        QuillCompatibilityDiagnostics.shared.clear()

        let updater = SPUUpdater()
        #expect(updater.canCheckForUpdates == false)
        #expect(QuillUpdateService.shared.canCheckForUpdates == false)

        updater.canCheckForUpdates = true
        #expect(updater.canCheckForUpdates)
        #expect(QuillUpdateService.shared.canCheckForUpdates)

        updater.checkForUpdates()
        #expect(QuillUpdateService.shared.updateCheckCount == 1)
        #expect(QuillUpdateService.shared.lastCheckDate != nil)
        #expect(QuillCompatibilityDiagnostics.shared.events.contains {
            $0.operation == "checkForUpdates"
        })

        QuillUpdateService.shared.reset()
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #expect(controller.updater.canCheckForUpdates)
        controller.updater.canCheckForUpdates = false
        #expect(QuillUpdateService.shared.canCheckForUpdates == false)

        QuillUpdateService.shared.reset()
    }

    @Test("ServiceManagement legacy login item toggle routes through QuillKit")
    func serviceManagementLegacyLoginItemToggleRoutesThroughQuillKit() throws {
        try SMAppService.mainApp.unregister()
        QuillCompatibilityDiagnostics.shared.clear()

        #expect(SMAppService.mainApp.status == .notRegistered)
        #expect(SMLoginItemSetEnabled("co.lorehex.quill.helper", true))
        #expect(QuillLaunchService.shared.isEnabled)
        #expect(SMAppService.mainApp.status == .enabled)
        #expect(QuillCompatibilityDiagnostics.shared.events.contains {
            $0.operation == "SMLoginItemSetEnabled" &&
                $0.message.contains("co.lorehex.quill.helper")
        })

        #expect(SMLoginItemSetEnabled("co.lorehex.quill.helper", false))
        #expect(QuillLaunchService.shared.isEnabled == false)
        #expect(SMAppService.mainApp.status == .notRegistered)

        try SMAppService.mainApp.unregister()
    }

    @Test("UserNotifications routes through QuillKit")
    func userNotificationsRoutesThroughQuillKit() async throws {
        let service = QuillNotificationService.shared
        let center = UNUserNotificationCenter.current()
        service.reset()
        center.setNotificationCategories([])
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
        service.configureAuthorization(status: .notDetermined, requestResult: true)
        QuillCompatibilityDiagnostics.shared.clear()
        let openedURLs = CompatibilityLockedValue<[URL]>([])
        QuillWorkspace.installOpenBackend(QuillWorkspace.OpenBackend(name: "ui-application-test") { url in
            openedURLs.update { $0.append(url) }
            return true
        })
        defer { QuillWorkspace.installOpenBackend(nil) }

        let granted = try await center.requestAuthorization(options: [.alert, .sound])
        #expect(granted)
        #expect(service.authorizationStatus == .authorized)

        var authorizationStatus: UNAuthorizationStatus?
        center.getNotificationSettings { settings in
            authorizationStatus = settings.authorizationStatus
        }
        #expect(authorizationStatus == .authorized)

        let openURL = URL(string: "https://example.com/quill-chat")!
        let completionResult = CompatibilityLockedValue<Bool?>(nil)
        let didOpen = await UIApplication.shared.open(openURL, options: [:]) { result in
            completionResult.update { $0 = result }
        }
        #expect(didOpen)
        #expect(completionResult.value == true)
        #expect(openedURLs.value == [openURL])

        await UIApplication.shared.registerForRemoteNotifications()
        let isRegisteredForRemoteNotifications = await UIApplication.shared.isRegisteredForRemoteNotifications
        #expect(isRegisteredForRemoteNotifications)
        #expect(service.remoteNotificationRegistrationCount == 1)
        await UIApplication.shared.unregisterForRemoteNotifications()
        let isRegisteredAfterUnregister = await UIApplication.shared.isRegisteredForRemoteNotifications
        #expect(isRegisteredAfterUnregister == false)

        let replyCategory = UNNotificationCategory(
            identifier: "reply",
            actions: [
                UNTextInputNotificationAction(
                    identifier: "reply.send",
                    title: "Reply",
                    textInputButtonTitle: "Send",
                    textInputPlaceholder: "Message"
                )
            ],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([replyCategory])
        var categoryIdentifiers: Set<String> = []
        center.getNotificationCategories { categories in
            categoryIdentifiers = Set(categories.map(\.identifier))
        }
        #expect(categoryIdentifiers == ["reply"])
        #expect(service.categoryIdentifiers == ["reply"])

        let immediateContent = UNMutableNotificationContent()
        immediateContent.title = "Ready"
        immediateContent.body = "Delivered now"
        immediateContent.categoryIdentifier = "reply"
        immediateContent.threadIdentifier = "chat"
        try await center.add(UNNotificationRequest(
            identifier: "now",
            content: immediateContent,
            trigger: nil
        ))

        let pendingContent = UNMutableNotificationContent()
        pendingContent.title = "Later"
        pendingContent.body = "Queued"
        var pendingAddCompleted = false
        center.add(UNNotificationRequest(
            identifier: "later",
            content: pendingContent,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )) { error in
            pendingAddCompleted = true
            #expect(error == nil)
        }
        #expect(pendingAddCompleted)

        #expect((await center.deliveredNotifications()).map(\.request.identifier) == ["now"])
        #expect((await center.pendingNotificationRequests()).map(\.identifier) == ["later"])
        var deliveredIdentifiers: [String] = []
        center.getDeliveredNotifications { notifications in
            deliveredIdentifiers = notifications.map(\.request.identifier)
        }
        var pendingIdentifiers: [String] = []
        center.getPendingNotificationRequests { requests in
            pendingIdentifiers = requests.map(\.identifier)
        }
        #expect(deliveredIdentifiers == ["now"])
        #expect(pendingIdentifiers == ["later"])
        #expect(service.deliveredNotificationRecords.map(\.identifier) == ["now"])
        #expect(service.pendingRequestRecords.map(\.identifier) == ["later"])

        center.removeDeliveredNotifications(withIdentifiers: ["now"])
        center.removePendingNotificationRequests(withIdentifiers: ["later"])
        #expect((await center.deliveredNotifications()).isEmpty)
        #expect((await center.pendingNotificationRequests()).isEmpty)

        let operations = Set(QuillCompatibilityDiagnostics.shared.events.map(\.operation))
        #expect(operations.contains("notifications.requestAuthorization"))
        #expect(operations.contains("notifications.setCategories"))
        #expect(operations.contains("notifications.addRequest"))
        #expect(operations.contains("notifications.registerForRemoteNotifications"))
        #expect(operations.contains("openURL"))

        service.reset()
    }

    @Test("Magnet hot keys use the shared QuillKit registry")
    func magnetHotKeysUseSharedQuillKitRegistry() {
        QuillHotkeyService.shared.unregisterAll()
        QuillCompatibilityDiagnostics.shared.clear()
        var handledEvents: [String] = []
        let combo = KeyCombo(key: .character("p"), cocoaModifiers: [.command, .shift])!

        let hotKey = HotKey(identifier: "togglePanelMode", keyCombo: combo) { key in
            handledEvents.append(key.identifier)
        }

        #expect(!HotKey.trigger(identifier: "togglePanelMode"))
        hotKey.register()
        #expect(hotKey.isRegistered)
        #expect(HotKey.trigger(identifier: "togglePanelMode"))
        #expect(HotKey.trigger(keyCombo: combo))
        #expect(handledEvents == ["togglePanelMode", "togglePanelMode"])

        let duplicate = HotKey(identifier: "duplicatePanelMode", keyCombo: combo) { key in
            handledEvents.append(key.identifier)
        }
        duplicate.register()
        #expect(!duplicate.isRegistered)
        #expect(QuillCompatibilityDiagnostics.shared.events.contains {
            $0.operation == "registerHotKey" && $0.severity == .warning
        })

        hotKey.unregister()
        #expect(!hotKey.isRegistered)
        #expect(!HotKey.trigger(identifier: "togglePanelMode"))
        #expect(!HotKey.trigger(keyCombo: combo))

        hotKey.trigger()
        #expect(handledEvents == ["togglePanelMode", "togglePanelMode", "togglePanelMode"])
        QuillHotkeyService.shared.unregisterAll()
    }

    @Test("MarkdownUI and Splash cover Enchanted markdown theme contracts")
    func markdownAndSplashContractsCompile() {
        let configuration = CodeBlockConfiguration(language: "swift", content: "let answer = 42")
        let highlighted = ContractSplashCodeSyntaxHighlighter(theme: .sunset(withFont: .init(size: 16)))
            .highlightCode(configuration.content, language: configuration.language)
        let richPlainText = Markdown.plainText(from: """
        # Plan

        - Render **Markdown**
        2) Keep parity
        > Keep code readable

        ```swift
        let answer = 42
        ```
        """)

        let inlinePlainText = Markdown.plainText(
            from: "Use **bold**, _italic_, `code`, ~~old~~, [link](https://example.com), and ![chart](chart.png)"
        )
        let tablePlainText = Markdown.plainText(from: """
        | Property | Value |
        | --- | --- |
        | display | `flex` |
        | align-items | `center` |
        """)

        #expect(inlinePlainText.contains("bold"))
        #expect(inlinePlainText.contains("italic"))
        #expect(inlinePlainText.contains("code"))
        #expect(inlinePlainText.contains("old"))
        #expect(inlinePlainText.contains("link (https://example.com)"))
        #expect(inlinePlainText.contains("chart (chart.png)"))
        #expect(tablePlainText.contains("Property | Value"))
        #expect(tablePlainText.contains("display | flex"))
        #expect(tablePlainText.contains("align-items | center"))
        #expect(richPlainText.contains("Plan"))
        #expect(richPlainText.contains("• Render Markdown"))
        #expect(richPlainText.contains("2. Keep parity"))
        #expect(richPlainText.contains("Keep code readable"))
        #expect(richPlainText.contains("let answer = 42"))
        #expect(configuration.language == "swift")
        #expect(highlighted.content.contains("answer"))
        #expect(Splash.Theme.wwdc17(withFont: .init(size: 16)).tokenColors[.keyword] != nil)

        _ = markdownContractTheme
        _ = Markdown("```swift\nlet answer = 42\n```")
            .markdownCodeSyntaxHighlighter(PlainTextCodeSyntaxHighlighter())
            .markdownTheme(markdownContractTheme)
        _ = Markdown("| Property | Value |\n| --- | --- |\n| display | `flex` |")
        _ = Text("one") + Text(" two")
        _ = configuration.label
            .relativeLineSpacing(.em(0.225))
            .markdownTextStyle {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .markdownMargin(top: .zero, bottom: .em(0.8))
    }

    @Test("MarkdownUI code fences match Enchanted parser closing rules")
    func markdownUICodeFencesMatchEnchantedClosingRules() {
        let nestedBacktickPlainText = Markdown.plainText(from: """
        ````swift
        ```swift
        let value = 1
        ```
        ````
        """)
        let trailingTextPlainText = Markdown.plainText(from: """
        ```swift
        let value = 1
        ``` trailing
        still code
        ```
        """)
        let mixedFencePlainText = Markdown.plainText(from: """
        ~~~~text
        ```
        body
        ```
        ~~~~
        """)

        #expect(nestedBacktickPlainText == "```swift\nlet value = 1\n```")
        #expect(trailingTextPlainText == "let value = 1\n``` trailing\nstill code")
        #expect(mixedFencePlainText == "```\nbody\n```")
    }

    @Test("MarkdownUI setext headings and dividers match Enchanted block rules")
    func markdownUISetextAndDividersMatchEnchantedBlockRules() {
        let richPlainText = Markdown.plainText(from: """
        Release Notes
        =============

        Intro paragraph

        ---
        Next section
        """)
        let lowerLevelPlainText = Markdown.plainText(from: """
        Minor update
        -
        Body
        """)
        let spacedDividerPlainText = Markdown.plainText(from: """
        Before

        * * *
        After
        """)

        #expect(richPlainText == "Release Notes\nIntro paragraph\n\nNext section")
        #expect(lowerLevelPlainText == "Minor update\nBody")
        #expect(spacedDividerPlainText == "Before\n\nAfter")
        #expect(!richPlainText.contains("="))
        #expect(!richPlainText.contains("---"))
        #expect(!spacedDividerPlainText.contains("* * *"))
    }

    @Test("MarkdownUI inline cleanup matches Enchanted text contracts")
    func markdownUIInlineCleanupMatchesEnchantedTextContracts() {
        let markerOnlyParagraphPlainText = Markdown.plainText(from: """
        **

        Body
        """)
        let emptySetextTitlePlainText = Markdown.plainText(from: """
        ``
        ==

        Body
        """)
        let linkAndImagePlainText = Markdown.plainText(
            from: "Use **bold**, __strong__, `code`, ~~old~~, [link](https://example.com), and ![chart](chart.png)"
        )
        let emptyLabelLinkAndImagePlainText = Markdown.plainText(
            from: "Status [](/health) and ![](file:///tmp/chart.png)"
        )
        let nestedDestinationPlainText = Markdown.plainText(
            from: "[Swift Array](https://developer.apple.com/documentation/swift/Array(_:)) and ![Chart](assets/chart(size).png)"
        )
        let autolinkPlainText = Markdown.plainText(
            from: "Open <https://example.com/docs?q=1> or email <support@example.com>; keep 2 < 3 > 1"
        )
        let characterReferencePlainText = Markdown.plainText(
            from: "Use &lt;model&gt; &amp; tools; it&rsquo;s ready &mdash; ship it &#x2713;; keep &unknown; literal"
        )
        let singleEmphasisPlainText = Markdown.plainText(
            from: "Use *local* and _remote_ models, but keep a literal * marker"
        )
        let escapedPunctuationPlainText = Markdown.plainText(
            from: "Show \\*literal\\*, \\[not a link](https://example.com), and \\# heading; keep \\path"
        )

        #expect(markerOnlyParagraphPlainText == "Body")
        #expect(emptySetextTitlePlainText == "Body")
        #expect(linkAndImagePlainText == "Use bold, strong, code, old, link (https://example.com), and chart (chart.png)")
        #expect(emptyLabelLinkAndImagePlainText == "Status (/health) and (file:///tmp/chart.png)")
        #expect(nestedDestinationPlainText == "Swift Array (https://developer.apple.com/documentation/swift/Array(_:)) and Chart (assets/chart(size).png)")
        #expect(autolinkPlainText == "Open https://example.com/docs?q=1 or email support@example.com; keep 2 < 3 > 1")
        #expect(characterReferencePlainText == "Use <model> & tools; it\u{2019}s ready \u{2014} ship it \u{2713}; keep &unknown; literal")
        #expect(singleEmphasisPlainText == "Use local and remote models, but keep a literal * marker")
        #expect(escapedPunctuationPlainText == "Show *literal*, [not a link](https://example.com), and # heading; keep \\path")
    }

    @Test("OllamaKit compatibility covers Enchanted model and chat contracts")
    func ollamaKitContractsCompileAndStream() async throws {
        let transport = FakeOllamaTransport(routes: [
            "/api/version": (200, #"{"version":"0.6.0"}"#),
            "/api/tags": (200, #"{"models":[{"name":"llava:latest","details":{"families":["clip"]}},{"name":"llama3.2:latest"}]}"#),
            "/api/chat": (
                200,
                """
                {"message":{"role":"assistant","content":"Hel"},"done":false}
                {"message":{"role":"assistant","content":"lo"},"done":false}
                {"done":true}
                """
            )
        ])
        let kit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            bearerToken: "secret",
            transport: transport
        )

        #expect(await kit.reachable())

        let models = try await kit.models()
        #expect(models.models.map(\.name) == ["llava:latest", "llama3.2:latest"])
        #expect(models.models.first?.details.families == ["clip"])

        var request = OKChatRequestData(
            model: "llava:latest",
            messages: [
                .init(role: .system, content: "short"),
                .init(role: .user, content: "describe", images: ["base64"])
            ]
        )
        request.options = OKCompletionOptions(temperature: 0)

        // Collect the stream with structured concurrency: iterating the
        // AsyncThrowingStream overload keeps every append and the reads below
        // on a single task, so the reads happen-after the writes. The previous
        // Combine `.sink` + polling loop mutated `values`/`finished` from the
        // sink's delivery thread while the test thread polled them without
        // synchronization, so `.finished` could become visible before the
        // appended values did — an intermittent data race that left `values`
        // empty despite `finished` being true.
        var values: [OKChatResponse] = []
        var finished = false
        var failure: Error?
        do {
            let stream: AsyncThrowingStream<OKChatResponse, Error> = kit.chat(data: request)
            for try await response in stream {
                values.append(response)
            }
            finished = true
        } catch {
            failure = error
        }

        #expect(failure == nil)
        #expect(finished)
        #expect(values.map { $0.message?.content ?? "" }.joined() == "Hello")
        #expect(values.last?.done == true)
        #expect(transport.requests.contains { $0.path == "/api/chat" && $0.authorization == "Bearer secret" })
        #expect(transport.chatBody?.contains(#""stream":true"#) == true)

        let sessionBackedKit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            bearerToken: "secret",
            session: "compat-session"
        )
        #expect(sessionBackedKit.baseURL.absoluteString == "http://localhost:11434")
        #expect(sessionBackedKit.bearerToken == "secret")
    }

    @Test("OllamaKit compatibility reports HTTP and stream parse failures")
    func ollamaKitErrorContractsAreDeterministic() async throws {
        let transport = FakeOllamaTransport(routes: [
            "/api/version": (503, #"{"error":"down"}"#),
            "/api/tags": (500, #"{"error":"boom"}"#)
        ])
        let kit = OllamaKit(
            baseURL: URL(string: "http://localhost:11434")!,
            transport: transport
        )

        #expect(await kit.reachable() == false)
        await #expect(throws: OllamaKitError.self) {
            _ = try await kit.models()
        }
        #expect(throws: (any Error).self) {
            _ = try OllamaKit.decodeChatResponses(from: Data("not-json\n".utf8))
        }
    }

    @Test("AsyncAlgorithms and Carbon compatibility cover prompt-panel imports")
    func asyncAlgorithmsAndCarbonContractsCompile() async {
        var iterator = AsyncTimerSequence(interval: .milliseconds(1), clock: .continuous).makeAsyncIterator()
        let firstTick = await iterator.next()

        #expect(firstTick != nil)
        #expect(CarbonCompatibility.available == false)
    }

    @Test("IOKit USB compatibility covers Quill USB watcher imports")
    func ioKitUSBContractsCompile() {
        var iterator: io_iterator_t = 99
        let port = IONotificationPortCreate(kIOMainPortDefault)
        let callback: IOServiceMatchingCallback = { _, iterator in
            _ = IOIteratorNext(iterator)
        }

        IONotificationPortSetDispatchQueue(port, nil)
        let result = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            nil,
            callback,
            nil,
            &iterator
        )

        #expect(result == kIOReturnUnsupported)
        #expect(iterator == 0)
        #expect(IOIteratorNext(iterator) == 0)
        #expect(IOObjectRelease(iterator) == kIOReturnSuccess)
        #expect(kIOUSBDeviceClassName == "IOUSBDevice")
        #expect(kUSBVendorID == "idVendor")
        #expect(kUSBProductID == "idProduct")

        IONotificationPortDestroy(port)
    }

    @Test("IOKit power-management compatibility covers Telegram call-screen imports")
    func ioKitPowerManagementContractsCompile() {
        var assertionID: IOPMAssertionID = 123
        let createResult = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "QuillUI Telegram call",
            &assertionID
        )

        #expect(createResult == kIOReturnUnsupported)
        #expect(assertionID == kIOPMNullAssertionID)
        #expect(IOPMAssertionRelease(assertionID) == kIOReturnSuccess)
        #expect(kIOPMAssertionLevelOff == 0)
        #expect(kIOPMAssertionLevelOn > kIOPMAssertionLevelOff)
    }

    @Test("CoreSpotlight compatibility covers Telegram search indexing imports")
    func coreSpotlightContractsCompile() async {
        let attributes = CSSearchableItemAttributeSet(itemContentType: kUTTypeData)
        attributes.title = "Quill"
        attributes.contentDescription = "Linux compatibility"
        attributes.thumbnailData = Data([1, 2, 3])
        attributes.creator = "QuillUI"
        attributes.kind = "Contact"

        let item = CSSearchableItem(
            uniqueIdentifier: "accountId=1&source=peerId:2",
            domainIdentifier: "quill.telegram",
            attributeSet: attributes
        )

        var indexed = false
        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            indexed = error == nil
        }
        var deleted = false
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [item.uniqueIdentifier]) { error in
            deleted = error == nil
        }

        #expect(indexed)
        #expect(deleted)
        #expect(CSSearchableItemActionType == "com.apple.corespotlightitem")
        #expect(CSSearchableItemActivityIdentifier == "kCSSearchableItemActivityIdentifier")
    }

    @Test("Vision compatibility covers Telegram text-recognition imports")
    func visionTextRecognitionContractsCompile() throws {
        let image = CGImage()
        let handler = VNImageRequestHandler(cgImage: image)
        var completed = false
        let request = VNRecognizeTextRequest { request, error in
            #expect(error == nil)
            #expect((request.results as? [VNRecognizedTextObservation])?.isEmpty == true)
            completed = true
        }
        request.preferBackgroundProcessing = true
        request.usesLanguageCorrection = true
        request.recognitionLevel = .accurate
        request.revision = VNRecognizeTextRequestRevision3
        request.automaticallyDetectsLanguage = true
        request.progressHandler = { _, progress, error in
            #expect(error == nil)
            #expect(progress == 1.0)
        }

        try handler.perform([request])
        #expect(completed)
        request.cancel()
    }

    @Test("Apple service modules provide diagnostic Linux fallbacks")
    @MainActor
    func appleServiceModulesCompile() throws {
        #expect(QuillKitPlatform.current == .linux)
        #expect(QuillKitCapabilities.status(for: .clipboard) == .emulated)
        let result = try AppleCompatibilitySmoke.runAppleServiceSmoke()
        #expect(result.pasteboardString == "hello")
        #expect(result.pasteboardItemString == "item text")
        #expect(result.pasteboardItemDataRoundTrip)
        #expect(result.pasteboardItemPropertyListRoundTrip)
        #expect(result.pasteboardItemTypesRoundTrip)
        #expect(result.pasteboardWriteObjectsItemsRoundTrip)
        #expect(result.pasteboardWriteObjectsDataRoundTrip)
        #expect(result.pasteboardReadObjectsRoundTrip)
        #expect(result.pasteboardClearResetsItems)
        #expect(result.pasteboardSetStringClearsOldData)
        #expect(result.pasteboardWriteObjectsClearsOldData)
        #expect(result.pasteboardDeclareTypesRoundTrip)
        #expect(result.pasteboardDeclareTypesClearsOldTypes)
        #expect(result.pasteboardDeclareTypesChangeCount)
        #expect(result.pasteboardDeclareTypesOwnerProvidesData)
        #expect(result.pasteboardAvailableTypeOrder)
        #expect(result.uiPasteboardString == "hello")
        #expect(result.imagesRoundTrip)
        #expect(result.speechStopSucceeded)
        #expect(result.speechRecognitionUnavailable)
        #expect(result.launchServiceEnabled)
        #expect(result.launchServiceDisabled)
        #expect(result.updaterUnavailable)
    }

    @Test("Security CoreGraphics Accessibility and Alamofire adapters compile")
    @MainActor
    func lowerLevelServiceModulesCompile() throws {
        #expect(try AppleCompatibilitySmoke.runLowerLevelServiceSmoke())
    }

    @Test("os Logger compatibility records privacy-aware diagnostics")
    @MainActor
    func osLoggerCompatibilityRecordsDiagnostics() {
        let result = AppleCompatibilitySmoke.runOSLogSmoke()
        #expect(result.operations.contains("Logger.info"))
        #expect(result.operations.contains("Logger.error"))
        #expect(result.renderedPublicValue)
        #expect(result.redactedPrivateValue)
    }

    @Test("Combine compatibility publishers support cancellation and timer sinks")
    func combineNoOpPublishersCompile() {
        let cancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in }
        cancellable.cancel()

        let publisher = AnyPublisher<Int, Never>()
            .map { $0 > 0 }
            .eraseToAnyPublisher()
        let mappedCancellable = publisher.sink { _ in }
        mappedCancellable.cancel()

        var stored = Set<AnyCancellable>()
        Just(1)
            .eraseToAnyPublisher()
            .sink { _ in }
            .store(in: &stored)
        #expect(stored.count == 1)
    }

    @Test("Combine compatibility publishers deliver completion edge cases")
    func combineCompletionEdgeCases() {
        var justEvents: [String] = []
        let justCancellable = Just("value")
            .eraseToAnyPublisher()
            .sink { completion in
                if case .finished = completion {
                    justEvents.append("finished")
                }
            } receiveValue: { value in
                justEvents.append(value)
            }
        justCancellable.cancel()
        #expect(justEvents == ["value", "finished"])

        var emptyCompleted = false
        _ = Empty<Int, Never>()
            .eraseToAnyPublisher()
            .sink { completion in
                if case .finished = completion {
                    emptyCompleted = true
                }
            } receiveValue: { _ in }
        #expect(emptyCompleted)

        var lazyEmptyCompleted = false
        _ = Empty<Int, Never>(completeImmediately: false)
            .eraseToAnyPublisher()
            .sink { _ in lazyEmptyCompleted = true } receiveValue: { _ in }
        #expect(lazyEmptyCompleted == false)

        var failedWithBoom = false
        _ = Fail<Int, CombineTestError>(error: .boom)
            .eraseToAnyPublisher()
            .sink { completion in
                if case .failure(.boom) = completion {
                    failedWithBoom = true
                }
            } receiveValue: { _ in
                Issue.record("Fail publisher should not emit values")
            }
        #expect(failedWithBoom)
    }

    @Test("Combine subjects and merge deliver values from both inputs")
    func combineSubjectsAndMergeDeliverValues() {
        let first = PassthroughSubject<Int, Never>()
        let second = PassthroughSubject<Int, Never>()
        var values: [Int] = []

        let cancellable = Publishers.Merge(first, second)
            .eraseToAnyPublisher()
            .sink { values.append($0) }

        first.send(1)
        second.send(2)
        cancellable.cancel()
        first.send(3)

        #expect(values == [1, 2])
    }

    @Test("Combine merge buffers values beyond current downstream demand")
    func combineMergeBuffersBeyondCurrentDemand() {
        let first = PassthroughSubject<Int, Never>()
        let second = PassthroughSubject<Int, Never>()
        let subscriber = DemandRecordingSubscriber<Int, Never>()

        Publishers.Merge(first, second).subscribe(subscriber)
        subscriber.subscription?.request(.max(1))

        first.send(1)
        second.send(2)
        #expect(subscriber.values == [1])
        #expect(subscriber.completions == 0)

        subscriber.subscription?.request(.max(1))
        #expect(subscriber.values == [1, 2])

        first.send(completion: .finished)
        #expect(subscriber.completions == 0)
        second.send(completion: .finished)
        #expect(subscriber.completions == 1)
    }

    @Test("Combine subject completion is terminal")
    func combineSubjectCompletionIsTerminal() {
        let subject = PassthroughSubject<Int, Never>()
        var values: [Int] = []
        var completions = 0

        let cancellable = subject.eraseToAnyPublisher().sink { completion in
            if case .finished = completion {
                completions += 1
            }
        } receiveValue: { value in
            values.append(value)
        }

        subject.send(1)
        subject.send(completion: .finished)
        subject.send(2)
        cancellable.cancel()

        var lateSubscriberCompleted = false
        _ = subject.eraseToAnyPublisher().sink { completion in
            if case .finished = completion {
                lateSubscriberCompleted = true
            }
        } receiveValue: { _ in
            Issue.record("Completed subjects should not emit values to late subscribers")
        }

        #expect(values == [1])
        #expect(completions == 1)
        #expect(lateSubscriberCompleted)
    }

    @Test("Combine timer and notification publishers emit values")
    func combineTimerAndNotificationPublishersEmitValues() throws {
        var timerEvents = 0
        let runLoop = RunLoop.current
        let timer = Timer.publish(every: 0.01, on: runLoop, in: .default)
            .autoconnect()
            .sink { _ in
                timerEvents += 1
            }

        let deadline = Date().addingTimeInterval(1)
        while timerEvents == 0, Date() < deadline {
            _ = runLoop.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        timer.cancel()
        #expect(timerEvents >= 1)

        let name = Notification.Name("quill.combine.notification.\(UUID().uuidString)")
        var notifications: [Notification] = []
        let notificationCancellable = NotificationCenter.default.publisher(for: name)
            .sink { notification in
                notifications.append(notification)
            }

        NotificationCenter.default.post(name: name, object: "payload")
        notificationCancellable.cancel()
        NotificationCenter.default.post(name: name, object: "ignored")

        #expect(notifications.count == 1)
        #expect(notifications.first?.object as? String == "payload")
    }

    @Test("Combine subject cancellation is scoped to the cancelled subscriber")
    func combineSubjectCancellationIsScoped() {
        let subject = PassthroughSubject<Int, Never>()
        var firstValues: [Int] = []
        var secondValues: [Int] = []

        let first = subject.eraseToAnyPublisher().sink { firstValues.append($0) }
        let second = subject.eraseToAnyPublisher().sink { secondValues.append($0) }

        subject.send(1)
        first.cancel()
        first.cancel()
        subject.send(2)
        second.cancel()
        subject.send(3)

        #expect(firstValues == [1])
        #expect(secondValues == [1, 2])
    }

    @Test("AnyCancellable cancellation is idempotent")
    func anyCancellableCancellationIsIdempotent() {
        var cancelCount = 0
        let cancellable = AnyCancellable {
            cancelCount += 1
        }

        cancellable.cancel()
        cancellable.cancel()

        #expect(cancelCount == 1)
    }

    @Test("platform fallback shims record diagnostics")
    @MainActor
    func platformFallbacksRecordDiagnostics() throws {
        let result = try AppleCompatibilitySmoke.runDiagnosticFallbackSmoke()
        #expect(result.speechAuthorizationDenied)
        #expect(result.operations.isSuperset(of: Set([
            "impactOccurred",
            "notificationOccurred",
            "speechSynthesis",
            "requestAuthorization",
            "recognitionTask",
            "keyState",
            "postEvent",
            "registerSingleUseSpace",
            "trustEvaluation",
            "launchAtLogin"
        ])))
    }

    @Test("previously-silent QuillUI stubs now record diagnostics")
    func previouslySilentStubsRecordDiagnostics() throws {
        QuillCompatibilityDiagnostics.shared.clear()

        // Animation chain methods: previously returned self with no diagnostic.
        _ = Animation.snappy()
        _ = Animation.snappy(duration: 0.5)
        let repeatedAnimation = Animation.easeOut(duration: 0.2)
            .delay(0.4)
            .repeatForever(autoreverses: false)
        #expect(repeatedAnimation.curve == .easeOut)
        #expect(repeatedAnimation.duration == 0.2)
        #expect(repeatedAnimation.delay == 0.4)
        #expect(repeatedAnimation.repeatsForever)
        #expect(repeatedAnimation.autoreverses == false)

        // ImageRenderer: Color content now produces real bytes without
        // requiring the GTK display path. Non-Color content returns nil until
        // a backend installs the SwiftOpenUI ImageRenderer hook.
        let renderer = ImageRenderer(content: Text("rendered"))
        #expect(renderer.uiImage == nil)
        #expect(renderer.nsImage == nil)
        let colorRenderer = ImageRenderer(content: Color.red)
        let renderedPlatformImage: PlatformImage? = colorRenderer.nsImage
        let renderedNSImage: NSImage? = colorRenderer.nsImage
        #expect(renderedPlatformImage?.data?.isEmpty == false)
        #expect(renderedNSImage?.data?.isEmpty == false)
        #expect(colorRenderer.cgImage?.data?.isEmpty == false)
        #expect(Image(systemName: "photo").render() == nil)
        let fileBackedImageData = "quill-render-\(UUID().uuidString)".data(using: .utf8)!
        #expect(Image(data: fileBackedImageData).render()?.data == fileBackedImageData)
        guard let platformImage = PlatformImage(data: Data([1, 2, 3])) else {
            Issue.record("PlatformImage(data:) should construct the RSImage-backed image container")
            return
        }
        #expect(platformImage.convertImageToBase64String() == "AQID")
        #expect(platformImage.aspectFittedToHeight(200).data == Data([1, 2, 3]))
        #expect(platformImage.compressImageData() == Data([1, 2, 3]))

        // NSImage.tiffRepresentation: corrupt PNG-like bytes now return nil
        // with a warning instead of returning the original non-TIFF bytes.
        let corruptPng = NSImage(data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(corruptPng?.tiffRepresentation == nil)

        let events = QuillCompatibilityDiagnostics.shared.events
        let operations = Set(events.map(\.operation))

        #expect(operations.isSuperset(of: Set([
            "Animation.snappy",
            "Animation.repeatForever",
            "Animation.delay",
            "Image.render",
            "PlatformImage.aspectFittedToHeight",
            "PlatformImage.compressImageData",
            "NSImage.tiffRepresentation"
        ])))

        // Severity: stubs that just no-op are .info; stubs that return wrong/missing
        // data (NSImage tiff lie, image transforms on invalid bytes) are
        // .warning so they surface louder in any diagnostic UI that filters by
        // severity.
        let severitiesByOperation = Dictionary(
            grouping: events,
            by: \.operation
        ).mapValues { Set($0.map(\.severity)) }

        #expect(severitiesByOperation["Animation.repeatForever"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.delay"]?.contains(.info) == true)
        #expect(severitiesByOperation["Animation.snappy"]?.contains(.warning) == true)
        #expect(severitiesByOperation["NSImage.tiffRepresentation"]?.contains(.warning) == true)
        #expect(severitiesByOperation["Image.render"]?.contains(.warning) == true)
        #expect(severitiesByOperation["PlatformImage.aspectFittedToHeight"]?.contains(.warning) == true)
        #expect(severitiesByOperation["PlatformImage.compressImageData"]?.contains(.warning) == true)
    }

    @Test("Image(data:) deduplicates identical bytes within a process")
    func imageDataInitDeduplicatesIdenticalBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillUIImages", isDirectory: true)

        // Snapshot existing files so we measure only the delta from this test.
        let before = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []

        // Make the bytes unique to this test run so we don't collide with other
        // tests' images that may share content.
        let unique = "quill-image-dedup-\(UUID().uuidString)".data(using: .utf8)!

        // Same bytes, three calls; should write exactly one file.
        _ = Image(data: unique)
        _ = Image(data: unique)
        _ = Image(data: unique)

        let after = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let added = Set(after).subtracting(Set(before))
        #expect(added.count == 1, "Image(data:) should write a single PNG for repeated identical bytes; instead wrote \(added.count): \(added.sorted())")

        // Different bytes should write a second file.
        let unique2 = "quill-image-dedup-2-\(UUID().uuidString)".data(using: .utf8)!
        _ = Image(data: unique2)

        let afterSecond = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let addedSecond = Set(afterSecond).subtracting(Set(before))
        #expect(addedSecond.count == 2, "Image(data:) with new bytes should add a second PNG; saw \(addedSecond.count) total new files")
    }

    #if os(Linux)
    @Test("Named images resolve from Linux resource directories")
    func namedImagesResolveFromLinuxResourceDirectories() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("QuillNamedImageResources-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let imageData = Data("quill named image".utf8)
        let imageURL = directory.appendingPathComponent("logo-nobg.png")
        try imageData.write(to: imageURL)

        let previous = getenv("QUILLUI_RESOURCE_DIRS").map { String(cString: $0) }
        setenv("QUILLUI_RESOURCE_DIRS", directory.path, 1)
        defer {
            if let previous {
                setenv("QUILLUI_RESOURCE_DIRS", previous, 1)
            } else {
                unsetenv("QUILLUI_RESOURCE_DIRS")
            }
        }

        let image = Image("logo-nobg")
        if case .filePath(let path) = image.source {
            #expect(path == imageURL.path)
        } else {
            Issue.record("Image(\"logo-nobg\") should resolve to a file-backed SwiftOpenUI image")
        }

        let nsImage = try #require(NSImage(named: "logo-nobg"))
        let uiImage = try #require(UIImage(named: "logo-nobg"))
        #expect(nsImage.data == imageData)
        #expect(uiImage.data == imageData)
        #expect(nsImage.quillResourceName == "logo-nobg")
        #expect(uiImage.quillResourceName == "logo-nobg")
        #expect((uiImage.copy() as? UIImage)?.quillResourceName == "logo-nobg")
        #expect(QuillResourceLookup.path(
            forResource: "logo-nobg",
            candidateExtensions: QuillResourceLookup.commonImageExtensions
        ) == imageURL.path)
    }

    @Test("Named images resolve vector PDF imagesets from asset catalogs")
    func namedImagesResolvePDFImagesetsFromAssetCatalogs() throws {
        let fileManager = FileManager.default
        let catalog = fileManager.temporaryDirectory
            .appendingPathComponent("QuillAssetCatalog-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Symbols.xcassets", isDirectory: true)
        let imageset = catalog
            .appendingPathComponent("message_status", isDirectory: true)
            .appendingPathComponent("message_status_sent.imageset", isDirectory: true)
        defer { try? fileManager.removeItem(at: catalog.deletingLastPathComponent()) }
        try fileManager.createDirectory(at: imageset, withIntermediateDirectories: true)

        try """
        {
          "images" : [
            {
              "filename" : "messagestatus-sent.pdf",
              "idiom" : "universal"
            }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """.write(to: imageset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

        let pdf = """
        %PDF-1.7
        1 0 obj
        << /Type /Page /MediaBox [0 0 12 12] >>
        endobj
        %%EOF
        """
        let pdfURL = imageset.appendingPathComponent("messagestatus-sent.pdf")
        try Data(pdf.utf8).write(to: pdfURL)

        let previous = getenv("QUILLUI_RESOURCE_DIRS").map { String(cString: $0) }
        setenv("QUILLUI_RESOURCE_DIRS", catalog.path, 1)
        defer {
            if let previous {
                setenv("QUILLUI_RESOURCE_DIRS", previous, 1)
            } else {
                unsetenv("QUILLUI_RESOURCE_DIRS")
            }
        }

        #expect(QuillResourceLookup.path(
            forResource: "message_status_sent",
            candidateExtensions: QuillResourceLookup.commonImageExtensions
        ) == pdfURL.path)
        let image = try #require(UIImage(named: "message_status_sent"))
        #expect(image.size == CGSize(width: 12, height: 12))
        #expect(image.quillResourceName == "message_status_sent")
    }

    @Test("System images preserve symbol identity for render backends")
    func systemImagesPreserveSymbolIdentityForRenderBackends() throws {
        let image = try #require(UIImage(systemName: "paperplane.fill"))
        #expect(image.quillSystemSymbolName == "paperplane.fill")
        #expect((image.copy() as? UIImage)?.quillSystemSymbolName == "paperplane.fill")
    }
    #endif

    // MARK: - Symbol name compatibility

    @Test("QuillSystemSymbol preserves backend-covered SF Symbols and maps close variants")
    func quillSystemSymbolMapsKnownAndPassesUnknown() {
        let knownMappings: [(input: String, expected: String)] = [
            ("paperplane.fill", "paperplane.fill"),
            ("photo", "photo"),
            ("photo.fill", "photo.fill"),
            ("lightbulb", "lightbulb"),
            ("lightbulb.circle", "lightbulb.circle"),
            ("lightbulb.circle.fill", "lightbulb.circle.fill"),
            ("character.cursor.ibeam", "character.cursor.ibeam"),
            ("textformat", "textformat"),
            ("textformat.abc", "textformat.abc"),
            ("keyboard", "keyboard"),
            ("waveform", "waveform"),
            ("xmark", "xmark.circle.fill"),
            ("x.circle", "xmark.circle.fill"),
            ("x.circle.fill", "xmark.circle.fill")
        ]

        for (input, expected) in knownMappings {
            #expect(
                QuillSystemSymbol.compatibleName(input) == expected,
                "Expected \(input) -> \(expected); got \(QuillSystemSymbol.compatibleName(input))"
            )
        }

        // Unknown names pass through unchanged so apps requesting symbols Quill
        // hasn't aliased yet still render the original token.
        #expect(QuillSystemSymbol.compatibleName("unknown.symbol.name") == "unknown.symbol.name")
        #expect(QuillSystemSymbol.compatibleName("") == "")
    }

    // MARK: - AppStorage round-trip

    @Test("AppStorage persists values across reads for every supported scalar type")
    func appStorageRoundTripsScalarValues() {
        let suffix = UUID().uuidString
        let stringKey = "quill.test.string.\(suffix)"
        let boolKey = "quill.test.bool.\(suffix)"
        let intKey = "quill.test.int.\(suffix)"
        let doubleKey = "quill.test.double.\(suffix)"

        defer {
            UserDefaults.standard.removeObject(forKey: stringKey)
            UserDefaults.standard.removeObject(forKey: boolKey)
            UserDefaults.standard.removeObject(forKey: intKey)
            UserDefaults.standard.removeObject(forKey: doubleKey)
        }

        // Default values are returned when the key has never been written.
        #expect(AppStorage(wrappedValue: "default-string", stringKey).wrappedValue == "default-string")
        #expect(AppStorage(wrappedValue: true, boolKey).wrappedValue == true)
        #expect(AppStorage(wrappedValue: 42, intKey).wrappedValue == 42)
        #expect(AppStorage(wrappedValue: 3.14, doubleKey).wrappedValue == 3.14)

        // Writing through one wrapper and reading from a fresh wrapper proves
        // the value persisted to UserDefaults rather than just to local state.
        let stringStorage = AppStorage(wrappedValue: "ignored", stringKey)
        stringStorage.wrappedValue = "written"
        #expect(AppStorage(wrappedValue: "fallback", stringKey).wrappedValue == "written")

        let boolStorage = AppStorage(wrappedValue: false, boolKey)
        boolStorage.wrappedValue = true
        #expect(AppStorage(wrappedValue: false, boolKey).wrappedValue == true)
        boolStorage.wrappedValue = false
        // After explicit false write, value reads back as false (not the
        // wrapped default). Tests the object-existence guard in the read path.
        #expect(AppStorage(wrappedValue: true, boolKey).wrappedValue == false)

        let intStorage = AppStorage(wrappedValue: 0, intKey)
        intStorage.wrappedValue = 7
        #expect(AppStorage(wrappedValue: 0, intKey).wrappedValue == 7)

        let doubleStorage = AppStorage(wrappedValue: 0.0, doubleKey)
        doubleStorage.wrappedValue = 2.5
        #expect(AppStorage(wrappedValue: 0.0, doubleKey).wrappedValue == 2.5)
    }

    @Test("AppStorage encodes RawRepresentable enums via their raw value")
    func appStorageEncodesRawRepresentableEnums() {
        let key = "quill.test.mode.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Default value when nothing is stored.
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .classic)

        let storage = AppStorage(wrappedValue: AppStorageMode.classic, key)
        storage.wrappedValue = .modern
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .modern)
        // Underlying storage uses the rawValue, not Codable JSON.
        #expect(UserDefaults.standard.string(forKey: key) == "modern")

        // A garbage rawValue at the storage key falls back to the default.
        UserDefaults.standard.set("not-a-case", forKey: key)
        #expect(AppStorage(wrappedValue: AppStorageMode.classic, key).wrappedValue == .classic)
    }

    // MARK: - File importer

    @Test("QuillFileImporter honors test-injected selection and validates types")
    func quillFileImporterUsesTestSelection() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillFileImporterTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pngURL = directory.appendingPathComponent("hello.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngURL)
        defer {
            try? FileManager.default.removeItem(at: directory)
            QuillFileImporter.setTestSelection(nil)
        }

        QuillFileImporter.setTestSelection(pngURL)

        // Happy path: PNG conforms to image / png.
        switch QuillFileImporter.selectURL(allowedContentTypes: [.image]) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected success, got failure: \(error)")
        }

        switch QuillFileImporter.selectURL(allowedContentTypes: [.png]) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected png to match png allowedType: \(error)")
        }

        // Empty allowedContentTypes accepts any URL (matches SwiftUI behavior).
        switch QuillFileImporter.selectURL(allowedContentTypes: []) {
        case .success(let url):
            #expect(url == pngURL)
        case .failure(let error):
            Issue.record("Expected empty allowedTypes to accept any URL: \(error)")
        }

        // Mismatched type fails with the right error case.
        switch QuillFileImporter.selectURL(allowedContentTypes: [.jpeg]) {
        case .success:
            Issue.record("Expected jpeg-only allowedTypes to reject a .png URL")
        case .failure(let error):
            guard let quillError = error as? QuillCompatibilityError else {
                Issue.record("Expected QuillCompatibilityError, got \(type(of: error)): \(error)")
                return
            }
            switch quillError {
            case .unsupportedFileSelection(let url, let allowed):
                #expect(url == pngURL)
                #expect(allowed == [.jpeg])
            default:
                Issue.record("Expected .unsupportedFileSelection, got \(quillError)")
            }
        }
    }

    // MARK: - UTType behavior

    @Test("UTType infers types from file extensions and reports conformance")
    func utTypeInfersAndConforms() {
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.png")) == .png)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.PNG")) == .png)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.jpeg")) == .jpeg)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.jpg")) == .jpeg)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.tiff")) == .tiff)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/photo.tif")) == .tiff)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/document.txt")) == .plainText)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/document.rtf")) == .rtf)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/feed.xml")) == .xml)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/clip.mp4")) == .mpeg4Movie)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/audio.mp3")) == .mp3)
        #expect(UTType.type(for: URL(fileURLWithPath: "/tmp/no-extension")) == nil)

        // Identity conformance.
        #expect(UTType.png.conforms(to: .png))
        #expect(UTType.jpeg.conforms(to: .jpeg))

        // Apple UTType conformance is transitive through content/data roots.
        #expect(UTType.png.conforms(to: .image))
        #expect(UTType.png.conforms(to: .data))
        #expect(UTType.png.conforms(to: .item))
        #expect(UTType.jpeg.conforms(to: .image))
        #expect(UTType.tiff.conforms(to: .image))
        #expect(UTType.utf8PlainText.conforms(to: .plainText))
        #expect(UTType.plainText.conforms(to: .text))
        #expect(UTType.html.conforms(to: .text))
        #expect(UTType.json.conforms(to: .data))
        #expect(UTType.fileURL.conforms(to: .url))
        #expect(UTType.url.conforms(to: .data))
        #expect(UTType.folder.conforms(to: .directory))
        #expect(UTType.folder.conforms(to: .item))
        #expect(UTType.directory.conforms(to: .data) == false)

        // A custom type does not inherit from image unless explicitly modeled.
        #expect(UTType("public.text")?.conforms(to: .image) == false)

        // Unrelated concrete types do not conform to each other.
        #expect(UTType.png.conforms(to: .jpeg) == false)
    }

    // MARK: - NSItemProvider data flow

    @Test("NSItemProvider delivers data and file representations matching content type")
    func nsItemProviderDeliversMatchingRepresentations() throws {
        let payload = Data([0xCA, 0xFE, 0xBA, 0xBE])

        // Data-backed provider, matching type.
        let dataProvider = NSItemProvider(data: payload, type: .png)
        let dataCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .png) { data, error in
            dataCaptured.value = (data, error)
        }
        #expect(dataCaptured.value?.0 == payload)
        #expect(dataCaptured.value?.1 == nil)

        // Data-backed provider, image supertype matches concrete png too.
        let imgCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .image) { data, error in
            imgCaptured.value = (data, error)
        }
        #expect(imgCaptured.value?.0 == payload)
        #expect(imgCaptured.value?.1 == nil)

        // Data-backed provider, mismatched type produces an error.
        let mismatchCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = dataProvider.loadDataRepresentation(for: .jpeg) { data, error in
            mismatchCaptured.value = (data, error)
        }
        #expect(mismatchCaptured.value?.0 == nil)
        #expect(mismatchCaptured.value?.1 != nil)

        // File-backed provider reads bytes from the URL.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuillItemProviderTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("payload.png")
        try payload.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileProvider = NSItemProvider(fileURL: fileURL)
        let fileCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = fileProvider.loadDataRepresentation(for: .png) { data, error in
            fileCaptured.value = (data, error)
        }
        #expect(fileCaptured.value?.0 == payload)
        #expect(fileCaptured.value?.1 == nil)

        // Empty provider always errors.
        let empty = NSItemProvider()
        let emptyCaptured = QuillTestBox<(Data?, Error?)>((nil, nil))
        _ = empty.loadDataRepresentation(for: .png) { data, error in
            emptyCaptured.value = (data, error)
        }
        #expect(emptyCaptured.value?.0 == nil)
        #expect(emptyCaptured.value?.1 != nil)
    }

    // MARK: - OpenURLAction custom handler

    @Test("OpenURLAction routes URLs through the configured handler")
    @MainActor
    func openURLActionInvokesCustomHandler() {
        let captured = QuillTestBox<URL>()
        let action = OpenURLAction { url in
            captured.value = url
            return true
        }

        let url = URL(string: "https://quill.test/path?q=1")!
        let result = action(url)
        #expect(result == .handled)
        #expect(captured.value == url)

        // Returning false from the handler propagates.
        let rejecting = OpenURLAction { _ in false }
        #expect(rejecting(URL(string: "https://example.com")!) == .discarded)
    }

    // MARK: - QuillMenuAction divider + disabled semantics

    @Test("QuillMenuAction divider is a divider and disabled actions never run")
    func quillMenuActionDividerAndDisabled() {
        let divider = QuillMenuAction.divider()
        #expect(divider.kind == .divider)
        // Calling perform() on a divider must not crash; the synthesized
        // empty closure is a no-op. Idempotent.
        divider.perform()
        divider.perform()

        // Disabled action does not invoke its closure.
        let disabledRan = QuillTestBox<Bool>(false)
        let disabled = QuillMenuAction(
            title: "Disabled",
            isDisabled: true,
            action: { disabledRan.value = true }
        )
        disabled.perform()
        #expect(disabledRan.value == false)

        // Enabled action invokes its closure exactly once per perform().
        let enabledCount = QuillTestBox<Int>(0)
        let enabled = QuillMenuAction(title: "Enabled") {
            enabledCount.value = (enabledCount.value ?? 0) + 1
        }
        enabled.perform()
        enabled.perform()
        #expect(enabledCount.value == 2)

        // Unspecified id falls back to the title.
        #expect(enabled.id == "Enabled")
        let withCustomID = QuillMenuAction(id: "explicit", title: "Title") {}
        #expect(withCustomID.id == "explicit")
    }

    // MARK: - Gradient.quillAverageColor

    @Test("Gradient.quillAverageColor averages stops by RGBA component")
    func gradientAverageColorAveragesStops() {
        // Two-stop gradient: red (1,0,0,1) and blue (0,0,1,1) averages to (0.5, 0, 0.5, 1).
        let twoStops = Gradient(colors: [
            Color(red: 1.0, green: 0.0, blue: 0.0, opacity: 1.0),
            Color(red: 0.0, green: 0.0, blue: 1.0, opacity: 1.0)
        ])
        let avg = twoStops.quillAverageColor
        #expect(abs(avg.red - 0.5) < 0.001, "expected red ~= 0.5, got \(avg.red)")
        #expect(abs(avg.green - 0.0) < 0.001, "expected green ~= 0.0, got \(avg.green)")
        #expect(abs(avg.blue - 0.5) < 0.001, "expected blue ~= 0.5, got \(avg.blue)")
        #expect(abs(avg.alpha - 1.0) < 0.001, "expected alpha ~= 1.0, got \(avg.alpha)")

        // Three identical stops average to that color (sanity check on the
        // reduce path; divisor must be count, not count - 1).
        let solid = Gradient(colors: [
            Color(red: 0.4, green: 0.6, blue: 0.8, opacity: 0.5),
            Color(red: 0.4, green: 0.6, blue: 0.8, opacity: 0.5),
            Color(red: 0.4, green: 0.6, blue: 0.8, opacity: 0.5)
        ])
        let solidAvg = solid.quillAverageColor
        #expect(abs(solidAvg.red - 0.4) < 0.001)
        #expect(abs(solidAvg.green - 0.6) < 0.001)
        #expect(abs(solidAvg.blue - 0.8) < 0.001)
        #expect(abs(solidAvg.alpha - 0.5) < 0.001)

        // Empty gradient returns .primary instead of dividing by zero.
        // We can't compare Color values directly across the SwiftOpenUI shim,
        // but accessing the property must not crash.
        _ = Gradient(colors: []).quillAverageColor
    }

    // MARK: - PresentationMode.dismiss

    @Test("PresentationMode invokes its dismiss closure")
    func presentationModeInvokesDismissClosure() {
        let invoked = QuillTestBox<Int>(0)
        let mode = PresentationMode(dismiss: {
            invoked.value = (invoked.value ?? 0) + 1
        })

        // The exposed `wrappedValue` returns self, so wrappedValue.dismiss()
        // hits the same action; both call paths must work.
        mode.dismiss()
        mode.wrappedValue.dismiss()
        #expect(invoked.value == 2)

        // Default initializer is a no-op closure that doesn't crash.
        PresentationMode().dismiss()
    }

    @Test("Environment presentationMode falls back to dismiss")
    func environmentPresentationModeFallsBackToDismiss() {
        let fallbackInvoked = QuillTestBox<Int>(0)
        let explicitInvoked = QuillTestBox<Int>(nil)
        let contextualInvoked = QuillTestBox<Int>(nil)
        var environment = EnvironmentValues()

        environment.dismiss = DismissAction {
            fallbackInvoked.value = (fallbackInvoked.value ?? 0) + 1
        }
        environment.presentationMode.dismiss()
        #expect(fallbackInvoked.value == 1)
        #expect(explicitInvoked.value == nil)
        #expect(contextualInvoked.value == nil)

        swiftOpenUIWithPresentationDismissAction({
            contextualInvoked.value = (contextualInvoked.value ?? 0) + 1
        }) {
            environment.presentationMode.dismiss()
        }
        #expect(fallbackInvoked.value == 1)
        #expect(contextualInvoked.value == 1)

        environment.presentationMode = PresentationMode {
            explicitInvoked.value = (explicitInvoked.value ?? 0) + 1
        }
        environment.presentationMode.dismiss()
        #expect(fallbackInvoked.value == 1)
        #expect(explicitInvoked.value == 1)
    }

    // MARK: - QuillCompatibilityError.errorDescription

    @Test("QuillCompatibilityError formats LocalizedError descriptions")
    func quillCompatibilityErrorDescriptions() {
        let unavailable = QuillCompatibilityError.representationUnavailable("public.png")
        #expect(unavailable.errorDescription == "No data representation is available for public.png.")

        let noProvider = QuillCompatibilityError.fileSelectionUnavailable
        #expect(noProvider.errorDescription == "No file selection provider is available.")

        let url = URL(fileURLWithPath: "/tmp/photo.txt")
        let unsupported = QuillCompatibilityError.unsupportedFileSelection(url, [.png, .jpeg])
        #expect(
            unsupported.errorDescription
                == "/tmp/photo.txt is not one of the allowed file types: public.png, public.jpeg.",
            "Got unexpected description: \(unsupported.errorDescription ?? "nil")"
        )

        // Empty allowedTypes still formats cleanly (joined separator collapses).
        let emptyAllowed = QuillCompatibilityError.unsupportedFileSelection(url, [])
        #expect(
            emptyAllowed.errorDescription
                == "/tmp/photo.txt is not one of the allowed file types: ."
        )
    }

    // MARK: - FocusState init paths

    @Test("FocusState exposes correct defaults across its three init paths")
    func focusStateInitPaths() {
        // Bool-defaulted init starts at false.
        let boolFocus = FocusState<Bool>()
        #expect(boolFocus.wrappedValue == false)

        // Optional<Wrapped> init starts at nil.
        let optionalFocus = FocusState<String?>()
        #expect(optionalFocus.wrappedValue == nil)

        // wrappedValue init starts at the provided Bool value.
        let provided = FocusState<Bool>(wrappedValue: true)
        #expect(provided.wrappedValue)

        // Mutating wrappedValue persists (FocusState boxes its storage so
        // nonmutating set works on a let-bound copy, just like SwiftUI).
        provided.wrappedValue = false
        #expect(!provided.wrappedValue)

        // Binding produced via projectedValue can read AND write.
        let binding = provided.projectedValue
        #expect(!binding.wrappedValue)
        binding.wrappedValue = true
        #expect(provided.wrappedValue)

        let optionalProvided = FocusState<String?>(wrappedValue: "message")
        #expect(optionalProvided.wrappedValue == "message")
    }

    // MARK: - Namespace identity

    @Test("Namespace generates unique IDs across instances and is Hashable")
    func namespaceGeneratesUniqueIdentities() {
        let first = Namespace()
        let second = Namespace()
        #expect(first.wrappedValue != second.wrappedValue)

        // Same Namespace returns the same ID across reads.
        let stored = first.wrappedValue
        #expect(first.wrappedValue == stored)

        // IDs are usable as Set / Dictionary keys.
        let ids: Set<Namespace.ID> = [
            first.wrappedValue,
            second.wrappedValue,
            first.wrappedValue
        ]
        #expect(ids.count == 2)
    }

    // MARK: - QuillSidebarNavigationAction.perform

    @Test("QuillSidebarNavigationAction perform invokes its action and id falls back to title")
    func quillSidebarNavigationActionPerformsAction() {
        let count = QuillTestBox<Int>(0)
        let action = QuillSidebarNavigationAction(
            title: "Settings",
            systemImage: "gear",
            action: { count.value = (count.value ?? 0) + 1 }
        )

        action.perform()
        action.perform()
        action.perform()
        #expect(count.value == 3)

        // id falls back to title when not provided.
        #expect(action.id == "Settings")

        // Explicit id wins over title.
        let custom = QuillSidebarNavigationAction(
            id: "settings.id",
            title: "Settings",
            systemImage: "gear",
            action: {}
        )
        #expect(custom.id == "settings.id")

        let completions = QuillTestBox<Int>(0)
        let shortcuts = QuillTestBox<Int>(0)
        let settings = QuillTestBox<Int>(0)
        let utilities = QuillSidebarNavigationAction.desktopChatUtilities(
            onCompletions: { completions.value = (completions.value ?? 0) + 1 },
            onShortcuts: { shortcuts.value = (shortcuts.value ?? 0) + 1 },
            onSettings: { settings.value = (settings.value ?? 0) + 1 }
        )

        #if os(macOS) || os(Linux)
        #expect(utilities.map(\.title) == ["Completions", "Shortcuts", "Settings"])
        #expect(utilities.map(\.systemImage) == ["textformat.abc", "keyboard.fill", "gearshape.fill"])
        #else
        #expect(utilities.map(\.title) == ["Settings"])
        #expect(utilities.map(\.systemImage) == ["gearshape.fill"])
        #endif

        utilities.forEach { $0.perform() }
        #if os(macOS) || os(Linux)
        #expect(completions.value == 1)
        #expect(shortcuts.value == 1)
        #else
        #expect(completions.value == 0)
        #expect(shortcuts.value == 0)
        #endif
        #expect(settings.value == 1)
    }

    // MARK: - QuillPrompt identity

    @Test("QuillPrompt id falls back to title and supports Hashable identity")
    func quillPromptIdentityFallsBackToTitle() {
        let untagged = QuillPrompt(title: "Summarize", systemImage: "doc.text")
        #expect(untagged.id == "Summarize")

        let tagged = QuillPrompt(id: "prompt.summarize.v2", title: "Summarize", systemImage: "doc.text")
        #expect(tagged.id == "prompt.summarize.v2")

        // Different titles with the same explicit id collapse via Hashable when
        // both id and title differ; Hashable is the full struct, not just id.
        let alpha = QuillPrompt(id: "x", title: "A", systemImage: "1.circle")
        let beta = QuillPrompt(id: "x", title: "A", systemImage: "1.circle")
        let gamma = QuillPrompt(id: "x", title: "B", systemImage: "1.circle")
        #expect(alpha == beta)
        #expect(alpha != gamma)

        let set: Set<QuillPrompt> = [alpha, beta, gamma]
        #expect(set.count == 2)
    }

    // MARK: - AnyTransition combinators

    @Test("AnyTransition combinators do not crash and return AnyTransition values")
    func anyTransitionCombinatorsAreSafe() {
        // Static factories.
        #expect(String(describing: AnyTransition.opacity).contains("opacity"))
        #expect(String(describing: AnyTransition.slide).contains("slide"))
        #expect(String(describing: AnyTransition.scale()).contains("scale"))
        #expect(String(describing: AnyTransition.scale(scale: 0.5, anchor: .center)).contains("0.5"))
        #expect(String(describing: AnyTransition.asymmetric(insertion: .opacity, removal: .slide)).contains("asymmetric"))

        // Init-from-self preserves the value.
        let copy = AnyTransition(.opacity)
        #expect(String(describing: copy).contains("opacity"))

        let combined = AnyTransition.opacity.combined(with: .slide)
        #expect(String(describing: combined).contains("combined"))
        #expect(String(describing: combined).contains("opacity"))
        #expect(String(describing: combined).contains("slide"))
    }

    // MARK: - QuillCompatibilityEvent equality

    // MARK: - SPI: view-tree introspection helpers

    @Test("quillTextLabel extracts text content from primitive view types")
    @MainActor
    func quillTextLabelExtractsFromPrimitives() {
        // Text: returns its content directly.
        #expect(QuillUI.quillTextLabel(from: Text("Hello")) == "Hello")
        #expect(QuillUI.quillTextLabel(from: Text("")) == "")

        // Label: returns its title (the system-image side is ignored here).
        #expect(QuillUI.quillTextLabel(from: Label("Settings", systemImage: "gear")) == "Settings")

        // Image: bridges through quillSystemImageName and returns the symbol token.
        #expect(QuillUI.quillTextLabel(from: Image(systemName: "paperplane.fill")) == "paperplane.fill")

        // Unknown view type returns an empty string fallback (used so callers can detect
        // "no extractable label" without crashing on opaque view types).
        struct Unknown: View {
            var body: some View { Text("nope") }
        }
        #expect(QuillUI.quillTextLabel(from: Unknown()) == "")
    }

    @Test("quillSystemImageName preserves backend-covered SF Symbols and falls back gracefully")
    @MainActor
    func quillSystemImageNameRemapsAndFallsBack() {
        // Backend-covered SF Symbols preserve the macOS token.
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "paperplane.fill")) == "paperplane.fill")
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "photo.fill")) == "photo.fill")
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "lightbulb.circle")) == "lightbulb.circle")

        // Unknown SF Symbol passes through unchanged.
        #expect(QuillUI.quillSystemImageName(from: Image(systemName: "custom.symbol.name")) == "custom.symbol.name")

        // Non-Image view returns a "circle" sentinel so the GTK-side has a real symbol
        // to render even if the caller passed something inappropriate.
        #expect(QuillUI.quillSystemImageName(from: Text("not-an-image")) == "circle")
    }

    @Test("quillTextLabel unwraps styled labels")
    @MainActor
    func quillTextLabelUnwrapsStyledLabels() {
        let styledLabel = Text("Styled")
            .font(.body)
            .foregroundColor(.primary)
            .lineLimit(1)
            .bold()
            .help("Tooltip")
        #expect(QuillUI.quillTextLabel(from: styledLabel) == "Styled")

        #expect(QuillUI.quillTextLabel(from: Text("Visible").accessibilityLabel("Accessible")) == "Visible")
        #expect(QuillUI.quillTextLabel(from: EmptyView().accessibilityLabel("Fallback")) == "Fallback")
    }

    @Test("quillMenuElements walks Button, Disabled, KeyboardShortcut, and recurses MultiChildView")
    @MainActor
    func quillMenuElementsWalksViewTree() {
        // Plain Button returns a single .item with the button's title and action.
        let buttonTapCount = QuillTestBox<Int>(0)
        let plainButton = Button("Save") {
            buttonTapCount.value = (buttonTapCount.value ?? 0) + 1
        }
        let plainElements = QuillUI.quillMenuElements(from: plainButton)
        #expect(plainElements.count == 1)
        if case .item(let label, let action) = plainElements.first {
            #expect(label == "Save")
            action()
            #expect(buttonTapCount.value == 1)
        } else {
            Issue.record("Expected .item, got \(String(describing: plainElements.first))")
        }

        // DisabledView wrapping a button replaces the action with a no-op
        // closure so calling it does nothing.
        let disabledTapCount = QuillTestBox<Int>(0)
        let disabledButton = Button("Delete") {
            disabledTapCount.value = (disabledTapCount.value ?? 0) + 1
        }.disabled(true)
        let disabledElements = QuillUI.quillMenuElements(from: disabledButton)
        #expect(disabledElements.count == 1)
        if case .item(let label, let action) = disabledElements.first {
            #expect(label == "Delete")
            action()
            // Disabled actions are replaced with empty closures, so the count
            // must stay at zero.
            #expect(disabledTapCount.value == 0)
        } else {
            Issue.record("Expected disabled .item, got \(String(describing: disabledElements.first))")
        }

        let chainedDisabledTapCount = QuillTestBox<Int>(0)
        let disabledThenShortcut = Button("Archive") {
            chainedDisabledTapCount.value = (chainedDisabledTapCount.value ?? 0) + 1
        }
        .disabled(true)
        .keyboardShortcut("a", modifiers: .command)
        let chainedDisabledElements = QuillUI.quillMenuElements(from: disabledThenShortcut)
        #expect(chainedDisabledElements.count == 1)
        if case .item(let label, let action) = chainedDisabledElements.first {
            #expect(label == "Archive")
            action()
            #expect(chainedDisabledTapCount.value == 0)
        } else {
            Issue.record("Expected chained disabled .item, got \(String(describing: chainedDisabledElements.first))")
        }

        let shortcutThenDisabled = Button("Export") {
            chainedDisabledTapCount.value = (chainedDisabledTapCount.value ?? 0) + 1
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(true)
        let shortcutThenDisabledElements = QuillUI.quillMenuElements(from: shortcutThenDisabled)
        #expect(shortcutThenDisabledElements.count == 1)
        if case .item(let label, let action) = shortcutThenDisabledElements.first {
            #expect(label == "Export")
            action()
            #expect(chainedDisabledTapCount.value == 0)
        } else {
            Issue.record("Expected shortcut then disabled .item, got \(String(describing: shortcutThenDisabledElements.first))")
        }

        let styledTapCount = QuillTestBox<Int>(0)
        let styledButton = Button(action: {
            styledTapCount.value = (styledTapCount.value ?? 0) + 1
        }) {
            Text("Rename")
                .font(.body)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .help("Rename item")
        let styledElements = QuillUI.quillMenuElements(from: styledButton)
        #expect(styledElements.count == 1)
        if case .item(let label, let action) = styledElements.first {
            #expect(label == "Rename")
            action()
            #expect(styledTapCount.value == 1)
        } else {
            Issue.record("Expected styled .item, got \(String(describing: styledElements.first))")
        }

        // Unknown view type returns []
        struct Unknown: View {
            var body: some View { Text("x") }
        }
        #expect(QuillUI.quillMenuElements(from: Unknown()).isEmpty)
    }

    @Test("confirmationDialog compatibility preserves buttons and message text")
    func confirmationDialogCompatibilityPreservesButtonsAndMessage() {
        let deleteTapCount = QuillTestBox<Int>(0)
        let cancelTapCount = QuillTestBox<Int>(0)
        let dialog = Text("Row").confirmationDialog("Delete?", isPresented: .constant(true)) {
            Button("Delete") {
                deleteTapCount.value = (deleteTapCount.value ?? 0) + 1
            }
            Button("Cancel", role: .cancel) {
                cancelTapCount.value = (cancelTapCount.value ?? 0) + 1
            }
        } message: {
            Text("Delete this completion?")
        }

        #expect(dialog.title == "Delete?")
        #expect(dialog.message == "Delete this completion?")
        #expect(dialog.buttons.count == 2)
        #expect(dialog.buttons.map { $0.label } == ["Delete", "Cancel"])
        guard dialog.buttons.count == 2 else {
            return
        }

        dialog.buttons[0].action()
        dialog.buttons[1].action()

        #expect(deleteTapCount.value == 1)
        #expect(cancelTapCount.value == 1)
    }

    @Test("quillCommandMenuItems extracts from Button and respects disabled state")
    @MainActor
    func quillCommandMenuItemsExtraction() {
        let count = QuillTestBox<Int>(0)
        let button = Button("Open") {
            count.value = (count.value ?? 0) + 1
        }

        let items = QuillUI.quillCommandMenuItems(from: button)
        #expect(items.count == 1)
        #expect(items.first?.label == "Open")

        // Verify the action is the button's action (calls increment counter).
        items.first?.action()
        #expect(count.value == 1)

        let disabledShortcut = Button("Archive") {
            count.value = (count.value ?? 0) + 1
        }
        .disabled(true)
        .keyboardShortcut("a", modifiers: .command)
        let disabledShortcutItems = QuillUI.quillCommandMenuItems(from: disabledShortcut)
        #expect(disabledShortcutItems.count == 1)
        #expect(disabledShortcutItems.first?.label == "Archive")
        #expect(disabledShortcutItems.first?.isDisabled == true)
        #expect(disabledShortcutItems.first?.shortcut == KeyboardShortcut("a", modifiers: .command))

        let shortcutDisabled = Button("Export") {
            count.value = (count.value ?? 0) + 1
        }
        .keyboardShortcut("e", modifiers: .command)
        .disabled(true)
        let shortcutDisabledItems = QuillUI.quillCommandMenuItems(from: shortcutDisabled)
        #expect(shortcutDisabledItems.count == 1)
        #expect(shortcutDisabledItems.first?.label == "Export")
        #expect(shortcutDisabledItems.first?.isDisabled == true)
        #expect(shortcutDisabledItems.first?.shortcut == KeyboardShortcut("e", modifiers: .command))

        let nestedDisabled = Button("Pinned") {
            count.value = (count.value ?? 0) + 1
        }
        .disabled(true)
        .disabled(false)
        let nestedDisabledItems = QuillUI.quillCommandMenuItems(from: nestedDisabled)
        #expect(nestedDisabledItems.count == 1)
        #expect(nestedDisabledItems.first?.label == "Pinned")
        #expect(nestedDisabledItems.first?.isDisabled == true)

        let styledCommand = Button("Sync") {
            count.value = (count.value ?? 0) + 1
        }
        .font(.body)
        .foregroundColor(.primary)
        .help("Sync now")
        let styledCommandItems = QuillUI.quillCommandMenuItems(from: styledCommand)
        #expect(styledCommandItems.count == 1)
        #expect(styledCommandItems.first?.label == "Sync")

        // Unknown view returns empty.
        struct Unknown: View {
            var body: some View { Text("x") }
        }
        #expect(QuillUI.quillCommandMenuItems(from: Unknown()).isEmpty)
    }

    @Test("quillPickerOptions extracts labels and tags from tagged view content")
    @MainActor
    func quillPickerOptionsExtraction() {
        let options = QuillUI.quillPickerOptions(from: HStack {
            Text("").tag("a")
            Image(systemName: "photo.fill").tag("b")
        })

        #expect(options.count == 2)
        #expect(options[0].label == "a")
        #expect(options[0].tag == AnyHashable("a"))
        #expect(options[1].label == "photo.fill")
        #expect(options[1].tag == AnyHashable("b"))

        let styledOptions = QuillUI.quillPickerOptions(from: HStack {
            Text("Compact")
                .font(.body)
                .tag("compact")
            Text("Detailed")
                .tag("detailed")
                .foregroundColor(.primary)
        })
        #expect(styledOptions.count == 2)
        #expect(styledOptions[0].label == "Compact")
        #expect(styledOptions[0].tag == AnyHashable("compact"))
        #expect(styledOptions[1].label == "Detailed")
        #expect(styledOptions[1].tag == AnyHashable("detailed"))

        struct Unknown: View {
            var body: some View { Text("x") }
        }
        #expect(QuillUI.quillPickerOptions(from: Unknown()).isEmpty)
    }

    // MARK: - NSImage.tiffRepresentation parity

    @Test("QuillImageFormatDetector identifies the common container formats")
    func quillImageFormatDetectorIdentifiesContainers() {
        // TIFF little-endian and big-endian magic.
        #expect(QuillImageFormatDetector.detect(Data([0x49, 0x49, 0x2A, 0x00])) == .tiff)
        #expect(QuillImageFormatDetector.detect(Data([0x4D, 0x4D, 0x00, 0x2A, 0xAA])) == .tiff)

        // PNG magic.
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00])
        #expect(QuillImageFormatDetector.detect(pngMagic) == .png)

        // JPEG magic (SOI + APP0/APP1 marker).
        #expect(QuillImageFormatDetector.detect(Data([0xFF, 0xD8, 0xFF, 0xE0])) == .jpeg)
        #expect(QuillImageFormatDetector.detect(Data([0xFF, 0xD8, 0xFF, 0xE1])) == .jpeg)

        // GIF87a / GIF89a.
        #expect(QuillImageFormatDetector.detect(Data("GIF87a".utf8)) == .gif)
        #expect(QuillImageFormatDetector.detect(Data("GIF89a".utf8)) == .gif)

        // BMP.
        #expect(QuillImageFormatDetector.detect(Data([0x42, 0x4D, 0x00])) == .bmp)

        // WebP container needs both RIFF and WEBP markers.
        let webp: [UInt8] = [
            0x52, 0x49, 0x46, 0x46,  // "RIFF"
            0x00, 0x00, 0x00, 0x00,  // size (any)
            0x57, 0x45, 0x42, 0x50   // "WEBP"
        ]
        #expect(QuillImageFormatDetector.detect(Data(webp)) == .webp)

        // Unknown / too short.
        #expect(QuillImageFormatDetector.detect(Data([0xDE, 0xAD, 0xBE, 0xEF])) == .unknown)
        #expect(QuillImageFormatDetector.detect(Data()) == .unknown)
        #expect(QuillImageFormatDetector.detect(Data([0xFF])) == .unknown)
    }

    @Test("NSImage.tiffRepresentation: TIFF input passes through unchanged on Linux")
    func nsImageTiffPassthroughIsDeterministic() {
        // A minimal little-endian TIFF header. Apple promises valid TIFF bytes
        // out for valid TIFF input, but not byte-for-byte equality. Linux keeps
        // this deterministic and returns source TIFF bytes unchanged.
        let tiffBytes = Data([0x49, 0x49, 0x2A, 0x00] + Array(repeating: 0xAA, count: 32))
        let img = NSImage(data: tiffBytes)
        #expect(img?.tiffRepresentation == tiffBytes)

        // Big-endian TIFF magic also passes through.
        let bigEndianTIFF = Data([0x4D, 0x4D, 0x00, 0x2A] + Array(repeating: 0xBB, count: 32))
        let img2 = NSImage(data: bigEndianTIFF)
        #expect(img2?.tiffRepresentation == bigEndianTIFF)
    }

    @Test("NSImage.tiffRepresentation: corrupt input returns nil and records a warning")
    func nsImageTiffCorruptInputReturnsNil() {
        QuillCompatibilityDiagnostics.shared.clear()

        // Corrupt PNG-like input should NOT come back labeled as TIFF.
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0x00, count: 16))
        let pngImage = NSImage(data: pngBytes)
        #expect(pngImage?.tiffRepresentation == nil)

        // Corrupt JPEG-like input returns nil.
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: 0x42, count: 16))
        let jpegImage = NSImage(data: jpegBytes)
        #expect(jpegImage?.tiffRepresentation == nil)

        // Unknown bytes return nil with a separate diagnostic message.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])
        let garbageImage = NSImage(data: garbage)
        #expect(garbageImage?.tiffRepresentation == nil)

        // All three calls recorded warnings (severity .warning, not .info).
        let warnings = QuillCompatibilityDiagnostics.shared.events
            .filter { $0.operation == "NSImage.tiffRepresentation" && $0.severity == .warning }
        #expect(warnings.count >= 3, "Expected at least 3 NSImage.tiffRepresentation warnings; got \(warnings.count)")
    }

    @Test("NSImage without bytes returns nil for TIFF")
    func nsImageWithoutBytesReturnsNilTIFF() {
        // The convenience init that takes only a size leaves data == nil.
        let blank = NSImage(size: CGSize(width: 64, height: 64))
        #expect(blank.tiffRepresentation == nil)
    }

    @Test("NSImage.tiffRepresentation transcodes a valid PNG to real TIFF via gdk-pixbuf")
    func nsImageTiffPNGToTIFFTranscodes() {
        // 67-byte 1x1 grayscale PNG. Same fixture as the cross-platform parity
        // test in QuillParityTests. Passing here proves the gdk-pixbuf bridge
        // produces TIFF output that's symmetric with what real Apple AppKit
        // produces on macOS.
        guard let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==") else {
            Issue.record("Failed to decode reference PNG fixture")
            return
        }

        guard let img = NSImage(data: png) else {
            Issue.record("NSImage(data:) failed to construct from valid PNG fixture")
            return
        }

        guard let tiff = img.tiffRepresentation else {
            Issue.record("Linux NSImage.tiffRepresentation returned nil for valid PNG; the gdk-pixbuf bridge should transcode it")
            return
        }

        #expect(tiff.count > 0, "TIFF output must not be empty")

        // Verify TIFF magic bytes (II*\0 little-endian or MM\0* big-endian).
        if tiff.count >= 4 {
            let prefix = Array(tiff.prefix(4))
            let isLittle = prefix == [0x49, 0x49, 0x2A, 0x00]
            let isBig = prefix == [0x4D, 0x4D, 0x00, 0x2A]
            #expect(isLittle || isBig, "Output must start with TIFF magic; got \(prefix)")
        }

        // Calling tiffRepresentation again must produce the same result (no
        // hidden mutation in the getter).
        let secondCall = img.tiffRepresentation
        #expect(secondCall == tiff, "tiffRepresentation must be deterministic for the same instance")
    }

    @Test("quillRenderSolidColorImage produces a real PNG of the requested size and color")
    func quillRenderSolidColorImageContract() {
        // Zero-size dimensions reject early.
        #expect(quillRenderSolidColorImage(red: 1, green: 0, blue: 0, alpha: 1, width: 0, height: 16) == nil)
        #expect(quillRenderSolidColorImage(red: 1, green: 0, blue: 0, alpha: 1, width: 16, height: 0) == nil)
        #expect(quillRenderSolidColorImage(red: 1, green: 0, blue: 0, alpha: 1, width: -1, height: 16) == nil)

        // Valid red 4×4 PNG.
        guard let png = quillRenderSolidColorImage(
            red: 1, green: 0, blue: 0, alpha: 1,
            width: 4, height: 4,
            format: .png
        ) else {
            Issue.record("Expected non-nil PNG for valid solid-color render")
            return
        }
        // PNG magic prefix: \x89 P N G \r \n \x1a \n (8 bytes).
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(png.prefix(8)) == pngMagic, "Output must have PNG magic; got \(Array(png.prefix(8)))")

        // PNG IHDR chunk follows the magic and encodes width/height as
        // big-endian Int32 at byte offsets 16..19 and 20..23.
        if png.count >= 24 {
            let bytes = Array(png)
            let width = (UInt32(bytes[16]) << 24) | (UInt32(bytes[17]) << 16)
                      | (UInt32(bytes[18]) << 8)  |  UInt32(bytes[19])
            let height = (UInt32(bytes[20]) << 24) | (UInt32(bytes[21]) << 16)
                       | (UInt32(bytes[22]) << 8)  |  UInt32(bytes[23])
            #expect(width == 4, "PNG IHDR width should be 4; got \(width)")
            #expect(height == 4, "PNG IHDR height should be 4; got \(height)")
        }

        // Same call as TIFF — verify the format option actually switches
        // encoders (TIFF magic instead of PNG magic).
        guard let tiff = quillRenderSolidColorImage(
            red: 0, green: 1, blue: 0, alpha: 1,
            width: 8, height: 8,
            format: .tiff
        ) else {
            Issue.record("Expected non-nil TIFF for valid solid-color render")
            return
        }
        let tiffPrefix = Array(tiff.prefix(4))
        let isLittle = tiffPrefix == [0x49, 0x49, 0x2A, 0x00]
        let isBig    = tiffPrefix == [0x4D, 0x4D, 0x00, 0x2A]
        #expect(isLittle || isBig, "TIFF output must have TIFF magic; got \(tiffPrefix)")
    }

    @Test("PlatformImage scales and compresses valid image bytes through gdk-pixbuf")
    func platformImageTransformsValidImageData() {
        QuillCompatibilityDiagnostics.shared.clear()

        guard let png = quillRenderSolidColorImage(
            red: 1, green: 0, blue: 0, alpha: 1,
            width: 4, height: 2,
            format: .png
        ) else {
            Issue.record("Expected non-nil PNG for valid solid-color render")
            return
        }

        guard let image = PlatformImage(data: png) else {
            Issue.record("PlatformImage(data:) should construct from valid PNG bytes")
            return
        }
        let resized = image.aspectFittedToHeight(6)
        guard let resizedData = resized.data else {
            Issue.record("Expected resized PlatformImage to retain PNG data")
            return
        }

        guard let dimensions = pngDimensions(resizedData) else {
            Issue.record("Expected resized image to be a valid PNG")
            return
        }
        #expect(dimensions.width == 12, "Aspect-fit width should scale from 4x2 to 12x6; got \(dimensions.width)x\(dimensions.height)")
        #expect(dimensions.height == 6, "Aspect-fit height should be 6; got \(dimensions.width)x\(dimensions.height)")

        guard let jpeg = image.compressImageData() else {
            Issue.record("Expected JPEG output for valid PNG input")
            return
        }
        #expect(Array(jpeg.prefix(3)) == [0xFF, 0xD8, 0xFF], "Compressed output must have JPEG magic; got \(Array(jpeg.prefix(3)))")

        let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
            ($0.operation == "PlatformImage.aspectFittedToHeight" || $0.operation == "PlatformImage.compressImageData")
                && $0.severity == .warning
        }
        #expect(warnings.isEmpty, "Valid image transforms should not record fallback warnings; got \(warnings.map(\.message))")
    }

    #if os(Linux)
    @Test("NSImage(data:) keeps finite size and survives AppKit-style resize/compress")
    func nsImageDataResizeCompressesThroughAppKitPath() throws {
        guard let png = quillRenderSolidColorImage(
            red: 0.2, green: 0.4, blue: 0.8, alpha: 1,
            width: 4, height: 2,
            format: .png
        ) else {
            Issue.record("Expected non-nil PNG for valid solid-color render")
            return
        }

        let rendered = try #require(Image(data: png).render())
        #expect(rendered.size == CGSize(width: 4, height: 2))
        #expect(rendered.cgImage?.width == 4)
        #expect(rendered.cgImage?.height == 2)

        let targetSize = CGSize(width: 12, height: 6)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        rendered.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: rendered.size),
            operation: .copy,
            fraction: 1
        )
        resized.unlockFocus()

        let tiff = try #require(resized.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let jpeg = try #require(bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.2]
        ))
        #expect(Array(jpeg.prefix(3)) == [0xFF, 0xD8, 0xFF])
    }
    #endif

    @Test("ImageRenderer rasterizes Color content to PNG bytes via gdk-pixbuf")
    func imageRendererRendersColorContent() {
        QuillCompatibilityDiagnostics.shared.clear()

        // Color is one of the few content types we currently support without
        // a full SwiftUI render pipeline; ImageRenderer should produce a real
        // PlatformImage with PNG bytes for it.
        let renderer = ImageRenderer(content: Color(red: 0.2, green: 0.4, blue: 0.6, opacity: 1.0))

        guard let image = renderer.nsImage else {
            Issue.record("Expected nsImage for Color content; got nil")
            return
        }
        guard let pngData = image.data else {
            Issue.record("PlatformImage produced by ImageRenderer must carry data")
            return
        }
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == pngMagic)

        // uiImage path returns the same shape (just a different ObjC accessor
        // name on Apple). Both paths share the underlying renderer.
        guard let uiImage = renderer.uiImage else {
            Issue.record("Expected uiImage for Color content; got nil")
            return
        }
        #expect(uiImage.data?.prefix(8) == Data(pngMagic))

        // No warnings should be recorded for the Color path — it's the
        // supported subset.
        let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
            $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
        }
        #expect(warnings.isEmpty, "Color rendering should not record warnings; got \(warnings.map(\.message))")
    }

    @Test("ImageRenderer exposes cgImage bytes for display-independent Color content")
    func imageRendererExposesCGImageBytesForColorContent() throws {
        QuillCompatibilityDiagnostics.shared.clear()

        let renderer = ImageRenderer(content: Color(red: 0.1, green: 0.6, blue: 0.2))
        guard let pngData = renderer.cgImage?.data else {
            Issue.record("Expected ImageRenderer.cgImage to carry PNG bytes for Color content")
            return
        }

        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == pngMagic, "Expected PNG magic; got \(Array(pngData.prefix(8)))")
        #expect(pngData.count > 32, "PNG output suspiciously small: \(pngData.count) bytes")

        let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
            $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
        }
        #expect(warnings.isEmpty, "Successful Color rendering should not record warnings; got \(warnings.map(\.message))")
    }

    @Test("ImageRenderer returns nil for arbitrary content until a backend hook is installed")
    func imageRendererReturnsNilForArbitraryContentWithoutBackendHook() {
        QuillCompatibilityDiagnostics.shared.clear()

        let renderer = ImageRenderer(content: Text("hello world"))

        if let image = renderer.nsImage {
            let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
            #expect(
                image.data?.prefix(8) == Data(pngMagic),
                "Expected PNG magic in offscreen-rendered image bytes; got \(image.data?.prefix(8) as Any)"
            )

            let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
                $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
            }
            #expect(warnings.isEmpty, "Successful rendering should not record warnings; got \(warnings.map(\.message))")
        } else {
            let warnings = QuillCompatibilityDiagnostics.shared.events.filter {
                $0.operation.hasPrefix("ImageRenderer") && $0.severity == .warning
            }
            #expect(warnings.isEmpty, "Renderer hook absence should not be reported as a QuillUI fallback warning")
        }
    }

    @Test("quillTranscodeImageDataToTIFF returns nil for empty / invalid input but TIFF for valid")
    func quillTranscodeImageDataToTIFFContract() {
        // Empty input returns nil.
        #expect(quillTranscodeImageDataToTIFF(Data()) == nil)

        // Garbage bytes return nil.
        let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])
        #expect(quillTranscodeImageDataToTIFF(garbage) == nil)

        // Truncated PNG (just the magic) returns nil.
        let truncated = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(quillTranscodeImageDataToTIFF(truncated) == nil)

        // Valid PNG returns non-nil TIFF with correct magic.
        guard let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==") else {
            Issue.record("Failed to decode reference PNG fixture")
            return
        }
        guard let tiff = quillTranscodeImageDataToTIFF(png) else {
            Issue.record("Bridge returned nil for valid PNG fixture")
            return
        }
        let prefix = Array(tiff.prefix(4))
        let isLittle = prefix == [0x49, 0x49, 0x2A, 0x00]
        let isBig = prefix == [0x4D, 0x4D, 0x00, 0x2A]
        #expect(isLittle || isBig, "Bridge output must have TIFF magic; got \(prefix)")
    }

    @Test("QuillCompatibilityEvent equality covers all fields")
    func quillCompatibilityEventEquatable() {
        let a = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .info,
            message: "msg"
        )
        let b = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .info,
            message: "msg"
        )
        let differentSeverity = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .warning,
            message: "msg"
        )
        let differentMessage = QuillCompatibilityEvent(
            subsystem: "QuillUI",
            operation: "op",
            severity: .info,
            message: "different"
        )

        #expect(a == b)
        #expect(a != differentSeverity)
        #expect(a != differentMessage)
    }
}

/// RawRepresentable enum for AppStorage round-trip tests. Defined at file
/// scope so its `RawValue` (String) is stable across compilations.
private enum AppStorageMode: String {
    case classic
    case modern
}

/// Tiny mutable reference container for capturing values out of closures in
/// tests without fighting Swift Testing's capture-list rules.
private final class QuillTestBox<Value>: @unchecked Sendable {
    var value: Value?

    init(_ value: Value? = nil) {
        self.value = value
    }
}

private struct CompatibilityModel: PersistentModel, Codable, Equatable {
    var id: String = UUID().uuidString
}

private final class FakeOllamaTransport: OllamaKitTransport, @unchecked Sendable {
    struct CapturedRequest: Sendable {
        var path: String
        var authorization: String?
    }

    private let routes: [String: (status: Int, body: String)]
    private let lock = NSLock()
    private var capturedRequests: [CapturedRequest] = []
    private var capturedChatBody: String?

    init(routes: [String: (Int, String)]) {
        self.routes = routes.mapValues { (status: $0.0, body: $0.1) }
    }

    var requests: [CapturedRequest] {
        lock.withLock { capturedRequests }
    }

    var chatBody: String? {
        lock.withLock { capturedChatBody }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? "/"
        lock.withLock {
            capturedRequests.append(
                CapturedRequest(
                    path: path,
                    authorization: request.value(forHTTPHeaderField: "Authorization")
                )
            )
            if path == "/api/chat", let httpBody = request.httpBody {
                capturedChatBody = String(data: httpBody, encoding: .utf8)
            }
        }

        let route = routes[path] ?? (404, #"{"error":"missing"}"#)
        let url = request.url ?? URL(string: "http://localhost")!
        let response = HTTPURLResponse(
            url: url,
            statusCode: route.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(route.body.utf8), response)
    }
}

private let markdownContractTheme = MarkdownUI.Theme()
    .text {
        FontSize(14)
    }
    .code {
        FontFamilyVariant(.monospaced)
        FontSize(.em(0.85))
        BackgroundColor(Color("bgCustom"))
    }
    .strong {
        FontWeight(.semibold)
    }
    .link {
        ForegroundColor(.blue)
    }
    .heading1 { configuration in
        VStack(alignment: .leading, spacing: 0) {
            configuration.label
                .relativePadding(.bottom, length: .em(0.3))
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(2))
                }
            Divider().overlay(Color.gray)
        }
    }
    .paragraph { configuration in
        configuration.label
            .fixedSize(horizontal: false, vertical: true)
            .relativeLineSpacing(.em(0.25))
            .markdownMargin(top: 0, bottom: 16)
    }
    .blockquote { configuration in
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray)
                .relativeFrame(width: .em(0.2))
            configuration.label
                .markdownTextStyle { ForegroundColor(.secondary) }
                .relativePadding(.horizontal, length: .em(1))
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    .codeBlock { configuration in
        VStack(spacing: 0) {
            Text(configuration.language ?? "code")
                .font(.system(size: 13, design: .monospaced))
                .fontWeight(.semibold)
            configuration.label
                .relativeLineSpacing(.em(0.225))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
        }
        .markdownMargin(top: .zero, bottom: .em(0.8))
    }
    .listItem { configuration in
        configuration.label.padding(.bottom, 10)
    }
    .taskListMarker { configuration in
        Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Color.gray, Color("bgCustom"))
            .imageScale(.small)
            .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
    }
    .table { configuration in
        configuration.label
            .markdownTableBorderStyle(.init(color: .gray))
            .markdownTableBackgroundStyle(.alternatingRows(.white, Color("bgCustom")))
            .markdownMargin(top: 0, bottom: 16)
    }
    .tableCell { configuration in
        configuration.label
            .markdownTextStyle {
                if configuration.row == 0 {
                    FontWeight(.semibold)
                }
                BackgroundColor(nil)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 13)
            .relativeLineSpacing(.em(0.25))
    }
    .thematicBreak {
        Divider()
            .relativeFrame(height: .em(0.25))
            .overlay(Color.gray)
            .markdownMargin(top: 24, bottom: 24)
    }

private struct ContractSplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let highlighter: SyntaxHighlighter<ContractTextOutputFormat>

    init(theme: Splash.Theme) {
        self.highlighter = SyntaxHighlighter(format: ContractTextOutputFormat(theme: theme))
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        guard language != nil else { return Text(content) }
        return highlighter.highlight(content)
    }
}

private struct ContractTextOutputFormat: OutputFormat {
    var theme: Splash.Theme

    func makeBuilder() -> Builder {
        Builder(theme: theme)
    }

    struct Builder: OutputBuilder {
        var theme: Splash.Theme
        var accumulatedText: [Text] = []

        mutating func addToken(_ token: String, ofType type: TokenType) {
            let color = theme.tokenColors[type] ?? theme.plainTextColor
            accumulatedText.append(Text(token).foregroundColor(.init(color)))
        }

        mutating func addPlainText(_ text: String) {
            accumulatedText.append(Text(text).foregroundColor(.init(theme.plainTextColor)))
        }

        mutating func addWhitespace(_ whitespace: String) {
            accumulatedText.append(Text(whitespace))
        }

        func build() -> Text {
            accumulatedText.reduce(Text(""), +)
        }
    }
}

private enum CombineTestError: Error {
    case boom
}

private final class DemandRecordingSubscriber<Input, Failure: Error>: Subscriber {
    var subscription: Subscription?
    var values: [Input] = []
    var completions = 0

    func receive(subscription: Subscription) {
        self.subscription = subscription
    }

    func receive(_ input: Input) -> Subscribers.Demand {
        values.append(input)
        return .none
    }

    func receive(completion: Subscribers.Completion<Failure>) {
        completions += 1
    }
}
