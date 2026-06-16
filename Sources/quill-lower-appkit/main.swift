import Foundation
import QuillSourceLowering

@main
struct QuillLowerAppKit {
    static func main() {
        let arguments = CommandLine.arguments
        let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-lower-appkit"

        guard arguments.count == 2 else {
            emitUsage(toolName: toolName, to: FileHandle.standardError)
            exit(64)
        }

        let sourceDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            FileHandle.standardError.write(
                Data("Generated source directory does not exist: \(sourceDir.path)\n".utf8)
            )
            exit(66)
        }

        do {
            let visited = try AppKitLowering().lowerInPlace(sourceDir: sourceDir)
            let summary = """
            Lowered AppKit target-action source for Linux in:
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
        Usage: \(toolName) GENERATED_SOURCE_DIR

        Applies automatic, app-agnostic AppKit target-action lowering to a
        generated/vendored macOS app source copy before building it against the
        QuillAppKit shadow on Linux (which has no Objective-C runtime). This is
        the AppKit companion to quill-lower-swiftui; the long-lived ground truth
        is the QuillSourceLowering.AppKitLowering library.

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
