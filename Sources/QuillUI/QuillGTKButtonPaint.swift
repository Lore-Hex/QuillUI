#if os(Linux)
import Foundation
import BackendGTK4
import QuillPaint
import QuillPaintCairo

enum QuillGTKButtonPaintAdapter {
    private static let lock = NSLock()
    private static var installed = false

    static func install() {
        lock.lock()
        defer { lock.unlock() }

        guard !installed else { return }

        gtkSetButtonPaintHook { cairoContext, width, height, state in
            let context = CairoPaintContext(pointer: cairoContext)
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
#endif
