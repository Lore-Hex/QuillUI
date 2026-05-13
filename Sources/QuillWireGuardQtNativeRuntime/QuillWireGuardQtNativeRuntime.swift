#if os(Linux)
import CQuillQt6WidgetsShim
import Foundation
import Glibc
import QuillWireGuardCore

public enum QuillWireGuardQtNativeApp {
    public static func run() -> Never {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let data = try encoder.encode(QuillWireGuardAppSnapshot.configurationManager)
            let payload = String(decoding: data, as: UTF8.self)
            let exitCode = payload.withCString { payloadPointer in
                quill_wireguard_qt_run_wireguard_json(
                    CommandLine.argc,
                    CommandLine.unsafeArgv,
                    payloadPointer
                )
            }
            exit(Int32(exitCode))
        } catch {
            fputs("quill-wireguard-qt: failed to encode Qt payload: \(error)\n", stderr)
            exit(70)
        }
    }
}
#endif
