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
