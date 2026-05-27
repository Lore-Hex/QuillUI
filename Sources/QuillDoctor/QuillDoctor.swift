import Foundation
import SwiftParser
import SwiftSyntax

/// Scans a Swift project for `import ModuleName` statements and reports
/// which modules are covered by QuillUI's compatibility layer.
///
/// This is the engine behind the `quill-doctor` CLI. The library is kept
/// separate from the CLI binary so tests can drive the scan in-process
/// without spawning subprocesses.
public struct QuillDoctor {
    public init() {}

    /// Modules considered covered by default even when they don't appear as
    /// a heading in the coverage matrix. These are Swift stdlib / Foundation
    /// pieces that ship on Linux directly and don't need a QuillUI shim, plus
    /// QuillUI's own internal modules that aren't external Apple frameworks.
    public static let alwaysCoveredBaseline: Set<String> = [
        // Swift stdlib / runtime
        "Swift", "_Concurrency", "_StringProcessing", "RegexBuilder",
        // Foundation umbrella (works on Linux via swift-corelibs-foundation)
        "Foundation", "FoundationEssentials", "FoundationNetworking", "FoundationXML",
        // Dispatch / platform stdlibs
        "Dispatch", "Darwin", "Glibc", "Musl", "ucrt", "WinSDK", "ObjectiveC",
        // Swift Testing / XCTest
        "Testing", "XCTest"
    ]

    public func scan(
        projectRoot: URL,
        coverageDocPath: URL,
        fileManager: FileManager = .default,
        additionalCoveredBaseline: Set<String> = []
    ) throws -> QuillDoctorReport {
        let importsByModule = try collectImports(in: projectRoot, fileManager: fileManager)
        var coveredModules = try parseCoveredModules(coverageDoc: coverageDocPath)
        coveredModules.formUnion(Self.alwaysCoveredBaseline)
        coveredModules.formUnion(additionalCoveredBaseline)

        var statuses: [QuillDoctorReport.ModuleStatus] = []
        for (module, files) in importsByModule {
            let status: QuillDoctorReport.ModuleStatus.Status =
                coveredModules.contains(module) ? .covered : .missing
            statuses.append(.init(
                module: module,
                status: status,
                usedInFiles: Array(files).sorted()
            ))
        }
        statuses.sort { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status.rank < rhs.status.rank }
            return lhs.module < rhs.module
        }
        return QuillDoctorReport(modules: statuses)
    }

    private func collectImports(
        in projectRoot: URL,
        fileManager: FileManager
    ) throws -> [String: Set<String>] {
        let normalized = projectRoot.resolvingSymlinksInPath()
        var importsByModule: [String: Set<String>] = [:]

        guard let enumerator = fileManager.enumerator(
            at: normalized,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return importsByModule
        }

        let rootPathWithSlash = normalized.path.hasSuffix("/")
            ? normalized.path
            : normalized.path + "/"

        for case let fileURL as URL in enumerator {
            let resolved = fileURL.resolvingSymlinksInPath()
            let resourceValues = try resolved.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            guard resolved.pathExtension == "swift" else { continue }

            let source: String
            do {
                source = try String(contentsOf: resolved, encoding: .utf8)
            } catch {
                continue
            }

            let tree = Parser.parse(source: source)
            let collector = ImportCollector(viewMode: .sourceAccurate)
            collector.walk(tree)

            let relativePath: String
            if resolved.path.hasPrefix(rootPathWithSlash) {
                relativePath = String(resolved.path.dropFirst(rootPathWithSlash.count))
            } else {
                relativePath = resolved.lastPathComponent
            }

            for module in collector.imports {
                importsByModule[module, default: []].insert(relativePath)
            }
        }
        return importsByModule
    }

    private func parseCoveredModules(coverageDoc: URL) throws -> Set<String> {
        let contents = try String(contentsOf: coverageDoc, encoding: .utf8)
        var modules: Set<String> = []
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("## ") else { continue }
            let heading = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            // Examples: "SwiftUI", "Network", "PhotosUI and Photos",
            // "Re-export-only Apple shims".
            // Skip meta headings (lowercased / hyphenated-many-words).
            let firstWord = heading.split(separator: " ").first.map(String.init) ?? heading
            if Self.looksLikeModuleName(firstWord) {
                modules.insert(firstWord)
            }
            if heading.contains(" and ") {
                let parts = heading.components(separatedBy: " and ")
                for part in parts {
                    let partTrimmed = part.trimmingCharacters(in: .whitespaces)
                    let candidate = partTrimmed.split(separator: " ").first.map(String.init) ?? partTrimmed
                    if Self.looksLikeModuleName(candidate) {
                        modules.insert(candidate)
                    }
                }
            }
        }
        return modules
    }

    /// A heuristic: Swift module names are typically PascalCase or start with
    /// an uppercase letter, contain no whitespace, and are short-ish. This
    /// filters out meta-section headings like "Re-export-only" that aren't
    /// real module names.
    private static func looksLikeModuleName(_ candidate: String) -> Bool {
        guard let first = candidate.first else { return false }
        guard first.isUppercase || first.isLowercase else { return false }
        // Modules are typically a single word; reject anything with hyphens
        // that look like prose.
        let hyphenCount = candidate.filter { $0 == "-" }.count
        if hyphenCount > 1 { return false }
        return true
    }
}

// MARK: - Report

public struct QuillDoctorReport: Equatable, Codable {
    public struct ModuleStatus: Equatable, Codable {
        public enum Status: String, Equatable, Codable {
            case covered
            case missing

            fileprivate var rank: Int {
                switch self {
                case .missing: return 0
                case .covered: return 1
                }
            }
        }

        public let module: String
        public let status: Status
        public let usedInFiles: [String]

        enum CodingKeys: String, CodingKey {
            case module = "name"
            case status
            case usedInFiles = "used_in_files"
        }
    }

    public let modules: [ModuleStatus]

    enum CodingKeys: String, CodingKey {
        case modules
        case coveredCount = "covered_count"
        case missingCount = "missing_count"
    }

    public init(modules: [ModuleStatus]) {
        self.modules = modules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.modules = try container.decode([ModuleStatus].self, forKey: .modules)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coveredCount, forKey: .coveredCount)
        try container.encode(missingCount, forKey: .missingCount)
        // Sort modules alphabetically as required by acceptance criteria
        let sortedModules = modules.sorted { $0.module < $1.module }
        try container.encode(sortedModules, forKey: .modules)
    }

    public var hasMissing: Bool {
        modules.contains { $0.status == .missing }
    }

    public var coveredCount: Int { modules.filter { $0.status == .covered }.count }
    public var missingCount: Int { modules.filter { $0.status == .missing }.count }

    /// Human-readable report suitable for printing to stdout.
    public func formattedReport() -> String {
        var lines: [String] = []
        lines.append("=== quill-doctor coverage report ===")
        lines.append("")

        let missing = modules.filter { $0.status == .missing }
        if !missing.isEmpty {
            lines.append("MISSING (\(missing.count)) — these modules import paths have no QuillUI compatibility surface yet:")
            for m in missing {
                let files = m.usedInFiles.prefix(3).joined(separator: ", ")
                let suffix = m.usedInFiles.count > 3 ? " (+\(m.usedInFiles.count - 3) more)" : ""
                lines.append("  - \(m.module)")
                lines.append("      used in: \(files)\(suffix)")
            }
            lines.append("")
        }

        let covered = modules.filter { $0.status == .covered }
        if !covered.isEmpty {
            lines.append("COVERED (\(covered.count)) — modules with at least a section in the QuillUI coverage matrix:")
            for m in covered {
                lines.append("  - \(m.module)")
            }
            lines.append("")
        }

        lines.append("Summary: \(coveredCount) covered, \(missingCount) missing.")
        if missingCount > 0 {
            lines.append("Each MISSING module is a candidate ticket — add a section in docs/apple-package-function-coverage.md and start porting the API surface.")
        }
        return lines.joined(separator: "\n")
    }

    /// Markdown-formatted ticket list, one ticket per missing module. Suitable
    /// for piping into `gh issue create` or copying into a roadmap.
    public func ticketMarkdown() -> String {
        var lines: [String] = []
        let missing = modules.filter { $0.status == .missing }.sorted { $0.module < $1.module }
        guard !missing.isEmpty else {
            return "_All scanned imports are covered. No tickets to generate._\n"
        }
        lines.append("# QuillUI coverage tickets")
        lines.append("")
        lines.append("Auto-generated by `quill-doctor`. One ticket per Swift module that is imported by the scanned project but has no section in the QuillUI coverage matrix.")
        lines.append("")
        for m in missing {
            lines.append("## Add coverage for `\(m.module)`")
            lines.append("")
            lines.append("Module imported by the project but missing from `docs/apple-package-function-coverage.md`.")
            lines.append("")
            lines.append("**Used in:**")
            for file in m.usedInFiles.prefix(10) {
                lines.append("- `\(file)`")
            }
            if m.usedInFiles.count > 10 {
                lines.append("- _(\(m.usedInFiles.count - 10) more)_")
            }
            lines.append("")
            lines.append("**Acceptance criteria:**")
            lines.append("- [ ] `## \(m.module)` section added to `docs/apple-package-function-coverage.md`.")
            lines.append("- [ ] Initial compile-only Swift shim target added (if no real implementation exists yet).")
            lines.append("- [ ] At least one row marked `Compile-only` or higher in the coverage table.")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Visitor

private final class ImportCollector: SyntaxVisitor {
    var imports: Set<String> = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        // `import Foundation.NSURL` — take the first component as the module
        // name.
        if let firstComponent = node.path.first {
            imports.insert(firstComponent.name.text)
        }
        return .skipChildren
    }
}
