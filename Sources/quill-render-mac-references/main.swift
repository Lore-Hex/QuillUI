import Foundation
import QuillPaint

// os(macOS), NOT canImport(CoreGraphics): this package ships a Linux
// CoreGraphics shim target, so in a unified build directory canImport()
// can flip true on Linux (the .swiftmodule is on the search path even
// without a declared dependency) while QuillPaintCoreGraphics' renderer
// types stay Apple-gated — breaking `swift test` on Linux. The tool is
// Apple-only by design; gate it on the platform, not module visibility.
#if os(macOS)
import QuillPaintCoreGraphics
#endif

@main
struct QuillRenderMacReferences {
    static func main() {
        #if os(macOS)
        let arguments = CommandLine.arguments
        let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-render-mac-references"

        var outputDir: URL? = nil
        var scale: Double = 2.0
        var i = 1
        while i < arguments.count {
            switch arguments[i] {
            case "--output", "-o":
                if i + 1 < arguments.count {
                    outputDir = URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
                    i += 2
                } else {
                    FileHandle.standardError.write(Data("--output requires a path argument\n".utf8))
                    exit(64)
                }
            case "--scale":
                if i + 1 < arguments.count, let value = Double(arguments[i + 1]), value > 0 {
                    scale = value
                    i += 2
                } else {
                    FileHandle.standardError.write(Data("--scale requires a positive number\n".utf8))
                    exit(64)
                }
            case "-h", "--help":
                Self.emitUsage(toolName: toolName, to: FileHandle.standardOutput)
                exit(0)
            default:
                FileHandle.standardError.write(Data("Unknown argument: \(arguments[i])\n".utf8))
                Self.emitUsage(toolName: toolName, to: FileHandle.standardError)
                exit(64)
            }
        }

        let resolvedOutput = outputDir ?? Self.defaultOutputDir()
        let renderer = MacReferenceRenderer(margin: 8, scale: scale)
        let manifest = MacReferenceManifest.entries

        do {
            for entry in manifest {
                let outputURL = resolvedOutput.appendingPathComponent("\(entry.name).png")
                try renderer.renderPNG(
                    control: entry.control,
                    frame: entry.size,
                    state: entry.state,
                    outputURL: outputURL
                )
                print("rendered \(outputURL.path)")
            }
            print("")
            print("Wrote \(manifest.count) reference snapshots to \(resolvedOutput.path)")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(70)
        }
        #else
        FileHandle.standardError.write(Data("""
        This tool requires CoreGraphics + ImageIO and only runs on Apple platforms.
        On Linux, reference snapshots ship pre-rendered in Tests/Fixtures/MacReference/.

        """.utf8))
        exit(78)
        #endif
    }

    #if os(macOS)
    /// Default output path: walk up from the cwd looking for a Package.swift
    /// alongside a Tests/ directory. If found, write to
    /// `Tests/Fixtures/MacReference/`. Otherwise fall back to ./MacReference/.
    static func defaultOutputDir() -> URL {
        let fm = FileManager.default
        var current = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<6 {
            let pkg = current.appendingPathComponent("Package.swift")
            let tests = current.appendingPathComponent("Tests", isDirectory: true)
            if fm.fileExists(atPath: pkg.path) && fm.fileExists(atPath: tests.path) {
                return tests.appendingPathComponent("Fixtures/MacReference", isDirectory: true)
            }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("MacReference", isDirectory: true)
    }

    static func emitUsage(toolName: String, to stream: FileHandle) {
        let usage = """
        Usage: \(toolName) [--output PATH] [--scale FACTOR]

        Renders the QuillPaint Mac-reference snapshot set as PNGs using the
        CoreGraphics backend. This is the canonical macOS reference for the
        strict Mac-reference visual verifier (Roadmap item 4); the Linux
        Cairo/Qt backends are validated against these PNGs.

        Options:
          --output PATH    Output directory. Default: walk up from the cwd
                           looking for a Package.swift, then write to
                           Tests/Fixtures/MacReference/.
          --scale FACTOR   Device-pixel scale. Default: 2.0 (retina).

        Exit codes:
          0  Success.
          64 Usage error.
          70 Renderer error.
          78 Tool unavailable on this platform (Apple-only).
        """
        stream.write(Data((usage + "\n").utf8))
    }
    #else
    static func emitUsage(toolName: String, to stream: FileHandle) {
        stream.write(Data("\(toolName): Apple-only tool.\n".utf8))
    }
    #endif
}
