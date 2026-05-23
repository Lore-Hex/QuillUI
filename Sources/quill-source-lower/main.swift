import Foundation
import QuillSourceLowering

let arguments = CommandLine.arguments
let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-source-lower"

func emitUsage(to stream: FileHandle) {
    let usage = """
    Usage: \(toolName) SOURCE_DIR OUTPUT_DIR

    Creates a generated Linux source copy that keeps app sources unchanged
    while lowering SwiftData-only syntax to QuillData-compatible Swift via
    SwiftSyntax. This is the structured replacement for the regex
    transformations in scripts/lower-swiftdata-for-quilldata.sh.

    Currently lowers:
      @Model class Foo: X { ... }   -> class Foo: X, PersistentModel { ... }
      @Transient var value: T       -> var value: T
      #Predicate<Foo> { ... }       -> #QuillPredicate<Foo> { ... }

    The relationship init-body pruning the shell script performs is not yet
    implemented here; use the shell script when that rewrite is required.
    """
    stream.write(Data((usage + "\n").utf8))
}

guard arguments.count == 3 else {
    emitUsage(to: FileHandle.standardError)
    exit(64)
}

let sourceDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputDir = URL(fileURLWithPath: arguments[2], isDirectory: true)

var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: sourceDir.path, isDirectory: &isDirectory),
      isDirectory.boolValue else {
    FileHandle.standardError.write(
        Data("Source directory does not exist: \(sourceDir.path)\n".utf8)
    )
    exit(66)
}

if FileManager.default.fileExists(atPath: outputDir.path) {
    FileHandle.standardError.write(
        Data("""
        Output path already exists: \(outputDir.path)
        Choose a fresh generated directory so app sources are never overwritten.

        """.utf8)
    )
    exit(73)
}

do {
    try SwiftDataLowering().lowerDirectory(sourceDir: sourceDir, outputDir: outputDir)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(70)
}

// Match the shell script's success summary so tooling that greps for the
// "Lowered N Swift files" line continues to work.
let enumerator = FileManager.default.enumerator(
    at: outputDir,
    includingPropertiesForKeys: [.isRegularFileKey]
)
var swiftFileCount = 0
while let next = enumerator?.nextObject() as? URL {
    if next.pathExtension == "swift" {
        swiftFileCount += 1
    }
}

let summary = """
Lowered \(swiftFileCount) Swift files from:
  \(sourceDir.path)
to:
  \(outputDir.path)
"""
print(summary)
