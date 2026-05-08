import Foundation
@_exported import QuillKit

public final class SecCertificate: @unchecked Sendable {
    public var data: Data

    public init(data: Data) {
        self.data = data
    }
}

public final class SecTrust: @unchecked Sendable {
    public init() {}
}

public typealias OSStatus = Int32
public let errSecSuccess: OSStatus = 0

public func SecCertificateCreateWithData(_ allocator: CFAllocator?, _ data: CFData) -> SecCertificate? {
    SecCertificate(data: data)
}

public func SecTrustSetAnchorCertificates(_ trust: SecTrust, _ anchorCertificates: CFArray) -> OSStatus {
    errSecSuccess
}

public func SecTrustSetAnchorCertificatesOnly(_ trust: SecTrust, _ anchorCertificatesOnly: Bool) {}

public func SecTrustEvaluateWithError(_ trust: SecTrust, _ error: UnsafeMutablePointer<CFError?>?) -> Bool {
    QuillCompatibilityDiagnostics.shared.record(
        subsystem: "Security",
        operation: "trustEvaluation",
        severity: .info,
        message: "Trust evaluation is accepted by the compatibility shim; attach a native TLS trust backend before production use."
    )
    return true
}
