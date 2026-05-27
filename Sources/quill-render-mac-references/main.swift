import Foundation
import QuillPaint

#if canImport(CoreGraphics) && canImport(ImageIO)
import QuillPaintCoreGraphics
#endif

@main
struct QuillRenderMacReferences {
    static func main() {
        #if canImport(CoreGraphics) && canImport(ImageIO)
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
        let manifest = Self.referenceManifest()

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

    #if canImport(CoreGraphics) && canImport(ImageIO)
    /// The full reference manifest. Each entry produces one PNG. Add to this
    /// list whenever a new control or state combination needs a reference.
    static func referenceManifest() -> [ReferenceEntry] {
        let buttonSize = PaintSize(width: 80, height: 22)
        let wideButtonSize = PaintSize(width: 160, height: 22)

        return [
            ReferenceEntry(
                name: "button-normal",
                control: MacButtonPaint(),
                size: buttonSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "button-pressed",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isPressed: true)
            ),
            ReferenceEntry(
                name: "button-focused",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isFocused: true)
            ),
            ReferenceEntry(
                name: "button-hovered",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isHovered: true)
            ),
            ReferenceEntry(
                name: "button-disabled",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isDisabled: true)
            ),
            ReferenceEntry(
                name: "button-default",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isDefault: true)
            ),
            ReferenceEntry(
                name: "button-default-pressed",
                control: MacButtonPaint(),
                size: buttonSize,
                state: PaintControlState(isPressed: true, isDefault: true)
            ),
            ReferenceEntry(
                name: "button-wide-normal",
                control: MacButtonPaint(),
                size: wideButtonSize,
                state: .normal
            ),
            ReferenceEntry(
                name: "button-wide-focused-default",
                control: MacButtonPaint(),
                size: wideButtonSize,
                state: PaintControlState(isFocused: true, isDefault: true)
            )
        ]
    }

    struct ReferenceEntry {
        let name: String
        let control: PaintControl
        let size: PaintSize
        let state: PaintControlState
    }

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
