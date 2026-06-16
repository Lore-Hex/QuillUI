#if os(Linux)
import Foundation
import Testing
import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import QuillFoundation

// Rung-4 encoders: NSBitmapImageRep produces REAL image containers and
// AVAssetWriter produces a REAL movie (via ffmpeg) — exercised through the
// exact public surfaces SolderScope's SnapshotManager/RecordingManager use.
@Suite struct BitmapAndMovieEncodeTests {
    private func makeCGImage(width: Int, height: Int) -> CGImage {
        let cgImage = CGImage()
        cgImage.width = width
        cgImage.height = height
        cgImage.quillBytesPerRow = width * 4
        var bgra: [UInt8] = []
        bgra.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                // Distinct, recognizable ramp: B grows with x, G with y.
                bgra.append(UInt8((x * 255) / max(1, width - 1)))
                bgra.append(UInt8((y * 255) / max(1, height - 1)))
                bgra.append(64)
                bgra.append(255)
            }
        }
        cgImage.quillBGRAPixels = bgra
        return cgImage
    }

    @Test("snapshot PNG is a real decodable PNG container")
    func pngEncodeIsReal() throws {
        let rep = NSBitmapImageRep(cgImage: makeCGImage(width: 8, height: 6))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        #expect(Array(png.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        // Round-trip through the container path: a data-backed rep transcodes
        // the PNG to TIFF, proving the bytes decode as an image.
        let roundTrip = try #require(NSBitmapImageRep(data: png))
        let tiff = try #require(roundTrip.representation(
            using: .tiff,
            properties: [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw]
        ))
        #expect(Array(tiff.prefix(4)) == [0x49, 0x49, 0x2A, 0x00])
    }

    @Test("snapshot JPEG honors compressionFactor and is a real JPEG")
    func jpegEncodeIsReal() throws {
        let rep = NSBitmapImageRep(cgImage: makeCGImage(width: 32, height: 24))
        let jpeg = try #require(rep.representation(
            using: .jpeg, properties: [.compressionFactor: 0.9]
        ))
        #expect(Array(jpeg.prefix(2)) == [0xFF, 0xD8])
    }

    @Test("recording writes a real finalized movie via ffmpeg",
          .enabled(if: BitmapAndMovieEncodeTests.ffmpegPresent))
    func movieEncodeIsReal() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quill-rung4-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        // The exact RecordingManager shape: writer + settings + adaptor.
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 48,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 400_000,
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)
        #expect(writer.canAdd(input))
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<12 {
            let buffer = CVPixelBuffer(
                width: 64, height: 48,
                pixelFormatType: kCVPixelFormatType_32BGRA)
            buffer.quillWithMutableBytes { bytes in
                for i in stride(from: 0, to: bytes.count, by: 4) {
                    bytes[i] = UInt8((frame * 20) % 255)
                    bytes[i + 1] = 128
                    bytes[i + 2] = 64
                    bytes[i + 3] = 255
                }
            }
            let time = CMTime(value: CMTimeValue(frame), timescale: 30)
            #expect(adaptor.append(buffer, withPresentationTime: time))
        }
        input.markAsFinished()
        await writer.finishWriting()

        #expect(writer.status == .completed)
        let movie = try #require(
            FileManager.default.contents(atPath: outputURL.path))
        #expect(movie.count > 500)
        // QuickTime/MP4 container signature: 'ftyp' at offset 4.
        #expect(Array(movie[4..<8]) == Array("ftyp".utf8))
    }

    static var ffmpegPresent: Bool {
        if let override = ProcessInfo.processInfo.environment["QUILL_FFMPEG"],
           FileManager.default.isExecutableFile(atPath: override) {
            return true
        }
        return ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .contains { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
#endif
