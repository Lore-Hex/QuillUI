//
// QuillUI Linux shim for `Accelerate` -- vDSP_desamp.
//
// Faithful pure-Swift port of Accelerate's FIR-based decimation routine, used by
// SignalServiceKit's AudioWaveformSampler (AudioWaveform.swift) to produce the
// audio-waveform downsample. No SIMD/hardware path, but numerically equivalent.
//
// Semantics (per Apple docs): for each output sample n,
//     C[n] = sum_{p in 0..<P} A[n*DF + p] * F[p]
// i.e. an FIR filter F of length P applied with decimation factor DF. Signal
// uses a moving-average filter (F[p] == 1/DF), giving a block-average downsample.
//
// vDSP_Stride (Int) and vDSP_Length (UInt) are already declared in
// Accelerate.swift in this same target, so they are NOT redeclared here.
//
#if os(Linux)
import Foundation

public func vDSP_desamp(
    _ __A: UnsafePointer<Float>,
    _ __DF: vDSP_Stride,
    _ __F: UnsafePointer<Float>,
    _ __C: UnsafeMutablePointer<Float>,
    _ __N: vDSP_Length,
    _ __P: vDSP_Length
) {
    let outCount = Int(__N)
    let filterLength = Int(__P)
    let decimation = Int(__DF)
    for n in 0..<outCount {
        var acc: Float = 0
        let base = n * decimation
        for p in 0..<filterLength {
            acc += __A[base + p] * __F[p]
        }
        __C[n] = acc
    }
}
#endif
