//
// QuillUI Linux shim for `Accelerate` — concrete symbols added as
// SignalServiceKit references surface. The vDSP routines below are the subset
// AudioWaveformSampler uses; they are FAITHFUL pure-math implementations (no
// SIMD/Accelerate hardware path, but numerically equivalent), since the audio
// waveform is real user-visible output. Part of the Signal-iOS -> QuillOS port.
//
import Foundation

// vDSP scalar typealiases (Accelerate: vDSP_Length = UInt, vDSP_Stride = Int).
public typealias vDSP_Length = UInt
public typealias vDSP_Stride = Int

public typealias vImagePixelCount = UInt
public typealias vImage_Flags = UInt
public typealias vImage_Error = Int

public let kvImageNoError: vImage_Error = 0
public let kvImageEdgeExtend: vImage_Flags = 1 << 1
public let kvImageDoNotTile: vImage_Flags = 1 << 4

public struct vImage_Buffer {
    public var data: UnsafeMutableRawPointer?
    public var height: vImagePixelCount
    public var width: vImagePixelCount
    public var rowBytes: Int

    public init(
        data: UnsafeMutableRawPointer? = nil,
        height: vImagePixelCount = 0,
        width: vImagePixelCount = 0,
        rowBytes: Int = 0
    ) {
        self.data = data
        self.height = height
        self.width = width
        self.rowBytes = rowBytes
    }
}

public struct vImage_YpCbCrToARGB {
    public init() {}
}

public struct vImage_YpCbCrPixelRange {
    public var Yp_bias: UInt8
    public var CbCr_bias: UInt8
    public var YpRangeMax: UInt8
    public var CbCrRangeMax: UInt8
    public var YpMax: UInt8
    public var YpMin: UInt8
    public var CbCrMax: UInt8
    public var CbCrMin: UInt8

    public init(
        Yp_bias: UInt8,
        CbCr_bias: UInt8,
        YpRangeMax: UInt8,
        CbCrRangeMax: UInt8,
        YpMax: UInt8,
        YpMin: UInt8,
        CbCrMax: UInt8,
        CbCrMin: UInt8
    ) {
        self.Yp_bias = Yp_bias
        self.CbCr_bias = CbCr_bias
        self.YpRangeMax = YpRangeMax
        self.CbCrRangeMax = CbCrRangeMax
        self.YpMax = YpMax
        self.YpMin = YpMin
        self.CbCrMax = CbCrMax
        self.CbCrMin = CbCrMin
    }
}

public var kvImage_YpCbCrToARGBMatrix_ITU_R_709_2: UnsafePointer<Float>? { nil }
public let kvImage420Yp8_Cb8_Cr8: UInt32 = 0
public let kvImageARGB8888: UInt32 = 1

public func vImageConvert_YpCbCrToARGB_GenerateConversion(
    _ matrix: UnsafePointer<Float>?,
    _ pixelRange: UnsafePointer<vImage_YpCbCrPixelRange>,
    _ info: UnsafeMutablePointer<vImage_YpCbCrToARGB>,
    _ sourceFormat: UInt32,
    _ destinationFormat: UInt32,
    _ flags: vImage_Flags
) -> vImage_Error {
    _ = (matrix, pixelRange, info, sourceFormat, destinationFormat, flags)
    return kvImageNoError
}

public func vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(
    _ srcYp: UnsafePointer<vImage_Buffer>,
    _ srcCb: UnsafePointer<vImage_Buffer>,
    _ srcCr: UnsafePointer<vImage_Buffer>,
    _ dest: UnsafePointer<vImage_Buffer>,
    _ info: UnsafePointer<vImage_YpCbCrToARGB>,
    _ permuteMap: UnsafePointer<UInt8>?,
    _ alpha: UInt8,
    _ flags: vImage_Flags
) -> vImage_Error {
    _ = (srcCb, srcCr, info, permuteMap, alpha, flags)
    guard let sourceData = srcYp.pointee.data, let destinationData = dest.pointee.data else {
        return kvImageNoError
    }
    let rows = min(Int(srcYp.pointee.height), Int(dest.pointee.height))
    for row in 0..<rows {
        let source = sourceData.advanced(by: row * srcYp.pointee.rowBytes)
        let destination = destinationData.advanced(by: row * dest.pointee.rowBytes)
        memset(destination, 0, dest.pointee.rowBytes)
        memcpy(destination, source, min(srcYp.pointee.rowBytes, dest.pointee.rowBytes))
    }
    return kvImageNoError
}

public func vImagePremultiplyData_Planar8(
    _ src: UnsafePointer<vImage_Buffer>,
    _ alpha: UnsafePointer<vImage_Buffer>,
    _ dest: UnsafePointer<vImage_Buffer>,
    _ flags: vImage_Flags
) -> vImage_Error {
    _ = (alpha, flags)
    guard let sourceData = src.pointee.data, let destinationData = dest.pointee.data else {
        return kvImageNoError
    }
    let rows = min(Int(src.pointee.height), Int(dest.pointee.height))
    for row in 0..<rows {
        memcpy(
            destinationData.advanced(by: row * dest.pointee.rowBytes),
            sourceData.advanced(by: row * src.pointee.rowBytes),
            min(src.pointee.rowBytes, dest.pointee.rowBytes)
        )
    }
    return kvImageNoError
}

public func vImageScale_ARGB8888(
    _ src: UnsafePointer<vImage_Buffer>,
    _ dest: UnsafePointer<vImage_Buffer>,
    _ tempBuffer: UnsafeMutableRawPointer?,
    _ flags: vImage_Flags
) -> vImage_Error {
    _ = (tempBuffer, flags)
    guard let sourceData = src.pointee.data, let destinationData = dest.pointee.data else {
        return kvImageNoError
    }
    let sourceWidth = max(1, Int(src.pointee.width))
    let sourceHeight = max(1, Int(src.pointee.height))
    let destWidth = max(1, Int(dest.pointee.width))
    let destHeight = max(1, Int(dest.pointee.height))
    for y in 0..<destHeight {
        let sourceY = min(sourceHeight - 1, y * sourceHeight / destHeight)
        let sourceRow = sourceData.advanced(by: sourceY * src.pointee.rowBytes)
        let destRow = destinationData.advanced(by: y * dest.pointee.rowBytes)
        for x in 0..<destWidth {
            let sourceX = min(sourceWidth - 1, x * sourceWidth / destWidth)
            memcpy(destRow.advanced(by: x * 4), sourceRow.advanced(by: sourceX * 4), 4)
        }
    }
    return kvImageNoError
}

public func vImageHorizontalReflect_ARGB8888(
    _ src: UnsafePointer<vImage_Buffer>,
    _ dest: UnsafePointer<vImage_Buffer>,
    _ flags: vImage_Flags
) -> vImage_Error {
    _ = flags
    guard let sourceData = src.pointee.data, let destinationData = dest.pointee.data else {
        return kvImageNoError
    }
    let width = Int(min(src.pointee.width, dest.pointee.width))
    let height = Int(min(src.pointee.height, dest.pointee.height))
    for y in 0..<height {
        let sourceRow = sourceData.advanced(by: y * src.pointee.rowBytes)
        let destRow = destinationData.advanced(by: y * dest.pointee.rowBytes)
        if sourceData == destinationData {
            var left = 0
            var right = width - 1
            var temp: UInt32 = 0
            while left < right {
                let leftPointer = destRow.advanced(by: left * 4)
                let rightPointer = destRow.advanced(by: right * 4)
                memcpy(&temp, leftPointer, 4)
                memcpy(leftPointer, rightPointer, 4)
                memcpy(rightPointer, &temp, 4)
                left += 1
                right -= 1
            }
        } else {
            for x in 0..<width {
                memcpy(destRow.advanced(by: x * 4), sourceRow.advanced(by: (width - 1 - x) * 4), 4)
            }
        }
    }
    return kvImageNoError
}

// C[i] = Float(A[i]) — convert 16-bit signed integer samples to single-precision.
public func vDSP_vflt16(
    _ __A: UnsafePointer<Int16>, _ __IA: vDSP_Stride,
    _ __C: UnsafeMutablePointer<Float>, _ __IC: vDSP_Stride,
    _ __N: vDSP_Length
) {
    for i in 0..<Int(__N) { __C[i * __IC] = Float(__A[i * __IA]) }
}

// C[i] = |A[i]| — element-wise absolute value.
public func vDSP_vabs(
    _ __A: UnsafePointer<Float>, _ __IA: vDSP_Stride,
    _ __C: UnsafeMutablePointer<Float>, _ __IC: vDSP_Stride,
    _ __N: vDSP_Length
) {
    for i in 0..<Int(__N) { __C[i * __IC] = abs(__A[i * __IA]) }
}

// C[i] = n * log10(A[i] / B[0]); n = 20 for amplitude (F != 0), 10 for power.
// Matches Accelerate's vDSP_vdbcon (single zero-dB reference in B).
public func vDSP_vdbcon(
    _ __A: UnsafePointer<Float>, _ __IA: vDSP_Stride,
    _ __B: UnsafePointer<Float>,
    _ __C: UnsafeMutablePointer<Float>, _ __IC: vDSP_Stride,
    _ __N: vDSP_Length, _ __F: UInt32
) {
    let reference = Double(__B[0])
    let scale: Double = (__F != 0) ? 20 : 10
    for i in 0..<Int(__N) {
        __C[i * __IC] = Float(scale * log10(Double(__A[i * __IA]) / reference))
    }
}

// D[i] = min(max(A[i], B[0]), C[0]) — clip each element to [low, high].
public func vDSP_vclip(
    _ __A: UnsafePointer<Float>, _ __IA: vDSP_Stride,
    _ __B: UnsafePointer<Float>, _ __C: UnsafePointer<Float>,
    _ __D: UnsafeMutablePointer<Float>, _ __ID: vDSP_Stride,
    _ __N: vDSP_Length
) {
    let low = __B[0], high = __C[0]
    for i in 0..<Int(__N) {
        __D[i * __ID] = Swift.min(Swift.max(__A[i * __IA], low), high)
    }
}

// C[0] = mean(A) — arithmetic mean of N elements.
public func vDSP_meanv(
    _ __A: UnsafePointer<Float>, _ __IA: vDSP_Stride,
    _ __C: UnsafeMutablePointer<Float>,
    _ __N: vDSP_Length
) {
    guard __N > 0 else { __C[0] = 0; return }
    var sum: Float = 0
    for i in 0..<Int(__N) { sum += __A[i * __IA] }
    __C[0] = sum / Float(__N)
}

public func vImageMatrixMultiply_ARGB8888(
    _ src: UnsafePointer<vImage_Buffer>,
    _ dest: UnsafePointer<vImage_Buffer>,
    _ matrix: UnsafePointer<Int16>,
    _ divisor: Int32,
    _ preBias: UnsafePointer<Int16>?,
    _ postBias: UnsafePointer<Int32>?,
    _ flags: vImage_Flags
) -> vImage_Error {
    _ = (matrix, divisor, preBias, postBias, flags)
    guard let sourceData = src.pointee.data, let destinationData = dest.pointee.data else {
        return kvImageNoError
    }

    let rows = min(Int(src.pointee.height), Int(dest.pointee.height))
    let sourceStride = src.pointee.rowBytes
    let destinationStride = dest.pointee.rowBytes
    let bytesPerRow = min(sourceStride, destinationStride)
    for row in 0..<rows {
        memcpy(
            destinationData.advanced(by: row * destinationStride),
            sourceData.advanced(by: row * sourceStride),
            bytesPerRow
        )
    }
    return kvImageNoError
}
