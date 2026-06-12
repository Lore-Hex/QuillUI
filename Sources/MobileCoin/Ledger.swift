// MobileCoin SDK ledger surface -- SignalUI's payments cluster:
//  * Payments/MobileCoinAPI.swift prepares/submits `Transaction`s, verifies
//    `Receipt`s (`txOutPublicKey`, `validateAndUnmaskValue(accountKey:)`) and
//    switches over `TransactionStatus` / `ReceiptStatus` (.accepted/.received
//    bind a `BlockMetadata` whose `index` and optional `timestamp` are read).
//  * Payments/PaymentsImpl.swift + PaymentsProcessor.swift round-trip both
//    types through `init?(serializedData:)` / `serializedData`.
//  * Payments/PaymentsReconciliation.swift walks `AccountActivity.txOuts`
//    (`OwnedTxOut`: value/publicKey/keyImage/receivedBlock/spentBlock) and
//    conforms both types to its MCTransactionHistory protocols.
//
// Inert on Linux: nothing is ever parsed or validated -- serialized blobs are
// carried verbatim, receipts never unmask a value, and account activity is
// only ever the empty value the stub client reports.

import Foundation

public struct Transaction {
    /// Real SDK: protobuf serialization. Shim: carried verbatim, never parsed.
    public let serializedData: Data

    /// Real SDK: decoded from the transaction protobuf. The shim cannot
    /// decode, so deserialized transactions report a zero fee.
    public let fee: UInt64

    public init?(serializedData: Data) {
        guard !serializedData.isEmpty else {
            return nil
        }
        self.serializedData = serializedData
        self.fee = 0
    }
}

public struct Receipt {
    /// Real SDK: protobuf serialization. Shim: carried verbatim, never parsed.
    public let serializedData: Data

    public init?(serializedData: Data) {
        guard !serializedData.isEmpty else {
            return nil
        }
        self.serializedData = serializedData
    }

    /// Real SDK: the TxOut public key parsed out of the receipt protobuf,
    /// used by SignalUI as a dedupe identifier. The shim cannot parse the
    /// protobuf, so it stands in the whole serialized receipt (deterministic
    /// and unique per receipt, which is all the dedupe logic needs).
    public var txOutPublicKey: Data {
        serializedData
    }

    /// Real SDK: decrypts the masked amount with the account's view key.
    /// No crypto on Linux, so the value is always unknown (nil) -- SignalUI
    /// maps this to PaymentsError.invalidAmount.
    public func validateAndUnmaskValue(accountKey: AccountKey) -> UInt64? {
        nil
    }
}

/// Result payload of `MobileCoinClient.prepareTransaction(to:amount:fee:)`.
public struct PendingSinglePayloadTransaction {
    public let transaction: Transaction
    public let receipt: Receipt

    public init(transaction: Transaction, receipt: Receipt) {
        self.transaction = transaction
        self.receipt = receipt
    }
}

public struct BlockMetadata: Equatable, Hashable {
    public let index: UInt64
    public let timestamp: Date?

    public init(index: UInt64, timestamp: Date?) {
        self.index = index
        self.timestamp = timestamp
    }
}

public enum TransactionStatus {
    case unknown
    case accepted(block: BlockMetadata)
    case failed
}

public enum ReceiptStatus {
    case unknown
    case received(block: BlockMetadata)
    case failed
}

public struct OwnedTxOut: Equatable, Hashable {
    public let value: UInt64
    public let tokenId: TokenId
    public let publicKey: Data
    public let keyImage: Data
    public let receivedBlock: BlockMetadata
    public let spentBlock: BlockMetadata?

    public init(
        value: UInt64,
        tokenId: TokenId,
        publicKey: Data,
        keyImage: Data,
        receivedBlock: BlockMetadata,
        spentBlock: BlockMetadata?
    ) {
        self.value = value
        self.tokenId = tokenId
        self.publicKey = publicKey
        self.keyImage = keyImage
        self.receivedBlock = receivedBlock
        self.spentBlock = spentBlock
    }
}

public struct AccountActivity {
    public let blockCount: UInt64
    public let txOuts: Set<OwnedTxOut>

    public init(blockCount: UInt64, txOuts: Set<OwnedTxOut>) {
        self.blockCount = blockCount
        self.txOuts = txOuts
    }
}
