#if os(Linux)
import CQuillQt6WidgetsShim
import Glibc
import QuillQtNativeRuntimeSupport
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
        QuillQtNativeRuntimeSupport.runEncodedPayload(
            QuillWireGuardAppSnapshot.configurationManager,
            executableName: QuillQtNativeRuntimeSupport.executableName(fallback: "quill-wireguard-qt")
        ) { payloadPointer in
            quill_wireguard_qt_run_wireguard_json(
                CommandLine.argc,
                CommandLine.unsafeArgv,
                payloadPointer,
                quill_wireguard_qt_import_config_json,
                quill_wireguard_qt_free_string
            )
        }
    }
}
#endif
