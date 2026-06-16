// MobileCoin SDK client surface -- SignalUI's
// Payments/MobileCoinAPI+Configuration.swift builds a client via
// `MobileCoinClient.Config.make(...)` (injecting an `HttpRequester` and
// `TransportProtocol.http`) and `MobileCoinClient.make(accountKey:config:)`;
// Payments/MobileCoinAPI.swift then drives every balance / fee / transaction
// API stubbed below.
//
// Inert on Linux: payments can never reach a MobileCoin consensus node or fog
// service from QuillOS, so every network-backed API completes immediately
// with `ConnectionError.connectionFailure` -- which SignalUI's
// convertMCError() maps to the expected, non-asserting
// PaymentsError.connectionFailure. The injected HttpRequester is stored but
// never invoked. Purely local queries return honest empty values
// (`.unknown` receipt status, empty account activity).

import Foundation
import LibMobileCoin

/// Real SDK: switches the client between GRPC and HTTP stacks. The shim
/// never opens a connection either way.
public struct TransportProtocol: Equatable, Sendable {
    public let description: String

    public static let grpc = TransportProtocol(description: "grpc")
    public static let http = TransportProtocol(description: "http")
}

/// Implemented by SignalUI (MobileCoinHttpRequester) to route the SDK's fog /
/// consensus HTTP traffic through OWSURLSession. The shim accepts the
/// requester via `Config.httpRequester` but never calls it.
public protocol HttpRequester {
    func request(
        url: URL,
        method: HTTPMethod,
        headers: [String: String]?,
        body: Data?,
        completion: @escaping (Result<HTTPResponse, Error>) -> Void
    )
}

/// Real SDK: global logging switches. SignalUI flips `logSensitiveData` for
/// internal builds; nothing in the shim logs, so the flag is write-only.
public enum MobileCoinLogging {
    nonisolated(unsafe) public static var logSensitiveData = false
}

public final class MobileCoinClient {

    // MARK: - Config

    public struct Config {
        public let consensusUrls: [String]
        public let consensusAttestation: Attestation
        public let fogUrls: [String]
        public let fogViewAttestation: Attestation
        public let fogKeyImageAttestation: Attestation
        public let fogMerkleProofAttestation: Attestation
        public let fogReportAttestation: Attestation
        public let transportProtocol: TransportProtocol

        /// Stored, never invoked (see header).
        public var httpRequester: HttpRequester?

        /// Real SDK validates the URL schemes (mc:// and fog://); the shim
        /// accepts anything -- the URLs are never dialed.
        public static func make(
            consensusUrls: [String],
            consensusAttestation: Attestation,
            fogUrls: [String],
            fogViewAttestation: Attestation,
            fogKeyImageAttestation: Attestation,
            fogMerkleProofAttestation: Attestation,
            fogReportAttestation: Attestation,
            transportProtocol: TransportProtocol
        ) -> Result<Config, InvalidInputError> {
            .success(
                Config(
                    consensusUrls: consensusUrls,
                    consensusAttestation: consensusAttestation,
                    fogUrls: fogUrls,
                    fogViewAttestation: fogViewAttestation,
                    fogKeyImageAttestation: fogKeyImageAttestation,
                    fogMerkleProofAttestation: fogMerkleProofAttestation,
                    fogReportAttestation: fogReportAttestation,
                    transportProtocol: transportProtocol
                )
            )
        }
    }

    // MARK: - Properties

    public let accountKey: AccountKey
    public let config: Config

    private init(accountKey: AccountKey, config: Config) {
        self.accountKey = accountKey
        self.config = config
    }

    public static func make(accountKey: AccountKey, config: Config) -> Result<MobileCoinClient, InvalidInputError> {
        .success(MobileCoinClient(accountKey: accountKey, config: config))
    }

    /// The error every network-backed API below reports.
    private static var offline: ConnectionError {
        .connectionFailure("MobileCoin services are not reachable from QuillOS/Linux")
    }

    // MARK: - Authorization

    /// Real SDK: installs HTTP basic-auth credentials for fog requests.
    /// No requests are ever made, so the credentials are dropped.
    public func setFogBasicAuthorization(username: String, password: String) {
        // Inert.
    }

    /// Counterpart for consensus credentials (unused by SignalUI today, kept
    /// for SDK-shape completeness).
    public func setConsensusBasicAuthorization(username: String, password: String) {
        // Inert.
    }

    // MARK: - Balances

    public func updateBalances(completion: @escaping (Result<Balances, BalanceUpdateError>) -> Void) {
        completion(.failure(.connectionError(Self.offline)))
    }

    public func amountTransferable(
        tokenId: TokenId,
        feeLevel: FeeLevel,
        completion: @escaping (Result<UInt64, BalanceTransferEstimationFetcherError>) -> Void
    ) {
        completion(.failure(.connectionError(Self.offline)))
    }

    // MARK: - Fees

    public func estimateTotalFee(
        toSendAmount amount: Amount,
        feeLevel: FeeLevel,
        completion: @escaping (Result<UInt64, TransactionEstimationFetcherError>) -> Void
    ) {
        completion(.failure(.connectionError(Self.offline)))
    }

    // MARK: - Transactions

    public func prepareTransaction(
        to recipient: PublicAddress,
        amount: Amount,
        fee: UInt64,
        completion: @escaping (Result<PendingSinglePayloadTransaction, TransactionPreparationError>) -> Void
    ) {
        completion(.failure(.connectionError(Self.offline)))
    }

    public func requiresDefragmentation(
        toSendAmount amount: Amount,
        feeLevel: FeeLevel,
        completion: @escaping (Result<Bool, TransactionEstimationFetcherError>) -> Void
    ) {
        completion(.failure(.connectionError(Self.offline)))
    }

    public func prepareDefragmentationStepTransactions(
        toSendAmount amount: Amount,
        feeLevel: FeeLevel,
        completion: @escaping (Result<[Transaction], DefragTransactionPreparationError>) -> Void
    ) {
        completion(.failure(.connectionError(Self.offline)))
    }

    public func submitTransaction(
        transaction: Transaction,
        completion: @escaping (Result<UInt64, SubmitTransactionError>) -> Void
    ) {
        completion(.failure(SubmitTransactionError(submissionError: .connectionError(Self.offline))))
    }

    public func txOutStatus(
        of transaction: Transaction,
        completion: @escaping (Result<TransactionStatus, ConnectionError>) -> Void
    ) {
        completion(.failure(Self.offline))
    }

    // MARK: - Receipts

    /// Real SDK: checks the receipt against the locally-cached ledger state.
    /// There is no ledger here, so the status is honestly unknown (SignalUI
    /// maps .unknown to PaymentsError.verificationStatusUnknown).
    public func status(of receipt: Receipt) -> Result<ReceiptStatus, InvalidInputError> {
        .success(.unknown)
    }

    // MARK: - Account activity

    /// Real SDK: the locally-synced transaction history. Never synced here,
    /// so the history is empty at block zero.
    public func accountActivity(for tokenId: TokenId) -> AccountActivity {
        AccountActivity(blockCount: 0, txOuts: [])
    }
}
