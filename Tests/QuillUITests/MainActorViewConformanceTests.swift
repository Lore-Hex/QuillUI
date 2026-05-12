import Foundation
import Testing

@Suite("MainActor View isolation")
struct MainActorViewConformanceTests {
    @Test("keeps main-actor View witnesses compatible with SwiftOpenUI")
    func keepsMainActorViewWitnessesCompatibleWithSwiftOpenUI() throws {
        let root = try packageRoot()
        let sources = root.appendingPathComponent("Sources")
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: sources,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var violations: [String] = []

        while let file = enumerator?.nextObject() as? URL {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, file.pathExtension == "swift" else {
                continue
            }

            let source = try String(contentsOf: file, encoding: .utf8)
            violations.append(contentsOf: findMainActorViewWitnessViolations(in: source, file: file, root: root))
        }

        #expect(violations.isEmpty, Comment(rawValue: violations.joined(separator: "\n")))
    }

    private func findMainActorViewWitnessViolations(in source: String, file: URL, root: URL) -> [String] {
        let lines = source.components(separatedBy: .newlines)
        var violations: [String] = []
        var pendingMainActorLine: Int?
        let relativePath = file.path.replacingOccurrences(of: root.path + "/", with: "")

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("//") {
                continue
            }

            let lineHasMainActor = line.hasPrefix("@MainActor")
            if lineHasMainActor {
                pendingMainActorLine = lineNumber
            }

            guard line.contains("struct "), let mainActorLine = pendingMainActorLine else {
                if !lineHasMainActor {
                    pendingMainActorLine = nil
                }
                continue
            }

            defer { pendingMainActorLine = nil }

            guard isViewStructDeclaration(line) else {
                continue
            }

            if line.contains(": @MainActor View") {
                violations.append("\(relativePath):\(mainActorLine): isolated View conformance: \(line)")
            }

            guard let body = findBodyWitness(after: index, in: lines) else {
                violations.append("\(relativePath):\(lineNumber): missing `body` witness for \(line)")
                continue
            }

            if !body.text.contains("nonisolated") {
                violations.append("\(relativePath):\(body.line): body witness must be nonisolated: \(body.text)")
            }

            if !usesMainActorViewHelper(after: body.index, in: lines) {
                violations.append(
                    "\(relativePath):\(body.line): nonisolated body must enter an approved main-actor view helper"
                )
            }
        }

        return violations
    }

    private func isViewStructDeclaration(_ line: String) -> Bool {
        line.contains(":")
            && line.contains("View")
            && !line.contains(": App")
            && !line.contains("ViewModifier")
    }

    private func findBodyWitness(after declarationIndex: Int, in lines: [String]) -> (index: Int, line: Int, text: String)? {
        let end = min(lines.count, declarationIndex + 120)
        guard declarationIndex + 1 < end else { return nil }

        for index in (declarationIndex + 1)..<end {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.contains("var body: some View") {
                return (index: index, line: index + 1, text: line)
            }
        }

        return nil
    }

    private func usesMainActorViewHelper(after bodyIndex: Int, in lines: [String]) -> Bool {
        let end = min(lines.count, bodyIndex + 8)
        guard bodyIndex + 1 < end else { return false }

        let approvedHelpers = [
            "QuillMainActorView.assumeIsolated",
            "ChatMainActorView.assumeIsolated",
        ]

        return lines[(bodyIndex + 1)..<end].contains { line in
            approvedHelpers.contains { helper in
                line.contains(helper)
            }
        }
    }

    private func packageRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        while directory.path != "/" {
            if fileManager.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "MainActorViewConformanceTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate package root from \(#filePath)"]
        )
    }
}
