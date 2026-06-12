import Foundation
@_exported import EncryptionProvider

public typealias AutoreleasingUnsafeMutablePointer<Pointee> = UnsafeMutablePointer<Pointee>
public typealias NSErrorPointer = UnsafeMutablePointer<NSError?>?

public final class MTRpcError: NSObject, Error {
    public let errorCode: Int32
    public let errorDescription: String

    public init(errorCode: Int32, errorDescription: String) {
        self.errorCode = errorCode
        self.errorDescription = errorDescription
        super.init()
    }

    public override convenience init() {
        self.init(errorCode: 0, errorDescription: "")
    }
}

public protocol MTDisposable: AnyObject {
    func dispose()
}

public final class MTDisposableAction: MTDisposable {
    private let action: () -> Void

    public init(_ action: @escaping () -> Void = {}) {
        self.action = action
    }

    public func dispose() {
        action()
    }
}

public final class MTBlockDisposable: MTDisposable {
    private let action: () -> Void

    public init(block: @escaping () -> Void) {
        self.action = block
    }

    public convenience init(_ block: @escaping () -> Void) {
        self.init(block: block)
    }

    public func dispose() {
        action()
    }
}

public final class MTSubscriber: NSObject {
    private let next: (Any?) -> Void
    private let error: (Any?) -> Void
    private let completed: () -> Void

    public init(next: @escaping (Any?) -> Void = { _ in }, error: @escaping (Any?) -> Void = { _ in }, completed: @escaping () -> Void = {}) {
        self.next = next
        self.error = error
        self.completed = completed
        super.init()
    }

    public func putNext(_ value: Any?) { next(value) }
    public func putError(_ value: Any?) { error(value) }
    public func putCompletion() { completed() }
}

public final class MTSignal: NSObject {
    public typealias Generator = (@escaping (Any?) -> Void, @escaping (Any?) -> Void, @escaping () -> Void) -> MTDisposable
    private let generator: Generator

    public override init() {
        self.generator = { _, _, completed in completed(); return MTDisposableAction() }
        super.init()
    }

    private init(callbacks generator: @escaping Generator) {
        self.generator = generator
        super.init()
    }

    public convenience init(generator: @escaping (MTSubscriber?) -> MTDisposable?) {
        self.init(callbacks: { next, error, completed in
            generator(MTSubscriber(next: next, error: error, completed: completed)) ?? MTDisposableAction()
        })
    }

    @discardableResult
    public func start(next: @escaping (Any?) -> Void) -> MTDisposable? {
        generator(next, { _ in }, {})
    }

    @discardableResult
    public func start(next: @escaping (Any?) -> Void, error: @escaping (Any?) -> Void, completed: @escaping () -> Void) -> MTDisposable? {
        generator(next, error, completed)
    }

    public static func single(_ next: Any?) -> MTSignal {
        MTSignal(callbacks: { nextHandler, _, completed in
            nextHandler(next)
            completed()
            return MTDisposableAction()
        })
    }

    public static func fail(_ error: Any?) -> MTSignal {
        MTSignal(callbacks: { _, errorHandler, _ in
            errorHandler(error)
            return MTDisposableAction()
        })
    }

    public static func never() -> MTSignal { MTSignal(callbacks: { _, _, _ in MTDisposableAction() }) }
    public static func complete() -> MTSignal { MTSignal() }
}

public final class MTHttpResponse: NSObject {
    public let headers: [AnyHashable: Any]
    public let data: Data

    public init(headers: [AnyHashable: Any] = [:], data: Data = Data()) {
        self.headers = headers
        self.data = data
        super.init()
    }
}

public final class MTHttpRequestOperation: NSObject {
    public class func data(forHttpUrl url: URL) -> MTSignal? {
        _ = url
        return .single(MTHttpResponse())
    }

    public class func data(forHttpUrl url: URL, headers: [AnyHashable: Any]) -> MTSignal? {
        _ = headers
        return data(forHttpUrl: url)
    }
}

public final class MTDatacenterAddress: NSObject, NSCopying, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let host: String?
    public let ip: String?
    public let port: UInt16
    public let preferForMedia: Bool
    public let restrictToTcp: Bool
    public let cdn: Bool
    public let preferForProxy: Bool
    public let secret: Data?

    public init(ip: String, port: UInt16, preferForMedia: Bool, restrictToTcp: Bool, cdn: Bool, preferForProxy: Bool, secret: Data?) {
        self.host = nil
        self.ip = ip
        self.port = port
        self.preferForMedia = preferForMedia
        self.restrictToTcp = restrictToTcp
        self.cdn = cdn
        self.preferForProxy = preferForProxy
        self.secret = secret
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        self.init(ip: "", port: 0, preferForMedia: false, restrictToTcp: false, cdn: false, preferForProxy: false, secret: nil)
    }

    public func encode(with coder: NSCoder) { _ = coder }
    public func copy(with zone: NSZone? = nil) -> Any { self }
    public func isEqual(to other: MTDatacenterAddress) -> Bool { ip == other.ip && port == other.port }
    public func isIpv6() -> Bool { ip?.contains(":") ?? false }
}

public final class MTDatacenterAddressListData: NSObject {
    public let addressList: [NSNumber: [Any]]

    public init(addressList: [NSNumber: [Any]]) {
        self.addressList = addressList
        super.init()
    }
}

public final class MTDatacenterVerificationData: NSObject {}

public final class MTExportedAuthorizationData: NSObject {
    public let authorizationBytes: Data
    public let authorizationId: Int64

    public init(authorizationBytes: Data, authorizationId: Int64) {
        self.authorizationBytes = authorizationBytes
        self.authorizationId = authorizationId
        super.init()
    }
}

public typealias MTExportAuthorizationResponseParser = (Data) -> MTExportedAuthorizationData?
public typealias MTRequestDatacenterAddressListParser = (Data) -> MTDatacenterAddressListData?
public typealias MTDatacenterVerificationDataParser = (Data) -> MTDatacenterVerificationData?
public typealias MTRequestNoopParser = (Data) -> Any?

public protocol MTSerialization: AnyObject {
    func currentLayer() -> UInt
    func parseMessage(_ data: Data!) -> Any!
    func exportAuthorization(_ datacenterId: Int32, data: AutoreleasingUnsafeMutablePointer<NSData?>) -> MTExportAuthorizationResponseParser!
    func importAuthorization(_ authId: Int64, bytes: Data!) -> Data!
    func requestDatacenterAddress(with data: AutoreleasingUnsafeMutablePointer<NSData?>) -> MTRequestDatacenterAddressListParser!
    func requestNoop(_ data: AutoreleasingUnsafeMutablePointer<NSData?>!) -> MTRequestNoopParser!
}

public protocol MTKeychain: AnyObject {}
public protocol MTTcpConnectionInterface: AnyObject {}
public protocol MTTcpConnectionInterfaceDelegate: AnyObject {
    func connectionInterfaceDidReadPartialData(ofLength partialLength: UInt, tag: Int)
    func connectionInterfaceDidRead(_ rawData: Data, withTag tag: Int, networkType: Int32)
    func connectionInterfaceDidConnect()
    func connectionInterfaceDidDisconnectWithError(_ error: Error?)
}

public extension MTTcpConnectionInterfaceDelegate {
    func connectionInterfaceDidReadPartialData(ofLength partialLength: UInt, tag: Int) { _ = (partialLength, tag) }
    func connectionInterfaceDidRead(_ rawData: Data, withTag tag: Int, networkType: Int32) { _ = (rawData, tag, networkType) }
    func connectionInterfaceDidConnect() {}
    func connectionInterfaceDidDisconnectWithError(_ error: Error?) { _ = error }
}
public protocol MTContextChangeListener: AnyObject {}

public final class MTQueue: NSObject {
    public let queue: DispatchQueue

    public init(_ queue: DispatchQueue = DispatchQueue(label: "MtProtoKit.MTQueue")) {
        self.queue = queue
        super.init()
    }

    public func async(_ f: @escaping () -> Void) {
        queue.async(execute: f)
    }
}

public final class MTApiEnvironment: NSObject {
    public var apiId: Int32 = 0
    public var langPack: String?
    public var layer: NSNumber?
    public var disableUpdates: Bool = false
    public var socksProxySettings: MTSocksProxySettings?
    public var langPackCode: String?
    public var languageCode: String?
    public var systemLanguageCode: String?
    public var networkSettings: MTNetworkSettings?
    public var deviceModelName: String?
    public var accessHostOverride: String?
    public var systemCode: Data?

    public override init() {
        super.init()
    }

    public convenience init(deviceModelName: String) {
        self.init()
        self.deviceModelName = deviceModelName
    }

    public convenience init(deviceModelName: String?) {
        self.init(deviceModelName: deviceModelName ?? "")
    }

    public init(
        apiId: Int32 = 0,
        deviceModel: String = "",
        systemVersion: String = "",
        appVersion: String = "",
        systemLangCode: String = "",
        langPack: String = "",
        langCode: String = "",
        layer: Int32 = 0,
        apiInitializationHash: String? = nil,
        appData: Data? = nil
    ) {
        _ = (deviceModel, systemVersion, appVersion, apiInitializationHash, appData)
        self.apiId = apiId
        self.layer = NSNumber(value: layer)
        self.langPack = langPack
        self.systemLanguageCode = systemLangCode
        self.langPackCode = langPack
        self.languageCode = langCode
        super.init()
    }

    public func withUpdatedSocksProxySettings(_ socksProxySettings: MTSocksProxySettings?) -> MTApiEnvironment {
        self.socksProxySettings = socksProxySettings
        return self
    }

    public func withUpdatedNetworkSettings(_ networkSettings: MTNetworkSettings?) -> MTApiEnvironment {
        self.networkSettings = networkSettings
        return self
    }

    public func withUpdatedLangPackCode(_ langPackCode: String?) -> MTApiEnvironment {
        self.langPackCode = langPackCode
        return self
    }

    public func withUpdatedSystemCode(_ systemCode: Data?) -> MTApiEnvironment {
        self.systemCode = systemCode
        return self
    }
}

public enum MTDatacenterAuthInfoSelector: Int32 {
    case persistent = 0
    case temporary = 1
    case ephemeralMain = 2
}

public final class MTDatacenterAuthInfo: NSObject {
    public let authKey: Data?
    public let authKeyId: Int64

    public init?(authKey: Data? = Data(), authKeyId: Int64 = 0, validUntilTimestamp: Int32 = 0, saltSet: [Any] = [], authKeyAttributes: [AnyHashable: Any] = [:]) {
        self.authKey = authKey
        self.authKeyId = authKeyId
        _ = (validUntilTimestamp, saltSet, authKeyAttributes)
        super.init()
    }
}

public final class MTNetworkUsageCalculationInfo: NSObject {
    public init(filePath: String = "", incomingWWANKey: Any = "", outgoingWWANKey: Any = "", incomingOtherKey: Any = "", outgoingOtherKey: Any = "") {
        _ = (filePath, incomingWWANKey, outgoingWWANKey, incomingOtherKey, outgoingOtherKey)
        super.init()
    }
}
public final class MTDatacenterAddressSet: NSObject {
    public let addressList: [MTDatacenterAddress]

    public override init() {
        self.addressList = []
        super.init()
    }

    public init(addressList: [MTDatacenterAddress]) {
        self.addressList = addressList
        super.init()
    }
}
public final class MTTransportScheme: NSObject {
    public let address: MTDatacenterAddress
    public let media: Bool
    public let isProxy: Bool

    public override init() {
        self.address = MTDatacenterAddress(ip: "", port: 0, preferForMedia: false, restrictToTcp: false, cdn: false, preferForProxy: false, secret: nil)
        self.media = false
        self.isProxy = false
        super.init()
    }

    public init(tcpTransport: Any, media: Bool, isProxy: Bool) {
        _ = tcpTransport
        self.address = MTDatacenterAddress(ip: "", port: 0, preferForMedia: media, restrictToTcp: false, cdn: false, preferForProxy: isProxy, secret: nil)
        self.media = media
        self.isProxy = isProxy
        super.init()
    }

    public init(transport: Any, address: MTDatacenterAddress, media: Bool) {
        _ = transport
        self.address = address
        self.media = media
        self.isProxy = false
        super.init()
    }
}
public final class MTSessionInfo: NSObject {}

public final class MTContext: NSObject {
    private static var fixedDifference: Int32 = 0

    public var keychain: MTKeychain?
    public let serialization: MTSerialization
    public var encryptionProvider: EncryptionProvider
    public let apiEnvironment: MTApiEnvironment
    public let isTestingEnvironment: Bool
    public let useTempAuthKeys: Bool
    public var tempKeyExpiration: Int32 = 0
    public var makeTcpConnectionInterface: ((MTTcpConnectionInterfaceDelegate, DispatchQueue) -> MTTcpConnectionInterface)?

    public init(serialization: MTSerialization, encryptionProvider: EncryptionProvider, apiEnvironment: MTApiEnvironment, isTestingEnvironment: Bool, useTempAuthKeys: Bool) {
        self.serialization = serialization
        self.encryptionProvider = encryptionProvider
        self.apiEnvironment = apiEnvironment
        self.isTestingEnvironment = isTestingEnvironment
        self.useTempAuthKeys = useTempAuthKeys
        super.init()
    }

    public class func fixedTimeDifference() -> Int32 { fixedDifference }
    public class func setFixedTimeDifference(_ fixedTimeDifference: Int32) { fixedDifference = fixedTimeDifference }
    public class func contextQueue() -> MTQueue { MTQueue() }
    public class func perform(withObjCTry block: () -> Void) { block() }
    public class func perform(objCTry block: () -> Void) { block() }
    public class func copyAuthInfo(from keychain: MTKeychain, toTempKeychain tempKeychain: MTKeychain) { _ = (keychain, tempKeychain) }
    public func performBatchUpdates(_ block: () -> Void) { block() }
    public func addChangeListener(_ changeListener: MTContextChangeListener) { _ = changeListener }
    public func removeChangeListener(_ changeListener: MTContextChangeListener) { _ = changeListener }
    public func globalTime() -> TimeInterval { Date().timeIntervalSince1970 }
    public func globalTimeDifference() -> TimeInterval { TimeInterval(Self.fixedDifference) }
    public func globalTimeOffsetFromUTC() -> TimeInterval { 0 }
    public func setGlobalTimeDifference(_ globalTimeDifference: TimeInterval) { Self.fixedDifference = Int32(globalTimeDifference) }
    public func authInfoForDatacenter(withId datacenterId: Int, selector: MTDatacenterAuthInfoSelector) -> MTDatacenterAuthInfo? { _ = (datacenterId, selector); return nil }
    public func authInfoForDatacenter(withIdRequired datacenterId: Int, isCdn: Bool, selector: MTDatacenterAuthInfoSelector, allowUnboundEphemeralKeys: Bool) -> MTDatacenterAuthInfo? {
        _ = (datacenterId, isCdn, selector, allowUnboundEphemeralKeys)
        return MTDatacenterAuthInfo()
    }
    public func updateAuthInfoForDatacenter(withId datacenterId: Int, authInfo: MTDatacenterAuthInfo?, selector: MTDatacenterAuthInfoSelector) { _ = (datacenterId, authInfo, selector) }
    public func authTokenForDatacenter(withId datacenterId: Int) -> Any? { _ = datacenterId; return nil }
    public func authTokenForDatacenter(withId datacenterId: Int, authTokenMasterDatacenterId: Int?, requiredAuthToken: Any?) -> Any? { _ = (datacenterId, authTokenMasterDatacenterId, requiredAuthToken); return nil }
    public func authTokenForDatacenter(withIdRequired datacenterId: Int, authToken: Any?, masterDatacenterId: Int?) -> Any? { _ = (datacenterId, authToken, masterDatacenterId); return nil }
    public func updateAuthTokenForDatacenter(withId datacenterId: Int, authToken: Any?) { _ = (datacenterId, authToken) }
    public func add(_ changeListener: MTContextChangeListener) { _ = changeListener }
    public func add(_ publicKeys: [Any], forDatacenterWithId datacenterId: Int) { _ = (publicKeys, datacenterId) }
    public func addPublicKeys(_ publicKeys: [Any], forDatacenterWithId datacenterId: Int) { _ = (publicKeys, datacenterId) }
    public func addAddressForDatacenter(withId datacenterId: Int, address: MTDatacenterAddress) { _ = (datacenterId, address) }
    public func updateAddressSetForDatacenter(withId datacenterId: Int, addressSet: MTDatacenterAddressSet, forceUpdateSchemes: Bool) { _ = (datacenterId, addressSet, forceUpdateSchemes) }
    public func updateTransportSchemeForDatacenter(withId datacenterId: Int, transportScheme: MTTransportScheme, media: Bool, isProxy: Bool) { _ = (datacenterId, transportScheme, media, isProxy) }
    public func setSeedAddressSetForDatacenterWithId(_ datacenterId: Int, seedAddressSet: MTDatacenterAddressSet) { _ = (datacenterId, seedAddressSet) }
    public func updateApiEnvironment(_ apiEnvironment: MTApiEnvironment) { _ = apiEnvironment }
    public func updateApiEnvironment(_ f: (MTApiEnvironment?) -> MTApiEnvironment?) { _ = f(apiEnvironment) }
    public func beginExplicitBackupAddressDiscovery() {}
    public func setDiscoverBackupAddressListSignal(_ signal: MTSignal?) { _ = signal }
    public func setExternalRequestVerification(_ f: ((String) -> MTSignal?)?) { _ = f }
    public func setExternalRecaptchaRequestVerification(_ f: ((String, String) -> MTSignal?)?) { _ = f }
    public func transportSchemesForDatacenter(withId datacenterId: Int, media: Bool, isProxy: Bool) -> [MTTransportScheme] {
        _ = (datacenterId, media, isProxy)
        return []
    }
    public func transportSchemesForDatacenter(withId datacenterId: Int, media: Bool, enforceMedia: Bool, isProxy: Bool) -> [MTTransportScheme] {
        _ = enforceMedia
        return transportSchemesForDatacenter(withId: datacenterId, media: media, isProxy: isProxy)
    }
}

public final class MTSocksProxySettings: NSObject {
    public let ip: String
    public let port: UInt16
    public let username: String?
    public let password: String?
    public let secret: Data?

    public override init() {
        self.ip = ""
        self.port = 0
        self.username = nil
        self.password = nil
        self.secret = nil
        super.init()
    }

    public init(ip: String, port: UInt16, username: String?, password: String?, secret: Data?) {
        self.ip = ip
        self.port = port
        self.username = username
        self.password = password
        self.secret = secret
        super.init()
    }
}

public enum MTProtoConnectionState: Int32 {
    case waitingForNetwork = 0
    case connecting = 1
    case connected = 2

    public var isConnected: Bool { self == .connected }
    public var proxyHasConnectionIssues: Bool { false }
    public var proxyAddress: String? { nil }
}

public protocol MTProtoDelegate: AnyObject {
    func mtProto(_ mtProto: MTProto, receivedMessage message: MTIncomingMessage)
    func mtProto(_ mtProto: MTProto, messageDeliveryFailed messageId: Int64)
    func mtProto(_ mtProto: MTProto, stateUpdated state: MTProtoConnectionState)
}

public extension MTProtoDelegate {
    func mtProto(_ mtProto: MTProto, receivedMessage message: MTIncomingMessage) { _ = (mtProto, message) }
    func mtProto(_ mtProto: MTProto, messageDeliveryFailed messageId: Int64) { _ = (mtProto, messageId) }
    func mtProto(_ mtProto: MTProto, stateUpdated state: MTProtoConnectionState) { _ = (mtProto, state) }
}

public protocol MTMessageService: AnyObject {
    func mtProtoDidAdd(_ mtProto: MTProto)
    func mtProtoWillAdd(_ mtProto: MTProto)
    func mtProtoDidChangeSession(_ mtProto: MTProto)
    func mtProtoServerDidChangeSession(_ mtProto: MTProto)
    func mtProtoDidAdd(_ mtProto: MTProto, service: MTMessageService)
    func mtProto(_ mtProto: MTProto, receivedMessage message: MTIncomingMessage)
}

public extension MTMessageService {
    func mtProtoDidAdd(_ mtProto: MTProto) { _ = mtProto }
    func mtProtoWillAdd(_ mtProto: MTProto) { _ = mtProto }
    func mtProtoDidChangeSession(_ mtProto: MTProto) { _ = mtProto }
    func mtProtoServerDidChangeSession(_ mtProto: MTProto) { _ = mtProto }
    func mtProtoDidAdd(_ mtProto: MTProto, service: MTMessageService) { _ = (mtProto, service) }
    func mtProto(_ mtProto: MTProto, receivedMessage message: MTIncomingMessage) { _ = (mtProto, message) }
}

public final class MTIncomingMessage: NSObject {
    public let body: Any?

    public init(body: Any? = nil) {
        self.body = body
        super.init()
    }
}

public final class MTOutgoingMessage: NSObject {}

public final class MTPreparedMessage: NSObject {}

public protocol MTRequestMessageServiceDelegate: AnyObject {
    func requestMessageService(_ service: MTRequestMessageService, requestCompleted request: MTRequest, response: Any?)
    func requestMessageService(_ service: MTRequestMessageService, requestFailed request: MTRequest, error: MTRpcError)
}

public extension MTRequestMessageServiceDelegate {
    func requestMessageService(_ service: MTRequestMessageService, requestCompleted request: MTRequest, response: Any?) { _ = (service, request, response) }
    func requestMessageService(_ service: MTRequestMessageService, requestFailed request: MTRequest, error: MTRpcError) { _ = (service, request, error) }
}

public final class MTRequestMessageService: NSObject, MTMessageService {
    public weak var delegate: MTRequestMessageServiceDelegate?
    public var forceBackgroundRequests: Bool = false
    public var didReceiveSoftAuthResetError: (() -> Void)?

    public override init() {
        super.init()
    }

    public init!(context: MTContext) {
        _ = context
        super.init()
    }

    public func add(_ request: MTRequest) {
        delegate?.requestMessageService(self, requestCompleted: request, response: nil)
    }

    public func removeRequest(byInternalId internalId: Any?) {
        _ = internalId
    }
}

public final class MTRequestErrorContext: NSObject {
    public let floodWaitSeconds: Int32
    public let floodWaitErrorText: String?
    public let internalServerErrorCount: Int32

    public init(floodWaitSeconds: Int32 = 0, floodWaitErrorText: String? = nil, internalServerErrorCount: Int32 = 0) {
        self.floodWaitSeconds = floodWaitSeconds
        self.floodWaitErrorText = floodWaitErrorText
        self.internalServerErrorCount = internalServerErrorCount
        super.init()
    }
}

public final class MTRequestResponseInfo: NSObject {
    public let timestamp: Double
    public let networkType: Int32
    public let duration: Double

    public init(timestamp: Double = 0, networkType: Int32 = 0, duration: Double = 0) {
        self.timestamp = timestamp
        self.networkType = networkType
        self.duration = duration
        super.init()
    }
}

public final class MTRequest: NSObject {
    public var body: Any?
    public var completed: ((Any?, MTRequestResponseInfo?, MTRpcError?) -> Void)?
    public var dependsOnPasswordEntry: Bool = false
    public var expectedResponseSize: Int32 = 0
    public var needsTimeoutTimer: Bool = true
    public var shouldContinueExecutionWithErrorContext: ((MTRequestErrorContext?) -> Bool)?
    public var acknowledgementReceived: (() -> Void)?
    public var progressUpdated: ((Float, Int) -> Void)?
    public var shouldDependOnRequest: ((MTRequest?) -> Bool)?
    public var internalId: Any = UUID().uuidString
    public var metadata: Any?
    public var shortMetadata: Any?

    public override init() {
        super.init()
    }

    public init(body: Any?, completed: ((Any?, MTRequestResponseInfo?, MTRpcError?) -> Void)? = nil) {
        self.body = body
        self.completed = completed
        super.init()
    }

    public func setPayload(_ payload: Data, metadata: Any?, shortMetadata: Any?, responseParser: @escaping (Data) -> Any?) {
        _ = payload
        self.metadata = metadata
        self.shortMetadata = shortMetadata
        self.completed = { response, _, _ in
            _ = (response as? Data).flatMap(responseParser)
        }
    }
}

public final class MTProto: NSObject {
    public weak var delegate: MTProtoDelegate?
    public let context: MTContext
    public let datacenterId: Int
    public var getLogPrefix: (() -> String?)?
    public var cdn: Bool = false
    public var useTempAuthKeys: Bool = false
    public var media: Bool = false
    public var requiredAuthToken: Any?
    public var authTokenMasterDatacenterId: Int?
    public var checkForProxyConnectionIssues: Bool = false

    public init!(context: MTContext, datacenterId: Int, usageCalculationInfo: MTNetworkUsageCalculationInfo? = nil, requiredAuthToken: Any? = nil, authTokenMasterDatacenterId: Int? = nil) {
        self.context = context
        self.datacenterId = datacenterId
        self.requiredAuthToken = requiredAuthToken
        self.authTokenMasterDatacenterId = authTokenMasterDatacenterId
        _ = usageCalculationInfo
        super.init()
    }

    public func add(_ messageService: MTMessageService) {
        messageService.mtProtoDidAdd(self)
    }

    public func add(_ messageService: MTMessageService?) {
        guard let messageService else {
            return
        }
        add(messageService)
    }

    public func remove(_ messageService: MTMessageService) {
        _ = messageService
    }

    public func requestTransportTransaction() {}
    public func finalizeSession() {}
    public func pause() {}
    public func resume() {}
    public func stop() {}
}

public final class MTNetworkSettings: NSObject {
    public let reducedBackupDiscoveryTimeout: Bool

    public init(reducedBackupDiscoveryTimeout: Bool = false) {
        self.reducedBackupDiscoveryTimeout = reducedBackupDiscoveryTimeout
        super.init()
    }
}

public final class MTNetworkUsageManager: NSObject {
    public init?(info: MTNetworkUsageCalculationInfo) {
        _ = info
        super.init()
    }

    public func addIncomingBytes(_ byteCount: UInt, interface: MTNetworkUsageManagerInterface) { _ = (byteCount, interface) }
    public func addOutgoingBytes(_ byteCount: UInt, interface: MTNetworkUsageManagerInterface) { _ = (byteCount, interface) }
    public func addIncomingBytes(_ byteCount: UInt, interface: Int32) { _ = (byteCount, interface) }
    public func addOutgoingBytes(_ byteCount: UInt, interface: Int32) { _ = (byteCount, interface) }
    public func resetKeys(_ keys: [NSNumber], setKeys: [NSNumber: NSNumber], completion: @escaping () -> Void) {
        _ = (keys, setKeys)
        completion()
    }

    public func currentStats(forKeys keys: [NSNumber]) -> MTSignal {
        let values = NSMutableDictionary()
        for key in keys {
            values[key] = NSNumber(value: 0)
        }
        return .single(values)
    }
}

public let MTNetworkUsageManagerInterfaceOther: Int32 = 0
public let MTNetworkUsageManagerInterfaceWWAN: Int32 = 1

public struct MTNetworkUsageManagerInterface: RawRepresentable, Equatable, Sendable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let wifi = MTNetworkUsageManagerInterface(rawValue: 0)
    public static let cellular = MTNetworkUsageManagerInterface(rawValue: 1)
}

public final class MTBackupAddressSignals: NSObject {
    public class func fetchBackupIps() -> MTSignal { .complete() }
    public class func fetchBackupIps(_ testingEnvironment: Bool, currentContext: MTContext, additionalSource: MTSignal?, phoneNumber: String?, mainDatacenterId: Int) -> MTSignal {
        _ = (testingEnvironment, currentContext, additionalSource, phoneNumber, mainDatacenterId)
        return .complete()
    }
}

public final class MTTcpTransport: NSObject {
    public override init() {
        super.init()
    }
}

public final class MTProxyConnectivityStatus: NSObject {
    public let reachable: Bool
    public let roundTripTime: TimeInterval

    public init(reachable: Bool = false, roundTripTime: TimeInterval = 0) {
        self.reachable = reachable
        self.roundTripTime = roundTripTime
        super.init()
    }
}

public final class MTProxyConnectivity: NSObject {
    public class func pingProxy(with context: MTContext, datacenterId: Int, settings: MTSocksProxySettings) -> MTSignal {
        _ = (context, datacenterId, settings)
        return .single(MTProxyConnectivityStatus())
    }
}

public func MTSha1(_ data: Data) -> Data {
    _ = data
    return Data(repeating: 0, count: 20)
}

public func MTSha256(_ data: Data) -> Data {
    _ = data
    return Data(repeating: 0, count: 32)
}

public func MTSubdataSha1(_ data: Data, _ offset: UInt, _ length: UInt) -> Data {
    let start = min(data.count, Int(offset))
    let end = min(data.count, start + Int(length))
    return MTSha1(data.subdata(in: start ..< end))
}

public func MTAesEncrypt(_ data: Data, _ key: Data, _ iv: Data) -> Data? {
    _ = (key, iv)
    return data
}

public func MTAesDecrypt(_ data: Data, _ key: Data, _ iv: Data) -> Data? {
    _ = (key, iv)
    return data
}

public func MTAesEncryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutableRawPointer?, _ length: Int, _ key: Data, _ iv: Data) {
    _ = (bytes, length, key, iv)
}

public func MTAesEncryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutablePointer<UInt8>, _ length: Int, _ key: Data, _ iv: Data) {
    MTAesEncryptBytesInplaceAndModifyIv(UnsafeMutableRawPointer(bytes), length, key, iv)
}

public func MTAesEncryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutablePointer<UInt8>, _ length: Int, _ key: Data, _ iv: UnsafeMutablePointer<UInt8>) {
    _ = (bytes, length, key, iv)
}

public func MTAesEncryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutablePointer<UInt8>, _ length: Int, _ key: UnsafeMutablePointer<UInt8>, _ iv: UnsafeMutablePointer<UInt8>) {
    _ = (bytes, length, key, iv)
}

public func MTAesDecryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutableRawPointer?, _ length: Int, _ key: Data, _ iv: Data) {
    _ = (bytes, length, key, iv)
}

public func MTAesDecryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutablePointer<UInt8>, _ length: Int, _ key: Data, _ iv: Data) {
    MTAesDecryptBytesInplaceAndModifyIv(UnsafeMutableRawPointer(bytes), length, key, iv)
}

public func MTAesDecryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutablePointer<UInt8>, _ length: Int, _ key: Data, _ iv: UnsafeMutablePointer<UInt8>) {
    _ = (bytes, length, key, iv)
}

public func MTAesDecryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutablePointer<UInt8>, _ length: Int, _ key: UnsafeMutablePointer<UInt8>, _ iv: UnsafeMutablePointer<UInt8>) {
    _ = (bytes, length, key, iv)
}

public func MTAesCtrDecrypt(_ data: Data, _ key: Data, _ iv: Data) -> Data? {
    _ = (key, iv)
    return data
}

public func MTPBKDF2(_ password: Data, _ salt: Data, _ iterations: Int32) -> Data? {
    _ = (password, salt, iterations)
    return Data(repeating: 0, count: 64)
}

public func MTCheckIsSafeB(_ encryptionProvider: EncryptionProvider, _ b: Data, _ p: Data) -> Bool {
    _ = (encryptionProvider, b, p)
    return true
}

public func MTIsZero(_ value: Data) -> Bool {
    value.allSatisfy { $0 == 0 }
}

public func MTIsZero(_ encryptionProvider: EncryptionProvider, _ value: Data) -> Bool {
    _ = encryptionProvider
    return MTIsZero(value)
}

public func MTModSub(_ encryptionProvider: EncryptionProvider, _ a: Data, _ b: Data, _ modulus: Data) -> Data? {
    _ = (encryptionProvider, b, modulus)
    return a
}

public func MTModMul(_ encryptionProvider: EncryptionProvider, _ a: Data, _ b: Data, _ modulus: Data) -> Data? {
    _ = (encryptionProvider, b, modulus)
    return a
}

public func MTAdd(_ encryptionProvider: EncryptionProvider, _ a: Data, _ b: Data) -> Data? {
    _ = (encryptionProvider, b)
    return a
}

public func MTMul(_ encryptionProvider: EncryptionProvider, _ a: Data, _ b: Data) -> Data? {
    _ = (encryptionProvider, b)
    return a
}

public enum MTDeprecated {
    public static func unarchiveDeprecated(with data: Data) -> Any? {
        try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
    }
}

public func MTRsaFingerprint(_ publicKey: String) -> Int64 {
    Int64(publicKey.hashValue)
}

public func MTRsaFingerprint(_ encryptionProvider: EncryptionProvider, _ publicKey: String) -> Int64 {
    _ = encryptionProvider
    return MTRsaFingerprint(publicKey)
}

public final class MTGzip: NSObject {
    public class func compress(_ data: Data) -> Data? { data }
    public class func decompress(_ data: Data) -> Data? { data }
}

public final class MTOutputStream: NSObject {
    private var data = Data()

    public override init() {
        super.init()
    }

    public func write(_ bytes: UnsafeRawPointer, maxLength: Int) -> Int {
        data.append(bytes.assumingMemoryBound(to: UInt8.self), count: maxLength)
        return maxLength
    }

    public func write(_ value: Int32) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    public func writeBytes(_ bytes: Data) {
        data.append(bytes)
    }

    public func currentBytes() -> Data {
        data
    }
}

public func MTExp(_ encryptionProvider: EncryptionProvider, _ base: Data, _ exponent: Data, _ modulus: Data) -> Data? {
    _ = (encryptionProvider, exponent, modulus)
    return base
}

public func MTCheckIsSafeG(_ g: UInt32) -> Bool {
    [2, 3, 4, 5, 6, 7].contains(g)
}

public func MTCheckIsSafeGAOrB(_ encryptionProvider: EncryptionProvider, _ gAOrB: Data, _ p: Data) -> Bool {
    _ = (encryptionProvider, gAOrB, p)
    return true
}

public func MTCheckMod(_ encryptionProvider: EncryptionProvider, _ p: Data, _ g: UInt32, _ keychain: MTKeychain?) -> Bool {
    _ = (encryptionProvider, p, g, keychain)
    return true
}

public func MTCheckIsSafePrime(_ encryptionProvider: EncryptionProvider, _ p: Data, _ keychain: MTKeychain?) -> Bool {
    _ = (encryptionProvider, p, keychain)
    return true
}

public func MTRsaEncryptPKCS1OAEP(_ encryptionProvider: EncryptionProvider, _ publicKey: String, _ data: Data) -> Data? {
    encryptionProvider.rsaEncryptPKCS1OAEP(withPublicKey: publicKey, data: data)
}
