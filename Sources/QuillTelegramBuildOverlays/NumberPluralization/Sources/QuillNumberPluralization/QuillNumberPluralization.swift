import Foundation

public enum NumberPluralizationForm: Int32, Sendable {
    case zero
    case one
    case two
    case few
    case many
    case other
}

public func numberPluralizationForm(_ lc: UInt32, _ n: Int32) -> NumberPluralizationForm {
    switch lc {
    case 0x6172: // ar
        if n == 0 { return .zero }
        if n == 1 { return .one }
        if n == 2 { return .two }
        let mod100 = n % 100
        if mod100 >= 3 && mod100 <= 10 { return .few }
        if mod100 >= 11 && mod100 <= 99 { return .many }
        return .other
    default:
        return n == 1 ? .one : .other
    }
}

public func languageCodehash(_ code: String) -> UInt32 {
    var rawCode = code
    if rawCode.hasSuffix("-raw"), let dash = rawCode.firstIndex(of: "-") {
        rawCode = String(rawCode[..<dash])
    }
    if let underscore = rawCode.firstIndex(of: "_") {
        rawCode = String(rawCode[..<underscore])
    }
    return rawCode.lowercased().utf8.reduce(UInt32(0)) { result, byte in
        (result << 8) &+ UInt32(byte)
    }
}
