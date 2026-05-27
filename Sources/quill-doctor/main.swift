import Foundation
import QuillDoctor

@main
struct QuillDoctorCLI {
    static func main() {
        let arguments = CommandLine.arguments
        let toolName = (arguments.first as NSString?)?.lastPathComponent ?? "quill-doctor"

        guard arguments.count >= 2 else {
            emitUsage(toolName: toolName, to: FileHandle.standardError)
            exit(64)
        }

        let projectRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
        var coverageDocPath: URL? = nil
        var outputTickets = false
        var outputJSON = false

        var i = 2
        while i < arguments.count {
            switch arguments[i] {
            case "--coverage-doc":
                if i + 1 < arguments.count {
                    coverageDocPath = URL(fileURLWithPath: arguments[i + 1])
                    i += 2
                } else {
                    FileHandle.standardError.write(Data("--coverage-doc requires a path argument\n".utf8))
                    exit(64)
                }
            case "--tickets":
                outputTickets = true
                i += 1
            case "--json":
                outputJSON = true
                i += 1
            case "-h", "--help":
                emitUsage(toolName: toolName, to: FileHandle.standardOutput)
                exit(0)
            default:
                FileHandle.standardError.write(Data("Unknown argument: \(arguments[i])\n".utf8))
                emitUsage(toolName: toolName, to: FileHandle.standardError)
                exit(64)
            }
        }

        if outputTickets && outputJSON {
            FileHandle.standardError.write(Data("--tickets and --json are mutually exclusive\n".utf8))
            emitUsage(toolName: toolName, to: FileHandle.standardError)
            exit(64)
        }

        // If --coverage-doc wasn't passed, try to discover it relative to the
        // current working directory (the common case is running from inside
        // the QuillUI repo).
        let resolvedCoverageDoc: URL
        if let explicit = coverageDocPath {
            resolvedCoverageDoc = explicit
        } else if let discovered = Self.discoverCoverageDoc() {
            resolvedCoverageDoc = discovered
        } else {
            FileHandle.standardError.write(Data("""
            Could not find docs/apple-package-function-coverage.md.
            Pass --coverage-doc PATH explicitly, or run from inside a QuillUI
            checkout.

            """.utf8))
            exit(64)
        }

        var projectIsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: projectRoot.path, isDirectory: &projectIsDirectory),
              projectIsDirectory.boolValue else {
            FileHandle.standardError.write(Data("Project directory does not exist: \(projectRoot.path)\n".utf8))
            exit(66)
        }

        guard FileManager.default.fileExists(atPath: resolvedCoverageDoc.path) else {
            FileHandle.standardError.write(Data("Coverage doc does not exist: \(resolvedCoverageDoc.path)\n".utf8))
            exit(66)
        }

        do {
            let report = try QuillDoctor().scan(
                projectRoot: projectRoot,
                coverageDocPath: resolvedCoverageDoc
            )
            if outputJSON {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(report)
                print(String(data: data, encoding: .utf8)!)
            } else if outputTickets {
                print(report.ticketMarkdown())
            } else {
                print(report.formattedReport())
            }
            exit(report.hasMissing ? 1 : 0)
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(70)
        }
    }

    private static func discoverCoverageDoc() -> URL? {
        let fileManager = FileManager.default
        var current = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        for _ in 0..<6 {
            let candidate = current.appendingPathComponent("docs/apple-package-function-coverage.md")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private static func emitUsage(toolName: String, to stream: FileHandle) {
        let usage = """
        Usage: \(toolName) PROJECT_ROOT [--coverage-doc PATH] [--tickets | --json]

        Scans a Swift project for `import ModuleName` statements and reports
        which modules are covered by QuillUI's compatibility matrix.

        Arguments:
          PROJECT_ROOT          Path to the project root (any directory that
                                contains .swift sources, recursive).
          --coverage-doc PATH   Path to QuillUI's
                                docs/apple-package-function-coverage.md. If
                                omitted, the tool walks up from the current
                                working directory looking for a docs/ folder.
          --tickets             Emit a markdown ticket list (one per missing
                                module) instead of the human-readable report.
                                Pipe into `gh issue create --body-file -` or
                                paste into a roadmap.
          --json                Emit a structured JSON report. Alphabetically
                                sorted by module name. Mutually exclusive with
                                --tickets.

        Exit codes:
          0  All imported modules are covered.
          1  At least one imported module is missing.
          64 Usage error.
          66 Project or coverage doc not found.
          70 Internal error during scan.
        """
        stream.write(Data((usage + "\n").utf8))
    }
}
