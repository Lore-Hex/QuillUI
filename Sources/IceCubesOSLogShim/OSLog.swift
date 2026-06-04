#if os(Linux)
// `import OSLog` shim for the vendored IceCubes NetworkClient. Re-exports the
// repo's `os` shim (which provides `Logger`) so upstream's `import OSLog`
// resolves on Linux. macOS uses the SDK OSLog module. Linux-only so it never
// shadows the real framework.
@_exported import os
#endif
