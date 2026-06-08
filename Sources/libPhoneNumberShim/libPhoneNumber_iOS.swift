//
// QuillUI Linux shim for signalapp/libPhoneNumber-iOS (NBPhoneNumberUtil).
//
// libPhoneNumber-iOS is an Objective-C port of Google's libphonenumber; it does
// not compile on Linux (no ObjC). Signal wraps it in PhoneNumber.swift /
// PhoneNumberUtil.swift for E.164 parsing/formatting of phone-number identities.
//
// This shim provides the NB* surface those two files use, with a best-effort
// E.164 implementation: parsing a leading "+<calling code><national>" is
// mechanical and correct for the common case (Signal identities are E.164).
// Full libphonenumber metadata behavior (per-region national formatting,
// validation, example numbers, as-you-type grouping) is NOT reproduced — those
// paths return best-effort/empty results. Wire a real libphonenumber (e.g.
// PhoneNumberKit) before relying on national formatting/validation in
// production. Registration/contact paths that need this are gated behind the
// real-account pause.
//
import Foundation

public enum NBEPhoneNumberFormat: Int, Sendable {
    case E164 = 0
    case INTERNATIONAL = 1
    case NATIONAL = 2
    case RFC3966 = 3
}

public enum NBEPhoneNumberType: Int, Sendable {
    case FIXED_LINE = 0
    case MOBILE = 1
    case FIXED_LINE_OR_MOBILE = 2
    case TOLL_FREE = 3
    case PREMIUM_RATE = 4
    case UNKNOWN = 99
}

// Common ITU country calling codes (greedy longest-match for E.164 splitting).
private let nbCallingCodes: Set<Int> = [
    1, 7, 20, 27, 30, 31, 32, 33, 34, 36, 39, 40, 41, 43, 44, 45, 46, 47, 48, 49,
    51, 52, 53, 54, 55, 56, 57, 58, 60, 61, 62, 63, 64, 65, 66, 81, 82, 84, 86,
    90, 91, 92, 93, 94, 95, 98, 212, 213, 216, 218, 220, 233, 234, 251, 254, 255,
    256, 260, 263, 351, 352, 353, 354, 355, 358, 359, 370, 371, 372, 373, 374,
    375, 376, 377, 378, 380, 381, 385, 386, 387, 389, 420, 421, 423, 852, 853,
    855, 856, 880, 886, 960, 961, 962, 963, 964, 965, 966, 967, 968, 970, 971,
    972, 973, 974, 975, 976, 977, 992, 993, 994, 995, 996, 998,
]

private let nbCallingCodeToRegion: [Int: String] = [
    1: "US", 7: "RU", 20: "EG", 27: "ZA", 30: "GR", 31: "NL", 32: "BE", 33: "FR",
    34: "ES", 39: "IT", 40: "RO", 41: "CH", 44: "GB", 45: "DK", 46: "SE", 47: "NO",
    48: "PL", 49: "DE", 52: "MX", 54: "AR", 55: "BR", 57: "CO", 60: "MY", 61: "AU",
    62: "ID", 63: "PH", 64: "NZ", 65: "SG", 66: "TH", 81: "JP", 82: "KR", 84: "VN",
    86: "CN", 90: "TR", 91: "IN", 92: "PK", 234: "NG", 254: "KE", 880: "BD",
    972: "IL", 971: "AE", 966: "SA",
]

private let nbRegionToCallingCode: [String: Int] = {
    var m: [String: Int] = [:]
    for (code, region) in nbCallingCodeToRegion { m[region] = code }
    return m
}()

private func nbDigits(_ s: String) -> String {
    String(s.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) })
}

// libPhoneNumber global region-code sentinels (Google libphonenumber values).
// SSK's PhoneNumberUtil.getFilteredRegionCodeForCallingCode compares against
// these to drop unknown / non-geographic results.
public let NB_UNKNOWN_REGION = "ZZ"
public let NB_REGION_CODE_FOR_NON_GEO_ENTITY = "001"

public final class NBPhoneNumber: NSObject {
    public var countryCode: NSNumber?
    public var nationalNumber: NSNumber?
    public var italianLeadingZero: Bool = false
    public var rawInput: String?
    public override init() { super.init() }
}

public final class NBPhoneMetaData: NSObject {
    public var nationalPrefixTransformRule: String?
    public var codeID: String?
    public override init() { super.init() }
}

public final class NBMetadataHelper: NSObject {
    public override init() { super.init() }
    public func getMetadataForRegion(_ regionCode: String?) -> NBPhoneMetaData? {
        let m = NBPhoneMetaData()
        m.codeID = regionCode
        return m
    }
}

public enum NBPhoneNumberError: Error { case invalid }

public final class NBPhoneNumberUtil: NSObject {
    public init(metadataHelper: NBMetadataHelper) { super.init() }
    public override convenience init() { self.init(metadataHelper: NBMetadataHelper()) }

    public func parse(_ numberToParse: String, defaultRegion: String?) throws -> NBPhoneNumber {
        let result = NBPhoneNumber()
        result.rawInput = numberToParse
        let trimmed = numberToParse.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("+") {
            let digits = nbDigits(trimmed)
            // Greedy longest (3→1 digit) country-code match.
            for len in stride(from: 3, through: 1, by: -1) where digits.count > len {
                if let code = Int(digits.prefix(len)), nbCallingCodes.contains(code) {
                    result.countryCode = NSNumber(value: code)
                    result.nationalNumber = NSNumber(value: Int(digits.dropFirst(len)) ?? 0)
                    return result
                }
            }
            // Fallback: assume 1-digit code.
            if let code = Int(digits.prefix(1)) {
                result.countryCode = NSNumber(value: code)
                result.nationalNumber = NSNumber(value: Int(digits.dropFirst(1)) ?? 0)
            }
            return result
        }
        let cc = defaultRegion.flatMap { nbRegionToCallingCode[$0] } ?? 0
        result.countryCode = NSNumber(value: cc)
        result.nationalNumber = NSNumber(value: Int(nbDigits(trimmed)) ?? 0)
        return result
    }

    public func format(_ phoneNumber: NBPhoneNumber, numberFormat: NBEPhoneNumberFormat) throws -> String {
        let cc = phoneNumber.countryCode?.intValue ?? 0
        let nn = phoneNumber.nationalNumber.map { "\($0.int64Value)" } ?? ""
        switch numberFormat {
        case .E164:
            return "+\(cc)\(nn)"
        case .INTERNATIONAL, .RFC3966:
            return "+\(cc) \(nn)"
        case .NATIONAL:
            return nn
        }
    }

    public func getNationalSignificantNumber(_ phoneNumber: NBPhoneNumber) -> String {
        phoneNumber.nationalNumber.map { "\($0.int64Value)" } ?? ""
    }

    public func getRegionCode(forCountryCode countryCode: NSNumber) -> String {
        nbCallingCodeToRegion[countryCode.intValue] ?? "ZZ"
    }

    public func getCountryCode(forRegion regionCode: String) -> NSNumber {
        NSNumber(value: nbRegionToCallingCode[regionCode] ?? 0)
    }

    public func isPossibleNumber(_ phoneNumber: NBPhoneNumber) -> Bool {
        let nn = getNationalSignificantNumber(phoneNumber)
        return nn.count >= 4 && nn.count <= 15
    }

    public func isValidNumber(_ phoneNumber: NBPhoneNumber) -> Bool {
        isPossibleNumber(phoneNumber)
    }

    public func getExampleNumber(forType regionCode: String, type: NBEPhoneNumberType) throws -> NBPhoneNumber {
        // Example numbers require libphonenumber metadata; not reproduced.
        throw NBPhoneNumberError.invalid
    }
}

public final class NBAsYouTypeFormatter: NSObject {
    private var accumulated = ""
    public init(regionCode: String?) { super.init() }
    public func inputDigit(_ digit: String) -> String {
        accumulated += digit
        return accumulated
    }
    public func removeLastDigit() -> String {
        if !accumulated.isEmpty { accumulated.removeLast() }
        return accumulated
    }
    public func clear() { accumulated = "" }
}
