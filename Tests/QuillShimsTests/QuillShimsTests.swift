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
@testable import Alamofire
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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
import KeychainSwift

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

    func testAlamofireDecodesMockResponse() {
        let capture = AlamofireRequestCapture()
        let payload = Data(#"{"message":"ok"}"#.utf8)
        let session = Session { request, completion in
            capture.record(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            completion(.success((payload, response)))
        }

        let done = expectation(description: "Alamofire mock decode")
        var decoded: AlamofireShimPayload?
        session.request("https://example.test/messages", method: .post)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: AlamofireShimPayload.self, queue: .global()) { response in
                decoded = try? response.result.get()
                done.fulfill()
            }
        wait(for: [done], timeout: 2.0)

        XCTAssertEqual(capture.request?.url?.absoluteString, "https://example.test/messages")
        XCTAssertEqual(capture.request?.httpMethod, "POST")
        XCTAssertEqual(decoded, AlamofireShimPayload(message: "ok"))
    }

    func testAlamofireRejectsUnacceptableStatusCode() {
        let session = Session { request, completion in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            completion(.success((Data(#"{"message":"unavailable"}"#.utf8), response)))
        }

        let done = expectation(description: "Alamofire status validation")
        var rejectedStatusCode: Int?
        session.request("https://example.test/messages", method: .get)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: AlamofireShimPayload.self, queue: .global()) { response in
                if case .failure(let error) = response.result,
                   let afError = error as? AFError,
                   case .responseValidationFailed(reason: .unacceptableStatusCode(let code)) = afError {
                    rejectedStatusCode = code
                }
                done.fulfill()
            }
        wait(for: [done], timeout: 2.0)

        XCTAssertEqual(rejectedStatusCode, 503)
    }

    func testAlamofireRejectsInvalidURL() {
        let session = Session { _, completion in
            XCTFail("Invalid URLs should fail before transport is invoked")
            completion(.failure(AFError.invalidURL(url: "not a url")))
        }

        let done = expectation(description: "Alamofire invalid URL")
        var sawInvalidURL = false
        session.request("not a url", method: .get)
            .responseDecodable(of: AlamofireShimPayload.self, queue: .global()) { response in
                if case .failure(let error) = response.result,
                   let afError = error as? AFError,
                   case .invalidURL = afError {
                    sawInvalidURL = true
                }
                done.fulfill()
            }
        wait(for: [done], timeout: 2.0)

        XCTAssertTrue(sawInvalidURL)
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

    func testKeychainSwiftShim() {
        let keychain = KeychainSwift(keyPrefix: "shims-\(UUID().uuidString)-")
        XCTAssertTrue(keychain.set("token", forKey: "access-token"))
        XCTAssertEqual(keychain.get("access-token"), "token")
        XCTAssertTrue(keychain.clear())
    }
}

private struct AlamofireShimPayload: Decodable, Equatable {
    let message: String
}

private final class AlamofireRequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    func record(_ request: URLRequest) {
        lock.lock()
        storedRequest = request
        lock.unlock()
    }
}
#endif
