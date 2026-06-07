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
import Security
import AVFoundation
import Speech
import ApplicationServices
import ServiceManagement
import Network
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

    func testQuillShimsReexportsQuillKitAliases() {
        XCTAssertTrue(Accessibility.shared === QuillAccessibilityService.shared)
        let hotkey = HotkeyCombination(keyBase: [.command], key: 0x09) {}
        XCTAssertEqual(hotkey.keyBase, [KeyBase.command])
        XCTAssertEqual(hotkey.key, 0x09)
        XCTAssertEqual(UInt16.kVK_ANSI_V, 0x09)
        XCTAssertEqual(CGKeyCode.kVK_ANSI_V, 0x09)
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

    func testNetworkShimParsesAddressLiteralsAndHosts() {
        let unsatisfiedReasons: [(NWPath.UnsatisfiedReason, String)] = [
            (.notAvailable, "notAvailable"),
            (.cellularDenied, "cellularDenied"),
            (.wifiDenied, "wifiDenied"),
            (.localNetworkDenied, "localNetworkDenied"),
        ]
        for (reason, description) in unsatisfiedReasons {
            XCTAssertEqual(String(describing: reason), description)
        }

        let ipv4Cases: [(String, [UInt8], String)] = [
            ("192.168.1.10", [192, 168, 1, 10], "192.168.1.10"),
            ("0.0.0.0", [0, 0, 0, 0], "0.0.0.0"),
            ("255.255.255.255", [255, 255, 255, 255], "255.255.255.255"),
            ("01.02.03.04", [1, 2, 3, 4], "1.2.3.4"),
            ("1", [0, 0, 0, 1], "0.0.0.1"),
            ("1.2", [1, 0, 0, 2], "1.0.0.2"),
            ("1.2.3", [1, 2, 0, 3], "1.2.0.3"),
            ("0x1.2.3.4", [1, 2, 3, 4], "1.2.3.4"),
            ("0377.0377.0377.0377", [255, 255, 255, 255], "255.255.255.255"),
            ("0xffffffff", [255, 255, 255, 255], "255.255.255.255"),
            ("4294967296", [0, 0, 0, 0], "0.0.0.0"),
        ]
        for (input, rawValue, description) in ipv4Cases {
            let address = IPv4Address(input)
            XCTAssertEqual(address?.rawValue, Data(rawValue), input)
            XCTAssertEqual(address?.description, description, input)
        }

        for input in ["192.168.1.10.extra", "1..2.3.4", "1.2.3.256", "1.2.3.4 ", " 1.2.3.4", "+1.2.3.4"] {
            XCTAssertNil(IPv4Address(input), input)
        }

        let ipv6Loopback = Data(Array(repeating: UInt8(0), count: 15) + [1])
        XCTAssertEqual(IPv6Address("::1")?.rawValue, ipv6Loopback)
        XCTAssertEqual(IPv6Address("::1")?.description, "::1")
        XCTAssertEqual(IPv6Address("::")?.description, "::")
        XCTAssertEqual(IPv6Address("2001:db8::1")?.description, "2001:db8::1")
        XCTAssertNil(IPv6Address("example.com"))
        XCTAssertNil(IPv6Address("::1 "))
        XCTAssertNil(IPv6Address(" ::1"))
        XCTAssertNil(IPv6Address("1.2.3.4"))

        XCTAssertNil(IPv4Address(Data([1, 2, 3])))
        XCTAssertEqual(IPv4Address(Data([1, 2, 3, 4]))?.description, "1.2.3.4")
        XCTAssertNil(IPv4Address(Data([1, 2, 3, 4, 5])))
        XCTAssertNil(IPv6Address(Data(Array(repeating: UInt8(0), count: 15))))
        XCTAssertEqual(IPv6Address(ipv6Loopback)?.description, "::1")
        XCTAssertNil(IPv6Address(Data(Array(repeating: UInt8(0), count: 17))))

        let ipv4Constants: [(IPv4Address, [UInt8], String, Bool, Bool, Bool)] = [
            (.any, [0, 0, 0, 0], "0.0.0.0", false, false, false),
            (.broadcast, [255, 255, 255, 255], "255.255.255.255", false, false, false),
            (.loopback, [127, 0, 0, 1], "127.0.0.1", true, false, false),
            (.allHostsGroup, [224, 0, 0, 1], "224.0.0.1", false, false, true),
            (.allRoutersGroup, [224, 0, 0, 2], "224.0.0.2", false, false, true),
            (.allReportsGroup, [224, 0, 0, 22], "224.0.0.22", false, false, true),
            (.mdnsGroup, [224, 0, 0, 251], "224.0.0.251", false, false, true),
        ]
        for (address, rawValue, description, isLoopback, isLinkLocal, isMulticast) in ipv4Constants {
            XCTAssertEqual(address.rawValue, Data(rawValue), description)
            XCTAssertEqual(String(describing: address), description)
            XCTAssertEqual(address.debugDescription, description)
            XCTAssertEqual(address.isLoopback, isLoopback, description)
            XCTAssertEqual(address.isLinkLocal, isLinkLocal, description)
            XCTAssertEqual(address.isMulticast, isMulticast, description)
            XCTAssertNil(address.interface, description)
        }
        XCTAssertFalse(IPv4Address("127.0.0.2")!.isLoopback)
        XCTAssertTrue(IPv4Address("169.254.1.2")!.isLinkLocal)
        XCTAssertTrue(IPv4Address("239.255.255.255")!.isMulticast)
        XCTAssertFalse(IPv4Address("240.0.0.1")!.isMulticast)

        let ipv6Constants: [(IPv6Address, [UInt8], String, Bool, Bool, Bool, IPv6Address.Scope?)] = [
            (.any, Array(repeating: UInt8(0), count: 16), "::", true, false, false, nil),
            (.broadcast, Array(repeating: UInt8(0), count: 16), "::", true, false, false, nil),
            (.loopback, Array(repeating: UInt8(0), count: 15) + [1], "::1", false, true, false, nil),
            (.nodeLocalNodes, [0xff, 0x01] + Array(repeating: UInt8(0), count: 13) + [1], "ff01::1", false, false, true, .nodeLocal),
            (.linkLocalNodes, [0xff, 0x02] + Array(repeating: UInt8(0), count: 13) + [1], "ff02::1", false, false, true, .linkLocal),
            (.linkLocalRouters, [0xff, 0x02] + Array(repeating: UInt8(0), count: 13) + [2], "ff02::2", false, false, true, .linkLocal),
        ]
        for (address, rawValue, description, isAny, isLoopback, isMulticast, scope) in ipv6Constants {
            XCTAssertEqual(address.rawValue, Data(rawValue), description)
            XCTAssertEqual(String(describing: address), description)
            XCTAssertEqual(address.debugDescription, description)
            XCTAssertEqual(address.isAny, isAny, description)
            XCTAssertEqual(address.isLoopback, isLoopback, description)
            XCTAssertEqual(address.isMulticast, isMulticast, description)
            XCTAssertEqual(address.multicastScope, scope, description)
            XCTAssertNil(address.interface, description)
        }
        XCTAssertTrue(IPv6Address("fe80::1")!.isLinkLocal)
        XCTAssertTrue(IPv6Address("febf::1")!.isLinkLocal)
        XCTAssertFalse(IPv6Address("fec0::1")!.isLinkLocal)
        XCTAssertTrue(IPv6Address("::ffff:192.0.2.1")!.isIPv4Mapped)
        XCTAssertFalse(IPv6Address("::ffff:192.0.2.1")!.isIPv4Compatabile)
        XCTAssertEqual(IPv6Address("::ffff:192.0.2.1")!.asIPv4?.description, "192.0.2.1")
        XCTAssertTrue(IPv6Address("::192.0.2.1")!.isIPv4Compatabile)
        XCTAssertFalse(IPv6Address("::192.0.2.1")!.isIPv4Mapped)
        XCTAssertEqual(IPv6Address("::192.0.2.1")!.asIPv4?.description, "192.0.2.1")
        XCTAssertFalse(IPv6Address("::")!.isIPv4Compatabile)
        XCTAssertFalse(IPv6Address("::1")!.isIPv4Compatabile)
        XCTAssertTrue(IPv6Address("2002:c000:0201::")!.is6to4)
        XCTAssertTrue(IPv6Address("fc00::1")!.isUniqueLocal)
        XCTAssertTrue(IPv6Address("fd00::1")!.isUniqueLocal)
        XCTAssertEqual(IPv6Address("ff05::1")!.multicastScope, .siteLocal)
        XCTAssertEqual(IPv6Address("ff08::1")!.multicastScope, .organizationLocal)
        XCTAssertEqual(IPv6Address("ff0e::1")!.multicastScope, .global)

        if case .ipv4(let address) = NWEndpoint.Host("192.168.1.10") {
            XCTAssertEqual(address.rawValue, Data([192, 168, 1, 10]))
            XCTAssertEqual(NWEndpoint.Host("192.168.1.10").description, "192.168.1.10")
        } else {
            XCTFail("Expected IPv4 endpoint host")
        }

        if case .ipv6(let address) = NWEndpoint.Host("::1") {
            XCTAssertEqual(address.rawValue, Data(Array(repeating: UInt8(0), count: 15) + [1]))
            XCTAssertEqual(NWEndpoint.Host("::1").description, "::1")
        } else {
            XCTFail("Expected IPv6 endpoint host")
        }

        if case .name(let name, nil) = NWEndpoint.Host("example.com") {
            XCTAssertEqual(name, "example.com")
            XCTAssertEqual(NWEndpoint.Host("example.com").description, "example.com")
        } else {
            XCTFail("Expected DNS-name endpoint host")
        }

        let directHosts: [(NWEndpoint.Host, String)] = [
            (.name("example.com", nil), "example.com"),
            (.name("", nil), ""),
            (.ipv4(IPv4Address("192.168.1.10")!), "192.168.1.10"),
            (.ipv6(IPv6Address("::1")!), "::1"),
        ]
        for (host, expectedDescription) in directHosts {
            XCTAssertEqual(host.description, expectedDescription)
            XCTAssertEqual(host.debugDescription, expectedDescription)
            XCTAssertEqual(String(reflecting: host), expectedDescription)
        }

        let literalPort: NWEndpoint.Port = 443
        XCTAssertEqual(literalPort.rawValue, 443)
        XCTAssertEqual(String(describing: literalPort), "443")
        XCTAssertEqual(literalPort.debugDescription, "443")
        XCTAssertEqual(NWEndpoint.Port("51820")?.rawValue, 51820)
        XCTAssertEqual(NWEndpoint.Port(" 80")?.rawValue, 80)
        XCTAssertEqual(NWEndpoint.Port("\t80")?.rawValue, 80)
        XCTAssertEqual(NWEndpoint.Port("+1")?.rawValue, 1)
        XCTAssertEqual(NWEndpoint.Port("-0")?.rawValue, 0)
        XCTAssertEqual(NWEndpoint.Port("00080")?.rawValue, 80)
        XCTAssertEqual(String(describing: NWEndpoint.Port(rawValue: 65535)!), "65535")
        XCTAssertEqual(NWEndpoint.Port(rawValue: 65535)?.debugDescription, "65535")
        let knownPorts: [(NWEndpoint.Port, UInt16)] = [
            (.any, 0),
            (.ssh, 22),
            (.smtp, 25),
            (.http, 80),
            (.pop, 110),
            (.imap, 143),
            (.https, 443),
            (.imaps, 993),
            (.socks, 1080),
        ]
        for (port, rawValue) in knownPorts {
            XCTAssertEqual(port.rawValue, rawValue)
            XCTAssertEqual(String(describing: port), String(rawValue))
            XCTAssertEqual(port.debugDescription, String(rawValue))
        }
        XCTAssertNil(NWEndpoint.Port("-1"))
        XCTAssertNil(NWEndpoint.Port("65536"))
        XCTAssertNil(NWEndpoint.Port("80 "))
        XCTAssertNil(NWEndpoint.Port("80\n"))
        XCTAssertNil(NWEndpoint.Port("0x50"))
        XCTAssertNil(NWEndpoint.Port("1.0"))

        XCTAssertEqual(NWPath.Status.satisfied.description, "satisfied")
        XCTAssertEqual(NWPath.Status.unsatisfied.description, "unsatisfied")
        XCTAssertEqual(NWPath.Status.requiresConnection.description, "requiresConnection")
        XCTAssertEqual(NWInterface.InterfaceType.other.description, "other")
        XCTAssertEqual(NWInterface.InterfaceType.wifi.description, "wifi")
        XCTAssertEqual(NWInterface.InterfaceType.cellular.description, "cellular")
        XCTAssertEqual(NWInterface.InterfaceType.wiredEthernet.description, "wiredEthernet")
        XCTAssertEqual(NWInterface.InterfaceType.loopback.description, "loopback")

        let endpoints: [(NWEndpoint, String)] = [
            (.hostPort(host: NWEndpoint.Host("example.com"), port: literalPort), "example.com:443"),
            (.hostPort(host: NWEndpoint.Host("192.168.1.10"), port: literalPort), "192.168.1.10:443"),
            (.hostPort(host: NWEndpoint.Host("::1"), port: literalPort), "::1.443"),
            (.unix(path: "/tmp/socket"), "/tmp/socket"),
            (.service(name: "svc", type: "_http._tcp", domain: "local", interface: nil), "svc._http._tcp.local."),
        ]
        for (endpoint, expectedDescription) in endpoints {
            XCTAssertEqual(endpoint.description, expectedDescription)
            XCTAssertEqual(endpoint.debugDescription, expectedDescription)
            XCTAssertEqual(String(reflecting: endpoint), expectedDescription)
        }
        XCTAssertEqual(NWEndpoint.unix(path: "").description, "")
        XCTAssertEqual(
            NWEndpoint.service(name: "svc", type: "_http._tcp.", domain: "local.", interface: nil).description,
            "svc._http._tcp.local."
        )
        XCTAssertEqual(
            NWEndpoint.service(name: "svc", type: "http", domain: "local", interface: nil).description,
            "svc.httplocal"
        )
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

#if !os(macOS) && !os(iOS)
// Exercises the SwiftUI `@Entry` macro (QuillDataMacros.QuillEntryMacro)
// surfaced through the SwiftUI shim. The macro must synthesize a computed
// get/set on each property, backed by a private `EnvironmentKey` peer that
// carries the declared default value. (SwiftUI is already imported above.)
extension EnvironmentValues {
    @Entry var quillEntryTestFlag: Bool = true
    @Entry var quillEntryTestCount: Int = 7
    @Entry var quillEntryTestLabel: String = "hello"
}

final class QuillEntryMacroTests: XCTestCase {
    func testEntryMacroProvidesDeclaredDefaults() {
        let env = EnvironmentValues()
        XCTAssertEqual(env.quillEntryTestFlag, true)
        XCTAssertEqual(env.quillEntryTestCount, 7)
        XCTAssertEqual(env.quillEntryTestLabel, "hello")
    }

    func testEntryMacroSetGetRoundtrip() {
        var env = EnvironmentValues()
        env.quillEntryTestFlag = false
        env.quillEntryTestCount = 42
        env.quillEntryTestLabel = "world"
        XCTAssertEqual(env.quillEntryTestFlag, false)
        XCTAssertEqual(env.quillEntryTestCount, 42)
        XCTAssertEqual(env.quillEntryTestLabel, "world")
    }
}
#endif

#if !os(macOS) && !os(iOS)
// Shared SwiftUI View-modifier / type surface used by vendored real source:
// no-op modifiers (tint/accessibilityHidden), Color.resolve, Font.weight.
final class QuillSwiftUIViewModifierShimTests: XCTestCase {
    func testColorResolve() {
        let color: SwiftUI.Color = .red
        let resolved = color.resolve(in: .init())
        XCTAssertEqual(resolved.red, 1.0, accuracy: 0.01)
    }

    func testFontWeightReturnsSelf() {
        let font: SwiftUI.Font = .body
        XCTAssertEqual(font.weight(.bold), font)
    }

    @MainActor func testModifiersCompileAndReturnView() {
        // No-op modifiers chain and return some View (compile-level check).
        let color: SwiftUI.Color = .red
        let _ = color
            .tint(.blue)
            .accessibilityHidden(true)
            .listRowBackground(SwiftUI.Color?.none)
            .previewLayout(.sizeThatFits)
    }
}

// Shared SwiftUI compat additions used by vendored real source (DesignSystem):
// `Color: Sendable` and the SwiftUI-style nesting `Font.Weight`/`.Design`/`.TextStyle`.
final class QuillSwiftUIColorFontShimTests: XCTestCase {
    func testColorIsSendable() {
        // Compiles only if Color conforms to Sendable.
        let c: any Sendable = SwiftUI.Color.red
        XCTAssertTrue(c is SwiftUI.Color)
    }

    func testFontTypeNesting() {
        XCTAssertEqual(SwiftUI.Font.Weight.semibold, SwiftUI.FontWeight.semibold)
        XCTAssertEqual(SwiftUI.Font.Design.rounded, SwiftUI.FontDesign.rounded)
        let style: SwiftUI.Font.TextStyle = .body
        XCTAssertEqual(style, SwiftUI.Font.body)
    }
}
#endif

#if !os(macOS) && !os(iOS)
// The `#Preview` macro expands to nothing on Linux; declaring one here proves
// the macro resolves and its body type-checks, so vendored real source that
// declares SwiftUI previews compiles.
#Preview {
    SwiftUI.Text("preview")
}
#endif
