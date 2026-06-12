// MobileCoin SDK error surface -- SignalUI's
// Payments/MobileCoinAPI.swift `convertMCError(error:)` dynamic-casts to each
// of these types and exhaustively switches over their cases, so the case
// names and associated values must match the real SDK exactly. The stub
// client (MobileCoinClient.swift) only ever produces
// `ConnectionError.connectionFailure`, which SignalUI maps to
// PaymentsError.connectionFailure -- an expected, non-asserting network
// failure.
//
// (`InvalidInputError` lives in Attestation.swift from an earlier wave.)

import Foundation

public enum ConnectionError: Error {
    case connectionFailure(String)
    case authorizationFailure(String)
    case invalidServerResponse(String)
    case attestationVerificationFailed(String)
    case outdatedClient(String)
    case serverRateLimited(String)
}

/// Real SDK: wraps Apple Security framework errors raised while loading
/// pinned TLS certificates. Only ever used in an `as?` cast by SignalUI;
/// the shim never throws it.
public struct SecurityError: Error, CustomStringConvertible {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var description: String { "Security error: \(reason)" }
}

/// Real SDK: fog view/ledger block indices drifting out of sync. SignalUI
/// only binds and logs it; the shim never produces it.
public struct FogSyncError: Error, CustomStringConvertible {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }

    public var description: String { "Fog sync error: \(reason)" }
}

public enum BalanceUpdateError: Error {
    case connectionError(ConnectionError)
    case fogSyncError(FogSyncError)
}

public enum TransactionPreparationError: Error {
    case invalidInput(String)
    case insufficientBalance(String = String())
    case defragmentationRequired(String = String())
    case connectionError(ConnectionError)
}

public enum TransactionSubmissionError: Error {
    case connectionError(ConnectionError)
    case invalidTransaction(String = String())
    case feeError(String = String())
    case tombstoneBlockTooFar(String = String())
    case inputsAlreadySpent(String = String())
    case missingMemo(String = String())
    case outputAlreadyExists(String = String())
}

/// Failure type of `MobileCoinClient.submitTransaction`; SignalUI rethrows
/// `error.submissionError`.
public struct SubmitTransactionError: Error {
    public let submissionError: TransactionSubmissionError
    public let consensusBlockCount: UInt64?

    public init(submissionError: TransactionSubmissionError, consensusBlockCount: UInt64? = nil) {
        self.submissionError = submissionError
        self.consensusBlockCount = consensusBlockCount
    }
}

public enum DefragTransactionPreparationError: Error {
    case invalidInput(String)
    case insufficientBalance(String = String())
    case connectionError(ConnectionError)
}

public enum BalanceTransferEstimationFetcherError: Error {
    case feeExceedsBalance(String = String())
    case balanceOverflow(String = String())
    case connectionError(ConnectionError)
}

public enum TransactionEstimationFetcherError: Error {
    case invalidInput(String)
    case insufficientBalance(String = String())
    case connectionError(ConnectionError)
}
