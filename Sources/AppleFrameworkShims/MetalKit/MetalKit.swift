import Foundation
@_exported import Metal
@_exported import QuillFoundation

public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>

public struct matrix_float4x4: Sendable {
    public var columns: (simd_float4, simd_float4, simd_float4, simd_float4)

    public init(_ columns: (simd_float4, simd_float4, simd_float4, simd_float4)) {
        self.columns = columns
    }
}

public typealias simd_float4x4 = matrix_float4x4

public let matrix_identity_float4x4 = matrix_float4x4((
    simd_float4(1, 0, 0, 0),
    simd_float4(0, 1, 0, 0),
    simd_float4(0, 0, 1, 0),
    simd_float4(0, 0, 0, 1)
))

public func matrix_multiply(_ lhs: matrix_float4x4, _ rhs: matrix_float4x4) -> matrix_float4x4 {
    func value(_ matrix: matrix_float4x4, _ row: Int, _ column: Int) -> Float {
        let c: simd_float4
        switch column {
        case 0: c = matrix.columns.0
        case 1: c = matrix.columns.1
        case 2: c = matrix.columns.2
        default: c = matrix.columns.3
        }
        return c[row]
    }

    func cell(_ row: Int, _ column: Int) -> Float {
        (0 ..< 4).reduce(Float(0)) { result, index in
            result + value(lhs, row, index) * value(rhs, index, column)
        }
    }

    return matrix_float4x4((
        simd_float4(cell(0, 0), cell(1, 0), cell(2, 0), cell(3, 0)),
        simd_float4(cell(0, 1), cell(1, 1), cell(2, 1), cell(3, 1)),
        simd_float4(cell(0, 2), cell(1, 2), cell(2, 2), cell(3, 2)),
        simd_float4(cell(0, 3), cell(1, 3), cell(2, 3), cell(3, 3))
    ))
}

public final class MTKTextureLoader {
    public struct Option: RawRepresentable, Hashable, Sendable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let SRGB = Option(rawValue: "MTKTextureLoaderOptionSRGB")
    }

    private let device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }

    public func newTexture(cgImage: CGImage, options: [Option: Any]? = nil) throws -> MTLTexture {
        _ = options
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(1, cgImage.width),
            height: max(1, cgImage.height),
            mipmapped: false
        )
        return device.makeTexture(descriptor: descriptor) ?? QuillMTLTexture(descriptor: descriptor)
    }
}
