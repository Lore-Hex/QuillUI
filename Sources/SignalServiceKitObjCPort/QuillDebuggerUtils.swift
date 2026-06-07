//
// SignalServiceKit ObjC port for QuillOS (Track B).
//
// DebuggerUtils.h (Debugging/) inline helpers. On Apple+DEBUG they detect and
// break into the debugger (or abort); on Linux there is no such hook, so these
// mirror the header's non-DEBUG inline definitions: no debugger is ever
// "attached" and trapping is a no-op.
//
import Foundation

/// Whether a debugger is attached to this process. Always false on Linux.
public func IsDebuggerAttached() -> Bool { false }

/// Break into the debugger if attached, otherwise abort. No-op on Linux.
public func TrapDebugger() {}
