import Foundation

public typealias compression_algorithm = Int32
public typealias compression_status = Int32

public let COMPRESSION_LZFSE: compression_algorithm = 0x801
public let COMPRESSION_LZ4: compression_algorithm = 0x100
public let COMPRESSION_ZLIB: compression_algorithm = 0x205
public let COMPRESSION_LZMA: compression_algorithm = 0x306

public let COMPRESSION_STATUS_ERROR: compression_status = -1
public let COMPRESSION_STATUS_OK: compression_status = 0
public let COMPRESSION_STATUS_END: compression_status = 1

public enum compression_stream_operation: Int32, Sendable {
    case encode = 0
    case decode = 1
}

public let COMPRESSION_STREAM_ENCODE = compression_stream_operation.encode
public let COMPRESSION_STREAM_DECODE = compression_stream_operation.decode

public enum compression_stream_flags: Int32, Sendable {
    case finalize = 1
}

public let COMPRESSION_STREAM_FINALIZE = compression_stream_flags.finalize

public struct compression_stream {
    public var dst_ptr: UnsafeMutablePointer<UInt8>?
    public var dst_size: Int
    public var src_ptr: UnsafePointer<UInt8>?
    public var src_size: Int
    public var state: UnsafeMutableRawPointer?

    public init(
        dst_ptr: UnsafeMutablePointer<UInt8>? = nil,
        dst_size: Int = 0,
        src_ptr: UnsafePointer<UInt8>? = nil,
        src_size: Int = 0,
        state: UnsafeMutableRawPointer? = nil
    ) {
        self.dst_ptr = dst_ptr
        self.dst_size = dst_size
        self.src_ptr = src_ptr
        self.src_size = src_size
        self.state = state
    }
}

public func compression_encode_scratch_buffer_size(_ algorithm: compression_algorithm) -> Int {
    _ = algorithm
    return 0
}

public func compression_decode_scratch_buffer_size(_ algorithm: compression_algorithm) -> Int {
    _ = algorithm
    return 0
}

public func compression_encode_buffer(
    _ dst_buffer: UnsafeMutablePointer<UInt8>,
    _ dst_size: Int,
    _ src_buffer: UnsafePointer<UInt8>,
    _ src_size: Int,
    _ scratch_buffer: UnsafeMutableRawPointer?,
    _ algorithm: compression_algorithm
) -> Int {
    _ = (scratch_buffer, algorithm)
    guard dst_size >= src_size else {
        return 0
    }
    memcpy(dst_buffer, src_buffer, src_size)
    return src_size
}

public func compression_decode_buffer(
    _ dst_buffer: UnsafeMutablePointer<UInt8>,
    _ dst_size: Int,
    _ src_buffer: UnsafePointer<UInt8>,
    _ src_size: Int,
    _ scratch_buffer: UnsafeMutableRawPointer?,
    _ algorithm: compression_algorithm
) -> Int {
    _ = (scratch_buffer, algorithm)
    let count = min(dst_size, src_size)
    memcpy(dst_buffer, src_buffer, count)
    return count
}

public func compression_stream_init(
    _ stream: UnsafeMutablePointer<compression_stream>,
    _ operation: compression_stream_operation,
    _ algorithm: compression_algorithm
) -> compression_status {
    _ = (operation, algorithm)
    stream.initialize(to: compression_stream())
    return COMPRESSION_STATUS_OK
}

public func compression_stream_process(
    _ stream: UnsafeMutablePointer<compression_stream>,
    _ flags: Int32
) -> compression_status {
    _ = flags
    guard let src = stream.pointee.src_ptr, let dst = stream.pointee.dst_ptr else {
        return COMPRESSION_STATUS_END
    }
    let count = min(stream.pointee.src_size, stream.pointee.dst_size)
    if count > 0 {
        memcpy(dst, src, count)
        stream.pointee.src_ptr = src.advanced(by: count)
        stream.pointee.dst_ptr = dst.advanced(by: count)
    }
    stream.pointee.src_size -= count
    stream.pointee.dst_size -= count
    return stream.pointee.src_size == 0 ? COMPRESSION_STATUS_END : COMPRESSION_STATUS_OK
}

public func compression_stream_destroy(_ stream: UnsafeMutablePointer<compression_stream>) {
    stream.deinitialize(count: 1)
}
