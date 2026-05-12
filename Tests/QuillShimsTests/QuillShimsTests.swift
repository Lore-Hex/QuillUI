import XCTest
#if !os(macOS) && !os(iOS)
@testable import QuillShims
#endif

final class QuillShimsTests: XCTestCase {
    
    @MainActor
    func testUIImageShim() async throws {
        #if !os(macOS) && !os(iOS)
        let image = UIImage()
        XCTAssertNotNil(image)
        XCTAssertEqual(image.size, CGSize(width: 0, height: 0))
        #endif
    }
    
    @MainActor
    func testUIViewShim() {
        #if !os(macOS) && !os(iOS)
        let view = UIView()
        XCTAssertNotNil(view)
        XCTAssertEqual(view.subviews.count, 0)
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(view.alpha, 1.0)
        
        let subview = UIView()
        view.addSubview(subview)
        XCTAssertNotNil(subview)
        #endif
    }
    
    @MainActor
    func testTreeControllerShim() {
        #if !os(macOS) && !os(iOS)
        let delegate = MockTreeDelegate()
        let controller = TreeController(delegate: delegate)
        
        XCTAssertNotNil(controller.rootNode)
        XCTAssertTrue(controller.rootNode.isRoot)
        #endif
    }
}

#if !os(macOS) && !os(iOS)
@MainActor
class MockTreeDelegate: TreeControllerDelegate {
    func treeController(treeController: TreeController, childNodesFor node: Node) -> [Node]? {
        return []
    }
}
#endif

// Linux-only smoke for the compatibility-product shims declared
// in Package.swift. Each `import` here will fail at link time if
// the matching QuillUI library product is missing or its target
// isn't actually compiling on Linux — the tests don't need to
// assert anything beyond reachability.
#if os(Linux)
import SwiftUI
import Combine
import AsyncAlgorithms
import Carbon
import CoreGraphics
import Security
import AVFoundation
import Speech
import ApplicationServices
import ServiceManagement
import Alamofire
import MarkdownUI
import Splash
import ActivityIndicatorView
import WrappingHStack
import Vortex
import KeyboardShortcuts
import PhotosUI
import Magnet
import OllamaKit
import Sparkle
import IOKit

final class LinuxCompatibilityProductsTests: XCTestCase {
    // The point of these tests is link-time: each `import` plus a
    // public-symbol reference proves the matching QuillUI library
    // product resolves on Linux. The assertion values are
    // intentionally trivial — what fails is the build, not the
    // expectation.

    func testCoreGraphicsShim() {
        XCTAssertEqual(CGEventFlags(rawValue: 0).rawValue, 0)
    }

    func testAVFoundationShim() {
        XCTAssertEqual(AVAudioPCMBuffer().frameLength, 0)
    }

    func testSpeechShim() {
        XCTAssertEqual(SFSpeechRecognizerAuthorizationStatus.denied, .denied)
    }

    func testCarbonShim() {
        // `Sources/Carbon/Carbon.swift` only exposes a placeholder
        // enum so the module is non-empty.
        _ = CarbonCompatibility.self
    }

    func testApplicationServicesShim() {
        XCTAssertFalse(AXIsProcessTrustedWithOptions(nil))
    }

    func testServiceManagementShim() {
        _ = SMAppService.self
    }

    func testAlamofireShim() {
        XCTAssertEqual(HTTPMethod.get, .get)
    }

    func testMagnetShim() {
        // `KeyCombo` is the workhorse type; its failable init returns
        // a value when both pieces are present.
        let combo = KeyCombo(key: .space, cocoaModifiers: _Modifiers(rawValue: 0))
        XCTAssertNotNil(combo)
    }

    func testSwiftUISpacingShims() {
        // Linux SwiftUI shim bridges baseline alignments to top/bottom.
        XCTAssertEqual(VerticalAlignment.firstTextBaseline, .top)
        XCTAssertEqual(VerticalAlignment.lastTextBaseline, .bottom)
    }

    func testCombineShim() {
        // The Combine shim re-exports OpenCombine. An empty
        // `AnyPublisher<Int, Never>()` proves both the import and
        // the local extension `AnyPublisher.init()` resolved.
        let publisher: AnyPublisher<Int, Never> = AnyPublisher()
        _ = publisher
    }

    func testIOKitShim() {
        // `kIOMainPortDefault` is a header-defined constant in
        // `Sources/IOKit/IOKit.h`; reaching it from Swift proves
        // the module map + header search path are wired in.
        XCTAssertEqual(kIOMainPortDefault, 0)
    }
}
#endif
