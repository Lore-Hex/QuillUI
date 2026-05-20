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

    func testDefaultProtocolStackMatchesAppleTextSurfaceAndComposition() {
        assertProtocolStack(
            NWParameters.tcp.defaultProtocolStack,
            applicationProtocolTexts: [],
            transportProtocolText: "Optional(Network.NWProtocolTCP.Options)",
            internetProtocolText: "Optional(Network.NWProtocolIP.Options)"
        )
        assertProtocolStack(
            NWParameters.udp.defaultProtocolStack,
            applicationProtocolTexts: [],
            transportProtocolText: "Optional(Network.NWProtocolUDP.Options)",
            internetProtocolText: "Optional(Network.NWProtocolIP.Options)"
        )
        assertProtocolStack(
            NWParameters.tls.defaultProtocolStack,
            applicationProtocolTexts: ["Network.NWProtocolTLS.Options"],
            transportProtocolText: "Optional(Network.NWProtocolTCP.Options)",
            internetProtocolText: "Optional(Network.NWProtocolIP.Options)"
        )
        assertProtocolStack(
            NWParameters.dtls.defaultProtocolStack,
            applicationProtocolTexts: ["Network.NWProtocolTLS.Options"],
            transportProtocolText: "Optional(Network.NWProtocolUDP.Options)",
            internetProtocolText: "Optional(Network.NWProtocolIP.Options)"
        )

        let parameters = NWParameters.tcp
        XCTAssertTrue(parameters.defaultProtocolStack !== parameters.defaultProtocolStack)
    }

    func testDefaultProtocolStackMutabilityAndCopyingMatchApple() {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let tlsOptions = NWProtocolTLS.Options()
        let parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let stack = parameters.defaultProtocolStack

        let storedTCP = stack.transportProtocol as? NWProtocolTCP.Options
        XCTAssertNotNil(storedTCP)
        XCTAssertTrue(storedTCP !== tcpOptions)
        XCTAssertEqual(storedTCP?.noDelay, true)
        let storedTLS = stack.applicationProtocols.first as? NWProtocolTLS.Options
        XCTAssertNotNil(storedTLS)
        XCTAssertTrue(storedTLS !== tlsOptions)

        let udpOptions = NWProtocolUDP.Options()
        udpOptions.preferNoChecksum = true
        stack.transportProtocol = udpOptions
        let storedUDP = parameters.defaultProtocolStack.transportProtocol as? NWProtocolUDP.Options
        XCTAssertNotNil(storedUDP)
        XCTAssertTrue(storedUDP !== udpOptions)
        XCTAssertEqual(storedUDP?.preferNoChecksum, true)

        stack.applicationProtocols = []
        XCTAssertEqual(parameters.defaultProtocolStack.applicationProtocols.count, 0)

        stack.internetProtocol = nil
        XCTAssertEqual(
            String(describing: parameters.defaultProtocolStack.internetProtocol),
            "Optional(Network.NWProtocolIP.Options)"
        )
    }

    func testIPOptionDefaultsAndSettersMatchAppleThroughDefaultProtocolStack() {
        let parameters = NWParameters.tcp
        guard let options = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options else {
            XCTFail("Expected a default IP protocol option")
            return
        }

        XCTAssertEqual(options.version, .any)
        XCTAssertEqual(options.hopLimit, 0)
        XCTAssertFalse(options.useMinimumMTU)
        XCTAssertFalse(options.disableFragmentation)
        XCTAssertFalse(options.shouldCalculateReceiveTime)
        XCTAssertEqual(options.localAddressPreference, .default)
        XCTAssertFalse(options.disableMulticastLoopback)
        assertOption(options, expectedText: "Network.NWProtocolIP.Options")

        options.version = .v6
        options.hopLimit = 64
        options.useMinimumMTU = true
        options.disableFragmentation = true
        options.shouldCalculateReceiveTime = true
        options.localAddressPreference = .stable
        options.disableMulticastLoopback = true

        let mutatedOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options
        XCTAssertEqual(mutatedOptions?.version, .v6)
        XCTAssertEqual(mutatedOptions?.hopLimit, 64)
        XCTAssertEqual(mutatedOptions?.useMinimumMTU, true)
        XCTAssertEqual(mutatedOptions?.disableFragmentation, true)
        XCTAssertEqual(mutatedOptions?.shouldCalculateReceiveTime, true)
        XCTAssertEqual(mutatedOptions?.localAddressPreference, .stable)
        XCTAssertEqual(mutatedOptions?.disableMulticastLoopback, true)
    }

    func testIPOptionEnumTextMatchesApple() {
        assertEnumText(
            NWProtocolIP.Options.Version.any,
            expectedText: "any",
            expectedReflection: "Network.NWProtocolIP.Options.Version.any"
        )
        assertEnumText(
            NWProtocolIP.Options.Version.v4,
            expectedText: "v4",
            expectedReflection: "Network.NWProtocolIP.Options.Version.v4"
        )
        assertEnumText(
            NWProtocolIP.Options.Version.v6,
            expectedText: "v6",
            expectedReflection: "Network.NWProtocolIP.Options.Version.v6"
        )
        assertEnumText(
            NWProtocolIP.Options.AddressPreference.default,
            expectedText: "default",
            expectedReflection: "Network.NWProtocolIP.Options.AddressPreference.default"
        )
        assertEnumText(
            NWProtocolIP.Options.AddressPreference.temporary,
            expectedText: "temporary",
            expectedReflection: "Network.NWProtocolIP.Options.AddressPreference.temporary"
        )
        assertEnumText(
            NWProtocolIP.Options.AddressPreference.stable,
            expectedText: "stable",
            expectedReflection: "Network.NWProtocolIP.Options.AddressPreference.stable"
        )
        assertEnumText(
            NWProtocolIP.ECN.nonECT,
            expectedText: "nonECT",
            expectedReflection: "Network.NWProtocolIP.ECN.nonECT"
        )
        assertEnumText(
            NWProtocolIP.ECN.ect0,
            expectedText: "ect0",
            expectedReflection: "Network.NWProtocolIP.ECN.ect0"
        )
        assertEnumText(
            NWProtocolIP.ECN.ect1,
            expectedText: "ect1",
            expectedReflection: "Network.NWProtocolIP.ECN.ect1"
        )
        assertEnumText(
            NWProtocolIP.ECN.ce,
            expectedText: "ce",
            expectedReflection: "Network.NWProtocolIP.ECN.ce"
        )
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
        assertSendable(NWParameters.tcp.defaultProtocolStack)
        if let ipOptions = NWParameters.tcp.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            assertSendable(ipOptions)
        } else {
            XCTFail("Expected a default IP protocol option")
        }
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

    private func assertProtocolStack(
        _ stack: NWParameters.ProtocolStack,
        applicationProtocolTexts: [String],
        transportProtocolText: String,
        internetProtocolText: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertOption(
            stack,
            expectedText: "Network.NWParameters.ProtocolStack",
            file: file,
            line: line
        )
        XCTAssertEqual(
            stack.applicationProtocols.map { String(describing: $0) },
            applicationProtocolTexts,
            file: file,
            line: line
        )
        XCTAssertEqual(
            stack.applicationProtocols.map { String(reflecting: $0) },
            applicationProtocolTexts,
            file: file,
            line: line
        )
        XCTAssertEqual(
            String(describing: stack.transportProtocol),
            transportProtocolText,
            file: file,
            line: line
        )
        XCTAssertEqual(
            String(reflecting: stack.transportProtocol),
            transportProtocolText,
            file: file,
            line: line
        )
        XCTAssertEqual(
            String(describing: stack.internetProtocol),
            internetProtocolText,
            file: file,
            line: line
        )
        XCTAssertEqual(
            String(reflecting: stack.internetProtocol),
            internetProtocolText,
            file: file,
            line: line
        )
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

    private func assertEnumText<T>(
        _ value: T,
        expectedText: String,
        expectedReflection: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(String(describing: value), expectedText, file: file, line: line)
        XCTAssertEqual(String(reflecting: value), expectedReflection, file: file, line: line)
    }

    private func assertSendable<T: Sendable>(_ value: T) {
        _ = value
    }
}
