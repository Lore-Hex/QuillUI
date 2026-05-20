import XCTest
import Network

final class NetworkParametersParityTests: XCTestCase {
    func testProtocolOptionConstructorsMatchAppleTextSurface() {
        assertOption(NWProtocolTCP.Options(), expectedText: "Network.NWProtocolTCP.Options")
        assertOption(NWProtocolUDP.Options(), expectedText: "Network.NWProtocolUDP.Options")
        assertOption(NWProtocolTLS.Options(), expectedText: "Network.NWProtocolTLS.Options")
    }

    func testProtocolOptionConstructorsReturnDistinctReferenceInstances() {
        XCTAssertTrue(NWProtocolTCP.Options() !== NWProtocolTCP.Options())
        XCTAssertTrue(NWProtocolUDP.Options() !== NWProtocolUDP.Options())
        XCTAssertTrue(NWProtocolTLS.Options() !== NWProtocolTLS.Options())
    }

    func testTCPOptionDefaultsAndSettersMatchApple() {
        let options = NWProtocolTCP.Options()

        XCTAssertFalse(options.noDelay)
        XCTAssertFalse(options.noPush)
        XCTAssertFalse(options.noOptions)
        XCTAssertFalse(options.enableKeepalive)
        XCTAssertEqual(options.keepaliveCount, 0)
        XCTAssertEqual(options.keepaliveIdle, 0)
        XCTAssertEqual(options.keepaliveInterval, 0)
        XCTAssertEqual(options.maximumSegmentSize, 0)
        XCTAssertEqual(options.connectionTimeout, 0)
        XCTAssertEqual(options.persistTimeout, 0)
        XCTAssertEqual(options.connectionDropTime, 0)
        XCTAssertFalse(options.retransmitFinDrop)
        XCTAssertFalse(options.disableAckStretching)
        XCTAssertFalse(options.enableFastOpen)
        XCTAssertFalse(options.disableECN)

        options.noDelay = true
        options.noPush = true
        options.noOptions = true
        options.enableKeepalive = true
        options.keepaliveCount = 31
        options.keepaliveIdle = 23
        options.keepaliveInterval = 29
        options.maximumSegmentSize = 1440
        options.connectionTimeout = 17
        options.persistTimeout = 19
        options.connectionDropTime = 37
        options.retransmitFinDrop = true
        options.disableAckStretching = true
        options.enableFastOpen = true
        options.disableECN = true

        XCTAssertTrue(options.noDelay)
        XCTAssertTrue(options.noPush)
        XCTAssertTrue(options.noOptions)
        XCTAssertTrue(options.enableKeepalive)
        XCTAssertEqual(options.keepaliveCount, 31)
        XCTAssertEqual(options.keepaliveIdle, 23)
        XCTAssertEqual(options.keepaliveInterval, 29)
        XCTAssertEqual(options.maximumSegmentSize, 1440)
        XCTAssertEqual(options.connectionTimeout, 17)
        XCTAssertEqual(options.persistTimeout, 19)
        XCTAssertEqual(options.connectionDropTime, 37)
        XCTAssertTrue(options.retransmitFinDrop)
        XCTAssertTrue(options.disableAckStretching)
        XCTAssertTrue(options.enableFastOpen)
        XCTAssertTrue(options.disableECN)
        assertOption(options, expectedText: "Network.NWProtocolTCP.Options")
    }

    func testUDPOptionDefaultsAndSettersMatchApple() {
        let options = NWProtocolUDP.Options()

        XCTAssertFalse(options.preferNoChecksum)

        options.preferNoChecksum = true

        XCTAssertTrue(options.preferNoChecksum)
        assertOption(options, expectedText: "Network.NWProtocolUDP.Options")
    }

    func testParameterFactoriesMatchAppleTextSurfaceAndInstanceFreshness() {
        assertParameters(NWParameters.tcp, expectedText: "tcp, attribution: developer")
        assertParameters(NWParameters.udp, expectedText: "udp, attribution: developer")
        assertParameters(NWParameters.tls, expectedText: "tcp, tls, attribution: developer")
        assertParameters(NWParameters.dtls, expectedText: "udp, tls, attribution: developer")

        XCTAssertTrue(NWParameters.tcp !== NWParameters.tcp)
        XCTAssertTrue(NWParameters.udp !== NWParameters.udp)
        XCTAssertTrue(NWParameters.tls !== NWParameters.tls)
        XCTAssertTrue(NWParameters.dtls !== NWParameters.dtls)
    }

    func testParameterInitializersMatchAppleTextSurface() {
        assertParameters(
            NWParameters(tls: nil, tcp: NWProtocolTCP.Options()),
            expectedText: "tcp, attribution: developer"
        )
        assertParameters(
            NWParameters(tls: NWProtocolTLS.Options(), tcp: NWProtocolTCP.Options()),
            expectedText: "tcp, tls, attribution: developer"
        )
        assertParameters(
            NWParameters(dtls: nil, udp: NWProtocolUDP.Options()),
            expectedText: "udp, attribution: developer"
        )
        assertParameters(
            NWParameters(dtls: NWProtocolTLS.Options(), udp: NWProtocolUDP.Options()),
            expectedText: "udp, tls, attribution: developer"
        )
    }

    func testParameterAndProtocolOptionSurfaceIsSendableLikeApple() {
        assertSendable(NWProtocolTCP.Options())
        assertSendable(NWProtocolUDP.Options())
        assertSendable(NWProtocolTLS.Options())
        assertSendable(NWParameters.tcp)
        assertSendable(NWParameters.udp)
        assertSendable(NWParameters.tls)
        assertSendable(NWParameters.dtls)
    }

    func testParameterPolicyEnumTextMatchesApple() {
        assertEnumText(NWParameters.Attribution.developer, expectedText: "developer")
        assertEnumText(NWParameters.Attribution.user, expectedText: "user")
        assertEnumText(NWParameters.ExpiredDNSBehavior.systemDefault, expectedText: "systemDefault")
        assertEnumText(NWParameters.ExpiredDNSBehavior.allow, expectedText: "allow")
        assertEnumText(NWParameters.ExpiredDNSBehavior.prohibit, expectedText: "prohibit")
        assertEnumText(NWParameters.MultipathServiceType.disabled, expectedText: "disabled")
        assertEnumText(NWParameters.MultipathServiceType.handover, expectedText: "handover")
        assertEnumText(NWParameters.MultipathServiceType.interactive, expectedText: "interactive")
        assertEnumText(NWParameters.MultipathServiceType.aggregate, expectedText: "aggregate")
        assertEnumText(NWParameters.ServiceClass.bestEffort, expectedText: "bestEffort")
        assertEnumText(NWParameters.ServiceClass.background, expectedText: "background")
        assertEnumText(NWParameters.ServiceClass.interactiveVideo, expectedText: "interactiveVideo")
        assertEnumText(NWParameters.ServiceClass.interactiveVoice, expectedText: "interactiveVoice")
        assertEnumText(NWParameters.ServiceClass.responsiveData, expectedText: "responsiveData")
        assertEnumText(NWParameters.ServiceClass.signaling, expectedText: "signaling")
    }

    func testParameterPolicyDefaultsMatchApple() {
        let parameters = NWParameters.tcp

        XCTAssertEqual(parameters.requiredInterfaceType, .other)
        XCTAssertNil(parameters.prohibitedInterfaceTypes)
        XCTAssertNil(parameters.requiredLocalEndpoint)
        XCTAssertFalse(parameters.allowLocalEndpointReuse)
        XCTAssertFalse(parameters.includePeerToPeer)
        XCTAssertEqual(parameters.serviceClass, .bestEffort)
        XCTAssertEqual(parameters.multipathServiceType, .disabled)
        XCTAssertEqual(parameters.expiredDNSBehavior, .systemDefault)
        XCTAssertFalse(parameters.allowFastOpen)
        XCTAssertFalse(parameters.prohibitExpensivePaths)
        XCTAssertFalse(parameters.prohibitConstrainedPaths)
        XCTAssertFalse(parameters.requiresDNSSECValidation)
        XCTAssertFalse(parameters.preferNoProxies)
        XCTAssertEqual(parameters.attribution, .developer)
    }

    func testParameterPolicySettersAndDebugTextMatchApple() {
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(IPv4Address("127.0.0.1")!),
            port: NWEndpoint.Port(rawValue: 8080)!
        )
        let parameters = NWParameters.tcp

        parameters.requiredInterfaceType = .wifi
        parameters.prohibitedInterfaceTypes = [.cellular, .loopback]
        parameters.requiredLocalEndpoint = endpoint
        parameters.allowLocalEndpointReuse = true
        parameters.includePeerToPeer = true
        parameters.serviceClass = .responsiveData
        parameters.multipathServiceType = .handover
        parameters.expiredDNSBehavior = .allow
        parameters.allowFastOpen = true
        parameters.prohibitExpensivePaths = true
        parameters.prohibitConstrainedPaths = true
        parameters.requiresDNSSECValidation = true
        parameters.preferNoProxies = true
        parameters.attribution = .user

        XCTAssertEqual(parameters.requiredInterfaceType, .wifi)
        XCTAssertEqual(parameters.prohibitedInterfaceTypes, [.cellular, .loopback])
        XCTAssertEqual(parameters.requiredLocalEndpoint, endpoint)
        XCTAssertTrue(parameters.allowLocalEndpointReuse)
        XCTAssertTrue(parameters.includePeerToPeer)
        XCTAssertEqual(parameters.serviceClass, .responsiveData)
        XCTAssertEqual(parameters.multipathServiceType, .handover)
        XCTAssertEqual(parameters.expiredDNSBehavior, .allow)
        XCTAssertTrue(parameters.allowFastOpen)
        XCTAssertTrue(parameters.prohibitExpensivePaths)
        XCTAssertTrue(parameters.prohibitConstrainedPaths)
        XCTAssertTrue(parameters.requiresDNSSECValidation)
        XCTAssertTrue(parameters.preferNoProxies)
        XCTAssertEqual(parameters.attribution, .user)
        assertParameters(
            parameters,
            expectedText: "tcp, traffic class: 300, local: 127.0.0.1:8080, multipath service: handover, fast-open, no expensive, no constrained, no cellular, prefer no proxy, attribution: website, requires DNSSEC"
        )
    }

    func testParameterPolicyOptionalSettersMatchApple() {
        let parameters = NWParameters.tcp

        parameters.prohibitedInterfaceTypes = []
        XCTAssertNil(parameters.prohibitedInterfaceTypes)
        assertParameters(parameters, expectedText: "tcp, attribution: developer")

        parameters.prohibitedInterfaceTypes = [.wifi]
        XCTAssertEqual(parameters.prohibitedInterfaceTypes, [.wifi])
        assertParameters(parameters, expectedText: "tcp, attribution: developer")

        parameters.prohibitedInterfaceTypes = nil
        XCTAssertNil(parameters.prohibitedInterfaceTypes)
        assertParameters(parameters, expectedText: "tcp, attribution: developer")

        parameters.requiredLocalEndpoint = .unix(path: "/tmp/quill.sock")
        XCTAssertEqual(parameters.requiredLocalEndpoint, .unix(path: "/tmp/quill.sock"))
        assertParameters(parameters, expectedText: "tcp, local: AF_UNIX:\"/tmp/quill.sock\", attribution: developer")
    }

    private func assertOption(
        _ option: Any,
        expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(String(describing: option), expectedText, file: file, line: line)
        XCTAssertEqual(String(reflecting: option), expectedText, file: file, line: line)
    }

    private func assertParameters(
        _ parameters: NWParameters,
        expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(String(describing: parameters), expectedText, file: file, line: line)
        XCTAssertEqual(String(reflecting: parameters), expectedText, file: file, line: line)
        XCTAssertEqual(parameters.debugDescription, expectedText, file: file, line: line)
    }

    private func assertEnumText<T>(
        _ value: T,
        expectedText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(String(describing: value), expectedText, file: file, line: line)
        XCTAssertEqual(
            String(reflecting: value),
            "Network.NWParameters.\(T.self).\(expectedText)",
            file: file,
            line: line
        )
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
