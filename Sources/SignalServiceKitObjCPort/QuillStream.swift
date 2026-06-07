//
// SignalServiceKit Stream raw-pointer overloads for QuillOS (Track B).
//
// swift-corelibs Foundation imports OutputStream.write(_:maxLength:) and
// InputStream.read(_:maxLength:) with typed UInt8 pointers
// (UnsafePointer<UInt8> / UnsafeMutablePointer<UInt8>). Several SSK call sites
// pass the baseAddress of a withUnsafeBytes / withUnsafeMutableBytes buffer,
// which is an UnsafeRawPointer / UnsafeMutableRawPointer (and one passes an
// UnsafePointer<Int8>), so the bare-corelibs calls fail with "cannot convert
// ... to expected argument type 'Unsafe[Mutable]Pointer<UInt8>'":
//   OWSMultipart.write   outputStream.write(bufferPtr.baseAddress!, ...)
//   OWSMultipart.read    inputStream.read($0.baseAddress!, ...)
//   InputStream+SSK      self.read($0.baseAddress!, ...)
//   OutputStreamable     self.write(bytes /* UnsafePointer<Int8> */, ...)
//
// Add raw-pointer overloads that rebind to UInt8 and forward to the typed
// methods. These are same-module as SSK (linked via quill-signal-link-ports), so
// the call sites resolve them without an import. The Int8 site resolves too
// because UnsafePointer<Int8> converts to UnsafeRawPointer. No recursion: the
// forwarded call passes UnsafePointer<UInt8>, which exact-matches the base
// method, not these overloads. On Apple the real SignalServiceKit is used, so
// this file is Linux-only (the port dir is only added to the Linux SSK target).
//
import Foundation

// @_disfavoredOverload so each forwarded call below (a typed UInt8 pointer)
// resolves to the swift-corelibs base method, not back to these overloads --
// otherwise the typed<->raw pointer conversion makes the re-dispatch ambiguous.
// External callers pass a raw pointer (or UnsafePointer<Int8>), which only these
// overloads accept.
extension OutputStream {
    @_disfavoredOverload
    func write(_ buffer: UnsafeRawPointer, maxLength len: Int) -> Int {
        write(buffer.assumingMemoryBound(to: UInt8.self), maxLength: len)
    }
}

extension InputStream {
    @_disfavoredOverload
    func read(_ buffer: UnsafeMutableRawPointer, maxLength len: Int) -> Int {
        read(buffer.assumingMemoryBound(to: UInt8.self), maxLength: len)
    }
}
