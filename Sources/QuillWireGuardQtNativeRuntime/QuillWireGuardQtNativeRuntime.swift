#if os(Linux)
import CQuillQt6WidgetsShim
import Foundation
import Glibc
import QuillWireGuardCore

@_cdecl("quill_wireguard_qt_import_config_json")
public func quill_wireguard_qt_import_config_json(
    _ configurationPointer: UnsafePointer<CChar>?,
    _ existingTunnelCount: CInt,
    _ suggestedNamePointer: UnsafePointer<CChar>?
) -> UnsafeMutablePointer<CChar>? {
    let response = QuillWireGuardNativeImportBridge.importResponse(
        configuration: configurationPointer.map { String(cString: $0) },
        existingTunnelCount: Int(existingTunnelCount),
        suggestedName: suggestedNamePointer.map { String(cString: $0) }
    )

    do {
        let payload = try QuillWireGuardNativeImportBridge.encodeResponsePayload(response)
        return payload.withCString { strdup($0) }
    } catch {
        let payload = QuillWireGuardNativeImportBridge.encodingFailurePayload
        return payload.withCString { strdup($0) }
    }
}

@_cdecl("quill_wireguard_qt_free_string")
public func quill_wireguard_qt_free_string(_ pointer: UnsafeMutablePointer<CChar>?) {
    if let pointer {
        free(UnsafeMutableRawPointer(pointer))
    }
}

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
                    payloadPointer,
                    quill_wireguard_qt_import_config_json,
                    quill_wireguard_qt_free_string
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
