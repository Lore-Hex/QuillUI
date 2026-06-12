// MobileCoin SDK amount/balance surface -- SignalUI's
// Payments/MobileCoinAPI.swift wraps pico-MOB values in `Amount(_:in: .MOB)`,
// reads `Balances.mobBalance` / `Balance.amount()` after
// `MobileCoinClient.updateBalances`, and passes `FeeLevel.minimum` to the fee
// estimation APIs. Payments/PaymentsFormat+MobileCoin.swift renders
// `TokenId.MOB.name` as the currency name.
//
// Inert on Linux: balances are only ever the zero value the stub client
// reports; no ledger is consulted.

import Foundation

public struct TokenId: Equatable, Hashable, CustomStringConvertible {
    public let value: UInt64

    public init(_ value: UInt64) {
        self.value = value
    }

    public static let MOB = TokenId(0)

    public var name: String {
        switch value {
        case 0:
            return "MOB"
        default:
            return "TokenId(\(value))"
        }
    }

    public var description: String { name }
}

public struct Amount: Equatable, Hashable {
    public let value: UInt64
    public let tokenId: TokenId

    public init(_ value: UInt64, in tokenId: TokenId) {
        self.value = value
        self.tokenId = tokenId
    }
}

public enum FeeLevel {
    case minimum
}

public struct Balance: CustomStringConvertible {
    public let amountPicoMob: UInt64
    public let blockCount: UInt64
    public let tokenId: TokenId

    public init(amountPicoMob: UInt64, blockCount: UInt64, tokenId: TokenId) {
        self.amountPicoMob = amountPicoMob
        self.blockCount = blockCount
        self.tokenId = tokenId
    }

    /// Real SDK: returns nil when the 128-bit balance overflows UInt64.
    /// Shim balances are always zero, so this is always representable.
    public func amount() -> UInt64? {
        amountPicoMob
    }

    public var description: String {
        "\(amountPicoMob) pico\(tokenId.name)"
    }
}

public struct Balances {
    public let balances: [TokenId: Balance]
    public let blockCount: UInt64

    public init(balances: [TokenId: Balance], blockCount: UInt64) {
        self.balances = balances
        self.blockCount = blockCount
    }

    public var mobBalance: Balance {
        balances[.MOB] ?? Balance(amountPicoMob: 0, blockCount: blockCount, tokenId: .MOB)
    }
}
