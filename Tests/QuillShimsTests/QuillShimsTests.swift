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

final class LinuxCompatibilityProductsTests: XCTestCase {
    func testCompatibilityShimsLink() {
        // Touch a public symbol from each shim so the linker
        // can't dead-strip the import. The assertions don't
        // matter — the value of the test is that this file
        // compiles + links at all.
        XCTAssertEqual(CGEventFlags(rawValue: 0).rawValue, 0)
        XCTAssertEqual(SFSpeechRecognizerAuthorizationStatus.denied, .denied)
        XCTAssertEqual(AVAudioPCMBuffer().frameLength, 0)
    }
}
#endif
