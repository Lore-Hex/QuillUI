import Foundation

public struct UserAgent: Sendable {
    public static func fromInfoPlist() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "UserAgent") as? String
    }

    public static func headers() -> [AnyHashable: String]? {
        guard let userAgent = fromInfoPlist() else {
            return nil
        }
        return [HTTPRequestHeader.userAgent: userAgent]
    }
}
