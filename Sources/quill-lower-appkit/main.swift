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
            Lowered AppKit / Objective-C target-action source in:
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

        Applies app-agnostic AppKit / Objective-C target-action source lowering to
        a generated source copy so unmodified macOS app source recompiles against
        the QuillAppKit shadow stack on Linux (which has no Objective-C runtime).
        Companion to quill-lower-swiftui.

        Edits in place — never point at an app's upstream source tree. Use against
        a generated copy produced by the upstream-fetch / profile pipelines.

        Currently lowers:
          @objc / @objcMembers / @IBAction / @IBOutlet / @IBInspectable
          @IBDesignable / @NSManaged / @GKInspectable / @NSApplicationMain
                                             attribute removal
          #selector(x)                       -> Selector("x")   (opaque token)
          classes with @objc actions         + QuillActionDispatching conformance
        """
        stream.write(Data((usage + "\n").utf8))
    }
}
