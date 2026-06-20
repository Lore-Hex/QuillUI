import Foundation

public extension String {
    static func localizedStringWithFormat(_ format: String, _ arguments: [CVarArg]) -> String {
        String(format: format, arguments: arguments)
    }
}
