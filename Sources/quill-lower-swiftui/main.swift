import Foundation
import QuillSourceLowering

@main
struct QuillLowerSwiftUI {
    static func main() {
        let arguments = CommandLine.arguments
        let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-lower-swiftui"

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
            let visited = try SwiftUILowering().lowerInPlace(sourceDir: sourceDir)
            let summary = """
            Lowered generic SwiftUI Linux source in:
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

        Applies conservative, app-agnostic SwiftUI source cleanup to a generated
        source copy before building it with QuillUI on Linux. This is the
        structured replacement for the regex transformations in
        scripts/lower-swiftui-source-for-linux.sh.

        Edits in place — never point at an app's upstream source tree. Use
        against a generated copy produced by the upstream-fetch / profile
        pipelines.

        Currently lowers:
          @main, @MainActor                  attribute removal (decl + inline type)
          @Observable                        -> QuillObservableObject + @QuillPublished
          : View, Sendable                   -> : View
          #Preview blocks                    deleted at top level
          os(macOS)                          -> (os(macOS) || os(Linux)) in #if conditions
        """
        stream.write(Data((usage + "\n").utf8))
    }
}
