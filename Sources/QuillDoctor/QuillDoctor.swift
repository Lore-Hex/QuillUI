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
    public static let version = "0.1.0"
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
        targetName: String? = nil,
        fileManager: FileManager = .default,
        additionalCoveredBaseline: Set<String> = []
    ) throws -> QuillDoctorReport {
        let scanRoot: URL
        if let targetName {
            scanRoot = try resolveSwiftPMTargetSourcePath(
                named: targetName,
                packageRoot: projectRoot,
                fileManager: fileManager
            )
        } else {
            scanRoot = projectRoot
        }

        let importsByModule = try collectImports(
            in: scanRoot,
            relativeTo: projectRoot,
            fileManager: fileManager
        )
        return try report(
            importsByModule: importsByModule,
            coverageDocPath: coverageDocPath,
            additionalCoveredBaseline: additionalCoveredBaseline
        )
    }

    /// Scans a workspace for multiple SwiftPM packages.
    public func scanWorkspace(
        workspaceRoot: URL,
        coverageDocPath: URL,
        fileManager: FileManager = .default,
        additionalCoveredBaseline: Set<String> = []
    ) throws -> QuillDoctorWorkspaceReport {
        let packageFiles = try findPackageFiles(in: workspaceRoot, fileManager: fileManager)
        var packageReports: [QuillDoctorWorkspaceReport.PackageReport] = []

        for packageFile in packageFiles {
            let packageDir = packageFile.deletingLastPathComponent()
            let packageName = packageDir.lastPathComponent
            let report = try scan(
                projectRoot: packageDir,
                coverageDocPath: coverageDocPath,
                fileManager: fileManager,
                additionalCoveredBaseline: additionalCoveredBaseline
            )
            packageReports.append(.init(packageName: packageName, report: report))
        }

        return QuillDoctorWorkspaceReport(packages: packageReports)
    }

    private func findPackageFiles(
        in root: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        var results: [URL] = []
        let normalized = root.resolvingSymlinksInPath()

        guard let enumerator = fileManager.enumerator(
            at: normalized,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let ignoredDirs = Set([".build", "node_modules", "Pods"])

        for case let fileURL as URL in enumerator {
            let lastComponent = fileURL.lastPathComponent

            if ignoredDirs.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }

            // Don't skip descendants after a hit: nested independent packages
            // (e.g. under Packages/ or External/) should each be reported.
            if lastComponent == "Package.swift" {
                results.append(fileURL)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    private func report(
        importsByModule: [String: Set<String>],
        coverageDocPath: URL,
        additionalCoveredBaseline: Set<String> = []
    ) throws -> QuillDoctorReport {
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
        in scanRoot: URL,
        relativeTo projectRoot: URL,
        fileManager: FileManager
    ) throws -> [String: Set<String>] {
        let normalizedScanRoot = scanRoot.resolvingSymlinksInPath()
        let normalizedProjectRoot = projectRoot.resolvingSymlinksInPath()
        var importsByModule: [String: Set<String>] = [:]

        guard let enumerator = fileManager.enumerator(
            at: normalizedScanRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return importsByModule
        }

        let projectRootPathWithSlash = normalizedProjectRoot.path.hasSuffix("/")
            ? normalizedProjectRoot.path
            : normalizedProjectRoot.path + "/"

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
            if resolved.path.hasPrefix(projectRootPathWithSlash) {
                relativePath = String(resolved.path.dropFirst(projectRootPathWithSlash.count))
            } else {
                relativePath = resolved.lastPathComponent
            }

            for module in collector.imports {
                importsByModule[module, default: []].insert(relativePath)
            }
        }
        return importsByModule
    }

    func resolveSwiftPMTargetSourcePath(
        named targetName: String,
        packageRoot: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let normalizedPackageRoot = packageRoot.resolvingSymlinksInPath()
        let manifest = normalizedPackageRoot.appendingPathComponent("Package.swift")
        guard fileManager.fileExists(atPath: manifest.path) else {
            throw QuillDoctorTargetResolutionError.packageManifestMissing(
                projectRoot: normalizedPackageRoot.path
            )
        }

        let packageDescription = try swiftPackageDescription(packageRoot: normalizedPackageRoot)
        let availableTargets = packageDescription.targets.map(\.name).sorted()
        guard let target = packageDescription.targets.first(where: { $0.name == targetName }) else {
            throw QuillDoctorTargetResolutionError.targetNotFound(
                name: targetName,
                availableTargets: availableTargets
            )
        }
        guard let path = target.path, !path.isEmpty else {
            throw QuillDoctorTargetResolutionError.targetPathMissing(name: targetName)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return normalizedPackageRoot
            .appendingPathComponent(path, isDirectory: true)
            .standardizedFileURL
    }

    private func swiftPackageDescription(packageRoot: URL) throws -> SwiftPackageDescription {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "package",
            "--package-path", packageRoot.path,
            "describe", "--type", "json"
        ]

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw QuillDoctorTargetResolutionError.packageDescribeFailed(
                projectRoot: packageRoot.path,
                details: error.localizedDescription
            )
        }
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            let failureDetails: String
            if let errorOutput, !errorOutput.isEmpty {
                failureDetails = errorOutput
            } else {
                failureDetails = "swift package describe exited with status \(process.terminationStatus)"
            }
            throw QuillDoctorTargetResolutionError.packageDescribeFailed(
                projectRoot: packageRoot.path,
                details: failureDetails
            )
        }

        do {
            return try JSONDecoder().decode(SwiftPackageDescription.self, from: outputData)
        } catch {
            throw QuillDoctorTargetResolutionError.packageDescribeFailed(
                projectRoot: packageRoot.path,
                details: "could not decode swift package describe output: \(error)"
            )
        }
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

public enum QuillDoctorTargetResolutionError: Error, Equatable, CustomStringConvertible {
    case packageManifestMissing(projectRoot: String)
    case packageDescribeFailed(projectRoot: String, details: String)
    case targetNotFound(name: String, availableTargets: [String])
    case targetPathMissing(name: String)

    public var description: String {
        switch self {
        case .packageManifestMissing(let projectRoot):
            return "--target requires PROJECT_ROOT to be a SwiftPM package with a Package.swift: \(projectRoot)"
        case .packageDescribeFailed(let projectRoot, let details):
            return "Could not describe SwiftPM package at \(projectRoot): \(details)"
        case .targetNotFound(let name, let availableTargets):
            let available = availableTargets.isEmpty
                ? "  (none)"
                : availableTargets.map { "  - \($0)" }.joined(separator: "\n")
            return """
            No SwiftPM target named '\(name)'.
            Available targets:
            \(available)
            """
        case .targetPathMissing(let name):
            return "SwiftPM target '\(name)' did not include a source path in swift package describe output."
        }
    }
}

private struct SwiftPackageDescription: Decodable {
    var targets: [SwiftPackageTarget]
}

private struct SwiftPackageTarget: Decodable {
    var name: String
    var path: String?
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
    public func formattedReport(includeHeader: Bool = true) -> String {
        var lines: [String] = []
        if includeHeader {
            lines.append("=== quill-doctor coverage report ===")
            lines.append("")
        }

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
    public func ticketMarkdown(includeHeader: Bool = true, headingLevel: Int = 2) throws -> String {
        var lines: [String] = []
        let missing = modules.filter { $0.status == .missing }.sorted { $0.module < $1.module }
        guard !missing.isEmpty else {
            return "_All scanned imports are covered. No tickets to generate._\n"
        }
        if includeHeader {
            lines.append("# QuillUI coverage tickets")
            lines.append("")
            lines.append("Auto-generated by `quill-doctor`. One ticket per Swift module that is imported by the scanned project but has no section in the QuillUI coverage matrix.")
            lines.append("")
        }
        
        let prefix = String(repeating: "#", count: headingLevel)
        
        for m in missing {
            lines.append("\(prefix) Add coverage for `\(m.module)`")
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

public struct QuillDoctorWorkspaceReport: Equatable {
    public struct PackageReport: Equatable {
        public let packageName: String
        public let report: QuillDoctorReport
    }

    public let packages: [PackageReport]

    public var hasMissing: Bool {
        packages.contains { $0.report.hasMissing }
    }

    public func formattedReport() -> String {
        var lines: [String] = []
        lines.append("=== quill-doctor workspace coverage report ===")
        lines.append("")
        for package in packages {
            lines.append("## \(package.packageName)")
            lines.append("")
            lines.append(package.report.formattedReport(includeHeader: false))
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func ticketMarkdown() throws -> String {
        var lines: [String] = []
        lines.append("# QuillUI coverage tickets")
        lines.append("")
        lines.append("Auto-generated by `quill-doctor` in workspace mode.")
        lines.append("")

        for package in packages {
            let tickets = try package.report.ticketMarkdown(includeHeader: false, headingLevel: 3)
            if tickets.contains("No tickets to generate") { continue }
            lines.append("## \(package.packageName)")
            lines.append("")
            lines.append(tickets)
            lines.append("")
        }
        
        // Actually, if lines only contains the header, then no tickets.
        if lines.count <= 4 {
            return "_All scanned imports are covered. No tickets to generate._\n"
        }
        
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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
