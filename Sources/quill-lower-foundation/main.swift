import Foundation
import QuillSourceLowering

@main
struct QuillLowerFoundation {
    static func main() {
        let arguments = CommandLine.arguments
        let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-lower-foundation"

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
            let visited = try FoundationLowering().lowerInPlace(sourceDir: sourceDir)
            let summary = """
            Lowered Foundation compatibility source for Linux in:
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

        Applies conservative, app-agnostic Foundation compatibility lowering to
        a generated/vendored Apple-platform source copy before building it on
        Linux with swift-corelibs-foundation.

        Edits in place - never point it at an app's pristine source tree.

        Currently lowers:
          NSSortDescriptor(key:..., ascending:...) -> NSSortDescriptor.quillKey(..., ascending:...)
          sortDescriptor.key                     -> sortDescriptor.quillKey
        """
        stream.write(Data((usage + "\n").utf8))
    }
}
