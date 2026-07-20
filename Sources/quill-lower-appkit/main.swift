import Foundation
import QuillSourceLowering

@main
struct QuillLowerAppKit {
    private enum Mode {
        case full
        case applicationDelegatesOnly
    }

    static func main() {
        let arguments = CommandLine.arguments
        let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-lower-appkit"
        let operands = Array(arguments.dropFirst())
        let mode: Mode
        let sourcePath: String
        if operands.count == 1 {
            mode = .full
            sourcePath = operands[0]
        } else if operands.count == 2, operands[0] == "--application-delegates-only" {
            mode = .applicationDelegatesOnly
            sourcePath = operands[1]
        } else {
            emitUsage(toolName: toolName, to: FileHandle.standardError)
            exit(64)
        }

        let sourceDir = URL(fileURLWithPath: sourcePath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            FileHandle.standardError.write(
                Data("Generated source directory does not exist: \(sourceDir.path)\n".utf8)
            )
            exit(66)
        }

        do {
            let visited: Int
            let label: String
            switch mode {
            case .full:
                visited = try AppKitLowering().lowerInPlace(sourceDir: sourceDir)
                label = "AppKit target-action"
            case .applicationDelegatesOnly:
                visited = try ApplicationDelegateAdaptorLowering().lowerInPlace(sourceDir: sourceDir)
                label = "application-delegate adaptor"
            }
            let summary = """
            Lowered \(label) source for Linux in:
              \(sourceDir.path)
            Swift files processed: \(visited)
            """
            print(summary)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(70)
        }
    }

    private static func emitUsage(toolName: String, to stream: FileHandle) {
        let usage = """
        Usage: \(toolName) [--application-delegates-only] GENERATED_SOURCE_DIR

        Applies automatic, app-agnostic AppKit target-action lowering to a
        generated/vendored macOS app source copy before building it against the
        QuillAppKit shadow on Linux (which has no Objective-C runtime). This is
        the AppKit companion to quill-lower-swiftui; the long-lived ground truth
        is the QuillSourceLowering.AppKitLowering library.

        Pass --application-delegates-only for UIKit/SwiftUI app sources that
        need UIApplicationDelegateAdaptor construction but no Objective-C or
        target-action rewrites.

        Edits in place — point it at a vendored copy of upstream source produced
        by the upstream-fetch pipeline, never at a pristine checkout you keep.

        Lowers:
          @objc / @objcMembers / @IB* / @NSManaged    attribute removal
          #selector(x)                                 -> Selector("x")
                                                          (leading type qualifier normalized)
          each class with @objc actions                -> an injected class-body
                                                          quillPerform(_:with:) dispatch
                                                          (QuillSelectorDispatching)
        """
        stream.write(Data((usage + "\n").utf8))
    }
}
