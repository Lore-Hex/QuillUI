import CoreImage
import CoreVideo
import Accelerate

final class FrameProcessor: @unchecked Sendable {
    private let width: Int
    private let height: Int
    private var integrationLevel: IntegrationLevel

    // Ring buffer for frame integration
    private var frameBuffer: [[Float]]
    private var bufferIndex: Int = 0
    private var bufferCount: Int = 0

    // Accumulated buffer for fast averaging
    private var accumulatorR: [Float]
    private var accumulatorG: [Float]
    private var accumulatorB: [Float]

    // Output buffer
    private var outputBuffer: [UInt8]

    private let lock = NSLock()

    init(width: Int, height: Int, integrationLevel: IntegrationLevel) {
        self.width = width
        self.height = height
        self.integrationLevel = integrationLevel

        let pixelCount = width * height

        // Initialize buffers
        self.frameBuffer = []
        self.accumulatorR = [Float](repeating: 0, count: pixelCount)
        self.accumulatorG = [Float](repeating: 0, count: pixelCount)
        self.accumulatorB = [Float](repeating: 0, count: pixelCount)
        self.outputBuffer = [UInt8](repeating: 0, count: pixelCount * 4)

        setupBuffers()
    }

    private func setupBuffers() {
        let pixelCount = width * height
        let n = integrationLevel.rawValue

        frameBuffer = (0..<n).map { _ in
            [Float](repeating: 0, count: pixelCount * 3)
        }
        bufferIndex = 0
        bufferCount = 0

        // Reset accumulators
        accumulatorR = [Float](repeating: 0, count: pixelCount)
        accumulatorG = [Float](repeating: 0, count: pixelCount)
        accumulatorB = [Float](repeating: 0, count: pixelCount)
    }

    func setIntegrationLevel(_ level: IntegrationLevel) {
        lock.lock()
        defer { lock.unlock() }

        if level != integrationLevel {
            integrationLevel = level
            setupBuffers()
        }
    }

    func process(pixelBuffer: CVPixelBuffer) -> CIImage {
        // If no integration, just return the image directly
        if integrationLevel == .one {
            return CIImage(cvPixelBuffer: pixelBuffer)
        }

        // Verify buffer dimensions match our expected size
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)

        if bufferWidth != width || bufferHeight != height {
            // Dimensions don't match, skip integration
            return CIImage(cvPixelBuffer: pixelBuffer)
        }

        lock.lock()
        defer { lock.unlock() }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return CIImage(cvPixelBuffer: pixelBuffer)
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelCount = width * height
        let n = integrationLevel.rawValue

        // Verify we have enough data
        let requiredBytes = (height - 1) * bytesPerRow + width * 4
        let bufferSize = CVPixelBufferGetDataSize(pixelBuffer)
        if bufferSize < requiredBytes {
            return CIImage(cvPixelBuffer: pixelBuffer)
        }

        // Extract current frame into float arrays
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        var currentR = [Float](repeating: 0, count: pixelCount)
        var currentG = [Float](repeating: 0, count: pixelCount)
        var currentB = [Float](repeating: 0, count: pixelCount)

        // Convert BGRA to separate float channels
        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * bytesPerRow + x * 4
                let dstIndex = y * width + x

                currentB[dstIndex] = Float(ptr[srcIndex])
                currentG[dstIndex] = Float(ptr[srcIndex + 1])
                currentR[dstIndex] = Float(ptr[srcIndex + 2])
            }
        }

        // If buffer is full, subtract oldest frame from accumulator
        if bufferCount == n {
            let oldIndex = bufferIndex
            let oldFrame = frameBuffer[oldIndex]

            for i in 0..<pixelCount {
                accumulatorR[i] -= oldFrame[i * 3]
                accumulatorG[i] -= oldFrame[i * 3 + 1]
                accumulatorB[i] -= oldFrame[i * 3 + 2]
            }
        }

        // Add current frame to accumulator and store in buffer
        for i in 0..<pixelCount {
            accumulatorR[i] += currentR[i]
            accumulatorG[i] += currentG[i]
            accumulatorB[i] += currentB[i]

            frameBuffer[bufferIndex][i * 3] = currentR[i]
            frameBuffer[bufferIndex][i * 3 + 1] = currentG[i]
            frameBuffer[bufferIndex][i * 3 + 2] = currentB[i]
        }

        // Update buffer state
        bufferIndex = (bufferIndex + 1) % n
        if bufferCount < n {
            bufferCount += 1
        }

        // Compute average and write to output buffer
        let divisor = Float(bufferCount)

        for y in 0..<height {
            for x in 0..<width {
                let srcIndex = y * width + x
                let dstIndex = (y * width + x) * 4

                outputBuffer[dstIndex] = UInt8(clamping: Int(accumulatorB[srcIndex] / divisor))
                outputBuffer[dstIndex + 1] = UInt8(clamping: Int(accumulatorG[srcIndex] / divisor))
                outputBuffer[dstIndex + 2] = UInt8(clamping: Int(accumulatorR[srcIndex] / divisor))
                outputBuffer[dstIndex + 3] = 255
            }
        }

        // Create CIImage from output buffer
        let data = Data(outputBuffer)
        let ciImage = CIImage(
            bitmapData: data,
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .BGRA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        return ciImage
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }

        bufferIndex = 0
        bufferCount = 0

        let pixelCount = width * height
        accumulatorR = [Float](repeating: 0, count: pixelCount)
        accumulatorG = [Float](repeating: 0, count: pixelCount)
        accumulatorB = [Float](repeating: 0, count: pixelCount)
    }
}
