// Real system zlib (libz) for SignalServiceKit's CRC32 + GzipStreamTransform.
// libz is available on Linux (zlib1g-dev) and macOS (SDK), so unlike the inert
// framework shims this exposes the genuine zlib C API — gzip/crc32 actually work.
#include <zlib.h>
