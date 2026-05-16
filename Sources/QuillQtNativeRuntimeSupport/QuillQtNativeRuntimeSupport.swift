#if os(Linux)
import Foundation
import Glibc

public enum QuillQtNativeRuntimeSupport {
    public static func boundedIndexOverride(environmentKey: String, count: Int) -> Int? {
        boundedIndexOverride(ProcessInfo.processInfo.environment[environmentKey], count: count)
    }

    public static func boundedIndexOverride(environmentKeys: [String], count: Int) -> Int? {
        for environmentKey in environmentKeys {
            if let boundedIndex = boundedIndexOverride(environmentKey: environmentKey, count: count) {
                return boundedIndex
            }
        }

        return nil
    }

    public static func boundedIndexOverride(_ value: String?, count: Int) -> Int? {
        guard count > 0, let value else {
            return nil
        }

        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let requestedIndex = Int(trimmedValue) else {
            return nil
        }

        return min(max(requestedIndex, 0), count - 1)
    }

    public static func executableName(arguments: [String] = CommandLine.arguments, fallback: String) -> String {
        guard let rawExecutablePath = arguments.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawExecutablePath.isEmpty
        else {
            return fallback
        }

        let executableName = URL(fileURLWithPath: rawExecutablePath).lastPathComponent
        return executableName.isEmpty ? fallback : executableName
    }

    public static func encodedPayloadString<Payload: Encodable>(_ payload: Payload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        return String(decoding: data, as: UTF8.self)
    }

    public static func runEncodedPayload<Payload: Encodable>(
        _ payload: Payload,
        executableName: String,
        run: (UnsafePointer<CChar>) -> CInt
    ) -> Never {
        do {
            let payload = try encodedPayloadString(payload)
            let exitCode = payload.withCString { payloadPointer in
                run(payloadPointer)
            }
            exit(exitCode)
        } catch {
            fputs("\(executableName): failed to encode Qt payload: \(error)\n", stderr)
            exit(70)
        }
    }
}
#endif
