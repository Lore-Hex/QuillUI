//
//  TransportError (RSWeb shim)
//
//  Minimal stand-in for Ranchero-Software/NetNewsWire's RSWeb module — just
//  the surface the Account module references so far (`TransportError`). The
//  target is named `RSWeb` so vendored `import RSWeb` resolves to it verbatim;
//  it grows toward real RSWeb (download session, conditional GET, …) as more
//  of Account is brought up.
//

import Foundation

public enum TransportError: LocalizedError, Equatable, Sendable {
    case noData
    case noURL
    case suspended
    case httpError(status: Int)

    public var errorDescription: String? {
        switch self {
        case .noData: return "No data received."
        case .noURL: return "No URL available."
        case .suspended: return "The request was not sent because syncing is suspended."
        case .httpError(let status): return "An HTTP error (status \(status)) occurred."
        }
    }
}
