#if os(Linux)
import Foundation
import Glibc

public enum QuillQtNativeRuntimeSupport {
    public static func runEncodedPayload<Payload: Encodable>(
        _ payload: Payload,
        executableName: String,
        run: (UnsafePointer<CChar>) -> CInt
    ) -> Never {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(payload)
            let payload = String(decoding: data, as: UTF8.self)
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
