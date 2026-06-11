#if os(Linux)
import AppKit

public enum ObjcUtils {
    public static func windowResizeNorthWestSouthEastCursor() -> NSCursor? {
        NSCursor.resizeLeftRight
    }

    public static func windowResizeNorthEastSouthWestCursor() -> NSCursor? {
        NSCursor.resizeLeftRight
    }
}
#endif
