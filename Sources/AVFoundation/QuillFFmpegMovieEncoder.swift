#if os(Linux)
import Foundation

/// Real movie encoding for AVAssetWriter on Linux (rung 4): pipes raw BGRA
/// frames into an `ffmpeg` child process that encodes H.264 into the target
/// container. QuillOS is Debian/Armbian-only, where ffmpeg is one
/// `apt install ffmpeg` away — shipping a codec stack in-process (libav*)
/// would dwarf the rest of the dependency graph for the same result.
///
/// Honest constraints, documented rather than hidden:
/// - Constant frame rate: rawvideo over a pipe carries no per-frame PTS, so
///   frames are encoded at the configured rate (SolderScope appends at the
///   camera's delivery rate with `expectsMediaDataInRealTime`, which matches).
/// - `ffmpeg` missing → `AVAssetWriter.startWriting()` returns false with
///   `status == .failed` and a descriptive error, exactly the failure path
///   upstream code already handles.
final class QuillFFmpegMovieEncoder: @unchecked Sendable {
    private let process: Process
    private let stdinPipe: Pipe
    private let width: Int
    private let height: Int
    private let lock = NSLock()
    private var failed = false

    /// Locate ffmpeg: QUILL_FFMPEG override, then the Debian paths.
    static func ffmpegPath() -> String? {
        if let override = ProcessInfo.processInfo.environment["QUILL_FFMPEG"],
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        for candidate in ["/usr/bin/ffmpeg", "/usr/local/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    static var isAvailable: Bool { ffmpegPath() != nil }

    init?(
        outputURL: URL,
        width: Int,
        height: Int,
        framesPerSecond: Double,
        averageBitRate: Int?,
        maxKeyFrameInterval: Int?
    ) {
        guard width > 0, height > 0, let ffmpeg = Self.ffmpegPath() else { return nil }
        self.width = width
        self.height = height

        var arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "rawvideo",
            "-pixel_format", "bgra",
            "-video_size", "\(width)x\(height)",
            "-framerate", String(max(1.0, framesPerSecond)),
            "-i", "pipe:0",
            "-c:v", "libx264",
            "-preset", "veryfast",
            // Even dimensions + broad-decoder pixel format.
            "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2",
            "-pix_fmt", "yuv420p",
        ]
        if let averageBitRate, averageBitRate > 0 {
            arguments += ["-b:v", String(averageBitRate)]
        }
        if let maxKeyFrameInterval, maxKeyFrameInterval > 0 {
            arguments += ["-g", String(maxKeyFrameInterval)]
        }
        arguments.append(outputURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = arguments
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        // Keep stderr quiet unless it matters; loglevel error already filters.
        do {
            try process.run()
        } catch {
            return nil
        }
        self.process = process
        self.stdinPipe = stdinPipe
    }

    /// Write one BGRA frame. Mismatched geometry or a dead encoder returns
    /// false (mirrors `AVAssetWriterInputPixelBufferAdaptor.append`).
    func appendFrame(_ pixelBuffer: CVPixelBuffer) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !failed, process.isRunning,
              pixelBuffer.width == width, pixelBuffer.height == height else {
            return false
        }
        let frame = pixelBuffer.quillWithReadOnlyBytes { Data($0) }
        do {
            try stdinPipe.fileHandleForWriting.write(contentsOf: frame)
            return true
        } catch {
            failed = true
            return false
        }
    }

    /// Close the input and wait for ffmpeg to finalize the container.
    /// Returns true when the encoder exited cleanly.
    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        try? stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()
        return !failed && process.terminationStatus == 0
    }

    /// Abandon the encode (writer cancelled): terminate and reap.
    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        failed = true
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
}
#endif
