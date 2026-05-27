// Backend facade modules re-export QuillUI so app targets can import one
// backend-specific product without duplicating the core UI import.
@_exported import QuillUI

#if os(Linux)
import Foundation
import BackendGTK4
import QuillPaint
#endif

public typealias QuillGtkRuntimeMode = QuillBackendRuntimeMode
public typealias QuillGtkRuntimeAvailability = QuillBackendRuntimeAvailability
public typealias QuillGtkBackendStatus = QuillBackendRuntimeStatus

public enum QuillGtkBackend: QuillBackend {
    public static let identifier: QuillBackendIdentifier = .gtk
}

public typealias QuillGtkApp = QuillBackendApp<QuillGtkBackend>

#if os(Linux)
public enum QuillGtkPaintAdapter {
    private static let lock = NSLock()
    private static var installed = false

    public static func install() {
        lock.withLock {
            guard !installed else { return }
            gtkSetButtonPaintHook { cairoContext, width, height, state in
                let context = QuillGtkCairoPaintContext(cairoContext: cairoContext)
                let paintState = PaintControlState(
                    isPressed: state.isPressed,
                    isFocused: state.isFocused,
                    isDisabled: state.isDisabled,
                    isHovered: state.isHovered,
                    isDefault: state.isDefault
                )
                MacButtonPaint().paint(
                    into: context,
                    frame: PaintRect(x: 0, y: 0, width: width, height: height),
                    state: paintState
                )
            }
            installed = true
        }
    }
}
#endif
