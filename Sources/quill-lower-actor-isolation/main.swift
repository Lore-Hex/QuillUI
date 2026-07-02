import Foundation
import QuillSourceLowering

/// Opt-in CLI wrapper around ``ActorIsolationLowering``. It is intentionally a
/// *separate* tool from `quill-lower-swiftui`: actor-isolation stripping is the
/// `stripActorIsolation` opt-in (see ``SwiftUILowering/Options``) and must run
/// only for headless single-threaded profiles (Enchanted / Quill Chat on the
/// generic GTK backend). Apps that keep real Swift concurrency (Signal /
/// Telegram) never invoke this tool.
///
/// It edits the generated source copy in place — never point it at an app's
/// upstream tree. It runs *only* the actor-isolation pass; the always-on
/// SwiftUI/Foundation/AppKit lowering has already happened earlier in the
/// pipeline, so there is no double-processing of those rules here.
@main
struct QuillLowerActorIsolation {
    static func main() {
        let arguments = CommandLine.arguments
        let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-lower-actor-isolation"

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
            let visited = try ActorIsolationLowering().lowerInPlace(sourceDir: sourceDir)
            let summary = """
            Lowered actor-isolation concurrency in:
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

        Opt-in: removes Swift actor-isolation concurrency from a generated source
        copy so it can build against the headless single-threaded GTK backend
        (Enchanted / Quill Chat profile). This is the first-class replacement for
        the per-app Perl rewrite rules under
        scripts/profiles/enchanted-full-source/rewrite-rules/.

        Edits in place — never point at an app's upstream source tree. Apps that
        keep real Swift concurrency (Signal / Telegram) must NOT run this tool.

        Lowers:
          actor Name { ... }   -> final class Name { ... }
          nonisolated          modifier removal
          await <self/instance call>  -> await dropped
            (await on type-qualified receivers and trailing-closure calls is kept)
        """
        stream.write(Data((usage + "\n").utf8))
    }
}
